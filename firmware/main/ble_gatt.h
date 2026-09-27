#pragma once

#include "esp_err.h"

esp_err_t ble_gatt_start(void);
void ble_gatt_request_adv_refresh(void);
