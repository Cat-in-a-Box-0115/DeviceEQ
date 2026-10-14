#ifndef DEVICE_EQ_DSP_H
#define DEVICE_EQ_DSP_H
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
#define DEQ_MAX_BANDS 64
/* Q uses RBJ peaking/pass/notch convention. Shelves use Q, not shelf slope S. */
typedef enum { DEQ_PEAK=0, DEQ_LOW_SHELF, DEQ_HIGH_SHELF, DEQ_HIGH_PASS, DEQ_LOW_PASS, DEQ_NOTCH } DEQFilterType;
typedef enum { DEQ_STEREO=0, DEQ_LEFT=1, DEQ_RIGHT=2 } DEQChannel;
typedef struct { int32_t type, channel, enabled; double frequency, gainDB, q; } DEQBand;
typedef struct {
    double sampleRate; int32_t bandCount; DEQBand bands[DEQ_MAX_BANDS];
    double preampDB; int32_t autoHeadroom, limiter, bypass;
} DEQConfig;
typedef struct DEQEngine DEQEngine;
DEQEngine *DEQCreate(double sampleRate);
void DEQDestroy(DEQEngine *engine);
/* Single serialized non-audio producer. False means invalid config or queue full.
   Retry from control thread, never wait or retry from an audio callback. */
bool DEQSetConfig(DEQEngine *engine, const DEQConfig *config);
/* In-place; channels 1/2 processed, other channels left untouched. No allocation or lock. */
void DEQProcessInterleaved(DEQEngine *engine, float *samples, uint32_t frames, uint32_t channels);
/* Control-thread helpers: response excludes preamp; channel 0=L,1=R. */
double DEQResponseDB(const DEQConfig *config, double frequency, int32_t channel);
double DEQEffectivePreampDB(const DEQConfig *config);
/* Optional limiter is a hard safety ceiling, not a look-ahead mastering limiter. */
#ifdef __cplusplus
}
#endif
#endif
