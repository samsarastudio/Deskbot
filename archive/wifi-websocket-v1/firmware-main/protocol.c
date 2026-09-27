#include "protocol.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"

#include "app_config.h"
#include "face.h"
#include "motion.h"

static const char *TAG = "proto";

char *protocol_hello_json(void)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "type", "hello");
    cJSON_AddStringToObject(root, "device_id", DESKBOT_DEVICE_ID);
    cJSON_AddNumberToObject(root, "protocol", 1);
    cJSON_AddStringToObject(root, "token", DESKBOT_DEVICE_TOKEN);
    cJSON *caps = cJSON_AddArrayToObject(root, "capabilities");
    cJSON_AddItemToArray(caps, cJSON_CreateString("lcd"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("rgb"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("servo"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("tf"));
    char *printed = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return printed;
}

esp_err_t protocol_heartbeat_json(char *buf, size_t len)
{
    int n = snprintf(buf, len, "{\"type\":\"heartbeat\"}");
    return (n > 0 && (size_t)n < len) ? ESP_OK : ESP_FAIL;
}

static void handle_object(cJSON *root)
{
    const cJSON *type = cJSON_GetObjectItem(root, "type");
    if (!cJSON_IsString(type) || !type->valuestring) {
        return;
    }
    if (!strcmp(type->valuestring, "hello_ack")) {
        const cJSON *unix_sec = cJSON_GetObjectItem(root, "unix");
        const cJSON *tz = cJSON_GetObjectItem(root, "tz");
        if (cJSON_IsNumber(unix_sec)) {
            face_apply_unix_time((long)unix_sec->valuedouble, cJSON_IsString(tz) ? tz->valuestring : NULL);
        }
        face_set_state(FACE_IDLE);
        ESP_LOGI(TAG, "brain hello_ack");
        return;
    }
    if (!strcmp(type->valuestring, "state")) {
        const cJSON *state = cJSON_GetObjectItem(root, "state");
        if (cJSON_IsString(state) && state->valuestring) {
            if (!strcmp(state->valuestring, "listening")) face_set_state(FACE_LISTENING);
            else if (!strcmp(state->valuestring, "thinking")) face_set_state(FACE_THINKING);
            else if (!strcmp(state->valuestring, "speaking")) face_set_state(FACE_SPEAKING);
            else if (!strcmp(state->valuestring, "sleep")) face_set_state(FACE_SLEEP);
            else if (!strcmp(state->valuestring, "offline")) face_set_state(FACE_OFFLINE);
            else if (!strcmp(state->valuestring, "idle")) face_set_state(FACE_IDLE);
        }
        return;
    }
    if (!strcmp(type->valuestring, "fx")) {
        const cJSON *name = cJSON_GetObjectItem(root, "name");
        if (cJSON_IsString(name) && name->valuestring && !strcmp(name->valuestring, "heart")) {
            face_play_heart();
        }
        return;
    }
    if (!strcmp(type->valuestring, "face") || !strcmp(type->valuestring, "behavior")) {
        const cJSON *expr = cJSON_GetObjectItem(root, "expression");
        if (!cJSON_IsString(expr) || !expr->valuestring) {
            expr = cJSON_GetObjectItem(root, "emotion");
        }
        const cJSON *face = cJSON_GetObjectItem(root, "face");
        const cJSON *intensity = cJSON_GetObjectItem(root, "intensity");
        if (cJSON_IsString(expr) && expr->valuestring) {
            face_set_expression(
                expr->valuestring,
                cJSON_IsNumber(intensity) ? (float)intensity->valuedouble : 0.5f
            );
        } else if (cJSON_IsString(face) && face->valuestring) {
            face_set_face_id(face->valuestring);
        }
        const cJSON *gaze = cJSON_GetObjectItem(root, "gaze");
        if (cJSON_IsString(gaze)) {
            face_set_gaze(gaze->valuestring);
        }
        const cJSON *gesture = cJSON_GetObjectItem(root, "gesture");
        if (cJSON_IsString(gesture) && gesture->valuestring) {
            if (!strcmp(gesture->valuestring, "look_left")) motion_set_joint("head_yaw", -22, 35);
            else if (!strcmp(gesture->valuestring, "look_right")) motion_set_joint("head_yaw", 22, 35);
            else if (!strcmp(gesture->valuestring, "nod") || !strcmp(gesture->valuestring, "tiny_nod")) {
                motion_set_joint("head_pitch", 6, 35);
            } else if (!strcmp(gesture->valuestring, "perk_up")) {
                motion_set_joint("head_pitch", 10, 35);
            }
        }
        return;
    }
    if (!strcmp(type->valuestring, "chat")) {
        const cJSON *speaker = cJSON_GetObjectItem(root, "speaker");
        const cJSON *text = cJSON_GetObjectItem(root, "text");
        face_set_chat(
            cJSON_IsString(speaker) ? speaker->valuestring : "nova",
            cJSON_IsString(text) ? text->valuestring : ""
        );
        const cJSON *emotion = cJSON_GetObjectItem(root, "emotion");
        if (!cJSON_IsString(emotion) || !emotion->valuestring) {
            emotion = cJSON_GetObjectItem(root, "expression");
        }
        const cJSON *face = cJSON_GetObjectItem(root, "face");
        if (cJSON_IsString(emotion) && emotion->valuestring) {
            face_set_expression(emotion->valuestring, 0.7f);
        } else if (cJSON_IsString(face) && face->valuestring) {
            face_set_face_id(face->valuestring);
        }
        return;
    }
    if (!strcmp(type->valuestring, "command")) {
        const cJSON *action = cJSON_GetObjectItem(root, "action");
        if (cJSON_IsString(action) && action->valuestring) {
            if (!strcmp(action->valuestring, "blink")) {
                face_force_blink();
            } else if (!strcmp(action->valuestring, "name_intro")) {
                face_play_intro();
            }
        }
        return;
    }
    if (!strcmp(type->valuestring, "motion")) {
        const cJSON *joint = cJSON_GetObjectItem(root, "joint");
        const cJSON *angle = cJSON_GetObjectItem(root, "angle");
        const cJSON *speed = cJSON_GetObjectItem(root, "speed");
        if (cJSON_IsString(joint) && cJSON_IsNumber(angle)) {
            motion_set_joint(
                joint->valuestring,
                (float)angle->valuedouble,
                cJSON_IsNumber(speed) ? speed->valueint : 35
            );
        }
        return;
    }
    if (!strcmp(type->valuestring, "audio_cancel")) {
        motion_cancel();
        face_set_state(FACE_LISTENING);
        return;
    }
}

void protocol_handle_text(const char *text, int len)
{
    cJSON *root = cJSON_ParseWithLength(text, len);
    if (!root) {
        ESP_LOGW(TAG, "bad json");
        return;
    }
    handle_object(root);
    cJSON_Delete(root);
}
