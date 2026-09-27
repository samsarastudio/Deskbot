#include "ownership.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_random.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "own";
static ownership_t s_own;
static char s_confirm[5] = "0000";

esp_err_t ownership_init(void)
{
    memset(&s_own, 0, sizeof(s_own));
    nvs_handle_t h;
    esp_err_t err = nvs_open("deskbot", NVS_READONLY, &h);
    if (err == ESP_OK) {
        size_t len = sizeof(s_own.device_id);
        nvs_get_str(h, "device_id", s_own.device_id, &len);
        len = sizeof(s_own.owner_token);
        if (nvs_get_str(h, "owner", s_own.owner_token, &len) == ESP_OK && s_own.owner_token[0]) {
            s_own.registered = true;
        }
        nvs_get_u32(h, "rev", &s_own.state_rev);
        nvs_close(h);
    }
    ESP_ERROR_CHECK(ownership_ensure_device_id());
    ownership_make_confirm_code(s_confirm);
    ESP_LOGI(TAG, "id=%s registered=%d rev=%lu", s_own.device_id, (int)s_own.registered,
             (unsigned long)s_own.state_rev);
    return ESP_OK;
}

const ownership_t *ownership_get(void)
{
    return &s_own;
}

esp_err_t ownership_ensure_device_id(void)
{
    if (s_own.device_id[0]) {
        return ESP_OK;
    }
    uint32_t r = esp_random();
    snprintf(s_own.device_id, sizeof(s_own.device_id), "nova-%08lx", (unsigned long)r);
    nvs_handle_t h;
    ESP_ERROR_CHECK(nvs_open("deskbot", NVS_READWRITE, &h));
    ESP_ERROR_CHECK(nvs_set_str(h, "device_id", s_own.device_id));
    ESP_ERROR_CHECK(nvs_commit(h));
    nvs_close(h);
    return ESP_OK;
}

static esp_err_t save(void)
{
    nvs_handle_t h;
    ESP_ERROR_CHECK(nvs_open("deskbot", NVS_READWRITE, &h));
    ESP_ERROR_CHECK(nvs_set_str(h, "device_id", s_own.device_id));
    if (s_own.registered) {
        ESP_ERROR_CHECK(nvs_set_str(h, "owner", s_own.owner_token));
    } else {
        nvs_erase_key(h, "owner");
    }
    ESP_ERROR_CHECK(nvs_set_u32(h, "rev", s_own.state_rev));
    ESP_ERROR_CHECK(nvs_commit(h));
    nvs_close(h);
    return ESP_OK;
}

esp_err_t ownership_register(const char *owner_token)
{
    if (!owner_token || !owner_token[0] || strlen(owner_token) >= sizeof(s_own.owner_token)) {
        return ESP_ERR_INVALID_ARG;
    }
    strlcpy(s_own.owner_token, owner_token, sizeof(s_own.owner_token));
    s_own.registered = true;
    if (s_own.state_rev == 0) {
        s_own.state_rev = 1;
    }
    return save();
}

esp_err_t ownership_clear(void)
{
    s_own.owner_token[0] = 0;
    s_own.registered = false;
    s_own.state_rev = 0;
    ownership_make_confirm_code(s_confirm);
    return save();
}

esp_err_t ownership_bump_rev(void)
{
    s_own.state_rev++;
    return save();
}

esp_err_t ownership_set_rev(uint32_t rev)
{
    s_own.state_rev = rev;
    return save();
}

bool ownership_token_matches(const char *token)
{
    return s_own.registered && token && strcmp(s_own.owner_token, token) == 0;
}

void ownership_make_confirm_code(char out4[5])
{
    uint32_t r = esp_random() % 10000u;
    snprintf(s_confirm, sizeof(s_confirm), "%04lu", (unsigned long)r);
    if (out4) {
        memcpy(out4, s_confirm, 5);
    }
}

const char *ownership_confirm_code(void)
{
    return s_confirm;
}
