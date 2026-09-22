// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Clocks and calendars.
//
// A convenience layer over `Win32.Kernel32`. Nothing here needs a `-l`.
//
// Windows keeps two kinds of time and they are not interchangeable. A
// `FILETIME` is 100-nanosecond ticks since 1601 and is what the filesystem and
// the calendar use. The performance counter is a monotonic tick with no epoch
// at all, and is the only one of the two that may be subtracted to measure how
// long something took: the wall clock moves when the user changes it, and again
// twice a year.
module Win32.Clock;

#if WINDOWS

import Win32;
import Win32.Kernel32;

// ================================================================= calendar

/// A `FILETIME`'s two halves as the number they represent: 100-nanosecond
/// ticks since 1 January 1601, UTC.
public ulong FileTimeToTicks(FileTime time)
{
    return ((ulong)time.High << 32) | (ulong)time.Low;
}

/// The number back into the pair Windows wants.
public FileTime TicksToFileTime(ulong ticks)
{
    FileTime time;
    time.Low = (uint)(ticks & 0xFFFFFFFFu);
    time.High = (uint)(ticks >> 32);
    return time;
}

/// Now, in UTC.
public SystemTime GetUtcNow()
{
    SystemTime time;
    GetSystemTime(&time);
    return time;
}

/// Now, in the machine's own time zone.
public SystemTime GetLocalNow()
{
    SystemTime time;
    GetLocalTime(&time);
    return time;
}

/// Now as ticks, which is the form to store and to subtract.
public ulong GetUtcNowTicks()
{
    FileTime time;
    GetSystemTimeAsFileTime(&time);
    return FileTimeToTicks(time);
}

/// A `FILETIME` as a calendar date, or a zeroed one if Windows refuses it.
public SystemTime TicksToSystemTime(ulong ticks)
{
    FileTime file = TicksToFileTime(ticks);
    SystemTime time;
    time.Year = 0u;
    if (!Win32.IsBoolSuccess(FileTimeToSystemTime(&file, &time)))
        time.Year = 0u;
    return time;
}

/// A calendar date as ticks, or 0 if Windows refuses it.
public ulong SystemTimeToTicks(SystemTime time)
{
    SystemTime input = time;
    FileTime file;
    if (!Win32.IsBoolSuccess(SystemTimeToFileTime(&input, &file)))
        return 0u;
    return FileTimeToTicks(file);
}

/// The same instant, expressed in the machine's time zone.
public ulong TicksToLocalTicks(ulong ticks)
{
    FileTime utc = TicksToFileTime(ticks);
    FileTime local;
    if (!Win32.IsBoolSuccess(FileTimeToLocalFileTime(&utc, &local)))
        return ticks;
    return FileTimeToTicks(local);
}

/// The Unix epoch as Windows ticks: 1 January 1970 is this far after 1601.
public const ulong UnixEpochTicks = 116444736000000000u;

/// Windows ticks as seconds since the Unix epoch, which is what every other
/// system in the world means by a timestamp.
public long TicksToUnixSeconds(ulong ticks)
{
    return (long)((ticks - UnixEpochTicks) / 10000000u);
}

public ulong UnixSecondsToTicks(long seconds)
{
    return UnixEpochTicks + (ulong)seconds * 10000000u;
}

/// `2026-09-03 21:47:12`, which sorts correctly as text.
public String FormatSystemTime(SystemTime time)
{
    return FormatSystemDate(time)
        + " " + PadNumber(time.Hour, 2u) + ":" + PadNumber(time.Minute, 2u)
        + ":" + PadNumber(time.Second, 2u);
}

/// `2026-09-03`, without the time of day.
public String FormatSystemDate(SystemTime time)
{
    return PadNumber(time.Year, 4u) + "-" + PadNumber(time.Month, 2u)
        + "-" + PadNumber(time.Day, 2u);
}

String PadNumber(ushort value, nuint width)
{
    String text = Text.FromInteger((long)value);
    while (text.ByteLength() < width)
        text = "0" + text;
    return text;
}

// ================================================================== elapsed

/// Milliseconds since the machine booted. Cheap, monotonic, and about 15ms
/// granular, which is the scheduler's tick rather than a limit of the call.
public ulong GetUptimeMilliseconds() => GetTickCount64();

/// The performance counter, in its own units. Meaningless on its own;
/// `ReadPerformanceFrequency()` is what turns a difference into seconds.
public long ReadPerformanceCounter()
{
    long count = 0;
    QueryPerformanceCounter(&count);
    return count;
}

/// How many counter units there are in a second. Fixed while the machine runs,
/// so it is worth asking once.
public long ReadPerformanceFrequency()
{
    long frequency = 0;
    QueryPerformanceFrequency(&frequency);
    return frequency;
}

/// Measures how long something took, in seconds, from two counter readings.
public double MeasureSecondsBetween(long from, long to)
{
    long frequency = ReadPerformanceFrequency();
    if (frequency == 0)
        return 0.0;
    return (double)(to - from) / (double)frequency;
}

/// A stopwatch, which is the counter and one subtraction wearing a name.
public class Stopwatch
{
    long _start;
    long _frequency;

    public Stopwatch()
    {
        _frequency = ReadPerformanceFrequency();
        _start = ReadPerformanceCounter();
    }

    /// Starts again from now.
    public void Restart() => _start = ReadPerformanceCounter();

    /// Seconds since the last start.
    public double GetElapsedSeconds()
    {
        if (_frequency == 0)
            return 0.0;
        return (double)(ReadPerformanceCounter() - _start) / (double)_frequency;
    }

    public double GetElapsedMilliseconds() => GetElapsedSeconds() * 1000.0;
}

#endif
