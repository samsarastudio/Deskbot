#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

esp_err_t desk_persist_init(void);

esp_err_t desk_persist_save_layout(bool eyes, int clock_place);
esp_err_t desk_persist_load_layout(bool *eyes, int *clock_place);

esp_err_t desk_persist_save_scenery(const uint16_t *pix, int w, int h);
esp_err_t desk_persist_load_scenery(uint16_t **out_pix, int *out_w, int *out_h);
esp_err_t desk_persist_clear_scenery(void);
bool desk_persist_has_scenery(void);

esp_err_t desk_persist_save_anim(const uint16_t *pix, int w, int h, int frames, int fps);
esp_err_t desk_persist_load_anim(uint16_t **out_pix, int *out_w, int *out_h, int *out_frames, int *out_fps);
esp_err_t desk_persist_clear_anim(void);
