// SPDX-License-Identifier: 0BSD
//
// Counts the copies of the Stainless runtime mapped into this process.
#ifdef _WIN32
#include <windows.h>
#include <string.h>

/* The kernel32 export, so nothing needs psapi.lib. */
BOOL WINAPI K32EnumProcessModules(HANDLE process, HMODULE *modules, DWORD size, LPDWORD needed);

int runtimes_loaded(void)
{
    HMODULE modules[512];
    DWORD needed = 0;
    if (!K32EnumProcessModules(GetCurrentProcess(), modules, sizeof modules, &needed))
        return -1;

    int count = 0;
    for (DWORD i = 0; i < needed / sizeof(HMODULE) && i < 512; i++)
    {
        char name[MAX_PATH];
        if (GetModuleFileNameA(modules[i], name, sizeof name) && strstr(name, "stainless-rt"))
            count++;
    }
    return count;
}
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <string.h>

int runtimes_loaded(void)
{
    int count = 0;
    uint32_t images = _dyld_image_count();
    for (uint32_t i = 0; i < images; i++)
    {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "stainless-rt"))
            count++;
    }
    return count;
}
#else
#define _GNU_SOURCE
#include <link.h>
#include <string.h>

static int count_runtime(struct dl_phdr_info *info, size_t size, void *data)
{
    (void)size;
    if (info->dlpi_name && strstr(info->dlpi_name, "stainless-rt"))
        ++*(int *)data;
    return 0;
}

int runtimes_loaded(void)
{
    int count = 0;
    dl_iterate_phdr(count_runtime, &count);
    return count;
}
#endif
