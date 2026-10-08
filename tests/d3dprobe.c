/* d3dprobe: creates a Direct3D 11 and a Direct3D 12 device and reports what answered.
 * Build: x86_64-w64-mingw32-gcc -O2 -o d3dprobe.exe d3dprobe.c -ld3d11 -ldxgi -ld3d12 -lole32 -luuid
 * Exit code: 0 when every requested API produced a device. */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <d3d11.h>
#include <d3d12.h>
#include <dxgi1_4.h>

static void module_path(const char *name)
{
    char path[MAX_PATH] = "";
    HMODULE m = GetModuleHandleA(name);
    if (m) GetModuleFileNameA(m, path, sizeof(path));
    printf("  %-12s %s\n", name, m ? path : "(not loaded)");
}

static int probe_d3d11(void)
{
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL fl = 0;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &dev, &fl, &ctx);
    printf("d3d11: hr=%#lx feature_level=%#x\n", (unsigned long)hr, (unsigned)fl);
    if (FAILED(hr)) return 1;
    IDXGIDevice *dxgi_dev;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi_dev)))
    {
        IDXGIAdapter *ad;
        DXGI_ADAPTER_DESC desc;
        if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgi_dev, &ad)) && SUCCEEDED(IDXGIAdapter_GetDesc(ad, &desc)))
            printf("  adapter: %ls vendor=%04x device=%04x vram=%llu MB\n", desc.Description,
                   desc.VendorId, desc.DeviceId, (unsigned long long)desc.DedicatedVideoMemory >> 20);
        IDXGIDevice_Release(dxgi_dev);
    }
    module_path("d3d11.dll");
    module_path("dxgi.dll");
    module_path("winemetal.dll");
    ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(dev);
    return 0;
}

static int probe_d3d12(void)
{
    ID3D12Device *dev = NULL;
    HRESULT hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev);
    printf("d3d12: hr=%#lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 o5 = {0};
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(dev, D3D12_FEATURE_D3D12_OPTIONS5, &o5, sizeof(o5))))
        printf("  raytracing tier=%d\n", o5.RaytracingTier);
    module_path("d3d12.dll");
    module_path("dxgi.dll");
    ID3D12Device_Release(dev);
    return 0;
}

int main(int argc, char **argv)
{
    int want11 = 1, want12 = 1, fail = 0;
    if (argc > 1) { want11 = !strcmp(argv[1], "11"); want12 = !strcmp(argv[1], "12"); }
    if (want11) fail |= probe_d3d11();
    if (want12) fail |= probe_d3d12();
    fflush(stdout);
    return fail;
}
