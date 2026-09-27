#pragma once

#include "esp_err.h"

esp_err_t motion_init(void);
void motion_set_joint(const char *joint, float angle, int speed);
void motion_cancel(void);
void motion_neutral(void);
