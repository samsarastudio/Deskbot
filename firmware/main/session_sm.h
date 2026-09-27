#pragma once

typedef enum {
    SM_UNREGISTERED = 0,
    SM_REGISTERED_OFFLINE,
    SM_CONNECTING,
    SM_AUTHENTICATING,
    SM_SYNCING,
    SM_CONNECTED,
    SM_RECONNECTING,
    SM_RECOVERY,
} session_state_t;

void session_sm_init(void);
session_state_t session_sm_get(void);
void session_sm_set(session_state_t state);
const char *session_sm_label(session_state_t state);
void session_sm_on_gap_connected(void);
void session_sm_on_gap_disconnected(void);
void session_sm_on_auth_ok(void);
void session_sm_on_auth_fail(void);
void session_sm_on_sync_done(void);
void session_sm_on_registered(void);
void session_sm_on_factory_reset(void);
void session_sm_enter_recovery(void);
