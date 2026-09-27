#include "face.h"

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

#include "esp_log.h"
#include "esp_random.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "led_strip.h"

#include "app_config.h"
#include "demo_scenery.h"
#include "desk_persist.h"
#include "lcd.h"
#include "manga_boot.h"
#include "pins.h"

static const char *TAG = "face";
static led_strip_handle_t s_led;
static face_state_t s_state = FACE_OFFLINE;
static char s_expression[24] = "neutral";
static char s_gaze[12] = "user";
static bool s_blink;
static bool s_dirty = true;
static SemaphoreHandle_t s_lock;
static int64_t s_next_blink_us;
static bool s_heart;
static int64_t s_heart_t0;
static int64_t s_heart_last_us;
static bool s_intro;
static int64_t s_intro_t0;
static char s_chat_user[80];
static char s_chat_nova[192];
static char s_face_id[20] = "neutral_01";
static int64_t s_prompt_t0;
static bool s_ble_status;
static char s_ble_label[24];
static char s_ble_code[8];
static int64_t s_ble_flash_until;
static bool s_ble_pip;

/* Phone-mirrored surfaces */
static bool s_notify_on;
static char s_notify_title[28];
static char s_notify_body[96];
static int64_t s_notify_until;
static char s_cal_title[36];
static char s_cal_when[20];
static uint16_t *s_scenery;
static int s_scenery_w;
static int s_scenery_h;
static bool s_scenery_ready;
static bool s_scenery_loading;
static size_t s_scenery_bytes;
static bool s_eyes_on = true;
/* 0=off 1=center 2=top 3=bottom 4=left 5=right */
static int s_clock_place = 1;

/* Looped manga/GIF frame strip (RGB565 frames packed). */
#define ANIM_MAX_FRAMES 6
static uint16_t *s_anim;
static int s_anim_w;
static int s_anim_h;
static int s_anim_n;
static int s_anim_i;
static int s_anim_fps;
static bool s_anim_ready;
static bool s_anim_loading;
static size_t s_anim_frame_bytes;
static int64_t s_anim_next_us;

#define HEART_MS 2400
#define INTRO_MS 2200
#define PART_N 48

typedef struct {
    float x, y, vx, vy, age, life, r;
    uint8_t kind;
    bool alive;
} part_t;

static part_t s_parts[PART_N];

static float frand(void)
{
    return (esp_random() & 0xFFFF) / 65535.0f;
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

static void rgb(uint8_t r, uint8_t g, uint8_t b)
{
    if (!s_led) {
        return;
    }
    led_strip_set_pixel(s_led, 0, r, g, b);
    led_strip_refresh(s_led);
}

static const char *state_label(face_state_t state)
{
    if (state == FACE_OFFLINE) {
        return "OFFLINE";
    }
    if (state == FACE_SLEEP) {
        return "SLEEP";
    }
    return "NOVA";
}

static void ascii_clip(char *dst, size_t dst_len, const char *src)
{
    if (!dst || dst_len == 0) {
        return;
    }
    size_t o = 0;
    if (src) {
        for (const unsigned char *p = (const unsigned char *)src; *p && o + 1 < dst_len; p++) {
            if (*p >= 32 && *p <= 126) {
                dst[o++] = (char)*p;
            }
        }
    }
    dst[o] = 0;
}

static void spawn_particle(part_t *p, float cx, float cy, bool burst)
{
    float ang = -1.5708f + (frand() * 2.0f - 1.0f) * 1.85f;
    float spd = 70.0f + frand() * 110.0f;
    if (burst) {
        spd += 40.0f;
    }
    p->x = cx + (frand() * 180.0f - 90.0f);
    p->y = cy + (frand() * 50.0f - 16.0f);
    p->vx = cosf(ang) * spd;
    p->vy = sinf(ang) * spd;
    p->age = 0.0f;
    p->life = 0.55f + frand() * 0.65f;
    p->r = 1.5f + frand() * 3.2f;
    p->kind = (uint8_t)(esp_random() % 3);
    p->alive = true;
}

static void heart_reset_parts(float cx, float cy)
{
    for (int i = 0; i < PART_N; i++) {
        s_parts[i].alive = false;
        if (i < 18) {
            spawn_particle(&s_parts[i], cx, cy, true);
            s_parts[i].age = frand() * 0.05f;
        }
    }
}

static void update_particles(float dt, float cx, float cy, float t)
{
    for (int i = 0; i < PART_N; i++) {
        part_t *p = &s_parts[i];
        if (!p->alive) {
            if (t > 0.08f && t < 1.55f && frand() < 0.55f) {
                spawn_particle(p, cx, cy, false);
            }
            continue;
        }
        p->age += dt;
        p->vy += 95.0f * dt;
        p->vx *= (1.0f - 0.35f * dt);
        p->x += p->vx * dt;
        p->y += p->vy * dt;
        if (p->age >= p->life || p->y < -12.0f || p->y > DESKBOT_LCD_HEIGHT + 10) {
            p->alive = false;
        }
    }
}

static void draw_particles(void)
{
    for (int i = 0; i < PART_N; i++) {
        const part_t *p = &s_parts[i];
        if (!p->alive) {
            continue;
        }
        float fade = 1.0f - p->age / p->life;
        if (fade < 0.08f) {
            continue;
        }
        int x = (int)(p->x + 0.5f);
        int y = (int)(p->y + 0.5f);
        if (p->kind == 1) {
            int s = (int)(10.0f + fade * 14.0f);
            lcd_blit_heart(x, y, s, (s * 7) / 8, COL_HEART, COL_HEART_H);
        } else if (p->kind == 2) {
            int arm = 2 + (int)(fade * 3.0f);
            lcd_spark(x, y, 1, COL_GOLD);
            lcd_fill_rect(x - arm, y, arm * 2 + 1, 1, COL_GOLD);
            lcd_fill_rect(x, y - arm, 1, arm * 2 + 1, COL_GOLD);
        } else {
            lcd_spark(x, y, 1 + (int)(p->r * fade * 0.6f), fade > 0.5f ? COL_SPARK : COL_HEART_H);
        }
    }
}

static float heart_pop(float t)
{
    if (t < 0.04f) {
        return 0.0f;
    }
    if (t < 0.16f) {
        float u = (t - 0.04f) / 0.12f;
        u = u * u * (3.0f - 2.0f * u);
        return u * 1.12f;
    }
    if (t < 0.26f) {
        float u = (t - 0.16f) / 0.10f;
        return 1.12f - 0.12f * u;
    }
    if (t < 1.85f) {
        return 1.0f + 0.018f * sinf(t * 10.0f);
    }
    float u = clampf((t - 1.85f) / 0.55f, 0.0f, 1.0f);
    u = u * u;
    return 1.0f - u;
}

static void draw_heart_scene(float t, float dt)
{
    const float cx = DESKBOT_LCD_WIDTH * 0.5f;
    const float cy = DESKBOT_LCD_HEIGHT * 0.52f;
    lcd_fill(COL_BG);
    update_particles(dt, cx, cy, t);
    float pop = heart_pop(t);
    if (pop > 0.03f) {
        int w = (int)(318.0f * pop);
        int h = (int)(168.0f * pop);
        lcd_blit_heart((int)cx, (int)cy, w, h, COL_HEART, COL_HEART_H);
        lcd_blit_heart((int)cx, (int)cy - h / 8, w / 3, h / 3, COL_SPARK, COL_HEART);
    }
    draw_particles();
}

static void schedule_blink(void)
{
    uint32_t span = 2400 + (esp_random() % 4200);
    if (!strcmp(s_expression, "sleepy") || s_state == FACE_SLEEP) {
        span = 1600 + (esp_random() % 1800);
    }
    s_next_blink_us = esp_timer_get_time() + (int64_t)span * 1000;
}

static void lid_chord(float cx, float cy, float rx, float ry, float y, float stroke)
{
    float ny = (y - cy) / ry;
    float inside = 1.0f - ny * ny;
    if (inside < 0.04f) {
        return;
    }
    float hw = rx * sqrtf(inside);
    lcd_neon_capsule(cx - hw, y, cx + hw, y, stroke * 0.55f, 5.5f, COL_FACE, COL_ACCENT);
}

static void draw_brow(float cx, float cy, float ry, float dy, float rot_deg, float width)
{
    float rad = rot_deg * 0.01745329252f;
    float y = cy - ry - 14.0f + dy;
    float hx = (width * 0.5f) * cosf(rad);
    float hy = (width * 0.5f) * sinf(rad);
    lcd_neon_capsule(cx - hx, y - hy, cx + hx, y + hy, 2.1f, 6.0f, COL_FACE, COL_ACCENT);
}

static void draw_eye(int cx, int cy, bool left, int pupil_dx, int pupil_dy, bool blink)
{
    float rx = 26.0f;
    float ry = 26.0f;
    float top_lid = 0.0f;
    float bot_lid = 0.0f;
    float brow_dy = 0.0f;
    float brow_rot = 0.0f;
    float brow_w = 30.0f;
    float pupil_r = 6.2f;
    float stroke = 3.4f;

    if (!strcmp(s_expression, "happy") || !strcmp(s_expression, "amused")) {
        ry = !strcmp(s_expression, "amused") ? 13.0f : 17.0f;
        top_lid = 0.10f;
        bot_lid = 0.28f;
        brow_dy = -3.0f;
        brow_rot = left ? -8.0f : 8.0f;
        pupil_r = 5.0f;
    } else if (!strcmp(s_expression, "curious")) {
        if (left) {
            top_lid = 0.16f;
            brow_rot = -6.0f;
            brow_dy = 1.0f;
        } else {
            ry = 31.0f;
            top_lid = 0.0f;
            brow_rot = 18.0f;
            brow_dy = -9.0f;
            brow_w = 32.0f;
        }
    } else if (!strcmp(s_expression, "surprised")) {
        rx = 21.0f;
        ry = 34.0f;
        pupil_r = 8.0f;
        brow_dy = -11.0f;
        brow_w = 26.0f;
        stroke = 3.8f;
    } else if (!strcmp(s_expression, "excited")) {
        rx = 28.0f;
        ry = 28.0f;
        brow_dy = -6.0f;
        pupil_r = 7.0f;
    } else if (!strcmp(s_expression, "focused")) {
        ry = 20.0f;
        top_lid = 0.18f;
        brow_dy = 3.0f;
        brow_rot = left ? 10.0f : -10.0f;
        pupil_r = 4.5f;
    } else if (!strcmp(s_expression, "sleepy")) {
        ry = 11.0f;
        top_lid = 0.22f;
        bot_lid = 0.30f;
        brow_dy = 6.0f;
        pupil_r = 4.0f;
    } else if (!strcmp(s_expression, "confused")) {
        if (left) {
            brow_rot = -18.0f;
            brow_dy = -4.0f;
            top_lid = 0.08f;
        } else {
            brow_rot = 8.0f;
            top_lid = 0.18f;
        }
    } else if (!strcmp(s_expression, "skeptical")) {
        if (left) {
            ry = 24.0f;
        } else {
            top_lid = 0.38f;
            brow_rot = -14.0f;
            brow_dy = 5.0f;
            pupil_r = 4.5f;
        }
    } else if (!strcmp(s_expression, "sympathetic") || !strcmp(s_expression, "sad") || !strcmp(s_expression, "worried")) {
        brow_rot = left ? -12.0f : 12.0f;
        brow_dy = 2.0f;
        top_lid = 0.12f;
        bot_lid = 0.08f;
    } else if (!strcmp(s_expression, "thinking")) {
        brow_dy = -4.0f;
        pupil_r = 5.4f;
        top_lid = 0.06f;
    } else if (!strcmp(s_expression, "laughing") || !strcmp(s_expression, "celebrating")) {
        ry = 12.0f;
        top_lid = 0.18f;
        bot_lid = 0.34f;
        brow_dy = -5.0f;
        pupil_r = 4.2f;
    } else if (!strcmp(s_expression, "angry")) {
        ry = 18.0f;
        top_lid = 0.22f;
        brow_rot = left ? 16.0f : -16.0f;
        brow_dy = 4.0f;
        pupil_r = 4.0f;
    } else if (!strcmp(s_expression, "shy")) {
        ry = 18.0f;
        top_lid = 0.20f;
        brow_dy = 4.0f;
        pupil_r = 4.8f;
    } else if (!strcmp(s_expression, "proud")) {
        ry = 22.0f;
        brow_dy = -4.0f;
        pupil_r = 5.6f;
    } else if (!strcmp(s_expression, "love")) {
        ry = 24.0f;
        brow_dy = -3.0f;
        pupil_r = 0.0f;
    }

    if (blink || s_state == FACE_SLEEP) {
        top_lid = 0.46f;
        bot_lid = 0.46f;
        pupil_r = 0.0f;
    }

    float y_min = cy - ry + top_lid * 2.0f * ry;
    float y_max = cy + ry - bot_lid * 2.0f * ry;
    if (y_max < y_min + 3.0f) {
        float mid = (y_min + y_max) * 0.5f;
        y_min = mid - 1.5f;
        y_max = mid + 1.5f;
    }

    draw_brow((float)cx, (float)cy, ry, brow_dy, brow_rot, brow_w);
    lcd_neon_ellipse_ring((float)cx, (float)cy, rx, ry, stroke, 6.5f, y_min, y_max, COL_FACE, COL_ACCENT);
    lid_chord((float)cx, (float)cy, rx, ry, y_min, stroke);
    lid_chord((float)cx, (float)cy, rx, ry, y_max, stroke);
    if (pupil_r > 0.5f) {
        float py = clampf((float)(cy + pupil_dy), y_min + pupil_r, y_max - pupil_r);
        lcd_neon_disk((float)(cx + pupil_dx), py, pupil_r, 5.5f, COL_FACE, COL_ACCENT);
    } else if (!blink && s_state != FACE_SLEEP && !strcmp(s_expression, "love")) {
        lcd_blit_heart(cx + pupil_dx, cy + pupil_dy, 18, 16, COL_HEART, COL_HEART_H);
    }
}

static int mouth_smile(void)
{
    if (!strcmp(s_expression, "happy") || !strcmp(s_expression, "amused") ||
        !strcmp(s_expression, "excited") || !strcmp(s_expression, "laughing") ||
        !strcmp(s_expression, "proud") || !strcmp(s_expression, "celebrating") ||
        !strcmp(s_expression, "love")) {
        return 2;
    }
    if (!strcmp(s_expression, "surprised") || !strcmp(s_expression, "angry")) {
        return -1;
    }
    if (!strcmp(s_expression, "sympathetic") || !strcmp(s_expression, "sleepy") ||
        !strcmp(s_expression, "sad") || !strcmp(s_expression, "worried") ||
        !strcmp(s_expression, "shy")) {
        return -1;
    }
    if (!strcmp(s_expression, "confused") || !strcmp(s_expression, "skeptical")) {
        return 0;
    }
    return 0;
}

static void draw_mouth(void)
{
    float cx = DESKBOT_LCD_WIDTH / 2.0f;
    float cy = 130.0f;
    float w = 34.0f;
    int smile = mouth_smile();
    if (!strcmp(s_expression, "surprised")) {
        lcd_neon_ellipse_ring(cx, cy, 7.0f, 5.0f, 2.2f, 5.5f, cy - 8.0f, cy + 8.0f, COL_FACE, COL_ACCENT);
        return;
    }
    if (!strcmp(s_expression, "happy") || !strcmp(s_expression, "amused")) {
        w = 40.0f;
    }
    float lift = 5.0f * (float)smile;
    lcd_neon_capsule(cx - w * 0.5f, cy, cx, cy - lift, 2.0f, 6.0f, COL_FACE, COL_ACCENT);
    lcd_neon_capsule(cx, cy - lift, cx + w * 0.5f, cy, 2.0f, 6.0f, COL_FACE, COL_ACCENT);
}

static void smile_arc(int cx, int cy, int w, int h, uint16_t color, bool frown)
{
    for (int x = -w; x <= w; x++) {
        int y = (x * x * h) / (w * w + 1);
        /* y grows downward, so a smile is ∪ (center lower) and a frown is ∩. */
        int py = frown ? (cy + y) : (cy - y);
        lcd_fill_rect(cx + x, py, 2, 3, color);
    }
}

static void draw_smiley(void)
{
    const int cx = DESKBOT_LCD_WIDTH / 2;
    const int cy = 50;
    const int r = 28;
    uint16_t skin = COL_GOLD;
    uint16_t ink = COL_BG;
    if (!strcmp(s_expression, "love")) {
        skin = COL_HEART;
    } else if (!strcmp(s_expression, "sad") || !strcmp(s_expression, "worried") || !strcmp(s_expression, "shy")) {
        skin = RGB565(186, 210, 230);
    } else if (!strcmp(s_expression, "angry")) {
        skin = RGB565(255, 118, 88);
    } else if (!strcmp(s_expression, "sleepy")) {
        skin = RGB565(210, 214, 160);
    }

    lcd_fill_circle(cx, cy, r, skin);

    bool closed = !strcmp(s_expression, "laughing") || !strcmp(s_expression, "amused") ||
                  !strcmp(s_expression, "sleepy");
    bool hearts = !strcmp(s_expression, "love");
    bool surprise = !strcmp(s_expression, "surprised");
    bool sad = !strcmp(s_expression, "sad") || !strcmp(s_expression, "worried");
    bool angry = !strcmp(s_expression, "angry");
    bool curious = !strcmp(s_expression, "curious");

    if (hearts) {
        lcd_blit_heart(cx - 11, cy - 6, 14, 12, COL_SPARK, COL_FACE);
        lcd_blit_heart(cx + 11, cy - 6, 14, 12, COL_SPARK, COL_FACE);
    } else if (closed) {
        smile_arc(cx - 10, cy - 5, 6, 3, ink, false);
        smile_arc(cx + 10, cy - 5, 6, 3, ink, false);
    } else {
        int er = surprise ? 6 : 4;
        int ey = cy - 6;
        lcd_fill_circle(cx - 10, ey, er, ink);
        lcd_fill_circle(cx + (curious ? 12 : 10), ey - (curious ? 3 : 0), curious ? 5 : er, ink);
        if (surprise) {
            lcd_fill_circle(cx - 10, ey, 2, COL_FACE);
            lcd_fill_circle(cx + 10, ey, 2, COL_FACE);
        }
    }

    if (angry) {
        lcd_fill_rect(cx - 16, cy - 14, 10, 2, ink);
        lcd_fill_rect(cx + 6, cy - 14, 10, 2, ink);
    }

    if (surprise) {
        lcd_fill_circle(cx, cy + 10, 6, ink);
        lcd_fill_circle(cx, cy + 10, 3, skin);
    } else if (sad) {
        smile_arc(cx, cy + 12, 10, 5, ink, true);
    } else if (!strcmp(s_expression, "thinking") || !strcmp(s_expression, "focused")) {
        lcd_fill_rect(cx - 8, cy + 10, 16, 2, ink);
    } else {
        smile_arc(cx, cy + 9, 12, 6, ink, false);
    }
}

static void draw_centered_fast(int y, int scale, uint16_t color, const char *text)
{
    if (!text || !text[0]) {
        return;
    }
    int w = lcd_text_width(scale, text);
    int x = (DESKBOT_LCD_WIDTH - w) / 2;
    if (x < 4) {
        x = 4;
    }
    lcd_draw_text_fast(x, y, scale, color, text);
}

#define PROMPT_COLS 22
#define PROMPT_MAX_LINES 12
#define PROMPT_LINE_H 18
#define PROMPT_VIS 4

static int wrap_prompt(const char *text, char lines[][PROMPT_COLS + 1], int max_lines)
{
    int n = 0;
    int col = 0;
    lines[0][0] = 0;
    if (!text) {
        return 0;
    }
    for (const char *p = text; *p && n < max_lines; p++) {
        if (*p == '\n') {
            lines[n][col] = 0;
            n++;
            col = 0;
            if (n < max_lines) {
                lines[n][0] = 0;
            }
            continue;
        }
        if (*p == ' ' && col == 0) {
            continue;
        }
        if (col >= PROMPT_COLS) {
            lines[n][PROMPT_COLS] = 0;
            n++;
            col = 0;
            if (n >= max_lines) {
                break;
            }
            if (*p == ' ') {
                lines[n][0] = 0;
                continue;
            }
        }
        lines[n][col++] = *p;
        lines[n][col] = 0;
    }
    if (n < max_lines && lines[n][0]) {
        n++;
    }
    return n;
}

static bool prompt_active(void)
{
    if (s_ble_status) {
        if (s_ble_flash_until && esp_timer_get_time() > s_ble_flash_until) {
            s_ble_status = false;
            s_ble_flash_until = 0;
            s_ble_label[0] = 0;
            s_chat_nova[0] = 0;
        } else {
            return true;
        }
    }
    return s_intro || s_chat_nova[0] || s_chat_user[0];
}

static void draw_ble_pip(bool connected)
{
    int x = DESKBOT_LCD_WIDTH - 14;
    int y = 8;
    uint16_t c = connected ? COL_ACCENT : COL_DIM;
    lcd_fill_circle(x, y, 4, c);
}

static void draw_ambient_fluid(void);

/** Soft cyan-ice status screen — setup / linking / recovery. */
static void draw_ble_status_scene(void)
{
    float t = esp_timer_get_time() / 1000000.0f;
    float breath = 0.5f + 0.5f * sinf(t * 1.35f);
    float sway = sinf(t * 0.9f) * 3.0f;

    if (s_scenery_ready && s_scenery) {
        lcd_blit_scaled(s_scenery, s_scenery_w, s_scenery_h);
    } else {
        int bx = (int)(40 + sway * 2.0f);
        int by = (int)(30 + breath * 6.0f);
        lcd_fill_circle(bx, by, (int)(28 + breath * 4.0f), RGB565(18, 42, 58));
        lcd_fill_circle(DESKBOT_LCD_WIDTH - 36, DESKBOT_LCD_HEIGHT - 40,
                        (int)(34 + (1.0f - breath) * 5.0f), RGB565(28, 36, 22));
        lcd_fill_circle(DESKBOT_LCD_WIDTH / 2, DESKBOT_LCD_HEIGHT - 18,
                        (int)(22 + breath * 3.0f), RGB565(40, 24, 36));
    }

    /* Brand */
    draw_centered_fast(6, 1, COL_ACCENT, "NOVA");

    /* Floating soft face */
    draw_smiley();

    /* Glass panel for status */
    int panel_y = 96;
    int panel_h = s_ble_code[0] ? 68 : 44;
    lcd_fill_round_rect(14, panel_y, DESKBOT_LCD_WIDTH - 28, panel_h, 14, RGB565(16, 28, 40));
    lcd_fill_round_rect(16, panel_y + 2, DESKBOT_LCD_WIDTH - 32, panel_h - 4, 12, RGB565(20, 34, 48));

    const char *label = s_ble_label[0] ? s_ble_label : "…";
    draw_centered_fast(panel_y + 10, 2, COL_FACE, label);

    if (s_ble_code[0]) {
        /* Spaced gold code */
        char spaced[16];
        size_t n = 0;
        for (const char *p = s_ble_code; *p && n + 2 < sizeof(spaced); p++) {
            if (n) {
                spaced[n++] = ' ';
            }
            spaced[n++] = *p;
        }
        spaced[n] = 0;
        draw_centered_fast(panel_y + 34, 3, COL_GOLD, spaced);
    }

    /* Soft breath ring around bottom */
    int ring_r = (int)(6 + breath * 3.0f);
    lcd_draw_ring(DESKBOT_LCD_WIDTH / 2, DESKBOT_LCD_HEIGHT - 10, ring_r + 2, ring_r, COL_ACCENT);
}

static void draw_scenery_bg(void)
{
    if (s_anim_ready && s_anim && s_anim_n > 0) {
        const uint16_t *fr = s_anim + (size_t)s_anim_i * (size_t)s_anim_w * (size_t)s_anim_h;
        lcd_blit_scaled(fr, s_anim_w, s_anim_h);
        return;
    }
    if (!s_scenery_ready || !s_scenery || s_scenery_w < 2 || s_scenery_h < 2) {
        draw_ambient_fluid();
        return;
    }
    lcd_blit_scaled(s_scenery, s_scenery_w, s_scenery_h);
}

static void draw_notify_scene(void)
{
    /* Fast path: flat panel + text only (no neon face / scenery blit). */
    lcd_fill(COL_BG);
    lcd_fill_round_rect(8, 40, DESKBOT_LCD_WIDTH - 16, 100, 12, RGB565(14, 26, 38));
    lcd_fill_round_rect(10, 42, DESKBOT_LCD_WIDTH - 20, 96, 10, RGB565(18, 32, 46));
    draw_centered_fast(56, 1, COL_ACCENT, s_notify_title[0] ? s_notify_title : "Alert");
    draw_centered_fast(84, 2, COL_FACE, s_notify_body[0] ? s_notify_body : "");
}

static void draw_calendar_strip(void)
{
    if (!s_cal_title[0]) {
        return;
    }
    char line[56];
    if (s_cal_when[0]) {
        snprintf(line, sizeof(line), "%.12s  %.36s", s_cal_when, s_cal_title);
    } else {
        snprintf(line, sizeof(line), "%.48s", s_cal_title);
    }
    char clipped[40];
    ascii_clip(clipped, sizeof(clipped), line);
    int y = DESKBOT_LCD_HEIGHT - 18;
    lcd_fill_round_rect(8, y - 2, DESKBOT_LCD_WIDTH - 16, 16, 6, RGB565(14, 26, 38));
    draw_centered_fast(y, 1, COL_GOLD, clipped);
}

static void draw_teleprompter(void)
{
    uint16_t ink = COL_FACE;
    draw_smiley();

    const char *body = s_chat_nova[0] ? s_chat_nova : s_chat_user;
    if (s_intro && !s_chat_nova[0] && !s_ble_status) {
        body = "That's me!";
    }
    if (!body || !body[0]) {
        body = "hi!";
    }
    char lines[PROMPT_MAX_LINES][PROMPT_COLS + 1];
    int n = wrap_prompt(body, lines, PROMPT_MAX_LINES);
    if (n < 1) {
        draw_centered_fast(100, 2, ink, "hi!");
        return;
    }
    int vis = (n < PROMPT_VIS) ? n : PROMPT_VIS;
    int extra = n - vis;
    int off = 0;
    if (extra > 0) {
        float t = (esp_timer_get_time() - s_prompt_t0) / 1000000.0f;
        if (t < 0.0f) {
            t = 0.0f;
        }
        float pause = 0.8f;
        float travel = extra * 1.4f;
        float cycle = pause * 2.0f + travel;
        if (cycle < 1.0f) {
            cycle = 1.0f;
        }
        float u = t - cycle * (float)((int)(t / cycle));
        if (u < pause) {
            off = 0;
        } else if (u > pause + travel) {
            off = extra;
        } else {
            off = (int)((u - pause) / travel * (float)extra + 0.5f);
            if (off > extra) {
                off = extra;
            }
        }
    }
    int y0 = 88;
    for (int i = 0; i < vis; i++) {
        int idx = off + i;
        if (idx >= n) {
            break;
        }
        draw_centered_fast(y0 + i * PROMPT_LINE_H, 2, ink, lines[idx]);
    }
}

static void draw_ambient_fluid(void)
{
    float t = esp_timer_get_time() / 1000000.0f;
    float a = 0.5f + 0.5f * sinf(t * 0.85f);
    float b = 0.5f + 0.5f * sinf(t * 1.1f + 1.2f);
    lcd_fill_circle((int)(28 + a * 10.0f), (int)(24 + b * 8.0f),
                    (int)(22 + a * 4.0f), RGB565(14, 32, 44));
    lcd_fill_circle((int)(DESKBOT_LCD_WIDTH - 30 - b * 8.0f), (int)(48 + a * 10.0f),
                    (int)(26 + b * 5.0f), RGB565(22, 28, 18));
    lcd_fill_circle(DESKBOT_LCD_WIDTH / 2, DESKBOT_LCD_HEIGHT - 12,
                    (int)(18 + a * 3.0f), RGB565(30, 20, 34));
}

static void render_locked(void)
{
    lcd_fill(COL_BG);

    if (s_ble_status) {
        draw_ble_status_scene();
        return;
    }

    if (s_notify_on) {
        draw_notify_scene();
        return;
    }

    draw_scenery_bg();

    const char *label = state_label(s_state);
    if (prompt_active()) {
        draw_centered_fast(6, 1, COL_ACCENT, label);
        draw_teleprompter();
        draw_calendar_strip();
        return;
    }

    if (s_eyes_on) {
        int label_w = lcd_text_width(1, label);
        lcd_draw_text_glow((DESKBOT_LCD_WIDTH - label_w) / 2, 4, 1, COL_ACCENT, COL_HALO, label);
        draw_ble_pip(s_ble_pip);

        char emo[16];
        ascii_clip(emo, sizeof(emo), s_expression);
        for (char *p = emo; *p; p++) {
            if (*p >= 'a' && *p <= 'z') {
                *p = (char)(*p - 32);
            }
        }
        int emo_w = lcd_text_width(1, emo);
        lcd_draw_text_fast((DESKBOT_LCD_WIDTH - emo_w) / 2, 16, 1, COL_DIM, emo);

        int pupil_dx = 0;
        int pupil_dy = 0;
        if (!strcmp(s_gaze, "left")) pupil_dx = -7;
        else if (!strcmp(s_gaze, "right")) pupil_dx = 7;
        else if (!strcmp(s_gaze, "down") || !strcmp(s_expression, "shy")) pupil_dy = 6;
        if (!strcmp(s_expression, "thinking")) {
            pupil_dy = -7;
        }

        bool blink = s_blink;
        draw_eye(50, 90, true, pupil_dx, pupil_dy, blink);
        draw_eye(DESKBOT_LCD_WIDTH - 50, 90, false, pupil_dx, pupil_dy, blink);
        draw_mouth();
    } else {
        draw_ble_pip(s_ble_pip);
    }

    if (s_clock_place != 0) {
        time_t now = time(NULL);
        struct tm local;
        localtime_r(&now, &local);
        char clock[8];
        char ampm[4];
        int hour = local.tm_hour % 12;
        if (hour == 0) {
            hour = 12;
        }
        if (now < 1700000000) {
            snprintf(clock, sizeof(clock), "--:--");
            snprintf(ampm, sizeof(ampm), "  ");
        } else {
            snprintf(clock, sizeof(clock), "%d:%02d", hour, local.tm_min);
            snprintf(ampm, sizeof(ampm), "%s", local.tm_hour >= 12 ? "PM" : "AM");
        }
        int clock_w = lcd_clock_width(clock);
        int clock_h = lcd_clock_height();
        int clock_x = (DESKBOT_LCD_WIDTH - clock_w) / 2;
        int clock_y = 48;
        switch (s_clock_place) {
        case 2: /* top */
            clock_y = 6;
            break;
        case 3: /* bottom */
            clock_y = DESKBOT_LCD_HEIGHT - clock_h - 22;
            break;
        case 4: /* left */
            clock_x = 6;
            clock_y = (DESKBOT_LCD_HEIGHT - clock_h) / 2;
            break;
        case 5: /* right */
            clock_x = DESKBOT_LCD_WIDTH - clock_w - 6;
            clock_y = (DESKBOT_LCD_HEIGHT - clock_h) / 2;
            break;
        default: /* center */
            clock_y = s_eyes_on ? 48 : (DESKBOT_LCD_HEIGHT - clock_h) / 2;
            break;
        }
        lcd_draw_clock(clock_x, clock_y, clock, COL_FACE);
        int ampm_w = lcd_text_width(1, ampm);
        lcd_draw_text_glow(clock_x + (clock_w - ampm_w) / 2, clock_y + clock_h + 2, 1, COL_ACCENT, COL_HALO, ampm);
    }
    if (s_eyes_on || s_clock_place != 0) {
        draw_calendar_strip();
    }
}

static void flush_eyes(void)
{
    lcd_flush_rect(6, 36, 100, 120);
    lcd_flush_rect(DESKBOT_LCD_WIDTH - 106, 36, 100, 120);
}

static void present(bool full)
{
    int64_t now_us = esp_timer_get_time();
    if (s_intro && (now_us - s_intro_t0) >= (int64_t)INTRO_MS * 1000) {
        s_intro = false;
    }
    if (s_heart) {
        float t = (now_us - s_heart_t0) / 1000000.0f;
        if (t >= HEART_MS / 1000.0f) {
            s_heart = false;
            render_locked();
            rgb(0, 18, 22);
        } else {
            float dt = s_heart_last_us ? (now_us - s_heart_last_us) / 1000000.0f : 0.016f;
            if (dt < 0.008f) {
                dt = 0.016f;
            }
            if (dt > 0.05f) {
                dt = 0.033f;
            }
            s_heart_last_us = now_us;
            draw_heart_scene(t, dt);
        }
        lcd_flush();
        return;
    }
    render_locked();
    if (full) {
        lcd_flush();
    } else {
        flush_eyes();
    }
}

static void render_task(void *arg)
{
    (void)arg;
    schedule_blink();
    int last_minute = -1;
    TickType_t last_wake = xTaskGetTickCount();
    while (1) {
        int64_t now_us = esp_timer_get_time();
        time_t now = time(NULL);
        struct tm local;
        localtime_r(&now, &local);
        int minute_key = (now < 1700000000) ? -2 : (local.tm_hour * 60 + local.tm_min);

        xSemaphoreTake(s_lock, portMAX_DELAY);
        bool heart = s_heart;
        bool prompting = prompt_active();
        bool ble_ui = s_ble_status;
        bool notify_ui = s_notify_on;
        if (notify_ui && s_notify_until > 0 && now_us >= s_notify_until) {
            s_notify_on = false;
            s_notify_title[0] = 0;
            s_notify_body[0] = 0;
            s_notify_until = 0;
            notify_ui = false;
            s_dirty = true;
        }
        if (s_anim_ready && s_anim_n > 1 && now_us >= s_anim_next_us) {
            s_anim_i = (s_anim_i + 1) % s_anim_n;
            int fps = s_anim_fps > 0 ? s_anim_fps : 8;
            s_anim_next_us = now_us + 1000000 / fps;
            s_dirty = true;
        }
        bool want_blink = s_eyes_on && !heart && !prompting && !ble_ui && !notify_ui && (now_us >= s_next_blink_us) && (s_state != FACE_SLEEP);
        /* Notify is static — only redraw when dirty, never in an animation loop. */
        bool full = s_dirty || (minute_key != last_minute) || heart || ble_ui;
        if (prompting && !full && !ble_ui) {
            static int64_t last_prompt_us;
            if (now_us - last_prompt_us > 220000) {
                full = true;
                last_prompt_us = now_us;
            }
        }
        if (ble_ui) {
            static int64_t last_ble_us;
            if (now_us - last_ble_us > 200000) { /* ~5fps setup UI */
                full = true;
                last_ble_us = now_us;
            }
        } else if (!heart && !prompting && !notify_ui && !s_scenery_ready) {
            static int64_t last_ambient_us;
            if (now_us - last_ambient_us > 3000000) {
                full = true;
                last_ambient_us = now_us;
            }
        }
        if (full) {
            s_blink = false;
            present(true);
            s_dirty = false;
            last_minute = minute_key;
        }
        if (want_blink) {
            s_blink = true;
            present(false);
            xSemaphoreGive(s_lock);
            vTaskDelay(pdMS_TO_TICKS(100));
            xSemaphoreTake(s_lock, portMAX_DELAY);
            s_blink = false;
            present(false);
            schedule_blink();
        }
        xSemaphoreGive(s_lock);
        if (heart) {
            vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(40));
        } else if (ble_ui) {
            last_wake = xTaskGetTickCount();
            vTaskDelay(pdMS_TO_TICKS(120));
        } else if (prompting) {
            last_wake = xTaskGetTickCount();
            vTaskDelay(pdMS_TO_TICKS(150));
        } else if (s_anim_ready) {
            last_wake = xTaskGetTickCount();
            vTaskDelay(pdMS_TO_TICKS(80));
        } else {
            last_wake = xTaskGetTickCount();
            vTaskDelay(pdMS_TO_TICKS(200));
        }
    }
}

esp_err_t face_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    led_strip_config_t strip_config = {
        .strip_gpio_num = PIN_RGB,
        .max_leds = 1,
    };
    led_strip_rmt_config_t rmt_config = {
        .resolution_hz = 10 * 1000 * 1000,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &s_led));
    ESP_ERROR_CHECK(lcd_init());
    setenv("TZ", "EST5EDT,M3.2.0,M11.1.0", 1);
    tzset();
    s_state = FACE_OFFLINE;
    rgb(12, 4, 0);

    /* Cinema mode: latest LTX Comfy clip, no eyes / no clock. */
    s_eyes_on = false;
    s_clock_place = 0;
    desk_persist_save_layout(false, 0);

    size_t anim_bytes = sizeof(MANGA_BOOT_PIX);
    free(s_anim);
    s_anim = (uint16_t *)malloc(anim_bytes);
    if (s_anim) {
        memcpy(s_anim, MANGA_BOOT_PIX, anim_bytes);
        s_anim_w = MANGA_BOOT_W;
        s_anim_h = MANGA_BOOT_H;
        s_anim_n = MANGA_BOOT_FRAMES;
        s_anim_fps = MANGA_BOOT_FPS;
        s_anim_frame_bytes = (size_t)MANGA_BOOT_W * (size_t)MANGA_BOOT_H * sizeof(uint16_t);
        s_anim_i = 0;
        s_anim_ready = true;
        s_anim_loading = false;
        s_anim_next_us = esp_timer_get_time();
        s_scenery_ready = false;
        desk_persist_save_anim(s_anim, s_anim_w, s_anim_h, s_anim_n, s_anim_fps);
        ESP_LOGI(TAG, "boot LTX kamehameha %dx%d x%d", s_anim_w, s_anim_h, s_anim_n);
    }

    xTaskCreate(render_task, "face", 10240, NULL, 6, NULL);
    ESP_LOGI(TAG, "LCD face + RGB ready");
    return ESP_OK;
}

void face_set_state(face_state_t state)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_state = state;
    s_dirty = true;
    xSemaphoreGive(s_lock);
    switch (state) {
    case FACE_SLEEP:     rgb(2, 2, 8); break;
    case FACE_IDLE:      rgb(0, 18, 22); break;
    case FACE_WAKE:      rgb(20, 40, 12); break;
    case FACE_LISTENING: rgb(8, 40, 48); break;
    case FACE_THINKING:  rgb(40, 24, 8); break;
    case FACE_SPEAKING:  rgb(16, 48, 20); break;
    case FACE_HAPPY:     rgb(48, 36, 8); break;
    case FACE_CONFUSED:  rgb(40, 12, 40); break;
    case FACE_WARNING:   rgb(48, 8, 0); break;
    case FACE_OFFLINE:   rgb(12, 4, 0); break;
    }
}

void face_set_expression(const char *expression, float intensity)
{
    (void)intensity;
    if (!expression) {
        return;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    strlcpy(s_expression, expression, sizeof(s_expression));
    s_dirty = true;
    xSemaphoreGive(s_lock);
    if (!strcmp(expression, "happy") || !strcmp(expression, "amused") ||
        !strcmp(expression, "excited") || !strcmp(expression, "laughing") ||
        !strcmp(expression, "proud") || !strcmp(expression, "celebrating")) {
        face_set_state(FACE_HAPPY);
    } else if (!strcmp(expression, "confused") || !strcmp(expression, "skeptical") ||
               !strcmp(expression, "worried") || !strcmp(expression, "angry")) {
        face_set_state(FACE_CONFUSED);
    } else if (!strcmp(expression, "focused") || !strcmp(expression, "curious") ||
               !strcmp(expression, "surprised") || !strcmp(expression, "thinking")) {
        face_set_state(FACE_THINKING);
    }
}

void face_set_gaze(const char *gaze)
{
    if (!gaze) {
        return;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    strlcpy(s_gaze, gaze, sizeof(s_gaze));
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_set_chat(const char *speaker, const char *text)
{
    char clipped[192];
    ascii_clip(clipped, sizeof(clipped), text ? text : "");
    bool user = speaker && (!strcmp(speaker, "user") || !strcmp(speaker, "you"));
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (user) {
        strlcpy(s_chat_user, clipped, sizeof(s_chat_user));
    } else {
        strlcpy(s_chat_nova, clipped, sizeof(s_chat_nova));
    }
    s_prompt_t0 = esp_timer_get_time();
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_set_face_id(const char *face)
{
    if (!face || !face[0]) {
        return;
    }
    ascii_clip(s_face_id, sizeof(s_face_id), face);
    char emotion[24];
    strlcpy(emotion, s_face_id, sizeof(emotion));
    char *us = strchr(emotion, '_');
    if (us) {
        *us = 0;
    }
    if (emotion[0]) {
        face_set_expression(emotion, 0.7f);
    }
}

void face_play_intro(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_intro = true;
    s_intro_t0 = esp_timer_get_time();
    s_prompt_t0 = s_intro_t0;
    strlcpy(s_chat_nova, "That's me!", sizeof(s_chat_nova));
    s_dirty = true;
    xSemaphoreGive(s_lock);
    face_set_expression("happy", 0.9f);
}

void face_force_blink(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_blink = true;
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_play_heart(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_heart = true;
    s_heart_t0 = esp_timer_get_time();
    s_heart_last_us = 0;
    s_dirty = true;
    heart_reset_parts(DESKBOT_LCD_WIDTH * 0.5f, DESKBOT_LCD_HEIGHT * 0.52f);
    xSemaphoreGive(s_lock);
    rgb(48, 6, 18);
}

void face_apply_unix_time(long unix_sec, const char *tz)
{
    struct timeval tv = { .tv_sec = unix_sec, .tv_usec = 0 };
    settimeofday(&tv, NULL);
    if (tz && tz[0]) {
        setenv("TZ", tz, 1);
        tzset();
    }
    s_dirty = true;
}

face_state_t face_current(void)
{
    return s_state;
}

void face_clear_ble_status(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_ble_status = false;
    s_ble_flash_until = 0;
    s_ble_label[0] = 0;
    s_ble_code[0] = 0;
    s_chat_nova[0] = 0;
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_set_ble_status(const char *label, const char *mood, const char *code)
{
    if (!label && !mood && !code) {
        face_clear_ble_status();
        return;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_ble_status = true;
    s_ble_flash_until = 0;
    if (label) {
        ascii_clip(s_ble_label, sizeof(s_ble_label), label);
        ascii_clip(s_chat_nova, sizeof(s_chat_nova), label);
    }
    if (code) {
        ascii_clip(s_ble_code, sizeof(s_ble_code), code);
    } else {
        s_ble_code[0] = 0;
    }
    s_prompt_t0 = esp_timer_get_time();
    s_dirty = true;
    xSemaphoreGive(s_lock);
    if (mood) {
        face_set_expression(mood, 0.85f);
    }
}

void face_flash_ble_status(const char *label, const char *mood, int ms)
{
    face_set_ble_status(label, mood, NULL);
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_ble_flash_until = esp_timer_get_time() + (int64_t)ms * 1000;
    xSemaphoreGive(s_lock);
}

void face_set_ble_pip(bool connected)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_ble_pip = connected;
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_show_notify(const char *title, const char *body, const char *mood, int ttl_ms)
{
    (void)mood; /* keep expression stable — mood changes force heavy redraws */
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_notify_on = true;
    ascii_clip(s_notify_title, sizeof(s_notify_title), title ? title : "Alert");
    ascii_clip(s_notify_body, sizeof(s_notify_body), body ? body : "");
    if (ttl_ms <= 0) {
        ttl_ms = 5000;
    }
    s_notify_until = esp_timer_get_time() + (int64_t)ttl_ms * 1000;
    s_dirty = true;
    xSemaphoreGive(s_lock);
    rgb(16, 28, 40);
}

void face_clear_notify(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_notify_on = false;
    s_notify_title[0] = 0;
    s_notify_body[0] = 0;
    s_notify_until = 0;
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_set_calendar(const char *title, const char *when_label)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    ascii_clip(s_cal_title, sizeof(s_cal_title), title ? title : "");
    ascii_clip(s_cal_when, sizeof(s_cal_when), when_label ? when_label : "");
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_clear_calendar(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_cal_title[0] = 0;
    s_cal_when[0] = 0;
    s_dirty = true;
    xSemaphoreGive(s_lock);
}

void face_set_layout(bool eyes, const char *clock_place)
{
    int place = 1;
    if (clock_place) {
        if (!strcmp(clock_place, "off") || !strcmp(clock_place, "none")) {
            place = 0;
        } else if (!strcmp(clock_place, "top")) {
            place = 2;
        } else if (!strcmp(clock_place, "bottom")) {
            place = 3;
        } else if (!strcmp(clock_place, "left")) {
            place = 4;
        } else if (!strcmp(clock_place, "right")) {
            place = 5;
        } else {
            place = 1; /* center */
        }
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_eyes_on = eyes;
    s_clock_place = place;
    s_dirty = true;
    xSemaphoreGive(s_lock);
    desk_persist_save_layout(eyes, place);
    ESP_LOGI(TAG, "layout eyes=%d clock=%d (saved)", eyes ? 1 : 0, place);
}

bool face_scenery_begin(int w, int h)
{
    /* Half-LCD photo max (160×86 ≈ 27KB). Single buffer only. */
    if (w < 8 || h < 8 || w > 160 || h > 86) {
        ESP_LOGW(TAG, "scenery size rejected %dx%d", w, h);
        return false;
    }
    size_t bytes = (size_t)w * (size_t)h * sizeof(uint16_t);
    xSemaphoreTake(s_lock, portMAX_DELAY);
    free(s_scenery);
    s_scenery = NULL;
    s_scenery_ready = false;
    s_scenery_loading = false;
    s_scenery = (uint16_t *)malloc(bytes);
    if (!s_scenery) {
        ESP_LOGE(TAG, "scenery alloc %u failed (free=%u)", (unsigned)bytes,
                 (unsigned)esp_get_free_heap_size());
        s_scenery_w = 0;
        s_scenery_h = 0;
        s_scenery_bytes = 0;
        xSemaphoreGive(s_lock);
        return false;
    }
    memset(s_scenery, 0, bytes);
    s_scenery_w = w;
    s_scenery_h = h;
    s_scenery_bytes = bytes;
    s_scenery_loading = true;
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "scenery begin %dx%d (%u bytes, free=%u)", w, h, (unsigned)bytes,
             (unsigned)esp_get_free_heap_size());
    return true;
}

bool face_scenery_write(size_t offset, const uint8_t *data, size_t len)
{
    if (!data || len == 0) {
        return false;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_scenery || !s_scenery_loading || offset + len > s_scenery_bytes) {
        xSemaphoreGive(s_lock);
        return false;
    }
    memcpy(((uint8_t *)s_scenery) + offset, data, len);
    xSemaphoreGive(s_lock);
    return true;
}

void face_scenery_commit(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_scenery || !s_scenery_loading || s_scenery_w < 1) {
        xSemaphoreGive(s_lock);
        ESP_LOGW(TAG, "scenery commit with nothing loaded");
        return;
    }
    s_scenery_loading = false;
    s_scenery_ready = true;
    s_dirty = true;
    int w = s_scenery_w;
    int h = s_scenery_h;
    uint16_t *pix = s_scenery;
    xSemaphoreGive(s_lock);
    desk_persist_save_scenery(pix, w, h);
    ESP_LOGI(TAG, "scenery ready %dx%d (saved)", w, h);
}

void face_scenery_clear(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    free(s_scenery);
    s_scenery = NULL;
    s_scenery_w = 0;
    s_scenery_h = 0;
    s_scenery_bytes = 0;
    s_scenery_ready = false;
    s_scenery_loading = false;
    s_dirty = true;
    xSemaphoreGive(s_lock);
    desk_persist_clear_scenery();
}

bool face_anim_begin(int w, int h, int frames, int fps)
{
    if (w < 8 || h < 8 || w > 96 || h > 52 || frames < 1 || frames > ANIM_MAX_FRAMES) {
        ESP_LOGW(TAG, "anim rejected %dx%d x%d", w, h, frames);
        return false;
    }
    size_t frame_bytes = (size_t)w * (size_t)h * sizeof(uint16_t);
    size_t total = frame_bytes * (size_t)frames;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    free(s_anim);
    s_anim = (uint16_t *)malloc(total);
    if (!s_anim) {
        ESP_LOGE(TAG, "anim alloc %u failed free=%u", (unsigned)total, (unsigned)esp_get_free_heap_size());
        s_anim_loading = false;
        s_anim_ready = false;
        xSemaphoreGive(s_lock);
        return false;
    }
    memset(s_anim, 0, total);
    s_anim_w = w;
    s_anim_h = h;
    s_anim_n = frames;
    s_anim_fps = fps > 0 ? fps : 8;
    s_anim_i = 0;
    s_anim_frame_bytes = frame_bytes;
    s_anim_loading = true;
    s_anim_ready = false;
    /* Prefer anim over still scenery while loading. */
    s_scenery_ready = false;
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "anim begin %dx%d x%d @%dfps", w, h, frames, s_anim_fps);
    return true;
}

bool face_anim_write_frame(int frame_index, size_t offset, const uint8_t *data, size_t len)
{
    if (!data || len == 0 || frame_index < 0) {
        return false;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_anim || !s_anim_loading || frame_index >= s_anim_n ||
        offset + len > s_anim_frame_bytes) {
        xSemaphoreGive(s_lock);
        return false;
    }
    uint8_t *dst = ((uint8_t *)s_anim) + (size_t)frame_index * s_anim_frame_bytes + offset;
    memcpy(dst, data, len);
    xSemaphoreGive(s_lock);
    return true;
}

void face_anim_commit(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_anim || !s_anim_loading || s_anim_n < 1) {
        xSemaphoreGive(s_lock);
        return;
    }
    s_anim_loading = false;
    s_anim_ready = true;
    s_anim_i = 0;
    s_anim_next_us = esp_timer_get_time();
    s_dirty = true;
    int w = s_anim_w, h = s_anim_h, n = s_anim_n, fps = s_anim_fps;
    uint16_t *pix = s_anim;
    xSemaphoreGive(s_lock);
    desk_persist_save_anim(pix, w, h, n, fps);
    ESP_LOGI(TAG, "anim ready %dx%d x%d", w, h, n);
}

void face_anim_clear(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    free(s_anim);
    s_anim = NULL;
    s_anim_w = s_anim_h = s_anim_n = 0;
    s_anim_ready = false;
    s_anim_loading = false;
    s_dirty = true;
    xSemaphoreGive(s_lock);
    desk_persist_clear_anim();
}
