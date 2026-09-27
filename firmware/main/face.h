#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

typedef enum {
    FACE_SLEEP = 0,
    FACE_IDLE,
    FACE_WAKE,
    FACE_LISTENING,
    FACE_THINKING,
    FACE_SPEAKING,
    FACE_HAPPY,
    FACE_CONFUSED,
    FACE_WARNING,
    FACE_OFFLINE,
} face_state_t;

esp_err_t face_init(void);
void face_set_state(face_state_t state);
void face_set_expression(const char *expression, float intensity);
void face_set_gaze(const char *gaze);
void face_set_chat(const char *speaker, const char *text);
void face_set_face_id(const char *face);
void face_play_heart(void);
void face_play_intro(void);
void face_force_blink(void);
void face_apply_unix_time(long unix_sec, const char *tz);
face_state_t face_current(void);

/* BLE companion status surface (SOW §4–§5). */
void face_set_ble_status(const char *label, const char *mood, const char *code);
void face_flash_ble_status(const char *label, const char *mood, int ms);
void face_set_ble_pip(bool connected);
void face_clear_ble_status(void);

/* Phone → desk display surfaces. */
void face_show_notify(const char *title, const char *body, const char *mood, int ttl_ms);
void face_clear_notify(void);
void face_set_calendar(const char *title, const char *when_label);
void face_clear_calendar(void);
void face_set_layout(bool eyes, const char *clock_place);
bool face_scenery_begin(int w, int h);
bool face_scenery_write(size_t offset, const uint8_t *data, size_t len);
void face_scenery_commit(void);
void face_scenery_clear(void);
