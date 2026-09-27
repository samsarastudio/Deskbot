#include "session_sm.h"

#include "esp_log.h"
#include "face.h"
#include "ownership.h"

static const char *TAG = "sm";
static session_state_t s_state = SM_UNREGISTERED;

static void apply_ui(session_state_t state)
{
    switch (state) {
    case SM_UNREGISTERED:
        face_set_ble_status("Open app", "curious", ownership_confirm_code());
        break;
    case SM_REGISTERED_OFFLINE:
        face_set_ble_status(NULL, NULL, NULL);
        face_set_ble_pip(false);
        face_set_state(FACE_IDLE);
        break;
    case SM_CONNECTING:
    case SM_RECONNECTING:
        face_set_ble_status("Connecting", "thinking", NULL);
        break;
    case SM_AUTHENTICATING:
        face_set_ble_status("Linking", "thinking", NULL);
        break;
    case SM_SYNCING:
        face_set_ble_status("Syncing", "thinking", NULL);
        break;
    case SM_CONNECTED:
        face_flash_ble_status("Connected", "happy", 1600);
        face_set_ble_pip(true);
        break;
    case SM_RECOVERY:
        face_set_ble_status("Auth fail", "worried", NULL);
        break;
    }
}

void session_sm_init(void)
{
    s_state = ownership_get()->registered ? SM_REGISTERED_OFFLINE : SM_UNREGISTERED;
    apply_ui(s_state);
    ESP_LOGI(TAG, "init state=%s", session_sm_label(s_state));
}

session_state_t session_sm_get(void)
{
    return s_state;
}

void session_sm_set(session_state_t state)
{
    if (s_state == state) {
        return;
    }
    ESP_LOGI(TAG, "%s -> %s", session_sm_label(s_state), session_sm_label(state));
    s_state = state;
    apply_ui(state);
}

const char *session_sm_label(session_state_t state)
{
    switch (state) {
    case SM_UNREGISTERED: return "UNREGISTERED";
    case SM_REGISTERED_OFFLINE: return "REGISTERED_OFFLINE";
    case SM_CONNECTING: return "CONNECTING";
    case SM_AUTHENTICATING: return "AUTHENTICATING";
    case SM_SYNCING: return "SYNCING";
    case SM_CONNECTED: return "CONNECTED";
    case SM_RECONNECTING: return "RECONNECTING";
    case SM_RECOVERY: return "RECOVERY";
    }
    return "?";
}

void session_sm_on_gap_connected(void)
{
    session_sm_set(SM_CONNECTING);
    session_sm_set(SM_AUTHENTICATING);
}

void session_sm_on_gap_disconnected(void)
{
    if (ownership_get()->registered) {
        session_sm_set(SM_RECONNECTING);
        session_sm_set(SM_REGISTERED_OFFLINE);
    } else {
        session_sm_set(SM_UNREGISTERED);
    }
}

void session_sm_on_auth_ok(void)
{
    session_sm_set(SM_SYNCING);
}

void session_sm_on_auth_fail(void)
{
    session_sm_set(SM_RECOVERY);
}

void session_sm_on_sync_done(void)
{
    session_sm_set(SM_CONNECTED);
}

void session_sm_on_registered(void)
{
    session_sm_set(SM_AUTHENTICATING);
}

void session_sm_on_factory_reset(void)
{
    session_sm_set(SM_UNREGISTERED);
}

void session_sm_enter_recovery(void)
{
    session_sm_set(SM_RECOVERY);
}
