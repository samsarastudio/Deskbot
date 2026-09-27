#include "esp_log.h"
#include "nvs_flash.h"

#include "ble_gatt.h"
#include "face.h"
#include "motion.h"
#include "ownership.h"
#include "session_sm.h"

static const char *TAG = "deskbot";

void app_main(void)
{
    ESP_LOGI(TAG, "NOVA Deskbot BLE boot");
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    } else {
        ESP_ERROR_CHECK(err);
    }

    ESP_ERROR_CHECK(face_init());
    face_set_state(FACE_WAKE);
    ESP_ERROR_CHECK(motion_init());
    motion_neutral();

    ESP_ERROR_CHECK(ownership_init());
    session_sm_init();

    ESP_ERROR_CHECK(ble_gatt_start());
    ESP_LOGI(TAG, "BLE companion ready");
}
