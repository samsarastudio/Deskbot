#pragma once

#include <stdint.h>
#include "esp_err.h"

esp_err_t lcd_init(void);
void lcd_fill(uint16_t color);
void lcd_fill_rect(int x, int y, int w, int h, uint16_t color);
void lcd_fill_circle(int cx, int cy, int r, uint16_t color);
void lcd_fill_round_rect(int x, int y, int w, int h, int r, uint16_t color);
void lcd_draw_ring(int cx, int cy, int r_outer, int r_inner, uint16_t color);
void lcd_draw_text(int x, int y, int scale, uint16_t color, const char *text);
void lcd_draw_text_glow(int x, int y, int scale, uint16_t core, uint16_t halo, const char *text);
void lcd_draw_text_fast(int x, int y, int scale, uint16_t color, const char *text);
int lcd_text_width(int scale, const char *text);
void lcd_draw_clock(int x, int y, const char *text, uint16_t color);
int lcd_clock_width(const char *text);
int lcd_clock_height(void);
void lcd_neon_disk(float cx, float cy, float radius, float glow, uint16_t core, uint16_t halo);
void lcd_neon_capsule(float x0, float y0, float x1, float y1, float radius, float glow, uint16_t core, uint16_t halo);
void lcd_neon_ellipse_ring(float cx, float cy, float rx, float ry, float stroke, float glow,
                           float y_min, float y_max, uint16_t core, uint16_t halo);
void lcd_neon_heart(float cx, float cy, float size, float glow, uint16_t core, uint16_t halo);
void lcd_blit_heart(int cx, int cy, int w, int h, uint16_t core, uint16_t halo);
void lcd_blit_scaled(const uint16_t *src, int sw, int sh);
void lcd_spark(int cx, int cy, int r, uint16_t color);
void lcd_heart_warmup(void);
void lcd_flush(void);
void lcd_flush_rect(int x, int y, int w, int h);

#define RGB565(r, g, b) ((uint16_t)(((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3))))
#define COL_BG      RGB565(7, 16, 24)
#define COL_FACE    RGB565(230, 251, 255)
#define COL_ACCENT  RGB565(110, 231, 255)
#define COL_HALO    RGB565(70, 180, 220)
#define COL_DIM     RGB565(40, 70, 88)
#define COL_HEART   RGB565(255, 55, 110)
#define COL_HEART_H RGB565(255, 90, 150)
#define COL_SPARK   RGB565(255, 230, 245)
#define COL_GOLD    RGB565(255, 214, 130)
