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
 * Two clocks, which answer different questions and must not be confused.
 *
 * The wall clock says what time it is. It can jump: a user sets it, NTP
 * corrects it, a laptop wakes up. Never subtract two readings of it to measure
 * how long something took.
 *
 * The monotonic clock only ever goes forward, at a steady rate, from an
 * arbitrary zero. It says nothing about the date and is the only one worth
 * measuring with.
 *
 * Both are reported in nanoseconds, in an int64, which is the unit and width
 * that make the arithmetic in Standard.Time ordinary subtraction. Signed
 * because a difference is signed, and 64 bits of nanoseconds is 292 years
 * either side of the epoch -- long enough that the range is not the reason
 * anything here would go wrong.
 *
 * The UTC calendar is computed here rather than by gmtime, because the
 * platforms disagree about the past -- Windows' gmtime_s refuses a negative
 * time_t, so every date before 1970 came back as zeroes. Local time still has
 * to ask the platform, because only it knows the zone rules.
 */

#include "stainless.h"

#include <time.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#endif

/* ------------------------------------------------------------- the clocks */

/*
 * Nanoseconds since 1970-01-01 UTC.
 *
 * Windows counts 100-nanosecond ticks from 1601, so the epoch is shifted and
 * the tick scaled. GetSystemTimePreciseAsFileTime rather than the ordinary one
 * because the latter moves in ~15ms steps, which would make two calls in the
 * same instant compare equal often enough to be surprising.
 */
long long sl_time_now(void)
{
#ifdef _WIN32
    /* 1601-01-01 to 1970-01-01, in 100ns ticks. */
    const long long toUnixEpoch = 116444736000000000LL;

    FILETIME filetime;
    GetSystemTimePreciseAsFileTime(&filetime);

    long long ticks = ((long long)filetime.dwHighDateTime << 32) | filetime.dwLowDateTime;
    return (ticks - toUnixEpoch) * 100LL;
#else
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) return 0;
    return (long long)now.tv_sec * 1000000000LL + now.tv_nsec;
#endif
}

/*
 * Nanoseconds on a clock that only goes forward, from an unspecified zero.
 *
 * The Windows counter's frequency is asked for once: it is fixed for the life
 * of the system, and asking every time would cost more than the reading does.
 * The multiply is done before the divide, on the remainder as well as the
 * whole seconds, so a high-frequency counter neither overflows nor loses
 * precision to integer division.
 */
long long sl_time_monotonic(void)
{
#ifdef _WIN32
    static LARGE_INTEGER frequency;
    if (frequency.QuadPart == 0) QueryPerformanceFrequency(&frequency);
    if (frequency.QuadPart == 0) return 0;

    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);

    long long whole = counter.QuadPart / frequency.QuadPart;
    long long part  = counter.QuadPart % frequency.QuadPart;

    return whole * 1000000000LL + (part * 1000000000LL) / frequency.QuadPart;
#else
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    return (long long)now.tv_sec * 1000000000LL + now.tv_nsec;
#endif
}

/* ----------------------------------------------------------- the calendar */

/*
 * Days since 1970-01-01 back to a civil date. Howard Hinnant's
 * civil_from_days, the inverse of the one below, and correct for any day the
 * Gregorian calendar can name.
 *
 * This is done here rather than by gmtime because the platforms disagree about
 * the past: Windows' gmtime_s refuses a negative time_t outright, so every
 * date before 1970 came back as zeroes. A calendar that stops at the epoch is
 * not a calendar.
 */
static void civil_from_days(long long days, long long *year, long long *month, long long *day)
{
    long long z = days + 719468;
    long long era = (z >= 0 ? z : z - 146096) / 146097;
    long long doe = z - era * 146097;                                   /* [0, 146096] */
    long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;  /* [0, 399] */
    long long y = yoe + era * 400;
    long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);            /* [0, 365] */
    long long mp = (5 * doy + 2) / 153;                                 /* [0, 11] */

    *day = doy - (153 * mp + 2) / 5 + 1;                                /* [1, 31] */
    *month = mp + (mp < 10 ? 3 : -9);                                   /* [1, 12] */
    *year = y + (*month <= 2);
}

/*
 * Howard Hinnant's days_from_civil, the inverse of the one above. March is
 * treated as the first month so that the leap day falls at the end of the
 * year and needs no special case.
 */
static long long days_from_civil(long long year, long long month, long long day)
{
    long long y = year - (month <= 2);
    long long era = (y >= 0 ? y : y - 399) / 400;
    long long yoe = y - era * 400;                                  /* [0, 399] */
    long long doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    long long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;           /* [0, 146096] */
    return era * 146097 + doe - 719468;
}

/* Whole seconds since the epoch for a civil date and time, read as UTC. */
static long long seconds_from_civil(long long year, long long month, long long day,
                                    long long hour, long long minute, long long second)
{
    return ((days_from_civil(year, month, day) * 24 + hour) * 60 + minute) * 60 + second;
}

/* The UTC calendar for whole seconds since the epoch; see sl_time_parts. */
static void utc_parts(long long seconds, long long nanosecond, long long *parts)
{
    /* Floor: -1 second is the day before, at 23:59:59. */
    long long days = seconds / 86400LL;
    long long inDay = seconds % 86400LL;
    if (inDay < 0) { inDay += 86400LL; days -= 1; }

    long long year, month, day;
    civil_from_days(days, &year, &month, &day);

    parts[0] = year;
    parts[1] = month;
    parts[2] = day;
    parts[3] = inDay / 3600;
    parts[4] = (inDay % 3600) / 60;
    parts[5] = inDay % 60;
    parts[6] = nanosecond;

    /* 1970-01-01 was a Thursday, which is 4 with Sunday at 0. The second form
     * is the floor-modulo, for days before the epoch. */
    parts[7] = days >= -4 ? (days + 4) % 7 : (days + 5) % 7 + 6;
    parts[8] = days - days_from_civil(year, 1, 1) + 1;
}

#ifdef _WIN32

/*
 * The CRT's local time stops at 1970, and the zone's own conversions do not:
 * a SYSTEMTIME reaches from 1601 to 30827. These are what the two directions
 * fall back on when localtime_s or mktime refuses a date.
 */
static _Bool system_time_from_seconds(long long seconds, SYSTEMTIME *out)
{
    long long parts[9];
    utc_parts(seconds, 0, parts);
    if (parts[0] < 1601 || parts[0] > 30827) return 0;

    out->wYear = (WORD)parts[0];
    out->wMonth = (WORD)parts[1];
    out->wDayOfWeek = (WORD)parts[7];
    out->wDay = (WORD)parts[2];
    out->wHour = (WORD)parts[3];
    out->wMinute = (WORD)parts[4];
    out->wSecond = (WORD)parts[5];
    out->wMilliseconds = 0;
    return 1;
}

static long long seconds_from_system_time(const SYSTEMTIME *time)
{
    return seconds_from_civil(time->wYear, time->wMonth, time->wDay,
                              time->wHour, time->wMinute, time->wSecond);
}

/* How far ahead of UTC the zone is at a UTC instant, in seconds. */
static _Bool zone_offset_at_utc(long long seconds, long long *offset)
{
    SYSTEMTIME utc, local;
    if (!system_time_from_seconds(seconds, &utc)) return 0;
    if (!SystemTimeToTzSpecificLocalTime(NULL, &utc, &local)) return 0;
    *offset = seconds_from_system_time(&local) - seconds;
    return 1;
}

/* A local time, given as seconds read as UTC, to the UTC instant it names. */
static _Bool utc_from_local(long long localSeconds, long long *seconds)
{
    SYSTEMTIME local, utc;
    if (!system_time_from_seconds(localSeconds, &local)) return 0;
    if (!TzSpecificLocalTimeToSystemTime(NULL, &local, &utc)) return 0;
    *seconds = seconds_from_system_time(&utc);
    return 1;
}

#endif

/*
 * A moment broken into its parts, written through the pointer rather than
 * returned: a struct crossing `extern "C"` would have to be one Stainless
 * declares, and this shape is not a layout worth agreeing on in two places.
 *
 * `parts` receives year, month (1-12), day (1-31), hour, minute, second,
 * nanosecond, day of week (0 = Sunday), day of year (1-366).
 *
 * Returns whether the conversion worked. Only the local path can fail, and
 * only where the platform will not name that instant.
 */
_Bool sl_time_parts(long long nanoseconds, _Bool local, long long *parts)
{
    if (parts == NULL) return 0;

    /*
     * Floor division, not truncation. C divides toward zero, so a negative
     * instant -- any date before 1970 -- would otherwise round the wrong way
     * and land a nanosecond into the following second.
     */
    long long seconds = nanoseconds / 1000000000LL;
    long long rest    = nanoseconds % 1000000000LL;
    if (rest < 0) { rest += 1000000000LL; seconds -= 1; }

    if (local) {
        /*
         * The local zone's rules are the platform's and there is no portable
         * way to compute them, so this is the one path that has to ask.
         */
        time_t when = (time_t)seconds;
        struct tm broken;

#ifdef _WIN32
        if (localtime_s(&broken, &when) != 0) {
            long long offset;
            if (!zone_offset_at_utc(seconds, &offset)) return 0;
            utc_parts(seconds + offset, rest, parts);
            return 1;
        }
#else
        if (localtime_r(&when, &broken) == NULL) return 0;
#endif

        parts[0] = (long long)broken.tm_year + 1900;
        parts[1] = (long long)broken.tm_mon + 1;
        parts[2] = (long long)broken.tm_mday;
        parts[3] = (long long)broken.tm_hour;
        parts[4] = (long long)broken.tm_min;
        parts[5] = (long long)broken.tm_sec;
        parts[6] = rest;
        parts[7] = (long long)broken.tm_wday;
        parts[8] = (long long)broken.tm_yday + 1;
        return 1;
    }

    utc_parts(seconds, rest, parts);
    return 1;
}

/*
 * The other direction: parts back to nanoseconds since the epoch.
 *
 * `local` says which zone the parts are in. `timegm` is not portable, so UTC
 * goes through the same arithmetic the calendar uses -- days since the epoch
 * from a civil date -- rather than through a second library function that half
 * the platforms spell differently.
 *
 * Local time asks mktime. Where mktime refuses -- before 1970 on Windows, past
 * a 32-bit time_t elsewhere -- Windows asks the zone directly, and failing that
 * the answer is the parts read as UTC less the zone's offset near that
 * instant, which is right everywhere but inside a daylight-saving change.
 */
long long sl_time_from_parts(long long year, long long month, long long day,
                             long long hour, long long minute, long long second,
                             long long nanosecond, _Bool local)
{
    long long asUtc = seconds_from_civil(year, month, day, hour, minute, second);
    if (!local) return asUtc * 1000000000LL + nanosecond;

    struct tm broken;
    broken.tm_year  = (int)(year - 1900);
    broken.tm_mon   = (int)(month - 1);
    broken.tm_mday  = (int)day;
    broken.tm_hour  = (int)hour;
    broken.tm_min   = (int)minute;
    broken.tm_sec   = (int)second;
    broken.tm_isdst = -1;       /* let the platform decide */

    /* -1 is also 1969-12-31 23:59:59 UTC. mktime fills in the day of the
     * week only when it succeeds, which is what tells the two apart. */
    broken.tm_wday  = -1;

    time_t when = mktime(&broken);
    if (when != (time_t)-1 || broken.tm_wday != -1)
        return (long long)when * 1000000000LL + nanosecond;

    long long seconds;
#ifdef _WIN32
    if (utc_from_local(asUtc, &seconds))
        return seconds * 1000000000LL + nanosecond;
#endif

    seconds = asUtc - sl_time_zone_offset(asUtc * 1000000000LL);
    seconds = asUtc - sl_time_zone_offset(seconds * 1000000000LL);
    return seconds * 1000000000LL + nanosecond;
}

/* The local zone's offset from UTC at a given moment, in seconds. */
long long sl_time_zone_offset(long long nanoseconds)
{
    long long parts[9];
    if (!sl_time_parts(nanoseconds, 1, parts)) return 0;

    long long asUtc = sl_time_from_parts(parts[0], parts[1], parts[2],
                                         parts[3], parts[4], parts[5], 0, 0);

    /* The local parts read as if they were UTC, minus the actual instant, is
     * exactly how far ahead of UTC the local zone is. */
    return (asUtc - (nanoseconds - parts[6])) / 1000000000LL;
}
