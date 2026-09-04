// Stainless - an experimental systems language.
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
public ulong Ticks(FileTime time) {
    return ((ulong)time.High << 32) | (ulong)time.Low;
}

/// The number back into the pair Windows wants.
public FileTime FromTicks(ulong ticks) {
    FileTime time;
    time.Low = (uint)(ticks & 0xFFFFFFFFu);
    time.High = (uint)(ticks >> 32);
    return time;
}

/// Now, in UTC.
public SystemTime UtcNow() {
    SystemTime time;
    GetSystemTime(&time);
    return time;
}

/// Now, in the machine's own time zone.
public SystemTime Now() {
    SystemTime time;
    GetLocalTime(&time);
    return time;
}

/// Now as ticks, which is the form to store and to subtract.
public ulong NowTicks() {
    FileTime time;
    GetSystemTimeAsFileTime(&time);
    return Ticks(time);
}

/// A `FILETIME` as a calendar date, or a zeroed one if Windows refuses it.
public SystemTime ToCalendar(ulong ticks) {
    FileTime file = FromTicks(ticks);
    SystemTime time;
    time.Year = 0u;
    if (!Win32.Succeeded(FileTimeToSystemTime(&file, &time))) { time.Year = 0u; }
    return time;
}

/// A calendar date as ticks, or 0 if Windows refuses it.
public ulong FromCalendar(SystemTime time) {
    SystemTime input = time;
    FileTime file;
    if (!Win32.Succeeded(SystemTimeToFileTime(&input, &file))) { return 0u; }
    return Ticks(file);
}

/// The same instant, expressed in the machine's time zone.
public ulong ToLocal(ulong ticks) {
    FileTime utc = FromTicks(ticks);
    FileTime local;
    if (!Win32.Succeeded(FileTimeToLocalFileTime(&utc, &local))) { return ticks; }
    return Ticks(local);
}

/// The Unix epoch as Windows ticks: 1 January 1970 is this far after 1601.
public const ulong UnixEpochTicks = 116444736000000000u;

/// Windows ticks as seconds since the Unix epoch, which is what every other
/// system in the world means by a timestamp.
public long ToUnixSeconds(ulong ticks) {
    return (long)((ticks - UnixEpochTicks) / 10000000u);
}

public ulong FromUnixSeconds(long seconds) {
    return UnixEpochTicks + (ulong)seconds * 10000000u;
}

/// `2026-09-03 21:47:12`, which sorts correctly as text.
public String Format(SystemTime time) {
    return Pad(time.Year, 4u) + "-" + Pad(time.Month, 2u) + "-" + Pad(time.Day, 2u)
        + " " + Pad(time.Hour, 2u) + ":" + Pad(time.Minute, 2u)
        + ":" + Pad(time.Second, 2u);
}

/// `2026-09-03`, without the time of day.
public String FormatDate(SystemTime time) {
    return Pad(time.Year, 4u) + "-" + Pad(time.Month, 2u) + "-" + Pad(time.Day, 2u);
}

String Pad(ushort value, nuint width) {
    String text = Text.FromInteger((long)value);
    while (text.ByteLength() < width) { text = "0" + text; }
    return text;
}

// ================================================================== elapsed

/// Milliseconds since the machine booted. Cheap, monotonic, and about 15ms
/// granular, which is the scheduler's tick rather than a limit of the call.
public ulong Uptime() { return GetTickCount64(); }

/// The performance counter, in its own units. Meaningless on its own;
/// `Frequency()` is what turns a difference into seconds.
public long Counter() {
    long count = 0;
    QueryPerformanceCounter(&count);
    return count;
}

/// How many counter units there are in a second. Fixed while the machine runs,
/// so it is worth asking once.
public long Frequency() {
    long frequency = 0;
    QueryPerformanceFrequency(&frequency);
    return frequency;
}

/// Measures how long something took, in seconds, from two counter readings.
public double Elapsed(long from, long to) {
    long frequency = Frequency();
    if (frequency == 0) { return 0.0; }
    return (double)(to - from) / (double)frequency;
}

/// A stopwatch, which is the counter and one subtraction wearing a name.
public class Stopwatch {
    long start;
    long frequency;

    public Stopwatch() {
        frequency = Frequency();
        start = Counter();
    }

    /// Starts again from now.
    public void Restart() { start = Counter(); }

    /// Seconds since the last start.
    public double Seconds() {
        if (frequency == 0) { return 0.0; }
        return (double)(Counter() - start) / (double)frequency;
    }

    public double Milliseconds() { return Seconds() * 1000.0; }
}

#endif
