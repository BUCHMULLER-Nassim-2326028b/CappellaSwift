#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// WinUI desktop pickers require their owning Window's native handle. This
// controls remain WinUI/Swift-WinRT; audio decoding uses Media Foundation.
int32_t cappella_attach_picker(void *picker, uint64_t window_id, int32_t *stage);
// Synchronously enumerate installed font families; names are valid during the callback.
int32_t cappella_system_font_families(void (*receive)(const uint16_t *, void *), void *context);
// Decode one native audio stream to interleaved PCM WAV for CappellaCore.
// Returns S_FALSE when the requested audio stream does not exist.
int32_t cappella_decode_audio(const uint16_t *source, const uint16_t *destination,
    int32_t ordinal, int32_t *streams, double *duration, int32_t (*cancelled)(void));
#ifdef __cplusplus
}
#endif
