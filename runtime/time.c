/*
 * Stainless - an experimental systems language.
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
 * A moment broken into its parts, written through the pointer rather than
 * returned: a struct crossing `extern "C"` would have to be one Stainless
 * declares, and this shape is not a layout worth agreeing on in two places.
 *
 * `parts` receives year, month (1-12), day (1-31), hour, minute, second,
 * nanosecond, day of week (0 = Sunday), day of year (1-366).
 *
 * Returns whether the conversion worked. Only the local path can now fail,
 * and only where the platform will not name that instant.
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
         * way to compute them, so this is the one path that has to ask. It
         * inherits the platform's limits, including a Windows that will not
         * name a date before 1970.
         */
        time_t when = (time_t)seconds;
        struct tm broken;

#ifdef _WIN32
        if (localtime_s(&broken, &when) != 0) return 0;
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

    /* Floor again: -1 second is the day before, at 23:59:59. */
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
    parts[6] = rest;

    /* 1970-01-01 was a Thursday, which is 4 with Sunday at 0. The second form
     * is the floor-modulo, for days before the epoch. */
    parts[7] = days >= -4 ? (days + 4) % 7 : (days + 5) % 7 + 6;

    /* Day of year, from the first of January in the year just computed. */
    long long januaryFirst = sl_time_from_parts(year, 1, 1, 0, 0, 0, 0, 0) / 1000000000LL / 86400LL;
    parts[8] = days - januaryFirst + 1;
    return 1;
}

/*
 * The other direction: parts back to nanoseconds since the epoch.
 *
 * `local` says which zone the parts are in. `timegm` is not portable, so UTC
 * goes through the same arithmetic the calendar uses -- days since the epoch
 * from a civil date -- rather than through a second library function that half
 * the platforms spell differently.
 */
long long sl_time_from_parts(long long year, long long month, long long day,
                             long long hour, long long minute, long long second,
                             long long nanosecond, _Bool local)
{
    if (local) {
        struct tm broken;
        broken.tm_year  = (int)(year - 1900);
        broken.tm_mon   = (int)(month - 1);
        broken.tm_mday  = (int)day;
        broken.tm_hour  = (int)hour;
        broken.tm_min   = (int)minute;
        broken.tm_sec   = (int)second;
        broken.tm_isdst = -1;       /* let the platform decide */

        time_t when = mktime(&broken);
        if (when == (time_t)-1) return 0;
        return (long long)when * 1000000000LL + nanosecond;
    }

    /*
     * Howard Hinnant's days_from_civil. March is treated as the first month so
     * that the leap day falls at the end of the year and needs no special case.
     */
    long long y = year - (month <= 2);
    long long era = (y >= 0 ? y : y - 399) / 400;
    long long yoe = y - era * 400;                                  /* [0, 399] */
    long long doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    long long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;           /* [0, 146096] */
    long long days = era * 146097 + doe - 719468;

    return ((days * 24 + hour) * 60 + minute) * 60000000000LL
         + second * 1000000000LL + nanosecond;
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
