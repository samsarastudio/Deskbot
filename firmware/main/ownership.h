#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

typedef struct {
    char device_id[24];
    char owner_token[72];
    bool registered;
    uint32_t state_rev;
} ownership_t;

esp_err_t ownership_init(void);
const ownership_t *ownership_get(void);
esp_err_t ownership_ensure_device_id(void);
esp_err_t ownership_register(const char *owner_token);
esp_err_t ownership_clear(void);
esp_err_t ownership_bump_rev(void);
esp_err_t ownership_set_rev(uint32_t rev);
bool ownership_token_matches(const char *token);
void ownership_make_confirm_code(char out4[5]);
const char *ownership_confirm_code(void);
