#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

typedef void (*frag_complete_cb_t)(const uint8_t *data, size_t len, void *ctx);

typedef struct {
    uint16_t msg_id;
    uint16_t next_index;
    size_t len;
    uint8_t buf[4096];
    bool active;
} frag_rx_t;

void frag_rx_init(frag_rx_t *rx);
esp_err_t frag_rx_feed(frag_rx_t *rx, const uint8_t *chunk, size_t chunk_len, frag_complete_cb_t cb, void *ctx);

/* Build fragments into caller-provided sink. Returns number of fragments written. */
int frag_tx_build(uint16_t msg_id, const uint8_t *data, size_t len,
                  void (*emit)(const uint8_t *frag, size_t frag_len, void *ctx), void *ctx);
