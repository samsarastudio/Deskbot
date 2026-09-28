#include "desk_persist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "esp_log.h"
#include "esp_spiffs.h"
#include "nvs.h"

static const char *TAG = "persist";
static bool s_fs_ok;

#define SCENERY_MAGIC 0x5C31

typedef struct __attribute__((packed)) {
    uint16_t magic;
    uint16_t w;
    uint16_t h;
    uint16_t reserved;
} scenery_hdr_t;

esp_err_t desk_persist_init(void)
{
    esp_vfs_spiffs_conf_t conf = {
        .base_path = "/spiffs",
        .partition_label = "storage",
        .max_files = 4,
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "SPIFFS mount failed: %s", esp_err_to_name(err));
        s_fs_ok = false;
        return err;
    }
    s_fs_ok = true;
    size_t total = 0, used = 0;
    if (esp_spiffs_info("storage", &total, &used) == ESP_OK) {
        ESP_LOGI(TAG, "SPIFFS total=%u used=%u", (unsigned)total, (unsigned)used);
    }
    return ESP_OK;
}

esp_err_t desk_persist_save_layout(bool eyes, int clock_place)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open("deskbot", NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    nvs_set_u8(h, "lay_eyes", eyes ? 1 : 0);
    nvs_set_u8(h, "lay_clock", (uint8_t)clock_place);
    err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t desk_persist_load_layout(bool *eyes, int *clock_place)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open("deskbot", NVS_READONLY, &h);
    if (err != ESP_OK) {
        return err;
    }
    uint8_t e = 1;
    uint8_t c = 1;
    nvs_get_u8(h, "lay_eyes", &e);
    nvs_get_u8(h, "lay_clock", &c);
    nvs_close(h);
    if (eyes) {
        *eyes = e != 0;
    }
    if (clock_place) {
        *clock_place = (int)c;
    }
    return ESP_OK;
}

esp_err_t desk_persist_save_scenery(const uint16_t *pix, int w, int h)
{
    if (!s_fs_ok || !pix || w < 1 || h < 1) {
        return ESP_ERR_INVALID_STATE;
    }
    FILE *f = fopen("/spiffs/scenery.bin", "wb");
    if (!f) {
        ESP_LOGE(TAG, "open scenery for write failed");
        return ESP_FAIL;
    }
    scenery_hdr_t hdr = {
        .magic = SCENERY_MAGIC,
        .w = (uint16_t)w,
        .h = (uint16_t)h,
        .reserved = 0,
    };
    size_t bytes = (size_t)w * (size_t)h * sizeof(uint16_t);
    bool ok = fwrite(&hdr, sizeof(hdr), 1, f) == 1 && fwrite(pix, 1, bytes, f) == bytes;
    fclose(f);
    if (!ok) {
        remove("/spiffs/scenery.bin");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "saved scenery %dx%d (%u bytes)", w, h, (unsigned)bytes);
    return ESP_OK;
}

esp_err_t desk_persist_load_scenery(uint16_t **out_pix, int *out_w, int *out_h)
{
    if (!s_fs_ok || !out_pix) {
        return ESP_ERR_INVALID_STATE;
    }
    *out_pix = NULL;
    FILE *f = fopen("/spiffs/scenery.bin", "rb");
    if (!f) {
        return ESP_ERR_NOT_FOUND;
    }
    scenery_hdr_t hdr;
    if (fread(&hdr, sizeof(hdr), 1, f) != 1 || hdr.magic != SCENERY_MAGIC ||
        hdr.w < 8 || hdr.h < 8 || hdr.w > 160 || hdr.h > 86) {
        fclose(f);
        return ESP_ERR_INVALID_SIZE;
    }
    size_t bytes = (size_t)hdr.w * (size_t)hdr.h * sizeof(uint16_t);
    uint16_t *buf = (uint16_t *)malloc(bytes);
    if (!buf) {
        fclose(f);
        return ESP_ERR_NO_MEM;
    }
    if (fread(buf, 1, bytes, f) != bytes) {
        free(buf);
        fclose(f);
        return ESP_FAIL;
    }
    fclose(f);
    *out_pix = buf;
    if (out_w) {
        *out_w = hdr.w;
    }
    if (out_h) {
        *out_h = hdr.h;
    }
    ESP_LOGI(TAG, "loaded scenery %dx%d", hdr.w, hdr.h);
    return ESP_OK;
}

esp_err_t desk_persist_clear_scenery(void)
{
    if (!s_fs_ok) {
        return ESP_OK;
    }
    remove("/spiffs/scenery.bin");
    return ESP_OK;
}

bool desk_persist_has_scenery(void)
{
    if (!s_fs_ok) {
        return false;
    }
    struct stat st;
    return stat("/spiffs/scenery.bin", &st) == 0 && st.st_size > (off_t)sizeof(scenery_hdr_t);
}

typedef struct __attribute__((packed)) {
    uint16_t magic; /* 0xA31F */
    uint16_t w;
    uint16_t h;
    uint16_t frames;
    uint16_t fps;
    uint16_t reserved;
} anim_hdr_t;

#define ANIM_MAGIC 0xA31F

esp_err_t desk_persist_save_anim(const uint16_t *pix, int w, int h, int frames, int fps)
{
    if (!s_fs_ok || !pix || w < 1 || h < 1 || frames < 1) {
        return ESP_ERR_INVALID_STATE;
    }
    FILE *f = fopen("/spiffs/anim.bin", "wb");
    if (!f) {
        return ESP_FAIL;
    }
    anim_hdr_t hdr = {
        .magic = ANIM_MAGIC,
        .w = (uint16_t)w,
        .h = (uint16_t)h,
        .frames = (uint16_t)frames,
        .fps = (uint16_t)(fps > 0 ? fps : 8),
        .reserved = 0,
    };
    size_t bytes = (size_t)w * (size_t)h * sizeof(uint16_t) * (size_t)frames;
    bool ok = fwrite(&hdr, sizeof(hdr), 1, f) == 1 && fwrite(pix, 1, bytes, f) == bytes;
    fclose(f);
    if (!ok) {
        remove("/spiffs/anim.bin");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "saved anim %dx%d x%d", w, h, frames);
    return ESP_OK;
}

esp_err_t desk_persist_load_anim(uint16_t **out_pix, int *out_w, int *out_h, int *out_frames, int *out_fps)
{
    if (!s_fs_ok || !out_pix) {
        return ESP_ERR_INVALID_STATE;
    }
    *out_pix = NULL;
    FILE *f = fopen("/spiffs/anim.bin", "rb");
    if (!f) {
        return ESP_ERR_NOT_FOUND;
    }
    anim_hdr_t hdr;
    if (fread(&hdr, sizeof(hdr), 1, f) != 1 || hdr.magic != ANIM_MAGIC ||
        hdr.w < 8 || hdr.h < 8 || hdr.w > 160 || hdr.h > 86 || hdr.frames < 1 || hdr.frames > 12) {
        fclose(f);
        return ESP_ERR_INVALID_SIZE;
    }
    size_t bytes = (size_t)hdr.w * (size_t)hdr.h * sizeof(uint16_t) * (size_t)hdr.frames;
    uint16_t *buf = (uint16_t *)malloc(bytes);
    if (!buf) {
        fclose(f);
        return ESP_ERR_NO_MEM;
    }
    if (fread(buf, 1, bytes, f) != bytes) {
        free(buf);
        fclose(f);
        return ESP_FAIL;
    }
    fclose(f);
    *out_pix = buf;
    if (out_w) *out_w = hdr.w;
    if (out_h) *out_h = hdr.h;
    if (out_frames) *out_frames = hdr.frames;
    if (out_fps) *out_fps = hdr.fps;
    ESP_LOGI(TAG, "loaded anim %dx%d x%d", hdr.w, hdr.h, hdr.frames);
    return ESP_OK;
}

esp_err_t desk_persist_clear_anim(void)
{
    if (!s_fs_ok) {
        return ESP_OK;
    }
    remove("/spiffs/anim.bin");
    return ESP_OK;
}
