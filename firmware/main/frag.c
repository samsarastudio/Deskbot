#include "frag.h"

#include <string.h>

#include "app_config.h"
#include "esp_log.h"

static const char *TAG = "frag";

void frag_rx_init(frag_rx_t *rx)
{
    memset(rx, 0, sizeof(*rx));
}

esp_err_t frag_rx_feed(frag_rx_t *rx, const uint8_t *chunk, size_t chunk_len, frag_complete_cb_t cb, void *ctx)
{
    if (!rx || !chunk || chunk_len < 6) {
        return ESP_ERR_INVALID_ARG;
    }
    if (chunk[0] != DESKBOT_FRAG_MAGIC) {
        return ESP_ERR_INVALID_STATE;
    }
    uint8_t flags = chunk[1];
    uint16_t msg_id = (uint16_t)chunk[2] | ((uint16_t)chunk[3] << 8);
    uint16_t index = (uint16_t)chunk[4] | ((uint16_t)chunk[5] << 8);
    const uint8_t *payload = chunk + 6;
    size_t plen = chunk_len - 6;

    if (!rx->active || rx->msg_id != msg_id || index == 0) {
        rx->active = true;
        rx->msg_id = msg_id;
        rx->next_index = 0;
        rx->len = 0;
    }
    if (index != rx->next_index) {
        ESP_LOGW(TAG, "frag order msg=%u got=%u want=%u", msg_id, index, rx->next_index);
        rx->active = false;
        return ESP_ERR_INVALID_STATE;
    }
    if (rx->len + plen > sizeof(rx->buf)) {
        rx->active = false;
        return ESP_ERR_NO_MEM;
    }
    memcpy(rx->buf + rx->len, payload, plen);
    rx->len += plen;
    rx->next_index++;

    if (flags & DESKBOT_FRAG_FINAL) {
        if (cb) {
            cb(rx->buf, rx->len, ctx);
        }
        rx->active = false;
    }
    return ESP_OK;
}

int frag_tx_build(uint16_t msg_id, const uint8_t *data, size_t len,
                  void (*emit)(const uint8_t *frag, size_t frag_len, void *ctx), void *ctx)
{
    if (!data || !emit) {
        return 0;
    }
    size_t off = 0;
    uint16_t index = 0;
    int count = 0;
    while (off < len || (len == 0 && index == 0)) {
        size_t take = len - off;
        if (take > DESKBOT_FRAG_PAYLOAD) {
            take = DESKBOT_FRAG_PAYLOAD;
        }
        uint8_t frag[6 + DESKBOT_FRAG_PAYLOAD];
        frag[0] = DESKBOT_FRAG_MAGIC;
        bool more = (off + take) < len;
        frag[1] = more ? DESKBOT_FRAG_MORE : DESKBOT_FRAG_FINAL;
        frag[2] = (uint8_t)(msg_id & 0xff);
        frag[3] = (uint8_t)((msg_id >> 8) & 0xff);
        frag[4] = (uint8_t)(index & 0xff);
        frag[5] = (uint8_t)((index >> 8) & 0xff);
        if (take) {
            memcpy(frag + 6, data + off, take);
        }
        emit(frag, 6 + take, ctx);
        count++;
        off += take;
        index++;
        if (len == 0) {
            break;
        }
    }
    return count;
}
