#include "AudioBridge.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio callback counters must be lock-free");

struct TTBlock { double time; uint32_t count; float samples[TT_BLOCK_FRAMES]; };
struct TTQueue {
    _Atomic uint32_t write_index;
    _Atomic uint32_t read_index;
    _Atomic uint32_t dropped;
    struct TTBlock blocks[TT_QUEUE_BLOCKS];
};
TTQueue *tt_queue_create(void) {
    TTQueue *q = calloc(1, sizeof(TTQueue));
    if (q) {
        atomic_init(&q->write_index, 0);
        atomic_init(&q->read_index, 0);
        atomic_init(&q->dropped, 0);
    }
    return q;
}
void tt_queue_destroy(TTQueue *q) { free(q); }
int tt_queue_write(TTQueue *q, const float *samples, uint32_t count, double time) {
    if (!q || !samples || !count || count > TT_BLOCK_FRAMES) return 0;
    uint32_t w = atomic_load_explicit(&q->write_index, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&q->read_index, memory_order_acquire);
    if (w - r >= TT_QUEUE_BLOCKS) {
        atomic_fetch_add_explicit(&q->dropped, 1, memory_order_relaxed);
        return 0;
    }
    struct TTBlock *block = &q->blocks[w % TT_QUEUE_BLOCKS];
    block->time = time;
    block->count = count;
    memcpy(block->samples, samples, count * sizeof(float));
    atomic_store_explicit(&q->write_index, w + 1, memory_order_release);
    return 1;
}
uint32_t tt_queue_read(TTQueue *q, float *samples, uint32_t capacity, double *time) {
    if (!q || !samples || !time) return 0;
    uint32_t r = atomic_load_explicit(&q->read_index, memory_order_relaxed);
    uint32_t w = atomic_load_explicit(&q->write_index, memory_order_acquire);
    if (r == w) return 0;
    struct TTBlock *block = &q->blocks[r % TT_QUEUE_BLOCKS];
    if (capacity < block->count) return 0;
    *time = block->time;
    memcpy(samples, block->samples, block->count * sizeof(float));
    uint32_t count = block->count;
    atomic_store_explicit(&q->read_index, r + 1, memory_order_release);
    return count;
}
uint32_t tt_queue_dropped(const TTQueue *q) {
    return q ? atomic_load_explicit(&q->dropped, memory_order_relaxed) : 0;
}
