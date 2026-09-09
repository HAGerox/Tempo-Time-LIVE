#ifndef TEMPO_AUDIO_BRIDGE_H
#define TEMPO_AUDIO_BRIDGE_H
#include <stdint.h>
#include <stddef.h>

#define TT_BLOCK_FRAMES 2048
#define TT_QUEUE_BLOCKS 64

typedef struct TTQueue TTQueue;
TTQueue *tt_queue_create(void);
void tt_queue_destroy(TTQueue *queue);
/* Single producer, single consumer. No locks or allocation after create. */
int tt_queue_write(TTQueue *queue, const float *samples, uint32_t count, double start_seconds);
uint32_t tt_queue_read(TTQueue *queue, float *samples, uint32_t capacity, double *start_seconds);
uint32_t tt_queue_dropped(const TTQueue *queue);

typedef struct {
    uint32_t id;
    uint32_t channels;
    double sample_rate;
    char name[256];
    char uid[256];
} TTDeviceInfo;
/* Returns the number of input devices, or a negative OSStatus. */
int tt_list_devices(TTDeviceInfo *devices, int capacity);

typedef struct TTCapture TTCapture;
/* channel is zero based. Does not change the system default device or rate. */
TTCapture *tt_capture_start(uint32_t device, uint32_t channel, int32_t *error);
void tt_capture_stop(TTCapture *capture);
double tt_capture_sample_rate(const TTCapture *capture);
uint32_t tt_capture_read(TTCapture *capture, float *samples, uint32_t capacity, double *start_seconds);
uint32_t tt_capture_dropped(const TTCapture *capture);
int32_t tt_capture_error(const TTCapture *capture);
#endif
