/* Exercise the actual callback transport concurrently, including full-queue retries. */
#include "AudioBridge.h"
#include <pthread.h>
#include <assert.h>
#include <sched.h>
#include <stdio.h>
#define BLOCKS 100000
static TTQueue *queue;
static void *producer(void *unused) {
    (void)unused;
    float samples[127];
    for (int block = 0; block < BLOCKS; block++) {
        for (int i = 0; i < 127; i++) samples[i] = (float)(block + i);
        while (!tt_queue_write(queue, samples, 127, block * 0.25)) sched_yield();
    }
    return NULL;
}
int main(void) {
    queue = tt_queue_create(); assert(queue);
    pthread_t thread; assert(!pthread_create(&thread, NULL, producer, NULL));
    float samples[127]; double time;
    for (int block = 0; block < BLOCKS; block++) {
        uint32_t count;
        while (!(count = tt_queue_read(queue, samples, 127, &time))) sched_yield();
        assert(count == 127); assert(time == block * 0.25);
        for (int i = 0; i < 127; i++) assert(samples[i] == (float)(block + i));
    }
    pthread_join(thread, NULL);
    tt_queue_destroy(queue);
    puts("SPSC stress passed: 100,000 blocks / 12,700,000 samples in order.");
}
