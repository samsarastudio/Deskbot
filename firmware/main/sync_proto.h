#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

typedef void (*sync_emit_fn)(const char *json, void *ctx);

void sync_proto_init(sync_emit_fn emit, void *ctx);
void sync_proto_on_message(const uint8_t *data, size_t len);
void sync_proto_on_session_control(const char *json);
void sync_proto_send_hello(void);
void sync_proto_send_challenge(void);
char *sync_proto_device_info_json(void); /* caller frees with free() */
bool sync_proto_session_authed(void);
void sync_proto_reset_session(void);
