#include "motion.h"

#include <string.h>

#include "esp_log.h"

static const char *TAG = "motion";
static float s_yaw;
static float s_pitch;

static float clampf(float value, float lo, float hi)
{
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

esp_err_t motion_init(void)
{
    s_yaw = 0;
    s_pitch = 0;
    ESP_LOGI(TAG, "motion safety layer ready (PCA9685 not wired yet)");
    return ESP_OK;
}

void motion_set_joint(const char *joint, float angle, int speed)
{
    (void)speed;
    if (!joint) {
        return;
    }
    if (!strcmp(joint, "head_yaw")) {
        s_yaw = clampf(angle, -35.0f, 35.0f);
    } else if (!strcmp(joint, "head_pitch")) {
        s_pitch = clampf(angle, -15.0f, 20.0f);
    } else {
        ESP_LOGW(TAG, "ignored joint %s", joint);
        return;
    }
    ESP_LOGI(TAG, "pose yaw=%.1f pitch=%.1f", s_yaw, s_pitch);
}

void motion_cancel(void)
{
    motion_neutral();
}

void motion_neutral(void)
{
    s_yaw = 0;
    s_pitch = 0;
    ESP_LOGI(TAG, "neutral pose");
}
