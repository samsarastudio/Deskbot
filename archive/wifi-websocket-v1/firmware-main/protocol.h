#pragma once

#include <stddef.h>

#include "cJSON.h"
#include "esp_err.h"

char *protocol_hello_json(void);
esp_err_t protocol_heartbeat_json(char *buf, size_t len);
void protocol_handle_text(const char *text, int len);
