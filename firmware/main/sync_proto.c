#include "sync_proto.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_log.h"
#include "esp_random.h"
#include "mbedtls/base64.h"
#include "mbedtls/md.h"

#include "app_config.h"
#include "face.h"
#include "ownership.h"
#include "session_sm.h"

static const char *TAG = "sync";
static sync_emit_fn s_emit;
static void *s_ctx;
static bool s_authed;
static char s_nonce[33];
static uint32_t s_msg_counter;

static void emit_json(cJSON *root)
{
    if (!s_emit || !root) {
        return;
    }
    char *printed = cJSON_PrintUnformatted(root);
    if (printed) {
        s_emit(printed, s_ctx);
        free(printed);
    }
}

static void send_type(const char *type, cJSON *body)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "v", DESKBOT_PROTOCOL_VER);
    cJSON_AddStringToObject(root, "type", type);
    char idbuf[24];
    snprintf(idbuf, sizeof(idbuf), "d-%lu", (unsigned long)(++s_msg_counter));
    cJSON_AddStringToObject(root, "id", idbuf);
    if (body) {
        cJSON_AddItemToObject(root, "body", body);
    } else {
        cJSON_AddObjectToObject(root, "body");
    }
    emit_json(root);
    cJSON_Delete(root);
}

static void hmac_hex(const char *key, const char *nonce, char out_hex[65])
{
    unsigned char mac[32];
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_setup(&ctx, info, 1);
    mbedtls_md_hmac_starts(&ctx, (const unsigned char *)key, strlen(key));
    mbedtls_md_hmac_update(&ctx, (const unsigned char *)nonce, strlen(nonce));
    mbedtls_md_hmac_finish(&ctx, mac);
    mbedtls_md_free(&ctx);
    for (int i = 0; i < 32; i++) {
        sprintf(out_hex + i * 2, "%02x", mac[i]);
    }
    out_hex[64] = 0;
}

void sync_proto_init(sync_emit_fn emit, void *ctx)
{
    s_emit = emit;
    s_ctx = ctx;
    s_authed = false;
    s_nonce[0] = 0;
    s_msg_counter = 0;
}

void sync_proto_reset_session(void)
{
    s_authed = false;
    s_nonce[0] = 0;
}

bool sync_proto_session_authed(void)
{
    return s_authed;
}

void sync_proto_send_hello(void)
{
    const ownership_t *o = ownership_get();
    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "device_id", o->device_id);
    cJSON_AddStringToObject(body, "role", "deskbot");
    cJSON_AddStringToObject(body, "fw", DESKBOT_FW_VERSION);
    cJSON_AddNumberToObject(body, "protocol", DESKBOT_PROTOCOL_VER);
    cJSON_AddStringToObject(body, "model", DESKBOT_MODEL);
    send_type("HELLO", body);
}

void sync_proto_send_challenge(void)
{
    uint8_t raw[16];
    esp_fill_random(raw, sizeof(raw));
    for (int i = 0; i < 16; i++) {
        sprintf(s_nonce + i * 2, "%02x", raw[i]);
    }
    s_nonce[32] = 0;
    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "op", "challenge");
    cJSON_AddStringToObject(body, "nonce", s_nonce);
    send_type("AUTH", body);
}

char *sync_proto_device_info_json(void)
{
    const ownership_t *o = ownership_get();
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "model", DESKBOT_MODEL);
    cJSON_AddStringToObject(root, "fw", DESKBOT_FW_VERSION);
    cJSON_AddNumberToObject(root, "protocol", DESKBOT_PROTOCOL_VER);
    cJSON_AddStringToObject(root, "device_id", o->device_id);
    cJSON_AddBoolToObject(root, "registered", o->registered);
    cJSON *caps = cJSON_AddArrayToObject(root, "capabilities");
    cJSON_AddItemToArray(caps, cJSON_CreateString("face"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("clock"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("sync_v1"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("notify_v1"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("calendar_v1"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("scenery_v1"));
    char *out = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return out;
}

static void send_ack(const char *for_id, bool ok)
{
    cJSON *body = cJSON_CreateObject();
    if (for_id) {
        cJSON_AddStringToObject(body, "for", for_id);
    }
    send_type(ok ? "ACK" : "NACK", body);
}

static void handle_register(cJSON *body)
{
    const cJSON *token = cJSON_GetObjectItem(body, "owner_token");
    const cJSON *confirm = cJSON_GetObjectItem(body, "confirm");
    if (!cJSON_IsString(token) || !token->valuestring) {
        send_ack(NULL, false);
        session_sm_on_auth_fail();
        return;
    }
    if (ownership_get()->registered) {
        /* Idempotent: same token = success; different token = reject. */
        if (ownership_token_matches(token->valuestring)) {
            s_authed = true;
            session_sm_on_auth_ok();
            send_ack(NULL, true);
            return;
        }
        ESP_LOGW(TAG, "already registered to another owner");
        send_ack(NULL, false);
        session_sm_enter_recovery();
        return;
    }
    if (cJSON_IsString(confirm) && confirm->valuestring) {
        if (strcmp(confirm->valuestring, ownership_confirm_code()) != 0) {
            ESP_LOGW(TAG, "bad confirm code");
            face_set_ble_status("CODE ?", "worried", ownership_confirm_code());
            send_ack(NULL, false);
            session_sm_on_auth_fail();
            return;
        }
    }
    if (ownership_register(token->valuestring) != ESP_OK) {
        send_ack(NULL, false);
        session_sm_on_auth_fail();
        return;
    }
    s_authed = true;
    session_sm_on_registered();
    session_sm_on_auth_ok();
    send_ack(NULL, true);
    cJSON *caps = cJSON_CreateObject();
    cJSON *arr = cJSON_AddArrayToObject(caps, "features");
    cJSON_AddItemToArray(arr, cJSON_CreateString("face"));
    cJSON_AddItemToArray(arr, cJSON_CreateString("sync_v1"));
    cJSON_AddItemToArray(arr, cJSON_CreateString("notify_v1"));
    cJSON_AddItemToArray(arr, cJSON_CreateString("calendar_v1"));
    cJSON_AddItemToArray(arr, cJSON_CreateString("scenery_v1"));
    send_type("CAPABILITIES", caps);
}

static void handle_display(cJSON *body)
{
    if (!s_authed) {
        send_ack(NULL, false);
        return;
    }
    const cJSON *op = cJSON_GetObjectItem(body, "op");
    if (!cJSON_IsString(op) || !op->valuestring) {
        send_ack(NULL, false);
        return;
    }
    if (!strcmp(op->valuestring, "notify")) {
        const cJSON *title = cJSON_GetObjectItem(body, "title");
        const cJSON *text = cJSON_GetObjectItem(body, "body");
        const cJSON *mood = cJSON_GetObjectItem(body, "mood");
        const cJSON *ttl = cJSON_GetObjectItem(body, "ttl_ms");
        face_show_notify(
            cJSON_IsString(title) ? title->valuestring : "Alert",
            cJSON_IsString(text) ? text->valuestring : "",
            cJSON_IsString(mood) ? mood->valuestring : "curious",
            cJSON_IsNumber(ttl) ? (int)ttl->valuedouble : 8000);
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "notify_clear")) {
        face_clear_notify();
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "calendar")) {
        const cJSON *title = cJSON_GetObjectItem(body, "title");
        const cJSON *when = cJSON_GetObjectItem(body, "when");
        if (cJSON_IsString(title) && title->valuestring && title->valuestring[0]) {
            face_set_calendar(title->valuestring,
                              cJSON_IsString(when) ? when->valuestring : "");
        } else {
            face_clear_calendar();
        }
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "calendar_clear")) {
        face_clear_calendar();
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "prompt")) {
        const cJSON *text = cJSON_GetObjectItem(body, "text");
        const cJSON *speaker = cJSON_GetObjectItem(body, "speaker");
        if (cJSON_IsString(text)) {
            face_set_chat(cJSON_IsString(speaker) ? speaker->valuestring : "nova", text->valuestring);
        }
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "time")) {
        const cJSON *unix_sec = cJSON_GetObjectItem(body, "unix");
        const cJSON *tz = cJSON_GetObjectItem(body, "tz");
        if (cJSON_IsNumber(unix_sec)) {
            face_apply_unix_time((long)unix_sec->valuedouble,
                                 cJSON_IsString(tz) ? tz->valuestring : NULL);
        }
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "scenery_begin")) {
        const cJSON *w = cJSON_GetObjectItem(body, "w");
        const cJSON *h = cJSON_GetObjectItem(body, "h");
        int wi = cJSON_IsNumber(w) ? (int)w->valuedouble : 0;
        int hi = cJSON_IsNumber(h) ? (int)h->valuedouble : 0;
        send_ack(NULL, face_scenery_begin(wi, hi));
    } else if (!strcmp(op->valuestring, "scenery_chunk")) {
        const cJSON *off = cJSON_GetObjectItem(body, "off");
        const cJSON *data = cJSON_GetObjectItem(body, "data");
        if (!cJSON_IsNumber(off) || !cJSON_IsString(data) || !data->valuestring) {
            send_ack(NULL, false);
            return;
        }
        size_t b64_len = strlen(data->valuestring);
        size_t olen = (b64_len / 4) * 3 + 4;
        uint8_t *buf = malloc(olen);
        if (!buf) {
            ESP_LOGE(TAG, "scenery chunk OOM");
            send_ack(NULL, false);
            return;
        }
        size_t written = 0;
        int rc = mbedtls_base64_decode(buf, olen, &written,
                                       (const unsigned char *)data->valuestring, b64_len);
        bool ok = (rc == 0) && face_scenery_write((size_t)off->valuedouble, buf, written);
        if (!ok) {
            ESP_LOGW(TAG, "scenery chunk fail off=%u len=%u rc=%d",
                     (unsigned)off->valuedouble, (unsigned)written, rc);
        }
        free(buf);
        send_ack(NULL, ok);
    } else if (!strcmp(op->valuestring, "scenery_end")) {
        face_scenery_commit();
        send_ack(NULL, true);
    } else if (!strcmp(op->valuestring, "scenery_clear")) {
        face_scenery_clear();
        send_ack(NULL, true);
    } else {
        send_ack(NULL, false);
    }
}

static void handle_auth(cJSON *body)
{
    const cJSON *op = cJSON_GetObjectItem(body, "op");
    if (!cJSON_IsString(op)) {
        return;
    }
    if (!strcmp(op->valuestring, "response")) {
        const cJSON *nonce = cJSON_GetObjectItem(body, "nonce");
        const cJSON *mac = cJSON_GetObjectItem(body, "mac");
        if (!ownership_get()->registered || !cJSON_IsString(nonce) || !cJSON_IsString(mac)) {
            session_sm_on_auth_fail();
            send_ack(NULL, false);
            return;
        }
        if (s_nonce[0] && strcmp(nonce->valuestring, s_nonce) != 0) {
            session_sm_on_auth_fail();
            send_ack(NULL, false);
            return;
        }
        char expect[65];
        hmac_hex(ownership_get()->owner_token, nonce->valuestring, expect);
        if (strcmp(expect, mac->valuestring) != 0) {
            ESP_LOGW(TAG, "auth mac mismatch");
            session_sm_on_auth_fail();
            send_ack(NULL, false);
            return;
        }
        s_authed = true;
        session_sm_on_auth_ok();
        send_ack(NULL, true);
        cJSON *ver = cJSON_CreateObject();
        cJSON_AddNumberToObject(ver, "rev", ownership_get()->state_rev);
        send_type("STATE_VERSION", ver);
        return;
    }
    if (!strcmp(op->valuestring, "challenge")) {
        /* App challenged us — respond if registered. */
        const cJSON *nonce = cJSON_GetObjectItem(body, "nonce");
        if (!ownership_get()->registered || !cJSON_IsString(nonce)) {
            session_sm_on_auth_fail();
            return;
        }
        char mac[65];
        hmac_hex(ownership_get()->owner_token, nonce->valuestring, mac);
        cJSON *resp = cJSON_CreateObject();
        cJSON_AddStringToObject(resp, "op", "response");
        cJSON_AddStringToObject(resp, "nonce", nonce->valuestring);
        cJSON_AddStringToObject(resp, "mac", mac);
        send_type("AUTH", resp);
    }
}

static void handle_state_version(cJSON *body)
{
    const cJSON *rev = cJSON_GetObjectItem(body, "rev");
    uint32_t peer = cJSON_IsNumber(rev) ? (uint32_t)rev->valuedouble : 0;
    uint32_t mine = ownership_get()->state_rev;
    if (peer == 0 || peer + 5 < mine || peer > mine + 5) {
        cJSON *snap = cJSON_CreateObject();
        cJSON_AddNumberToObject(snap, "rev", mine);
        cJSON_AddStringToObject(snap, "expression", "happy");
        cJSON_AddBoolToObject(snap, "ble_pip", true);
        cJSON *settings = cJSON_AddObjectToObject(snap, "settings");
        cJSON_AddNumberToObject(settings, "brightness", 50);
        send_type("STATE_SNAPSHOT", snap);
    } else if (peer < mine) {
        cJSON *delta = cJSON_CreateObject();
        cJSON_AddNumberToObject(delta, "from", peer);
        cJSON_AddNumberToObject(delta, "to", mine);
        cJSON_AddStringToObject(delta, "expression", "happy");
        send_type("DELTA", delta);
    } else {
        send_ack(NULL, true);
    }
    session_sm_on_sync_done();
}

static void handle_snapshot_or_delta(cJSON *body, bool snapshot)
{
    const cJSON *rev = cJSON_GetObjectItem(body, "rev");
    if (!rev) {
        rev = cJSON_GetObjectItem(body, "to");
    }
    if (cJSON_IsNumber(rev)) {
        ownership_set_rev((uint32_t)rev->valuedouble);
    }
    const cJSON *expr = cJSON_GetObjectItem(body, "expression");
    if (cJSON_IsString(expr) && expr->valuestring) {
        face_set_expression(expr->valuestring, 0.8f);
    }
    (void)snapshot;
    send_ack(NULL, true);
    session_sm_on_sync_done();
}

void sync_proto_on_message(const uint8_t *data, size_t len)
{
    if (!data || len == 0 || len >= DESKBOT_MAX_MSG) {
        return;
    }
    char *tmp = malloc(len + 1);
    if (!tmp) {
        return;
    }
    memcpy(tmp, data, len);
    tmp[len] = 0;
    cJSON *root = cJSON_Parse(tmp);
    free(tmp);
    if (!root) {
        ESP_LOGW(TAG, "bad json");
        return;
    }
    const cJSON *type = cJSON_GetObjectItem(root, "type");
    cJSON *body = cJSON_GetObjectItem(root, "body");
    if (!cJSON_IsString(type)) {
        cJSON_Delete(root);
        return;
    }
    ESP_LOGI(TAG, "rx %s", type->valuestring);

    if (!strcmp(type->valuestring, "HELLO")) {
        sync_proto_send_hello();
        if (ownership_get()->registered) {
            sync_proto_send_challenge();
        } else {
            face_set_ble_status("CODE", "focused", ownership_confirm_code());
        }
    } else if (!strcmp(type->valuestring, "AUTH")) {
        handle_auth(body);
    } else if (!strcmp(type->valuestring, "CAPABILITIES")) {
        /* ignore peer caps for now */
    } else if (!strcmp(type->valuestring, "STATE_VERSION")) {
        if (!s_authed && ownership_get()->registered) {
            session_sm_on_auth_fail();
        } else {
            handle_state_version(body);
        }
    } else if (!strcmp(type->valuestring, "STATE_SNAPSHOT")) {
        handle_snapshot_or_delta(body, true);
    } else if (!strcmp(type->valuestring, "DELTA")) {
        handle_snapshot_or_delta(body, false);
    } else if (!strcmp(type->valuestring, "DISPLAY")) {
        handle_display(body);
    } else if (!strcmp(type->valuestring, "ACK")) {
        if (session_sm_get() == SM_SYNCING) {
            session_sm_on_sync_done();
        }
    } else if (!strcmp(type->valuestring, "FACTORY_RESET")) {
        if (s_authed || !ownership_get()->registered || session_sm_get() == SM_RECOVERY) {
            ownership_clear();
            sync_proto_reset_session();
            session_sm_on_factory_reset();
            send_ack(NULL, true);
        } else {
            send_ack(NULL, false);
        }
    }

    /* Control path register via envelope type REGISTER for convenience */
    if (!strcmp(type->valuestring, "REGISTER")) {
        handle_register(body);
    }

    cJSON_Delete(root);
}

/* Session control JSON (unframed writes to Control characteristic). */
void sync_proto_on_session_control(const char *json)
{
    if (!json) {
        return;
    }
    cJSON *root = cJSON_Parse(json);
    if (!root) {
        return;
    }
    const cJSON *op = cJSON_GetObjectItem(root, "op");
    if (cJSON_IsString(op) && !strcmp(op->valuestring, "register")) {
        handle_register(root);
    } else if (cJSON_IsString(op) && !strcmp(op->valuestring, "show_code")) {
        ownership_make_confirm_code(NULL);
        face_set_ble_status("CODE", "focused", ownership_confirm_code());
        cJSON *hint = cJSON_CreateObject();
        cJSON_AddStringToObject(hint, "code", ownership_confirm_code());
        send_type("UI_HINT", hint);
    } else if (cJSON_IsString(op) && !strcmp(op->valuestring, "factory_reset")) {
        /* Allowed without auth so recovery can always clear a bad ownership token. */
        ownership_clear();
        sync_proto_reset_session();
        session_sm_on_factory_reset();
        face_set_ble_status("Open app", "curious", ownership_confirm_code());
        send_ack(NULL, true);
    }
    cJSON_Delete(root);
}
