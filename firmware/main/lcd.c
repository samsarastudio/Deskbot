#include "lcd.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_types.h"
#include "esp_log.h"

#include "app_config.h"
#include "font5x7.h"
#include "pins.h"

static const char *TAG = "lcd";
static esp_lcd_panel_handle_t s_panel;
static uint16_t *s_fb;
static size_t s_fb_len;

static int clampi(int v, int lo, int hi)
{
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
}

static void backlight_init(void)
{
    ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_8_BIT,
        .timer_num = LEDC_TIMER_0,
        .freq_hz = 5000,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    ledc_channel_config_t channel = {
        .gpio_num = PIN_LCD_BL,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_0,
        .timer_sel = LEDC_TIMER_0,
        .duty = 128,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel));
}

esp_err_t lcd_init(void)
{
    gpio_config_t tf_cs = {
        .pin_bit_mask = 1ULL << PIN_TF_CS,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&tf_cs);
    gpio_set_level(PIN_TF_CS, 1);

    backlight_init();
    s_fb_len = DESKBOT_LCD_WIDTH * DESKBOT_LCD_HEIGHT * sizeof(uint16_t);
    s_fb = heap_caps_malloc(s_fb_len, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    if (!s_fb) {
        s_fb = heap_caps_malloc(s_fb_len, MALLOC_CAP_8BIT);
    }
    if (!s_fb) {
        ESP_LOGE(TAG, "framebuffer alloc failed (%u bytes)", (unsigned)s_fb_len);
        return ESP_ERR_NO_MEM;
    }

    spi_bus_config_t buscfg = {
        .sclk_io_num = PIN_SPI_SCLK,
        .mosi_io_num = PIN_SPI_MOSI,
        .miso_io_num = -1,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = DESKBOT_LCD_WIDTH * DESKBOT_LCD_HEIGHT * sizeof(uint16_t) + 8,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &buscfg, SPI_DMA_CH_AUTO));

    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = PIN_LCD_DC,
        .cs_gpio_num = PIN_LCD_CS,
        .pclk_hz = 80 * 1000 * 1000,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 16,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi(SPI2_HOST, &io_config, &io_handle));

    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = PIN_LCD_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .data_endian = LCD_RGB_DATA_ENDIAN_LITTLE,
        .bits_per_pixel = 16,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_st7789(io_handle, &panel_config, &s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_reset(s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_invert_color(s_panel, true));
    ESP_ERROR_CHECK(esp_lcd_panel_set_gap(s_panel, 0, 34));
    ESP_ERROR_CHECK(esp_lcd_panel_swap_xy(s_panel, true));
    ESP_ERROR_CHECK(esp_lcd_panel_mirror(s_panel, true, false));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(s_panel, true));

    lcd_fill(COL_BG);
    lcd_flush();
    lcd_heart_warmup();
    ESP_LOGI(TAG, "ST7789 landscape %dx%d framebuffer ready", DESKBOT_LCD_WIDTH, DESKBOT_LCD_HEIGHT);
    return ESP_OK;
}

void lcd_fill(uint16_t color)
{
    if (!s_fb) {
        return;
    }
    uint32_t pair = ((uint32_t)color << 16) | color;
    uint32_t *dst = (uint32_t *)s_fb;
    size_t n = (DESKBOT_LCD_WIDTH * DESKBOT_LCD_HEIGHT) / 2;
    for (size_t i = 0; i < n; i++) {
        dst[i] = pair;
    }
}

void lcd_fill_rect(int x, int y, int w, int h, uint16_t color)
{
    if (!s_fb || w <= 0 || h <= 0) {
        return;
    }
    int x0 = clampi(x, 0, DESKBOT_LCD_WIDTH);
    int y0 = clampi(y, 0, DESKBOT_LCD_HEIGHT);
    int x1 = clampi(x + w, 0, DESKBOT_LCD_WIDTH);
    int y1 = clampi(y + h, 0, DESKBOT_LCD_HEIGHT);
    if (x1 <= x0 || y1 <= y0) {
        return;
    }
    int width = x1 - x0;
    uint32_t pair = ((uint32_t)color << 16) | color;
    for (int row = y0; row < y1; row++) {
        uint16_t *dst = s_fb + row * DESKBOT_LCD_WIDTH + x0;
        int i = 0;
        if (((uintptr_t)dst & 3) == 0) {
            for (; i + 1 < width; i += 2) {
                *(uint32_t *)(dst + i) = pair;
            }
        }
        for (; i < width; i++) {
            dst[i] = color;
        }
    }
}

void lcd_fill_circle(int cx, int cy, int r, uint16_t color)
{
    if (r <= 0) {
        return;
    }
    for (int dy = -r; dy <= r; dy++) {
        int span = (int)sqrtf((float)(r * r - dy * dy));
        lcd_fill_rect(cx - span, cy + dy, span * 2 + 1, 1, color);
    }
}

void lcd_draw_ring(int cx, int cy, int r_outer, int r_inner, uint16_t color)
{
    lcd_fill_circle(cx, cy, r_outer, color);
    lcd_fill_circle(cx, cy, r_inner, COL_BG);
}

static inline uint16_t *fb_at(int x, int y)
{
    return s_fb + y * DESKBOT_LCD_WIDTH + x;
}

static void blend_pixel(int x, int y, uint16_t color, uint8_t alpha)
{
    if (!s_fb || alpha == 0) {
        return;
    }
    if ((unsigned)x >= (unsigned)DESKBOT_LCD_WIDTH || (unsigned)y >= (unsigned)DESKBOT_LCD_HEIGHT) {
        return;
    }
    uint16_t *dst = fb_at(x, y);
    if (alpha >= 250) {
        *dst = color;
        return;
    }
    uint16_t d = *dst;
    int dr = (d >> 11) & 31;
    int dg = (d >> 5) & 63;
    int db = d & 31;
    int cr = (color >> 11) & 31;
    int cg = (color >> 5) & 63;
    int cb = color & 31;
    int ia = 255 - alpha;
    int r = (cr * alpha + dr * ia + 127) / 255;
    int g = (cg * alpha + dg * ia + 127) / 255;
    int b = (cb * alpha + db * ia + 127) / 255;
    *dst = (uint16_t)((r << 11) | (g << 5) | b);
}

static uint8_t glow_alpha(float sd, float glow)
{
    if (sd <= 0.0f) {
        return 255;
    }
    if (glow <= 0.1f || sd >= glow) {
        return 0;
    }
    float t = 1.0f - sd / glow;
    t *= t;
    int a = (int)(t * 220.0f);
    if (a < 0) {
        return 0;
    }
    if (a > 220) {
        return 220;
    }
    return (uint8_t)a;
}

static float clampf(float v, float lo, float hi)
{
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
}

static float capsule_sd(float px, float py, float x0, float y0, float x1, float y1)
{
    float vx = x1 - x0;
    float vy = y1 - y0;
    float wx = px - x0;
    float wy = py - y0;
    float c2 = vx * vx + vy * vy;
    float t = (c2 > 0.001f) ? (wx * vx + wy * vy) / c2 : 0.0f;
    t = clampf(t, 0.0f, 1.0f);
    float dx = wx - vx * t;
    float dy = wy - vy * t;
    return sqrtf(dx * dx + dy * dy);
}

static void neon_field(int x0, int y0, int x1, int y1, float (*sd)(int, int, const void *), const void *ctx,
                       float glow, uint16_t core, uint16_t halo)
{
    x0 = clampi(x0, 0, DESKBOT_LCD_WIDTH);
    y0 = clampi(y0, 0, DESKBOT_LCD_HEIGHT);
    x1 = clampi(x1, 0, DESKBOT_LCD_WIDTH);
    y1 = clampi(y1, 0, DESKBOT_LCD_HEIGHT);
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            float d = sd(x, y, ctx);
            if (d <= 0.45f) {
                blend_pixel(x, y, core, 255);
            } else {
                uint8_t a = glow_alpha(d, glow);
                if (a) {
                    blend_pixel(x, y, halo, a);
                }
            }
        }
    }
}

typedef struct {
    float cx, cy, radius;
} disk_ctx_t;

static float sd_disk(int x, int y, const void *v)
{
    const disk_ctx_t *c = v;
    float dx = (x + 0.5f) - c->cx;
    float dy = (y + 0.5f) - c->cy;
    return sqrtf(dx * dx + dy * dy) - c->radius;
}

void lcd_neon_disk(float cx, float cy, float radius, float glow, uint16_t core, uint16_t halo)
{
    disk_ctx_t ctx = { cx, cy, radius };
    int pad = (int)(radius + glow + 2.0f);
    neon_field((int)cx - pad, (int)cy - pad, (int)cx + pad + 1, (int)cy + pad + 1, sd_disk, &ctx, glow, core, halo);
}

typedef struct {
    float x0, y0, x1, y1, radius;
} cap_ctx_t;

static float sd_cap(int x, int y, const void *v)
{
    const cap_ctx_t *c = v;
    return capsule_sd(x + 0.5f, y + 0.5f, c->x0, c->y0, c->x1, c->y1) - c->radius;
}

void lcd_neon_capsule(float x0, float y0, float x1, float y1, float radius, float glow, uint16_t core, uint16_t halo)
{
    cap_ctx_t ctx = { x0, y0, x1, y1, radius };
    int pad = (int)(radius + glow + 2.0f);
    int minx = (int)fminf(x0, x1) - pad;
    int miny = (int)fminf(y0, y1) - pad;
    int maxx = (int)fmaxf(x0, x1) + pad + 1;
    int maxy = (int)fmaxf(y0, y1) + pad + 1;
    neon_field(minx, miny, maxx, maxy, sd_cap, &ctx, glow, core, halo);
}

typedef struct {
    float cx, cy, rx, ry, stroke, y_min, y_max;
} ell_ctx_t;

static float sd_ell_ring(int x, int y, const void *v)
{
    const ell_ctx_t *c = v;
    float px = x + 0.5f;
    float py = y + 0.5f;
    if (py < c->y_min || py > c->y_max) {
        return 1000.0f;
    }
    float nx = (px - c->cx) / c->rx;
    float ny = (py - c->cy) / c->ry;
    float ell = sqrtf(nx * nx + ny * ny);
    float scale = 0.5f * (c->rx + c->ry);
    return fabsf(ell - 1.0f) * scale - c->stroke * 0.5f;
}

void lcd_neon_ellipse_ring(float cx, float cy, float rx, float ry, float stroke, float glow,
                           float y_min, float y_max, uint16_t core, uint16_t halo)
{
    ell_ctx_t ctx = { cx, cy, rx, ry, stroke, y_min, y_max };
    int pad = (int)(fmaxf(rx, ry) + glow + stroke + 2.0f);
    neon_field((int)cx - pad, (int)cy - pad, (int)cx + pad + 1, (int)cy + pad + 1, sd_ell_ring, &ctx, glow, core, halo);
}

typedef struct {
    float cx, cy, scale;
} heart_ctx_t;

static float sd_heart_unit(float x, float y)
{
    x = fabsf(x);
    if (x + y > 1.0f) {
        float dx = x - 0.25f;
        float dy = y - 0.75f;
        return sqrtf(dx * dx + dy * dy) - 0.35355339f;
    }
    float d1 = x * x + (y - 1.0f) * (y - 1.0f);
    float k = 0.5f * fmaxf(x + y, 0.0f);
    float d2 = (x - k) * (x - k) + (y - k) * (y - k);
    float d = sqrtf(fminf(d1, d2));
    return (x > y) ? d : -d;
}

static float sd_heart_px(int x, int y, const void *v)
{
    const heart_ctx_t *c = v;
    float u = ((x + 0.5f) - c->cx) / c->scale;
    float vup = (c->cy - (y + 0.5f)) / c->scale + 0.55f;
    return sd_heart_unit(u, vup) * c->scale;
}

void lcd_neon_heart(float cx, float cy, float size, float glow, uint16_t core, uint16_t halo)
{
    if (size < 1.5f) {
        lcd_neon_disk(cx, cy, fmaxf(size, 1.0f), glow, core, halo);
        return;
    }
    heart_ctx_t ctx = { cx, cy, size };
    int pad = (int)(size * 1.15f + glow + 4.0f);
    neon_field((int)cx - pad, (int)cy - pad, (int)cx + pad + 1, (int)cy + pad + 1, sd_heart_px, &ctx, glow, core, halo);
}

#define HEART_MASK 96

static uint8_t s_heart_mask[HEART_MASK * HEART_MASK];
static bool s_heart_ready;
static uint16_t s_lut[32];
static uint16_t s_lut_core;
static uint16_t s_lut_halo;

static uint16_t mix565(uint16_t a, uint16_t b, int t)
{
    int ar = (a >> 11) & 31, ag = (a >> 5) & 63, ab = a & 31;
    int br = (b >> 11) & 31, bg = (b >> 5) & 63, bb = b & 31;
    int r = (ar * (255 - t) + br * t) / 255;
    int g = (ag * (255 - t) + bg * t) / 255;
    int bl = (ab * (255 - t) + bb * t) / 255;
    return (uint16_t)((r << 11) | (g << 5) | bl);
}

void lcd_heart_warmup(void)
{
    if (s_heart_ready) {
        return;
    }
    const float glow = 0.22f;
    for (int y = 0; y < HEART_MASK; y++) {
        for (int x = 0; x < HEART_MASK; x++) {
            float u = (x + 0.5f) / HEART_MASK * 2.2f - 1.1f;
            float v = 1.15f - (y + 0.5f) / HEART_MASK * 1.9f;
            float sd = sd_heart_unit(u, v);
            uint8_t a = 0;
            if (sd <= 0.0f) {
                a = 255;
            } else if (sd < glow) {
                float t = 1.0f - sd / glow;
                a = (uint8_t)(t * t * 210.0f);
            }
            s_heart_mask[y * HEART_MASK + x] = a;
        }
    }
    s_heart_ready = true;
}

static void heart_lut(uint16_t core, uint16_t halo)
{
    if (core == s_lut_core && halo == s_lut_halo) {
        return;
    }
    s_lut_core = core;
    s_lut_halo = halo;
    for (int i = 0; i < 32; i++) {
        int a = i * 8 + 4;
        uint16_t c = (a >= 176) ? core : halo;
        s_lut[i] = mix565(COL_BG, c, a);
    }
}

void lcd_blit_heart(int cx, int cy, int w, int h, uint16_t core, uint16_t halo)
{
    if (w < 4 || h < 4 || !s_fb) {
        return;
    }
    lcd_heart_warmup();
    heart_lut(core, halo);
    int x0 = cx - w / 2;
    int y0 = cy - h / 2;
    int y_start = 0;
    int y_end = h;
    int x_start = 0;
    int x_end = w;
    if (y0 < 0) {
        y_start = -y0;
    }
    if (y0 + h > DESKBOT_LCD_HEIGHT) {
        y_end = DESKBOT_LCD_HEIGHT - y0;
    }
    if (x0 < 0) {
        x_start = -x0;
    }
    if (x0 + w > DESKBOT_LCD_WIDTH) {
        x_end = DESKBOT_LCD_WIDTH - x0;
    }
    if (y_start >= y_end || x_start >= x_end) {
        return;
    }
    for (int y = y_start; y < y_end; y++) {
        int sy = y * HEART_MASK / h;
        const uint8_t *src = s_heart_mask + sy * HEART_MASK;
        uint16_t *dst = s_fb + (y0 + y) * DESKBOT_LCD_WIDTH + x0;
        for (int x = x_start; x < x_end; x++) {
            uint8_t a = src[x * HEART_MASK / w];
            if (a) {
                dst[x] = s_lut[a >> 3];
            }
        }
    }
}

void lcd_spark(int cx, int cy, int r, uint16_t color)
{
    if (r < 1) {
        r = 1;
    }
    int r2 = r * r;
    for (int y = -r; y <= r; y++) {
        int fy = cy + y;
        if ((unsigned)fy >= (unsigned)DESKBOT_LCD_HEIGHT) {
            continue;
        }
        int yy = y * y;
        uint16_t *dst = s_fb + fy * DESKBOT_LCD_WIDTH;
        for (int x = -r; x <= r; x++) {
            int fx = cx + x;
            if ((unsigned)fx >= (unsigned)DESKBOT_LCD_WIDTH) {
                continue;
            }
            if (x * x + yy <= r2) {
                dst[fx] = color;
            }
        }
    }
}

void lcd_fill_round_rect(int x, int y, int w, int h, int r, uint16_t color)
{
    if (w <= 0 || h <= 0) {
        return;
    }
    if (r < 1) {
        lcd_fill_rect(x, y, w, h, color);
        return;
    }
    if (r * 2 > w) {
        r = w / 2;
    }
    if (r * 2 > h) {
        r = h / 2;
    }
    lcd_fill_rect(x + r, y, w - 2 * r, h, color);
    lcd_fill_rect(x, y + r, w, h - 2 * r, color);
    lcd_fill_circle(x + r, y + r, r, color);
    lcd_fill_circle(x + w - 1 - r, y + r, r, color);
    lcd_fill_circle(x + r, y + h - 1 - r, r, color);
    lcd_fill_circle(x + w - 1 - r, y + h - 1 - r, r, color);
}

void lcd_draw_text(int x, int y, int scale, uint16_t color, const char *text)
{
    lcd_draw_text_glow(x, y, scale, color, COL_HALO, text);
}

void lcd_draw_text_fast(int x, int y, int scale, uint16_t color, const char *text)
{
    if (!text || scale < 1 || !s_fb) {
        return;
    }
    int cx = x;
    for (const char *p = text; *p; p++) {
        unsigned ch = (unsigned char)(*p);
        if (ch < 32 || ch > 126) {
            cx += 6 * scale;
            continue;
        }
        unsigned idx = ch - 32;
        if (idx >= 96) {
            idx = 0;
        }
        for (int col = 0; col < 5; col++) {
            uint8_t bits = FONT5X7[idx][col];
            for (int row = 0; row < 7; row++) {
                if (!(bits & (1u << row))) {
                    continue;
                }
                int px = cx + col * scale;
                int py = y + row * scale;
                for (int sy = 0; sy < scale; sy++) {
                    int fy = py + sy;
                    if ((unsigned)fy >= (unsigned)DESKBOT_LCD_HEIGHT) {
                        continue;
                    }
                    uint16_t *dst = s_fb + fy * DESKBOT_LCD_WIDTH;
                    for (int sx = 0; sx < scale; sx++) {
                        int fx = px + sx;
                        if ((unsigned)fx < (unsigned)DESKBOT_LCD_WIDTH) {
                            dst[fx] = color;
                        }
                    }
                }
            }
        }
        cx += 6 * scale;
    }
}

void lcd_draw_text_glow(int x, int y, int scale, uint16_t core, uint16_t halo, const char *text)
{
    if (!text || scale < 1) {
        return;
    }
    int cx = x;
    for (const char *p = text; *p; p++) {
        unsigned idx = (unsigned char)(*p) - 32;
        if (idx >= 96) {
            idx = 0;
        }
        for (int col = 0; col < 5; col++) {
            uint8_t bits = FONT5X7[idx][col];
            for (int row = 0; row < 7; row++) {
                if (bits & (1u << row)) {
                    float px = cx + col * scale + scale * 0.5f;
                    float py = y + row * scale + scale * 0.5f;
                    lcd_neon_disk(px, py, scale * 0.42f, scale * 1.6f + 1.5f, core, halo);
                }
            }
        }
        cx += 6 * scale;
    }
}

int lcd_text_width(int scale, const char *text)
{
    if (!text) {
        return 0;
    }
    return (int)strlen(text) * 6 * scale;
}

#define CLOCK_DIGIT_W  22
#define CLOCK_DIGIT_H  38
#define CLOCK_THICK    2.6f
#define CLOCK_GLOW     6.5f
#define CLOCK_COLON_W  12
#define CLOCK_GAP      5

int lcd_clock_height(void)
{
    return CLOCK_DIGIT_H;
}

int lcd_clock_width(const char *text)
{
    if (!text || !text[0]) {
        return 0;
    }
    int width = 0;
    for (const char *p = text; *p; p++) {
        if (p != text) {
            width += CLOCK_GAP;
        }
        width += (*p == ':') ? CLOCK_COLON_W : CLOCK_DIGIT_W;
    }
    return width;
}

static void clock_seg_h(float x, float y, float w, uint16_t core, uint16_t halo)
{
    lcd_neon_capsule(x, y, x + w, y, CLOCK_THICK, CLOCK_GLOW, core, halo);
}

static void clock_seg_v(float x, float y, float h, uint16_t core, uint16_t halo)
{
    lcd_neon_capsule(x, y, x, y + h, CLOCK_THICK, CLOCK_GLOW, core, halo);
}

static void draw_clock_digit(int x, int y, char ch, uint16_t core, uint16_t halo)
{
    const float w = (float)CLOCK_DIGIT_W;
    const float h = (float)CLOCK_DIGIT_H;
    const float t = CLOCK_THICK;
    const float mid_y = y + h * 0.5f;
    const float x0 = x + t + 1.0f;
    const float x1 = x + w - t - 1.0f;
    const float y0 = y + t + 1.0f;
    const float y1 = y + h - t - 1.0f;

    if (ch == '-') {
        clock_seg_h(x0, mid_y, x1 - x0, core, halo);
        return;
    }
    if (ch == '1') {
        clock_seg_v(x + w * 0.55f, y0, y1 - y0, core, halo);
        return;
    }

    uint8_t mask = 0;
    switch (ch) {
    case '0': mask = 0x3F; break;
    case '2': mask = 0x5B; break;
    case '3': mask = 0x4F; break;
    case '4': mask = 0x66; break;
    case '5': mask = 0x6D; break;
    case '6': mask = 0x7D; break;
    case '7': mask = 0x07; break;
    case '8': mask = 0x7F; break;
    case '9': mask = 0x6F; break;
    default: return;
    }
    if (mask & 0x01) clock_seg_h(x0, (float)y + t, x1 - x0, core, halo);
    if (mask & 0x02) clock_seg_v(x + w - t, y0, mid_y - y0, core, halo);
    if (mask & 0x04) clock_seg_v(x + w - t, mid_y, y1 - mid_y, core, halo);
    if (mask & 0x08) clock_seg_h(x0, (float)y + h - t, x1 - x0, core, halo);
    if (mask & 0x10) clock_seg_v(x + t, mid_y, y1 - mid_y, core, halo);
    if (mask & 0x20) clock_seg_v(x + t, y0, mid_y - y0, core, halo);
    if (mask & 0x40) clock_seg_h(x0, mid_y, x1 - x0, core, halo);
}

void lcd_draw_clock(int x, int y, const char *text, uint16_t color)
{
    (void)color;
    if (!text) {
        return;
    }
    int cx = x;
    for (const char *p = text; *p; p++) {
        if (*p == ':') {
            lcd_neon_disk(cx + CLOCK_COLON_W / 2.0f, y + CLOCK_DIGIT_H * 0.32f, 2.2f, CLOCK_GLOW, COL_FACE, COL_ACCENT);
            lcd_neon_disk(cx + CLOCK_COLON_W / 2.0f, y + CLOCK_DIGIT_H * 0.68f, 2.2f, CLOCK_GLOW, COL_FACE, COL_ACCENT);
            cx += CLOCK_COLON_W + CLOCK_GAP;
            continue;
        }
        draw_clock_digit(cx, y, *p, COL_FACE, COL_ACCENT);
        cx += CLOCK_DIGIT_W + CLOCK_GAP;
    }
}

void lcd_flush_rect(int x, int y, int w, int h)
{
    if (!s_panel || !s_fb || w <= 0 || h <= 0) {
        return;
    }
    int x0 = clampi(x, 0, DESKBOT_LCD_WIDTH);
    int y0 = clampi(y, 0, DESKBOT_LCD_HEIGHT);
    int x1 = clampi(x + w, 0, DESKBOT_LCD_WIDTH);
    int y1 = clampi(y + h, 0, DESKBOT_LCD_HEIGHT);
    if (x1 <= x0 || y1 <= y0) {
        return;
    }
    /* Full-width rows are contiguous in the FB — one DMA transaction, one window set. */
    if (x0 == 0 && (x1 - x0) == DESKBOT_LCD_WIDTH) {
        esp_lcd_panel_draw_bitmap(s_panel, 0, y0, DESKBOT_LCD_WIDTH, y1, s_fb + y0 * DESKBOT_LCD_WIDTH);
        return;
    }
    for (int row = y0; row < y1; row++) {
        esp_lcd_panel_draw_bitmap(s_panel, x0, row, x1, row + 1, s_fb + row * DESKBOT_LCD_WIDTH + x0);
    }
}

void lcd_flush(void)
{
    lcd_flush_rect(0, 0, DESKBOT_LCD_WIDTH, DESKBOT_LCD_HEIGHT);
}
