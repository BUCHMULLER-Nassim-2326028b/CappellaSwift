#define NOMINMAX
#include <windows.h>
#include <dwrite.h>
#include <wrl/client.h>
#include "include/desktop.h"

using Microsoft::WRL::ComPtr;

// Enumerate through DirectWrite, which is also used by WinUI for text. No
// registry scraping, extra font package, or dependency on the MSVC STL.
int32_t cappella_system_font_families(void (*receive)(const uint16_t *, void *), void *context) {
    if (!receive) return E_INVALIDARG;
    ComPtr<IDWriteFactory> factory;
    HRESULT hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
        reinterpret_cast<IUnknown **>(factory.GetAddressOf()));
    if (FAILED(hr)) return hr;
    ComPtr<IDWriteFontCollection> collection;
    hr = factory->GetSystemFontCollection(collection.GetAddressOf(), FALSE);
    if (FAILED(hr)) return hr;
    for (UINT32 i = 0; i < collection->GetFontFamilyCount(); ++i) {
        ComPtr<IDWriteFontFamily> family;
        ComPtr<IDWriteLocalizedStrings> names;
        if (FAILED(collection->GetFontFamily(i, family.GetAddressOf())) ||
            FAILED(family->GetFamilyNames(names.GetAddressOf())) || names->GetCount() == 0) continue;
        UINT32 index = 0;
        BOOL exists = FALSE;
        // Canonical names remain valid if the user's Windows language changes.
        if (FAILED(names->FindLocaleName(L"en-us", &index, &exists)) || !exists) index = 0;
        UINT32 length = 0;
        hr = names->GetStringLength(index, &length);
        if (FAILED(hr) || length == 0 || length > 65535) continue;
        wchar_t *name = static_cast<wchar_t *>(HeapAlloc(GetProcessHeap(), 0, (length + 1) * sizeof(wchar_t)));
        if (!name) return E_OUTOFMEMORY;
        hr = names->GetString(index, name, length + 1);
        if (SUCCEEDED(hr)) receive(reinterpret_cast<const uint16_t *>(name), context);
        HeapFree(GetProcessHeap(), 0, name);
    }
    return S_OK;
}
