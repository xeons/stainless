/*
 * Stainless - an experimental general-purpose language.
 * Copyright (C) 2026 Brandon Scott
 *
 * This file is part of the Stainless runtime library. It is free
 * software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any
 * later version.
 *
 * It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * As an additional permission under section 7 of that License, compiling
 * a program with Stainless does not by itself place that program under
 * the GNU General Public License. See LICENSE.RUNTIME.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * What only the platform knows about time zones.
 *
 * Standard.Time.TimeZoneInfo does the arithmetic, in Stainless, from one
 * shape of rule. On Unix it reads that shape out of the IANA database's files
 * itself, and needs only the local zone's name from here. On Windows the rules
 * live behind the time zone API, so this asks it for a zone's rule in a given
 * year -- Windows keeps one per year where a country has changed its mind --
 * and for the names, and maps IANA names through the ICU Windows 10 ships.
 */

#include "stainless.h"

#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  pragma comment(lib, "advapi32")
#else
#  include <unistd.h>
#endif

#ifdef _WIN32

static long long wide_out(const WCHAR *text, char *buffer, size_t size)
{
    int written = WideCharToMultiByte(CP_UTF8, 0, text, -1, buffer, (int)size, NULL, NULL);
    return written > 0 ? (long long)written - 1 : -1;
}

/* The dynamic zone whose registry key is `id`, compared without regard to case. */
static _Bool find_zone(const char *id, DYNAMIC_TIME_ZONE_INFORMATION *zone)
{
    WCHAR wanted[128];
    if (MultiByteToWideChar(CP_UTF8, 0, id, -1, wanted, 128) == 0) return 0;

    for (DWORD index = 0; EnumDynamicTimeZoneInformation(index, zone) == ERROR_SUCCESS; index++)
        if (_wcsicmp(zone->TimeZoneKeyName, wanted) == 0) return 1;
    return 0;
}

static void put_date(const SYSTEMTIME *date, long long *out)
{
    out[0] = date->wYear;
    out[1] = date->wMonth;
    out[2] = date->wDayOfWeek;
    out[3] = date->wDay;
    out[4] = date->wHour;
    out[5] = date->wMinute;
    out[6] = date->wSecond;
}

#else

/* Copies `text` into `buffer` when it fits with its NUL, and answers its length or -1. */
static long long copy_out(const char *text, char *buffer, size_t size)
{
    size_t length = strlen(text);
    if (length + 1 > size) return -1;
    memcpy(buffer, text, length + 1);
    return (long long)length;
}

#endif

/*
 * The local zone's name: its IANA name on Unix, read off the link
 * /etc/localtime is, and its registry key name on Windows. Answers the
 * length, or -1 when it cannot say.
 */
long long sl_tz_local_name(char *buffer, size_t size)
{
#ifdef _WIN32
    DYNAMIC_TIME_ZONE_INFORMATION zone;
    if (GetDynamicTimeZoneInformation(&zone) == TIME_ZONE_ID_INVALID) return -1;
    return wide_out(zone.TimeZoneKeyName, buffer, size);
#else
    char target[512];
    ssize_t length = readlink("/etc/localtime", target, sizeof target - 1);
    if (length <= 0) return -1;
    target[length] = 0;

    const char *name = strstr(target, "zoneinfo/");
    return name ? copy_out(name + 9, buffer, size) : -1;
#endif
}

#ifdef _WIN32

/* The registry key a zone keeps its data under, and `suffix` after it. */
static void zone_key(const WCHAR *keyName, const WCHAR *suffix, WCHAR *key)
{
    wcscpy(key, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\");
    wcsncat(key, keyName, 128);
    wcsncat(key, suffix, 32);
}

/* Reads a DWORD under the zone's "Dynamic DST" key, or answers 0. */
static DWORD dynamic_entry(const WCHAR *keyName, const WCHAR *value)
{
    WCHAR key[300];
    zone_key(keyName, L"\\Dynamic DST", key);
    DWORD read = 0;
    DWORD bytes = sizeof read;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, value, RRF_RT_REG_DWORD, NULL, &read, &bytes) != ERROR_SUCCESS)
        return 0;
    return read;
}

/* Appends `text` and its NUL to `buffer` at `*at`, when it fits. */
static _Bool append_name(const WCHAR *text, char *buffer, size_t size, size_t *at)
{
    if (*at >= size) return 0;
    int written = WideCharToMultiByte(CP_UTF8, 0, text, -1, buffer + *at, (int)(size - *at), NULL, NULL);
    if (written <= 0) return 0;
    *at += (size_t)written;
    return 1;
}

#endif

/*
 * Windows: one zone, found by its registry key name `id`, or by `index` when
 * `id` is NULL. Writes its rules for `count` years from `firstYear` --
 * seventeen values a year: the bias, the standard bias and the daylight bias
 * in minutes, then the standard date and the daylight date, each as year,
 * month, weekday, day or week, hour, minute and second -- and its key name,
 * standard name, daylight name and display name into `names`, each ended by a
 * NUL. Answers the bytes written to `names`, or -1 when there is no such zone.
 *
 * A zone keeps a rule of its own only for the years its "Dynamic DST" key
 * lists; outside them, and for a zone with no such key, the nearest listed
 * year's stands, so only those years are asked for.
 */
long long sl_tz_windows_zone(const char *id, long long index, long long firstYear, long long count,
                             long long *rules, char *names, size_t size)
{
#ifdef _WIN32
    DYNAMIC_TIME_ZONE_INFORMATION zone;
    if (id ? !find_zone(id, &zone)
           : EnumDynamicTimeZoneInformation((DWORD)index, &zone) != ERROR_SUCCESS)
        return -1;

    DWORD first = dynamic_entry(zone.TimeZoneKeyName, L"FirstEntry");
    DWORD last = dynamic_entry(zone.TimeZoneKeyName, L"LastEntry");
    long long asked = -1;

    for (long long i = 0; i < count; i++)
    {
        long long year = firstYear + i;
        if (first == 0 || last < first) year = firstYear;
        else if (year < (long long)first) year = first;
        else if (year > (long long)last) year = last;

        long long *out = rules + i * 17;
        if (year == asked)
        {
            memcpy(out, out - 17, 17 * sizeof *out);
            continue;
        }

        TIME_ZONE_INFORMATION rule;
        if (!GetTimeZoneInformationForYear((USHORT)year, &zone, &rule)) return -1;
        out[0] = rule.Bias;
        out[1] = rule.StandardBias;
        out[2] = rule.DaylightBias;
        put_date(&rule.StandardDate, out + 3);
        put_date(&rule.DaylightDate, out + 10);
        asked = year;
    }

    WCHAR key[300];
    zone_key(zone.TimeZoneKeyName, L"", key);
    WCHAR display[256];
    DWORD bytes = sizeof display;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, L"Display", RRF_RT_REG_SZ, NULL, display, &bytes) != ERROR_SUCCESS)
        wcscpy(display, zone.StandardName);

    size_t at = 0;
    if (!append_name(zone.TimeZoneKeyName, names, size, &at) ||
        !append_name(zone.StandardName, names, size, &at) ||
        !append_name(zone.DaylightName, names, size, &at) ||
        !append_name(display, names, size, &at))
        return -1;
    return (long long)at;
#else
    (void)id; (void)index; (void)firstYear; (void)count; (void)rules; (void)names; (void)size;
    return -1;
#endif
}

#ifdef _WIN32

/* ICU's mapping calls, from the icu.dll Windows 10 1903 and later carry. */
typedef int (*IcuMap)(const WCHAR *, int, const char *, WCHAR *, int, int *);
typedef int (*IcuToWindows)(const WCHAR *, int, WCHAR *, int, int *);

/* Two threads may both load it; the second load is a count on the same module. */
static HMODULE icu(void)
{
    static HMODULE module;
    static _Bool tried;
    if (!tried)
    {
        module = LoadLibraryExW(L"icu.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
        tried = 1;
    }
    return module;
}

#endif

/*
 * An IANA name as a Windows zone's key name, or a Windows key name as the
 * IANA name for the zone's own region, as `toWindows` says. Answers the
 * length, or -1 when there is no ICU to ask or no mapping.
 */
long long sl_tz_map_id(const char *id, _Bool toWindows, char *buffer, size_t size)
{
#ifdef _WIN32
    HMODULE library = icu();
    if (!library) return -1;

    WCHAR wide[128];
    WCHAR mapped[128];
    int status = 0;
    int length = MultiByteToWideChar(CP_UTF8, 0, id, -1, wide, 128);
    if (length == 0) return -1;

    int written;
    if (toWindows)
    {
        IcuToWindows call = (IcuToWindows)(void *)GetProcAddress(library, "ucal_getWindowsTimeZoneID");
        if (!call) return -1;
        written = call(wide, length - 1, mapped, 127, &status);
    }
    else
    {
        IcuMap call = (IcuMap)(void *)GetProcAddress(library, "ucal_getTimeZoneIDForWindowsID");
        if (!call) return -1;
        written = call(wide, length - 1, NULL, mapped, 127, &status);
    }

    if (status > 0 || written <= 0) return -1;
    mapped[written] = 0;
    return wide_out(mapped, buffer, size);
#else
    (void)id; (void)toWindows; (void)buffer; (void)size;
    return -1;
#endif
}
