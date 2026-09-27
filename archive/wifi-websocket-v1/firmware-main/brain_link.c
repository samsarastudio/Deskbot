#include "brain_link.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_websocket_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "app_config.h"
#include "face.h"
#include "protocol.h"

static const char *TAG = "brain";
static esp_websocket_client_handle_t s_client;

static void heartbeat_task(void *arg)
{
    char buf[48];
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(DESKBOT_HEARTBEAT_MS));
        if (!s_client || !esp_websocket_client_is_connected(s_client)) {
            continue;
        }
        if (protocol_heartbeat_json(buf, sizeof(buf)) == ESP_OK) {
            esp_websocket_client_send_text(s_client, buf, strlen(buf), pdMS_TO_TICKS(1000));
        }
    }
}

static void on_ws(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    esp_websocket_event_data_t *data = (esp_websocket_event_data_t *)event_data;
    switch (event_id) {
    case WEBSOCKET_EVENT_CONNECTED: {
        ESP_LOGI(TAG, "connected");
        char *hello = protocol_hello_json();
        if (hello) {
            esp_websocket_client_send_text(s_client, hello, strlen(hello), pdMS_TO_TICKS(2000));
            free(hello);
        }
        break;
    }
    case WEBSOCKET_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "disconnected");
        face_set_state(FACE_OFFLINE);
        break;
    case WEBSOCKET_EVENT_DATA:
        if (data->op_code == 1 && data->data_ptr && data->data_len > 0) {
            protocol_handle_text(data->data_ptr, data->data_len);
        }
        break;
    case WEBSOCKET_EVENT_ERROR:
        ESP_LOGE(TAG, "socket error");
        face_set_state(FACE_WARNING);
        break;
    default:
        break;
    }
}

esp_err_t brain_link_start(void)
{
    char uri[96];
    snprintf(uri, sizeof(uri), "ws://%s:%d%s", DESKBOT_BRAIN_HOST, DESKBOT_BRAIN_PORT, DESKBOT_BRAIN_PATH);
    esp_websocket_client_config_t cfg = {
        .uri = uri,
        .reconnect_timeout_ms = 3000,
        .network_timeout_ms = 5000,
    };
    s_client = esp_websocket_client_init(&cfg);
    if (!s_client) {
        return ESP_FAIL;
    }
    ESP_ERROR_CHECK(esp_websocket_register_events(s_client, WEBSOCKET_EVENT_ANY, on_ws, NULL));
    ESP_ERROR_CHECK(esp_websocket_client_start(s_client));
    xTaskCreate(heartbeat_task, "hb", 3072, NULL, 5, NULL);
    ESP_LOGI(TAG, "connecting %s", uri);
    return ESP_OK;
}
