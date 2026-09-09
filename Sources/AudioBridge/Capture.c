#include "AudioBridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <math.h>

#ifdef __APPLE__
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>

static OSStatus property(AudioObjectID object, AudioObjectPropertySelector selector,
                         AudioObjectPropertyScope scope, void *value, UInt32 *size) {
    AudioObjectPropertyAddress address = {selector, scope, kAudioObjectPropertyElementMain};
    return AudioObjectGetPropertyData(object, &address, 0, NULL, size, value);
}
static uint32_t input_channels(AudioDeviceID device) {
    AudioObjectPropertyAddress address = {kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) || !size) return 0;
    AudioBufferList *buffers = malloc(size);
    if (!buffers) return 0;
    uint32_t channels = 0;
    if (!AudioObjectGetPropertyData(device, &address, 0, NULL, &size, buffers)) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; i++) channels += buffers->mBuffers[i].mNumberChannels;
    }
    free(buffers);
    return channels;
}
static void device_string(AudioDeviceID device, AudioObjectPropertySelector selector, char *out, size_t capacity) {
    CFStringRef string = NULL;
    UInt32 size = sizeof(string);
    if (!property(device, selector, kAudioObjectPropertyScopeGlobal, &string, &size) && string) {
        CFStringGetCString(string, out, capacity, kCFStringEncodingUTF8);
        CFRelease(string);
    }
}
int tt_list_devices(TTDeviceInfo *out, int capacity) {
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size);
    if (status) return status < 0 ? status : -status;
    if (!size) return 0;
    AudioDeviceID *ids = malloc(size);
    if (!ids) return -108;
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids);
    if (status) { free(ids); return status < 0 ? status : -status; }
    int count = 0;
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); i++) {
        uint32_t channels = input_channels(ids[i]);
        UInt32 alive = 0, alive_size = sizeof(alive);
        if (!channels || property(ids[i], kAudioDevicePropertyDeviceIsAlive,
            kAudioObjectPropertyScopeGlobal, &alive, &alive_size) || !alive) continue;
        if (out && count < capacity) {
            TTDeviceInfo *info = &out[count];
            memset(info, 0, sizeof(*info));
            info->id = ids[i]; info->channels = channels;
            UInt32 rate_size = sizeof(info->sample_rate);
            property(ids[i], kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
                     &info->sample_rate, &rate_size);
            device_string(ids[i], kAudioObjectPropertyName, info->name, sizeof(info->name));
            device_string(ids[i], kAudioDevicePropertyDeviceUID, info->uid, sizeof(info->uid));
        }
        count++;
    }
    free(ids);
    return count;
}

struct TTCapture {
    AudioUnit unit;
    TTQueue *queue;
    float *buffer;
    UInt32 max_frames;
    double sample_rate;
    double host_seconds_per_tick;
    _Atomic int32_t error;
};

static OSStatus capture_callback(void *context, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timestamp, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    (void)bus; (void)unused;
    TTCapture *c = context;
    if (frames > c->max_frames) {
        atomic_store_explicit(&c->error, kAudioUnitErr_TooManyFramesToProcess, memory_order_relaxed);
        return kAudioUnitErr_TooManyFramesToProcess;
    }
    AudioBufferList list = {.mNumberBuffers = 1,
        .mBuffers = {{.mNumberChannels = 1, .mDataByteSize = frames * sizeof(float), .mData = c->buffer}}};
    OSStatus status = AudioUnitRender(c->unit, flags, timestamp, 1, frames, &list);
    if (status) { atomic_store_explicit(&c->error, status, memory_order_relaxed); return status; }
    // Queue timestamps share the monotonic host clock with the service/UI bridge.
    double start = (timestamp->mFlags & kAudioTimeStampHostTimeValid)
        ? timestamp->mHostTime * c->host_seconds_per_tick
        : mach_absolute_time() * c->host_seconds_per_tick - frames / c->sample_rate;
    for (UInt32 offset = 0; offset < frames; offset += TT_BLOCK_FRAMES) {
        UInt32 count = frames - offset;
        if (count > TT_BLOCK_FRAMES) count = TT_BLOCK_FRAMES;
        tt_queue_write(c->queue, c->buffer + offset, count, start + offset / c->sample_rate);
    }
    return noErr;
}

TTCapture *tt_capture_start(uint32_t device, uint32_t channel, int32_t *error) {
    OSStatus status = noErr;
    TTCapture *c = calloc(1, sizeof(*c));
    if (!c) { if (error) *error = -108; return NULL; }
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    c->host_seconds_per_tick = (double)timebase.numer / timebase.denom / 1e9;
    atomic_init(&c->error, 0);
    c->queue = tt_queue_create();
    if (!c->queue) { status = -108; goto fail; }
    if (channel >= input_channels(device)) { status = kAudio_ParamError; goto fail; }
    AudioComponentDescription description = {.componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput, .componentManufacturer = kAudioUnitManufacturer_Apple};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) { status = kAudio_ParamError; goto fail; }
#define TT_CHECK(call) do { status = (call); if (status) goto fail; } while (0)
    TT_CHECK(AudioComponentInstanceNew(component, &c->unit));
    UInt32 enable = 1, disable = 0;
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, sizeof(enable)));
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, sizeof(disable)));
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device)));
    AudioStreamBasicDescription hardware = {0};
    UInt32 size = sizeof(hardware);
    TT_CHECK(AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size));
    c->sample_rate = hardware.mSampleRate;
    if (!isfinite(c->sample_rate) || c->sample_rate < 8000 || c->sample_rate > 384000) { status = kAudio_ParamError; goto fail; }
    AudioStreamBasicDescription format = {.mSampleRate = c->sample_rate,
        .mFormatID = kAudioFormatLinearPCM, .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mBytesPerPacket = sizeof(float), .mFramesPerPacket = 1, .mBytesPerFrame = sizeof(float),
        .mChannelsPerFrame = 1, .mBitsPerChannel = 32};
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format)));
    SInt32 mapping = (SInt32)channel;
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, &mapping, sizeof(mapping)));
    c->max_frames = 8192;
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &c->max_frames, sizeof(c->max_frames)));
    size = sizeof(c->max_frames);
    TT_CHECK(AudioUnitGetProperty(c->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &c->max_frames, &size));
    if (!c->max_frames || c->max_frames > 1048576) { status = kAudio_ParamError; goto fail; }
    c->buffer = calloc(c->max_frames, sizeof(float));
    if (!c->buffer) { status = -108; goto fail; }
    AURenderCallbackStruct callback = {.inputProc = capture_callback, .inputProcRefCon = c};
    TT_CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(callback)));
    TT_CHECK(AudioUnitInitialize(c->unit));
    TT_CHECK(AudioOutputUnitStart(c->unit));
    if (error) *error = 0;
    return c;
fail:
    if (error) *error = status;
    tt_capture_stop(c);
    return NULL;
#undef TT_CHECK
}
void tt_capture_stop(TTCapture *c) {
    if (!c) return;
    if (c->unit) {
        AudioOutputUnitStop(c->unit);
        AudioUnitUninitialize(c->unit);
        AudioComponentInstanceDispose(c->unit);
    }
    tt_queue_destroy(c->queue);
    free(c->buffer);
    free(c);
}
double tt_capture_sample_rate(const TTCapture *c) { return c ? c->sample_rate : 0; }
uint32_t tt_capture_read(TTCapture *c, float *samples, uint32_t capacity, double *time) {
    return c ? tt_queue_read(c->queue, samples, capacity, time) : 0;
}
uint32_t tt_capture_dropped(const TTCapture *c) { return c ? tt_queue_dropped(c->queue) : 0; }
int32_t tt_capture_error(const TTCapture *c) { return c ? atomic_load_explicit(&c->error, memory_order_relaxed) : 0; }
#else
int tt_list_devices(TTDeviceInfo *d, int n) { (void)d; (void)n; return -1; }
TTCapture *tt_capture_start(uint32_t d, uint32_t ch, int32_t *e) { (void)d; (void)ch; if (e) *e = -1; return NULL; }
void tt_capture_stop(TTCapture *c) { (void)c; }
double tt_capture_sample_rate(const TTCapture *c) { (void)c; return 0; }
uint32_t tt_capture_read(TTCapture *c, float *s, uint32_t n, double *t) { (void)c; (void)s; (void)n; (void)t; return 0; }
uint32_t tt_capture_dropped(const TTCapture *c) { (void)c; return 0; }
int32_t tt_capture_error(const TTCapture *c) { (void)c; return -1; }
#endif
