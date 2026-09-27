#include "ble_gatt.h"

#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs_flash.h"

#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "store/config/ble_store_config.h"

/* Provided by NimBLE store config component. */
void ble_store_config_init(void);

#include "app_config.h"
#include "frag.h"
#include "ownership.h"
#include "session_sm.h"
#include "sync_proto.h"

static const char *TAG = "ble";

static uint8_t s_own_addr_type;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_evt_val_handle;
static uint16_t s_cmd_val_handle;
static uint16_t s_info_val_handle;
static uint16_t s_sess_val_handle;
static bool s_evt_notify_enabled;
static frag_rx_t s_frag_rx;
static uint16_t s_tx_msg_id = 1;
static SemaphoreHandle_t s_tx_lock;

/* 128-bit UUID helpers — little-endian byte order for NimBLE.
 * UUID string: 6e6f7661-0001-4000-8000-6465736b626f
 */
static const ble_uuid128_t UUID_SVC = BLE_UUID128_INIT(
    0x6f, 0x62, 0x6b, 0x73, 0x65, 0x64, 0x00, 0x80, 0x00, 0x40, 0x01, 0x00, 0x61, 0x76, 0x6f, 0x6e);
static const ble_uuid128_t UUID_CMD = BLE_UUID128_INIT(
    0x6f, 0x62, 0x6b, 0x73, 0x65, 0x64, 0x00, 0x80, 0x00, 0x40, 0x02, 0x00, 0x61, 0x76, 0x6f, 0x6e);
static const ble_uuid128_t UUID_EVT = BLE_UUID128_INIT(
    0x6f, 0x62, 0x6b, 0x73, 0x65, 0x64, 0x00, 0x80, 0x00, 0x40, 0x03, 0x00, 0x61, 0x76, 0x6f, 0x6e);
static const ble_uuid128_t UUID_INFO = BLE_UUID128_INIT(
    0x6f, 0x62, 0x6b, 0x73, 0x65, 0x64, 0x00, 0x80, 0x00, 0x40, 0x04, 0x00, 0x61, 0x76, 0x6f, 0x6e);
static const ble_uuid128_t UUID_SESS = BLE_UUID128_INIT(
    0x6f, 0x62, 0x6b, 0x73, 0x65, 0x64, 0x00, 0x80, 0x00, 0x40, 0x05, 0x00, 0x61, 0x76, 0x6f, 0x6e);

static void start_advertise(void);

static void on_msg_complete(const uint8_t *data, size_t len, void *ctx)
{
    (void)ctx;
    sync_proto_on_message(data, len);
}

static int gap_event(struct ble_gap_event *event, void *arg);

static void emit_frag(const uint8_t *frag, size_t frag_len, void *ctx)
{
    (void)ctx;
    if (!s_evt_notify_enabled || s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        return;
    }
    struct os_mbuf *om = ble_hs_mbuf_from_flat(frag, frag_len);
    if (!om) {
        return;
    }
    ble_gatts_notify_custom(s_conn_handle, s_evt_val_handle, om);
}

static void sync_emit(const char *json, void *ctx)
{
    (void)ctx;
    if (!json) {
        return;
    }
    if (s_tx_lock) {
        xSemaphoreTake(s_tx_lock, portMAX_DELAY);
    }
    uint16_t id = s_tx_msg_id++;
    frag_tx_build(id, (const uint8_t *)json, strlen(json), emit_frag, NULL);
    if (s_tx_lock) {
        xSemaphoreGive(s_tx_lock);
    }
}

static int cmd_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    uint8_t *buf = malloc(len);
    if (!buf) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL);
    frag_rx_feed(&s_frag_rx, buf, len, on_msg_complete, NULL);
    free(buf);
    return 0;
}

static int info_access(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    char *json = sync_proto_device_info_json();
    if (!json) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    int rc = os_mbuf_append(ctxt->om, json, strlen(json));
    free(json);
    return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int sess_access(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        const char *st = session_sm_label(session_sm_get());
        char buf[96];
        snprintf(buf, sizeof(buf), "{\"state\":\"%s\",\"code\":\"%s\"}", st, ownership_confirm_code());
        int rc = os_mbuf_append(ctxt->om, buf, strlen(buf));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        char *buf = malloc(len + 1);
        if (!buf) {
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL);
        buf[len] = 0;
        sync_proto_on_session_control(buf);
        free(buf);
        return 0;
    }
    return BLE_ATT_ERR_UNLIKELY;
}

static int evt_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    (void)ctxt;
    return 0;
}

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &UUID_SVC.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &UUID_CMD.u,
                .access_cb = cmd_access,
                .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
                .val_handle = &s_cmd_val_handle,
            },
            {
                .uuid = &UUID_EVT.u,
                .access_cb = evt_access,
                .flags = BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_evt_val_handle,
            },
            {
                .uuid = &UUID_INFO.u,
                .access_cb = info_access,
                .flags = BLE_GATT_CHR_F_READ,
                .val_handle = &s_info_val_handle,
            },
            {
                .uuid = &UUID_SESS.u,
                .access_cb = sess_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_sess_val_handle,
            },
            { 0 },
        },
    },
    { 0 },
};

static void start_advertise(void)
{
    struct ble_hs_adv_fields fields = { 0 };
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &UUID_SVC;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    const ownership_t *o = ownership_get();
    uint8_t mfg[7];
    mfg[0] = 0x01;
    mfg[1] = DESKBOT_PROTOCOL_VER;
    mfg[2] = o->registered ? 0x01 : 0x02;
    uint32_t short_id = 0;
    if (strlen(o->device_id) >= 8) {
        short_id = (uint32_t)strtoul(o->device_id + strlen(o->device_id) - 8, NULL, 16);
    }
    memcpy(mfg + 3, &short_id, 4);
    fields.mfg_data = mfg;
    fields.mfg_data_len = sizeof(mfg);

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv fields rc=%d", rc);
        return;
    }

    struct ble_hs_adv_fields rsp = { 0 };
    const char *name = o->registered ? DESKBOT_ADV_NAME_REG : DESKBOT_ADV_NAME_SETUP;
    rsp.name = (uint8_t *)name;
    rsp.name_len = strlen(name);
    rsp.name_is_complete = 1;
    ble_gap_adv_rsp_set_fields(&rsp);

    struct ble_gap_adv_params adv = { 0 };
    adv.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv.disc_mode = BLE_GAP_DISC_MODE_GEN;
    adv.itvl_min = BLE_GAP_ADV_FAST_INTERVAL1_MIN;
    adv.itvl_max = BLE_GAP_ADV_FAST_INTERVAL1_MAX;
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &adv, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv start rc=%d", rc);
    } else {
        ESP_LOGI(TAG, "advertising as %s", name);
    }
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
            ESP_LOGI(TAG, "connected handle=%u", s_conn_handle);
            frag_rx_init(&s_frag_rx);
            sync_proto_reset_session();
            session_sm_on_gap_connected();
        } else {
            start_advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnected reason=%d", event->disconnect.reason);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        s_evt_notify_enabled = false;
        sync_proto_reset_session();
        session_sm_on_gap_disconnected();
        start_advertise();
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_evt_val_handle) {
            s_evt_notify_enabled = event->subscribe.cur_notify;
            ESP_LOGI(TAG, "evt notify=%d", (int)s_evt_notify_enabled);
            if (s_evt_notify_enabled) {
                sync_proto_send_hello();
                if (ownership_get()->registered) {
                    sync_proto_send_challenge();
                }
            }
        }
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "mtu=%d", event->mtu.value);
        return 0;
    default:
        return 0;
    }
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    assert(rc == 0);
    rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    assert(rc == 0);
    start_advertise();
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "nimble reset reason=%d", reason);
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

esp_err_t ble_gatt_start(void)
{
    s_tx_lock = xSemaphoreCreateMutex();
    frag_rx_init(&s_frag_rx);
    sync_proto_init(sync_emit, NULL);

    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.gatts_register_cb = NULL;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    ble_store_config_init();

    ble_svc_gap_init();
    ble_svc_gatt_init();
    ESP_ERROR_CHECK(ble_gatts_count_cfg(s_gatt_svcs));
    ESP_ERROR_CHECK(ble_gatts_add_svcs(s_gatt_svcs));

    const char *name = ownership_get()->registered ? DESKBOT_ADV_NAME_REG : DESKBOT_ADV_NAME_SETUP;
    ble_svc_gap_device_name_set(name);

    nimble_port_freertos_init(host_task);
    return ESP_OK;
}

void ble_gatt_request_adv_refresh(void)
{
    if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        ble_gap_adv_stop();
        start_advertise();
    }
}
