#define NOMINMAX
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>
#include <math.h>
#include <string.h>
#include <stddef.h>
#include <wchar.h>
#include "include/desktop.h"

using Microsoft::WRL::ComPtr;

// No STL headers: Windows ARM64 builds also use Swift's bundled Clang.
struct Movie {
    ComPtr<IMFSinkWriter> writer;
    ComPtr<IMFSourceReader> reader;
    ComPtr<IMFSample> held, next, painted;
    DWORD videoStream = 0, audioStream = 0;
    UINT32 sourceWidth = 0, sourceHeight = 0;
    LONG sourceStride = 0;
    int width = 0, height = 0, fps = 0, audioRate = 0, audioChannels = 0, audioBits = 0;
    bool com = false, mf = false, eof = false, finished = false, positioned = false;
    HDC dc = nullptr, videoDC = nullptr;
    HBITMAP videoBitmap = nullptr;
    HGDIOBJ oldVideoBitmap = nullptr;
    int videoWidth = 0, videoHeight = 0;
    HBITMAP bitmap = nullptr;
    HGDIOBJ previous = nullptr;
    BYTE *pixels = nullptr;
    BYTE *sourcePixels = nullptr;
    size_t sourceCapacity = 0;
    ~Movie() {
        writer.Reset(); reader.Reset(); held.Reset(); next.Reset(); painted.Reset();
        if (dc && previous) SelectObject(dc, previous);
        if (bitmap) DeleteObject(bitmap);
        if (dc) DeleteDC(dc);
        if (sourcePixels) HeapFree(GetProcessHeap(), 0, sourcePixels);
        if (videoDC && oldVideoBitmap) SelectObject(videoDC, oldVideoBitmap);
        if (videoBitmap) DeleteObject(videoBitmap);
        if (videoDC) DeleteDC(videoDC);
        if (mf) MFShutdown();
        if (com) CoUninitialize();
    }
    HRESULT readNext() {
        next.Reset();
        if (!reader || eof) return S_OK;
        for (;;) {
            DWORD flags = 0;
            HRESULT hr = reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, nullptr, &next);
            if (FAILED(hr)) return hr;
            if (flags & MF_SOURCE_READERF_ERROR) return E_FAIL;
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
                ComPtr<IMFMediaType> actual;
                UINT32 w = 0, h = 0, stride = 0; GUID subtype = {};
                if (FAILED(hr = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &actual))) return hr;
                if (FAILED(hr = MFGetAttributeSize(actual.Get(), MF_MT_FRAME_SIZE, &w, &h))) return hr;
                if (FAILED(hr = actual->GetGUID(MF_MT_SUBTYPE, &subtype))) return hr;
                if (!w || !h || w > 16384 || h > 16384 || subtype != MFVideoFormat_RGB32) return MF_E_INVALIDMEDIATYPE;
                if (held && (w != sourceWidth || h != sourceHeight)) return MF_E_INVALIDMEDIATYPE;
                sourceWidth = w; sourceHeight = h;
                sourceStride = SUCCEEDED(actual->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride)) ? (LONG)stride : (LONG)(w * 4);
            }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) eof = true;
            if (next || eof) return S_OK;
        }
    }
    HRESULT paintVideo(double seconds) {
        if (!reader || seconds < 0) return S_OK;
        LONGLONG target = (LONGLONG)floor(seconds * 10000000.0 + 0.5);
        if (!positioned) {
            if (target > 0) {
                PROPVARIANT position = {}; position.vt = VT_I8; position.hVal.QuadPart = target;
                HRESULT hr = reader->SetCurrentPosition(GUID_NULL, position);
                if (FAILED(hr)) return hr;
            }
            positioned = true;
        }
        if (!next && !eof) { HRESULT hr = readNext(); if (FAILED(hr)) return hr; }
        while (next) {
            LONGLONG stamp = 0;
            HRESULT hr = next->GetSampleTime(&stamp);
            if (FAILED(hr)) return hr;
            if (stamp > target) break;
            held = next;
            if (FAILED(hr = readNext())) return hr;
        }
        if (!held) return S_OK;
        if (painted.Get() == held.Get()) {
            return BitBlt(dc, 0, 0, videoWidth, videoHeight, videoDC, 0, 0, SRCCOPY) ? S_OK : E_FAIL;
        }
        if (!videoDC) {
            videoWidth = width * 3 / 4; videoHeight = height * 3 / 4;
            videoDC = CreateCompatibleDC(dc);
            videoBitmap = CreateCompatibleBitmap(dc, videoWidth, videoHeight);
            if (!videoDC || !videoBitmap) return E_OUTOFMEMORY;
            oldVideoBitmap = SelectObject(videoDC, videoBitmap);
        }
        ComPtr<IMFMediaBuffer> buffer;
        HRESULT hr = held->ConvertToContiguousBuffer(&buffer);
        if (FAILED(hr)) return hr;
        size_t required = (size_t)sourceWidth * sourceHeight * 4;
        if (required > sourceCapacity) {
            if (sourcePixels) HeapFree(GetProcessHeap(), 0, sourcePixels);
            sourcePixels = (BYTE *)HeapAlloc(GetProcessHeap(), 0, required);
            sourceCapacity = sourcePixels ? required : 0;
            if (!sourcePixels) return E_OUTOFMEMORY;
        }
        BYTE *top = nullptr; LONG stride = sourceStride;
        ComPtr<IMF2DBuffer> surface;
        bool twoD = SUCCEEDED(buffer.As(&surface)) && SUCCEEDED(surface->Lock2D(&top, &stride));
        if (!twoD) {
            DWORD length = 0;
            if (FAILED(hr = buffer->Lock(&top, nullptr, &length))) return hr;
            if ((size_t)length < (size_t)abs(stride) * sourceHeight) { buffer->Unlock(); return MF_E_BUFFERTOOSMALL; }
            // RGB32 fallback buffers are bottom-up when their DIB stride is positive.
            if (stride > 0) { top += (size_t)(sourceHeight - 1) * stride; stride = -stride; }
        }
        for (UINT32 row = 0; row < sourceHeight; ++row)
            memcpy(sourcePixels + (size_t)row * sourceWidth * 4, top + (ptrdiff_t)row * stride, sourceWidth * 4);
        if (twoD) surface->Unlock2D(); else buffer->Unlock();
        BITMAPINFO info = {};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = sourceWidth; info.bmiHeader.biHeight = -(LONG)sourceHeight;
        info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
        double scale = width / 1920.0;
        double fit = (1440.0 / sourceWidth < 810.0 / sourceHeight) ? 1440.0 / sourceWidth : 810.0 / sourceHeight;
        int w = (int)floor(sourceWidth * fit * scale + 0.5), h = (int)floor(sourceHeight * fit * scale + 0.5);
        PatBlt(videoDC, 0, 0, videoWidth, videoHeight, BLACKNESS);
        SetStretchBltMode(videoDC, HALFTONE); SetBrushOrgEx(videoDC, 0, 0, nullptr);
        int result = StretchDIBits(videoDC, ((int)(1440 * scale) - w) / 2, ((int)(810 * scale) - h) / 2, w, h,
            0, 0, sourceWidth, sourceHeight, sourcePixels, &info, DIB_RGB_COLORS, SRCCOPY);
        if (result == GDI_ERROR) return E_FAIL;
        painted = held;
        return BitBlt(dc, 0, 0, videoWidth, videoHeight, videoDC, 0, 0, SRCCOPY) ? S_OK : E_FAIL;
    }
};

static HRESULT videoType(IMFMediaType *type, GUID subtype, int w, int h, int fps) {
    HRESULT hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, subtype);
    if (SUCCEEDED(hr)) hr = MFSetAttributeSize(type, MF_MT_FRAME_SIZE, w, h);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(type, MF_MT_FRAME_RATE, fps, 1);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(type, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    type->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
    type->SetUINT32(MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709);
    type->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
    return hr;
}

extern "C" void *cappella_movie_create(const uint16_t *destination, const uint16_t *video,
    int32_t width, int32_t height, int32_t fps, int32_t bitRate,
    int32_t audioRate, int32_t audioChannels, int32_t audioBits, int32_t *status) {
    if (!status) return nullptr;
    *status = E_INVALIDARG;
    if (!destination || width <= 0 || height <= 0 || width > 3840 || height > 2160 || width % 2 || height % 2 || fps <= 0) return nullptr;
    Movie *m = new Movie();
    m->width = width; m->height = height; m->fps = fps;
    m->audioRate = audioRate; m->audioChannels = audioChannels; m->audioBits = audioBits;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    m->com = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) hr = S_OK;
    if (SUCCEEDED(hr)) { hr = MFStartup(MF_VERSION); m->mf = SUCCEEDED(hr); }
    if (SUCCEEDED(hr)) {
        m->dc = CreateCompatibleDC(nullptr);
        BITMAPINFO info = {};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height; info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        if (m->dc) m->bitmap = CreateDIBSection(m->dc, &info, DIB_RGB_COLORS, (void **)&m->pixels, nullptr, 0);
        if (!m->dc || !m->bitmap) hr = E_OUTOFMEMORY;
        else m->previous = SelectObject(m->dc, m->bitmap);
    }
    if (SUCCEEDED(hr) && video && *video) {
        ComPtr<IMFAttributes> attrs;
        hr = MFCreateAttributes(&attrs, 2);
        if (SUCCEEDED(hr)) hr = attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
        if (SUCCEEDED(hr)) hr = MFCreateSourceReaderFromURL((const wchar_t *)video, attrs.Get(), &m->reader);
        if (SUCCEEDED(hr)) hr = m->reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE);
        if (SUCCEEDED(hr)) hr = m->reader->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
        ComPtr<IMFMediaType> rgb, actual;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&rgb);
        if (SUCCEEDED(hr)) { rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video); rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32); }
        if (SUCCEEDED(hr)) hr = m->reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, rgb.Get());
        if (SUCCEEDED(hr)) hr = m->reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &actual);
        if (SUCCEEDED(hr)) hr = MFGetAttributeSize(actual.Get(), MF_MT_FRAME_SIZE, &m->sourceWidth, &m->sourceHeight);
        if (SUCCEEDED(hr) && (!m->sourceWidth || !m->sourceHeight || m->sourceWidth > 16384 || m->sourceHeight > 16384)) hr = E_INVALIDARG;
        UINT32 stride = 0;
        if (SUCCEEDED(hr)) {
            if (FAILED(actual->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride))) stride = m->sourceWidth * 4;
            m->sourceStride = (LONG)stride;
        }
    }
    ComPtr<IMFAttributes> attrs;
    if (SUCCEEDED(hr)) hr = MFCreateAttributes(&attrs, 2);
    if (SUCCEEDED(hr)) {
        attrs->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
        attrs->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);
        hr = MFCreateSinkWriterFromURL((const wchar_t *)destination, nullptr, attrs.Get(), &m->writer);
    }
    ComPtr<IMFMediaType> output, input;
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&output);
    if (SUCCEEDED(hr)) hr = videoType(output.Get(), MFVideoFormat_H264, width, height, fps);
    if (SUCCEEDED(hr)) hr = output->SetUINT32(MF_MT_AVG_BITRATE, bitRate);
    if (SUCCEEDED(hr)) hr = m->writer->AddStream(output.Get(), &m->videoStream);
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&input);
    if (SUCCEEDED(hr)) hr = videoType(input.Get(), MFVideoFormat_NV12, width, height, fps);
    if (SUCCEEDED(hr)) hr = m->writer->SetInputMediaType(m->videoStream, input.Get(), nullptr);
    if (SUCCEEDED(hr) && audioRate > 0) {
        ComPtr<IMFMediaType> aac, pcm;
        hr = MFCreateMediaType(&aac);
        if (SUCCEEDED(hr)) {
            aac->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio); aac->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
            aac->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, audioChannels);
            aac->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, (audioRate == 44100) ? 44100 : 48000);
            aac->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
            aac->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audioChannels == 1 ? 12000 : 24000);
            hr = m->writer->AddStream(aac.Get(), &m->audioStream);
        }
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&pcm);
        if (SUCCEEDED(hr)) {
            pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio); pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
            pcm->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, audioChannels); pcm->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, audioRate);
            pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, audioBits);
            pcm->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, audioChannels * audioBits / 8);
            pcm->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audioRate * audioChannels * audioBits / 8);
            hr = m->writer->SetInputMediaType(m->audioStream, pcm.Get(), nullptr);
        }
    }
    if (SUCCEEDED(hr)) hr = m->writer->BeginWriting();
    *status = hr;
    if (FAILED(hr)) { delete m; return nullptr; }
    return m;
}

static int clampByte(int value) { return value < 0 ? 0 : value > 255 ? 255 : value; }
extern "C" int32_t cappella_movie_frame(void *movie, double videoSeconds, int64_t index,
    void (*draw)(void *, void *), void *context) {
    Movie *m = (Movie *)movie;
    if (!m || m->finished || index < 0) return E_INVALIDARG;
    memset(m->pixels, 0, (size_t)m->width * m->height * 4);
    HRESULT hr = m->paintVideo(videoSeconds);
    if (FAILED(hr)) return hr;
    int saved = SaveDC(m->dc);
    SetGraphicsMode(m->dc, GM_ADVANCED);
    XFORM scale = {(FLOAT)(m->width / 1920.0), 0, 0, (FLOAT)(m->height / 1080.0), 0, 0};
    SetWorldTransform(m->dc, &scale);
    if (draw) draw(m->dc, context);
    RestoreDC(m->dc, saved); GdiFlush();
    ComPtr<IMFMediaBuffer> buffer;
    DWORD size = (DWORD)((size_t)m->width * m->height * 3 / 2);
    hr = MFCreateMemoryBuffer(size, &buffer);
    BYTE *target = nullptr;
    if (SUCCEEDED(hr)) hr = buffer->Lock(&target, nullptr, nullptr);
    if (FAILED(hr)) return hr;
    const int w = m->width, h = m->height;
    for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
        const BYTE *p = m->pixels + ((size_t)y * w + x) * 4;
        target[(size_t)y * w + x] = (BYTE)clampByte(16 + ((47 * p[2] + 157 * p[1] + 16 * p[0] + 128) >> 8));
    }
    BYTE *uv = target + (size_t)w * h;
    for (int y = 0; y < h; y += 2) for (int x = 0; x < w; x += 2) {
        int r = 0, g = 0, b = 0;
        for (int dy = 0; dy < 2; ++dy) for (int dx = 0; dx < 2; ++dx) {
            const BYTE *p = m->pixels + ((size_t)(y + dy) * w + x + dx) * 4;
            b += p[0]; g += p[1]; r += p[2];
        }
        r /= 4; g /= 4; b /= 4;
        uv[(size_t)(y / 2) * w + x] = (BYTE)clampByte(128 + ((-26 * r - 87 * g + 112 * b + 128) >> 8));
        uv[(size_t)(y / 2) * w + x + 1] = (BYTE)clampByte(128 + ((112 * r - 102 * g - 10 * b + 128) >> 8));
    }
    buffer->Unlock(); buffer->SetCurrentLength(size);
    ComPtr<IMFSample> sample;
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
    LONGLONG start = index * 10000000 / m->fps, end = (index + 1) * 10000000 / m->fps;
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(start);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration(end - start);
    if (SUCCEEDED(hr)) hr = m->writer->WriteSample(m->videoStream, sample.Get());
    return hr;
}
extern "C" int32_t cappella_movie_audio(void *movie, const uint8_t *bytes, int32_t count, int64_t frame) {
    Movie *m = (Movie *)movie;
    if (!m || m->finished || m->audioRate <= 0 || !bytes || count <= 0 || frame < 0) return E_INVALIDARG;
    ComPtr<IMFMediaBuffer> buffer; ComPtr<IMFSample> sample;
    HRESULT hr = MFCreateMemoryBuffer(count, &buffer);
    BYTE *target = nullptr;
    if (SUCCEEDED(hr)) hr = buffer->Lock(&target, nullptr, nullptr);
    if (SUCCEEDED(hr)) { memcpy(target, bytes, count); buffer->Unlock(); hr = buffer->SetCurrentLength(count); }
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
    LONGLONG frames = count / (m->audioChannels * m->audioBits / 8);
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(frame * 10000000 / m->audioRate);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration((frame + frames) * 10000000 / m->audioRate - frame * 10000000 / m->audioRate);
    if (SUCCEEDED(hr)) hr = m->writer->WriteSample(m->audioStream, sample.Get());
    return hr;
}
extern "C" int32_t cappella_movie_finish(void *movie) {
    Movie *m = (Movie *)movie;
    if (!m || m->finished) return E_INVALIDARG;
    HRESULT hr = m->writer->Finalize(); m->finished = true; return hr;
}
extern "C" void cappella_movie_close(void *movie) { delete (Movie *)movie; }

static COLORREF rgb(uint32_t color) { return RGB((color >> 16) & 255, (color >> 8) & 255, color & 255); }
static void clip(HDC dc, int32_t sidebar) {
    if (sidebar) IntersectClipRect(dc, 1440, 0, 1920, 810);
    else IntersectClipRect(dc, 0, 810, 1920, 1080);
}
extern "C" void cappella_movie_rect(void *raw, double x, double y, double w, double h, uint32_t color, int32_t sidebar) {
    HDC dc = (HDC)raw; int saved = SaveDC(dc); clip(dc, sidebar);
    HBRUSH brush = CreateSolidBrush(rgb(color));
    RECT rect = {(LONG)floor(x), (LONG)floor(y), (LONG)ceil(x + w), (LONG)ceil(y + h)};
    FillRect(dc, &rect, brush); DeleteObject(brush); RestoreDC(dc, saved);
}
extern "C" void cappella_movie_text(void *raw, const uint16_t *text, double x, double y, double size,
    double width, uint32_t color, int32_t underline, int32_t sidebar) {
    if (!text || !*text) return;
    HDC dc = (HDC)raw; int saved = SaveDC(dc); clip(dc, sidebar);
    HFONT font = CreateFontW(-(int)floor(size + 0.5), 0, 0, 0, FW_NORMAL, FALSE, underline != 0, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Arial");
    if (font) {
        SelectObject(dc, font); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, rgb(color)); SetTextAlign(dc, TA_LEFT | TA_TOP);
        int count = (int)wcslen((const wchar_t *)text); SIZE measured = {};
        GetTextExtentPoint32W(dc, (const wchar_t *)text, count, &measured);
        XFORM transform = {}; GetWorldTransform(dc, &transform);
        transform.eDx += (FLOAT)(x * transform.eM11); transform.eDy += (FLOAT)(y * transform.eM22);
        if (width >= 0 && measured.cx > 0) transform.eM11 *= (FLOAT)(width / measured.cx);
        SetWorldTransform(dc, &transform); TextOutW(dc, 0, 0, (const wchar_t *)text, count);
        RestoreDC(dc, saved); DeleteObject(font);
    } else RestoreDC(dc, saved);
}
