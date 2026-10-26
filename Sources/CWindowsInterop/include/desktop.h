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
// Offline MP4 encoder. The caller owns the session on one worker thread.
void *cappella_movie_create(const uint16_t *destination, const uint16_t *video,
    int32_t width, int32_t height, int32_t fps, int32_t bit_rate,
    int32_t audio_rate, int32_t audio_channels, int32_t audio_bits, int32_t *status);
int32_t cappella_movie_frame(void *movie, double video_seconds, int64_t index,
    void (*draw)(void *dc, void *context), void *context);
int32_t cappella_movie_audio(void *movie, const uint8_t *bytes, int32_t count, int64_t first_frame);
int32_t cappella_movie_finish(void *movie);
void cappella_movie_close(void *movie);
void cappella_movie_rect(void *dc, double x, double y, double width, double height, uint32_t color, int32_t sidebar);
void cappella_movie_text(void *dc, const uint16_t *text, double x, double y, double size,
    double width, uint32_t color, int32_t underline, int32_t sidebar);
#ifdef __cplusplus
}
#endif
