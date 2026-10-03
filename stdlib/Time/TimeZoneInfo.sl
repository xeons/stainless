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

module Standard.Time;

import Standard.Collections;
import Standard.Env;
import Standard.File;

extern "C"
{
    long sl_tz_local_name(byte* buffer, nuint size);
    long sl_tz_windows_zone(byte* id, long index, long firstYear, long count, long* rules,
                            byte* names, nuint size);
    long sl_tz_map_id(byte* id, bool toWindows, byte* buffer, nuint size);
}

/// `numerator / denominator`, rounded down rather than towards zero.
long FloorDivide(long numerator, long denominator)
{
    long quotient = numerator / denominator;
    return quotient * denominator > numerator ? quotient - 1 : quotient;
}

/// A time zone, and the rules that move its clocks: C#'s `System.TimeZoneInfo`.
///
///     if (TimeZoneInfo.FindSystemTimeZoneById("Europe/Paris") is Ok paris)
///         var there = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, paris.Value);
///
/// On Linux and macOS the zones are the IANA database's, read from
/// `/usr/share/zoneinfo` (or `TZDIR`), and named as it names them. On Windows
/// they are the system's, named by their registry keys, and an IANA name finds
/// the zone it maps to where Windows carries ICU to map it.
///
/// `DateTimeOffset` here is an instant with no offset of its own, so a time
/// converted into a zone is the `DateTime` its clocks read, where C# answers
/// with a `DateTimeOffset` carrying the offset. A wall-clock time the zone
/// skips is `TimeError.Invalid`, where C# throws; one it passes twice is read
/// as standard time, as C# reads it.
public sealed class TimeZoneInfo : IEquatable<TimeZoneInfo>, IHashable
{
    String _id;
    String _displayName;
    String _standardName;
    String _daylightName;
    bool _ianaId;

    // In force before the first transition.
    long _initialOffset;
    bool _initialDaylight;

    // The instant each change happens, in seconds since 1970, and what the
    // clocks read after it.
    List<long> _transitions;
    List<long> _offsets;
    List<bool> _daylight;

    // In force after the last transition.
    bool _hasRule;
    ZoneRule _rule;

    TimeZoneInfo(String id)
    {
        _id = id;
        _displayName = id;
        _standardName = id;
        _daylightName = id;
        _transitions = new List<long>();
        _offsets = new List<long>();
        _daylight = new List<bool>();
        _rule.StandardName = "";
        _rule.DaylightName = "";
    }

    // ------------------------------------------------------------ the zones

    /// Coordinated Universal Time.
    public static TimeZoneInfo Utc
    {
        get
        {
            var utc = new TimeZoneInfo("UTC");
            utc._displayName = "(UTC) Coordinated Universal Time";
            utc._standardName = "Coordinated Universal Time";
            utc._daylightName = "Coordinated Universal Time";
            utc._ianaId = true;
            return utc;
        }
    }

    /// The zone this machine is set to, or UTC when it cannot say.
    public static TimeZoneInfo Local
    {
        get
        {
#if WINDOWS
            if (LocalName() is Some name && FindSystemTimeZoneById(name.Value) is Ok local)
                return local.Value;
#else
            String? tz = GetEnvironmentVariable("TZ");
            if (tz != null && !tz.IsEmpty)
            {
                String named = tz.StartsWith(":") ? tz.Substring(1u) : tz;
                if (named.StartsWith("/") && FromFile(named, named) is Ok fromPath)
                    return fromPath.Value;
                if (FindSystemTimeZoneById(named) is Ok byName)
                    return byName.Value;
                if (ReadPosixRule(named) is Some posix)
                    return FromRule(named, posix.Value);
            }

            String id = LocalName() is Some linked ? linked.Value : "Local";
            if (FromFile("/etc/localtime", id) is Ok local)
                return local.Value;
#endif
            return Utc;
        }
    }

    static Optional<String> LocalName()
    {
        byte[] buffer = new byte[256];
        long length = sl_tz_local_name(&buffer[0], buffer.Length);
        return length > 0 ? Some(Text.FromBytes(&buffer[0], (nuint)length)) : None;
    }

    /// The zone named `id`: an IANA name on Linux and macOS, a registry key
    /// name on Windows, and an IANA name there too where Windows can map it.
    ///
    /// @failure TimeError.NotFound  no zone of that name
    public static Result<TimeZoneInfo, TimeError> FindSystemTimeZoneById(String id)
    {
        if (id == "UTC")
            return Ok(Utc);

#if WINDOWS
        if (FromWindows(id, -1, id) is Ok found)
            return Ok(found.Value);

        String windowsId;
        if (TryConvertIanaIdToWindowsId(id, out windowsId) && FromWindows(windowsId, -1, id) is Ok mapped)
        {
            mapped.Value._ianaId = true;
            return Ok(mapped.Value);
        }
        return Fail(TimeError.NotFound);
#else
        // A name is a path under the database, and MUST NOT climb out of it.
        if (id.IsEmpty || id.Contains("..") || id.StartsWith("/"))
            return Fail(TimeError.NotFound);
        return FromFile(ZoneDirectory() + "/" + id, id);
#endif
    }

    /// Every zone the system knows, by offset and then by name.
    public static List<TimeZoneInfo> GetSystemTimeZones()
    {
        var zones = new List<TimeZoneInfo>();
#if WINDOWS
        for (long index = 0; FromWindows("", index, "") is Ok zone; index++)
            zones.Add(zone.Value);
#else
        String directory = ZoneDirectory();
        var table = ReadAllLines(directory + "/zone1970.tab");
        if (table is Fail)
            table = ReadAllLines(directory + "/zone.tab");
        zones.Add(Utc);
        if (table is Ok lines)
        {
            foreach (var line in lines.Value)
            {
                if (line.StartsWith("#"))
                    continue;
                String[] columns = line.Split('\t');
                if (columns.Length >= 3u && FindSystemTimeZoneById(columns[2]) is Ok zone)
                    zones.Add(zone.Value);
            }
        }
#endif
        Sort(zones, (a, b) =>
        {
            int byOffset = TimeSpan.Compare(a.BaseUtcOffset, b.BaseUtcOffset);
            return byOffset != 0 ? byOffset : a.DisplayName.CompareTo(b.DisplayName);
        });
        return zones;
    }

    /// A zone of one offset and no daylight time.
    public static TimeZoneInfo CreateCustomTimeZone(
        String id, TimeSpan baseUtcOffset, String displayName, String standardName)
    {
        var made = new TimeZoneInfo(id);
        made._initialOffset = baseUtcOffset.Nanoseconds / NanosecondsPerSecond;
        made._displayName = displayName;
        made._standardName = standardName;
        made._daylightName = standardName;
        return made;
    }

    /// The Windows key name an IANA name maps to, where Windows carries ICU
    /// to ask. Never, elsewhere.
    public static bool TryConvertIanaIdToWindowsId(String ianaId, out String windowsId) =>
        MapId(ianaId, true, out windowsId);

    /// The IANA name a Windows key name maps to, where Windows carries ICU to
    /// ask. Never, elsewhere.
    public static bool TryConvertWindowsIdToIanaId(String windowsId, out String ianaId) =>
        MapId(windowsId, false, out ianaId);

    static bool MapId(String id, bool toWindows, out String mapped)
    {
        byte[] buffer = new byte[256];
        long length = sl_tz_map_id(id.ToPointer(), toWindows, &buffer[0], buffer.Length);
        mapped = length > 0 ? Text.FromBytes(&buffer[0], (nuint)length) : "";
        return length > 0;
    }

    // ------------------------------------------------------------- converting

    /// What the clocks in `destination` read at `instant`.
    public static DateTime ConvertTime(DateTimeOffset instant, TimeZoneInfo destination) =>
        WallClock(instant.Nanoseconds, destination.OffsetAt(instant.Nanoseconds).Item1);

    /// What the clocks in `destination` read when those in `source` read
    /// `wallClock`.
    ///
    /// @failure TimeError.Invalid  `source` skips that time
    public static Result<DateTime, TimeError> ConvertTime(
        DateTime wallClock, TimeZoneInfo source, TimeZoneInfo destination)
    {
        if (ConvertTimeToUtc(wallClock, source) is not Ok instant)
            return Fail(TimeError.Invalid);
        return Ok(ConvertTime(instant.Value, destination));
    }

    /// The instant at which the clocks in `source` read `wallClock`.
    ///
    /// @failure TimeError.Invalid  `source` skips that time
    public static Result<DateTimeOffset, TimeError> ConvertTimeToUtc(DateTime wallClock, TimeZoneInfo source)
    {
        var offsets = source.OffsetsReading(wallClock);
        if (offsets.Count == 0u)
            return Fail(TimeError.Invalid);

        DateTimeOffset instant;
        instant.Nanoseconds = (WallSeconds(wallClock) - offsets[0]) * NanosecondsPerSecond + (long)wallClock.Nanosecond;
        return Ok(instant);
    }

    /// What the clocks in `destination` read when UTC reads `utc`.
    public static DateTime ConvertTimeFromUtc(DateTime utc, TimeZoneInfo destination)
    {
        DateTimeOffset instant;
        instant.Nanoseconds = WallSeconds(utc) * NanosecondsPerSecond + (long)utc.Nanosecond;
        return ConvertTime(instant, destination);
    }

    /// What the clocks in the zone named `id` read at `instant`.
    ///
    /// @failure TimeError.NotFound  no zone of that name
    public static Result<DateTime, TimeError> ConvertTimeBySystemTimeZoneId(DateTimeOffset instant, String id)
    {
        if (FindSystemTimeZoneById(id) is not Ok zone)
            return Fail(TimeError.NotFound);
        return Ok(ConvertTime(instant, zone.Value));
    }

    // ----------------------------------------------------------------- asking

    /// What it is called: an IANA name or a Windows key name.
    public String Id => _id;

    /// How a person would recognise it, with its offset.
    public String DisplayName => _displayName;

    /// What standard time there is called.
    public String StandardName => _standardName;

    /// What daylight time there is called.
    public String DaylightName => _daylightName;

    /// Whether `Id` is an IANA name.
    public bool HasIanaId => _ianaId;

    /// How far ahead of UTC standard time is, as the zone keeps it now.
    public TimeSpan BaseUtcOffset
    {
        get
        {
            if (_hasRule)
                return TimeSpan.FromSeconds(_rule.StandardOffset);
            for (nuint i = _offsets.Count; i > 0u; i--)
            {
                if (!_daylight[i - 1u])
                    return TimeSpan.FromSeconds(_offsets[i - 1u]);
            }
            return TimeSpan.FromSeconds(_initialOffset);
        }
    }

    /// Whether its clocks have changed for daylight time since 1970, which
    /// is as far back as every platform's data reaches: India's clocks did
    /// in the 1940s, and India's zone is still one that does not.
    public bool SupportsDaylightSavingTime
    {
        get
        {
            if (_hasRule && _rule.HasDaylight)
                return true;
            for (nuint i = 0u; i < _daylight.Count; i++)
            {
                if (_daylight[i] && _transitions[i] >= 0)
                    return true;
            }
            return false;
        }
    }

    /// How far ahead of UTC the clocks are at `instant`.
    public TimeSpan GetUtcOffset(DateTimeOffset instant) =>
        TimeSpan.FromSeconds(OffsetAt(instant.Nanoseconds).Item1);

    /// How far ahead of UTC the clocks are when they read `wallClock`:
    /// standard time where they read it twice, and the offset before the
    /// change where they skip it.
    public TimeSpan GetUtcOffset(DateTime wallClock)
    {
        var offsets = OffsetsReading(wallClock);
        if (offsets.Count > 0u)
            return TimeSpan.FromSeconds(offsets[0]);
        return TimeSpan.FromSeconds(OffsetAtSeconds(WallSeconds(wallClock) - 86400).Item1);
    }

    /// Whether the clocks keep daylight time at `instant`.
    public bool IsDaylightSavingTime(DateTimeOffset instant) => OffsetAt(instant.Nanoseconds).Item2;

    /// Whether the clocks keep daylight time when they read `wallClock`.
    public bool IsDaylightSavingTime(DateTime wallClock)
    {
        var offsets = OffsetsReading(wallClock);
        return offsets.Count > 0u && OffsetAtSeconds(WallSeconds(wallClock) - offsets[0]).Item2;
    }

    /// Whether the clocks read `wallClock` twice, as they do when they go back.
    public bool IsAmbiguousTime(DateTime wallClock) => OffsetsReading(wallClock).Count > 1u;

    /// Whether the clocks never read `wallClock`, as when they go forward.
    public bool IsInvalidTime(DateTime wallClock) => OffsetsReading(wallClock).Count == 0u;

    /// The display name.
    public String ToString() => _displayName;

    public bool Equals(TimeZoneInfo other) => _id == other._id;

    public nuint GetHashCode()
    {
        nuint hash = 0u;
        for (nuint i = 0u; i < _id.ByteLength(); i++)
            hash = hash * 31u + (nuint)_id.GetByteAt(i);
        return hash;
    }

    // ------------------------------------------------------------- the engine

    (long, bool) OffsetAt(long nanoseconds) => OffsetAtSeconds(FloorDivide(nanoseconds, NanosecondsPerSecond));

    /// The offset and whether it is daylight time, at `seconds` since 1970.
    (long, bool) OffsetAtSeconds(long seconds)
    {
        nuint count = _transitions.Count;
        if (count == 0u || seconds < _transitions[0])
            return count == 0u && _hasRule ? RuleOffsetAt(_rule, seconds) : (_initialOffset, _initialDaylight);

        if (seconds >= _transitions[count - 1u] && _hasRule)
            return RuleOffsetAt(_rule, seconds);

        // The last transition at or before `seconds`.
        nuint low = 0u;
        nuint high = count;
        while (high - low > 1u)
        {
            nuint middle = low + (high - low) / 2u;
            if (_transitions[middle] <= seconds)
                low = middle;
            else
                high = middle;
        }
        return (_offsets[low], _daylight[low]);
    }

    /// Each offset under which the clocks read `wallClock`, standard time
    /// first: none where they skip it, two where they read it twice.
    List<long> OffsetsReading(DateTime wallClock)
    {
        long local = WallSeconds(wallClock);
        var found = new List<long>();

        long[3] tried;
        tried[0] = OffsetAtSeconds(local - 86400).Item1;
        tried[1] = OffsetAtSeconds(local).Item1;
        tried[2] = OffsetAtSeconds(local + 86400).Item1;

        for (nuint i = 0u; i < 3u; i++)
        {
            long offset = tried[i];
            if (found.Contains(offset))
                continue;
            var (actual, daylight) = OffsetAtSeconds(local - offset);
            if (actual != offset)
                continue;
            if (!daylight)
                found.Insert(0u, offset);
            else
                found.Add(offset);
        }
        return found;
    }

    /// The offset `rule` gives at `seconds` since 1970.
    static (long, bool) RuleOffsetAt(ZoneRule rule, long seconds)
    {
        if (!rule.HasDaylight)
            return (rule.StandardOffset, false);

        long year = CivilFromDays(FloorDivide(seconds + rule.StandardOffset, 86400)).Item1;
        long start = LocalSecondsOf(rule.Start, year) - rule.StandardOffset;
        long end = LocalSecondsOf(rule.End, year) - rule.DaylightOffset;

        // South of the equator daylight time spans the new year, and starts
        // later in the year than it ends.
        bool daylight = start < end
            ? seconds >= start && seconds < end
            : !(seconds >= end && seconds < start);
        return daylight ? (rule.DaylightOffset, true) : (rule.StandardOffset, false);
    }

    /// When `point` falls in `year`, in local seconds since 1970.
    static long LocalSecondsOf(RulePoint point, long year)
    {
        long days;
        switch (point.Kind)
        {
            case 0:
            {
                long first = DaysFromCivil(year, (long)point.Month, 1);
                long firstWeekday = ((first + 4) % 7 + 7) % 7;
                days = first + ((long)point.Weekday - firstWeekday + 7) % 7 + (long)(point.Week - 1) * 7;
                long past = first + (long)DaysInMonth((int)year, point.Month);
                while (days >= past)
                    days -= 7;
                break;
            }
            case 1:
                days = DaysFromCivil(year, 1, 1) + (long)point.Day - 1 +
                       (IsLeapYear((int)year) && point.Day >= 60 ? 1 : 0);
                break;
            case 2:
                days = DaysFromCivil(year, 1, 1) + (long)point.Day;
                break;
            default:
                days = DaysFromCivil(year, (long)point.Month, (long)point.Day);
                break;
        }
        return days * 86400 + point.Seconds;
    }

    /// `wallClock` read as though it were UTC, in seconds since 1970.
    static long WallSeconds(DateTime wallClock) =>
        DaysFromCivil((long)wallClock.Year, (long)wallClock.Month, (long)wallClock.Day) * 86400 +
        (long)wallClock.Hour * 3600 + (long)wallClock.Minute * 60 + (long)wallClock.Second;

    /// What clocks `offset` seconds ahead of UTC read at `nanoseconds` since 1970.
    static DateTime WallClock(long nanoseconds, long offset)
    {
        long total = nanoseconds + offset * NanosecondsPerSecond;
        long days = FloorDivide(total, NanosecondsPerDay);
        long within = total - days * NanosecondsPerDay;
        var (year, month, day) = CivilFromDays(days);

        DateTime when;
        when.Year = (int)year;
        when.Month = (int)month;
        when.Day = (int)day;
        when.Hour = (int)(within / NanosecondsPerHour);
        when.Minute = (int)(within / NanosecondsPerMinute % 60);
        when.Second = (int)(within / NanosecondsPerSecond % 60);
        when.Nanosecond = (int)(within % NanosecondsPerSecond);
        when.DayOfWeek = (int)(((days + 4) % 7 + 7) % 7);
        when.DayOfYear = (int)(days - DaysFromCivil(year, 1, 1) + 1);
        return when;
    }

    /// `(UTC+01:00) name`, as C# writes a display name.
    static String OffsetDisplay(long offset, String name)
    {
        long minutes = (offset < 0 ? -offset : offset) / 60;
        String sign = offset < 0 ? "-" : "+";
        return offset == 0
            ? "(UTC) " + name
            : "(UTC" + sign + PadNumber(minutes / 60, 2u) + ":" + PadNumber(minutes % 60, 2u) + ") " + name;
    }

    void AddTransition(long seconds, long offset, bool daylight)
    {
        _transitions.Add(seconds);
        _offsets.Add(offset);
        _daylight.Add(daylight);
    }

    /// The names and display name, once the rules are known.
    void Describe()
    {
        if (_hasRule)
        {
            _standardName = _rule.StandardName;
            _daylightName = _rule.HasDaylight ? _rule.DaylightName : _rule.StandardName;
        }
        _displayName = OffsetDisplay(BaseUtcOffset.Nanoseconds / NanosecondsPerSecond, _id);
    }

    // -------------------------------------------------------- a POSIX TZ rule

    /// A zone that is `rule` and nothing else.
    static TimeZoneInfo FromRule(String id, ZoneRule rule)
    {
        var made = new TimeZoneInfo(id);
        made._hasRule = true;
        made._rule = rule;
        made._initialOffset = rule.StandardOffset;
        made.Describe();
        return made;
    }

    /// A rule as POSIX writes one: `EST5EDT,M3.2.0,M11.1.0`, or `<+0530>-5:30`.
    static Optional<ZoneRule> ReadPosixRule(String text)
    {
        ZoneRule rule;
        nuint at = 0u;

        if (ReadRuleName(text, ref at) is not Some standard)
            return None;
        if (ReadRuleOffset(text, ref at) is not Some standardOffset)
            return None;

        rule.StandardName = standard.Value;
        rule.DaylightName = standard.Value;
        rule.StandardOffset = -standardOffset.Value;
        rule.DaylightOffset = rule.StandardOffset;
        rule.HasDaylight = false;
        if (at == text.ByteLength())
            return Some(rule);

        if (ReadRuleName(text, ref at) is not Some daylight)
            return None;
        rule.DaylightName = daylight.Value;
        rule.HasDaylight = true;
        rule.DaylightOffset = rule.StandardOffset + 3600;
        if (at < text.ByteLength() && text.GetByteAt(at) != (byte)',')
        {
            if (ReadRuleOffset(text, ref at) is not Some daylightOffset)
                return None;
            rule.DaylightOffset = -daylightOffset.Value;
        }

        // No dates is the United States' rule, which is what C libraries assume.
        String dates = at < text.ByteLength() ? text.Substring(at) : ",M3.2.0,M11.1.0";
        String[] parts = dates.Split(',');
        if (parts.Length != 3u || !parts[0].IsEmpty)
            return None;
        if (ReadRulePoint(parts[1]) is not Some start || ReadRulePoint(parts[2]) is not Some end)
            return None;
        rule.Start = start.Value;
        rule.End = end.Value;
        return Some(rule);
    }

    static Optional<String> ReadRuleName(String text, ref nuint at)
    {
        nuint start = at;
        if (at < text.ByteLength() && text.GetByteAt(at) == (byte)'<')
        {
            long close = text.IndexOf(">", at);
            if (close < 0)
                return None;
            at = (nuint)close + 1u;
            return Some(text.Substring(start + 1u, (nuint)close - start - 1u));
        }

        while (at < text.ByteLength() && IsRuleLetter(text.GetByteAt(at)))
            at++;
        return at - start >= 3u ? Some(text.Substring(start, at - start)) : None;
    }

    static bool IsRuleLetter(byte c) => (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z');

    /// `[+-]hh[:mm[:ss]]` in seconds, west positive as POSIX writes it.
    static Optional<long> ReadRuleOffset(String text, ref nuint at)
    {
        long sign = 1;
        if (at < text.ByteLength() && (text.GetByteAt(at) == (byte)'+' || text.GetByteAt(at) == (byte)'-'))
        {
            sign = text.GetByteAt(at) == (byte)'-' ? -1 : 1;
            at++;
        }

        long seconds = 0;
        for (int part = 0; part < 3; part++)
        {
            nuint start = at;
            long value = 0;
            while (at < text.ByteLength() && text.GetByteAt(at) >= (byte)'0' && text.GetByteAt(at) <= (byte)'9')
            {
                value = value * 10 + (long)(text.GetByteAt(at) - (byte)'0');
                at++;
            }
            if (at == start)
                return part == 0 ? None : Some(sign * seconds);

            seconds += value * (part == 0 ? 3600 : part == 1 ? 60 : 1);
            if (at >= text.ByteLength() || text.GetByteAt(at) != (byte)':')
                break;
            at++;
        }
        return Some(sign * seconds);
    }

    /// `Mm.w.d`, `Jn` or `n`, then `/time`.
    static Optional<RulePoint> ReadRulePoint(String text)
    {
        RulePoint point;
        point.Seconds = 7200;

        String date = text;
        long slash = text.IndexOf('/');
        if (slash >= 0)
        {
            date = text.Substring(0u, (nuint)slash);
            nuint at = (nuint)slash + 1u;
            if (ReadRuleOffset(text, ref at) is not Some time)
                return None;
            point.Seconds = time.Value;
        }

        if (date.StartsWith("M"))
        {
            String[] fields = date.Substring(1u).Split('.');
            if (fields.Length != 3u || ParseDecimal(fields[0]) is not Ok month ||
                ParseDecimal(fields[1]) is not Ok week || ParseDecimal(fields[2]) is not Ok weekday)
                return None;
            point.Kind = 0;
            point.Month = month.Value;
            point.Week = week.Value;
            point.Weekday = weekday.Value;
            return month.Value >= 1 && month.Value <= 12 && week.Value >= 1 && week.Value <= 5 &&
                   weekday.Value <= 6 ? Some(point) : None;
        }

        bool julian = date.StartsWith("J");
        if (ParseDecimal(julian ? date.Substring(1u) : date) is not Ok day)
            return None;
        point.Kind = julian ? 1 : 2;
        point.Day = day.Value;
        return Some(point);
    }

    /// Decimal digits and nothing else, as an int.
    static Result<int, TimeError> ParseDecimal(String text)
    {
        if (text.IsEmpty || text.ByteLength() > 9u)
            return Fail(TimeError.Malformed);
        int value = ParseDigits(text, 0u, text.ByteLength());
        return value < 0 ? Fail(TimeError.Malformed) : Ok(value);
    }

    // --------------------------------------------------------- a TZif file

#if !WINDOWS
    static String ZoneDirectory()
    {
        String? directory = GetEnvironmentVariable("TZDIR");
        return directory != null && !directory.IsEmpty ? directory : "/usr/share/zoneinfo";
    }
#endif

    /// The zone in the TZif file at `path` (RFC 8536), named `id`.
    static Result<TimeZoneInfo, TimeError> FromFile(String path, String id)
    {
        if (ReadAllBytes(path) is not Ok bytes)
            return Fail(TimeError.NotFound);

        var made = new TimeZoneInfo(id);
        made._ianaId = true;
        if (!made.ReadTzif(bytes.Value))
            return Fail(TimeError.NotFound);
        made.Describe();
        return Ok(made);
    }

    static long ReadBigEndian(byte[] data, nuint at, nuint size)
    {
        ulong value = 0u;
        for (nuint i = 0u; i < size; i++)
            value = (value << 8) | (ulong)data[at + i];
        // Sign-extended from its own width.
        if (size == 4u)
            return (long)(int)(uint)value;
        return (long)value;
    }

    bool ReadTzif(byte[] data)
    {
        if (data.Length < 44u || data[0] != (byte)'T' || data[1] != (byte)'Z' || data[2] != (byte)'i' ||
            data[3] != (byte)'f')
            return false;

        nuint header = 0u;
        nuint timeSize = 4u;

        // A version 2 file has a second, 64-bit copy after the first: skip to it.
        if (data[4] >= (byte)'2')
        {
            nuint skipped = 44u + BlockSize(data, 0u, 4u);
            if (skipped + 44u > data.Length)
                return false;
            header = skipped;
            timeSize = 8u;
        }

        nuint isUtCount = (nuint)ReadBigEndian(data, header + 20u, 4u);
        nuint isStdCount = (nuint)ReadBigEndian(data, header + 24u, 4u);
        nuint leapCount = (nuint)ReadBigEndian(data, header + 28u, 4u);
        nuint timeCount = (nuint)ReadBigEndian(data, header + 32u, 4u);
        nuint typeCount = (nuint)ReadBigEndian(data, header + 36u, 4u);
        nuint charCount = (nuint)ReadBigEndian(data, header + 40u, 4u);

        nuint times = header + 44u;
        nuint indices = times + timeCount * timeSize;
        nuint types = indices + timeCount;
        nuint chars = types + typeCount * 6u;
        nuint end = chars + charCount + leapCount * (timeSize + 4u) + isStdCount + isUtCount;
        if (typeCount == 0u || end > data.Length)
            return false;

        // RFC 8536: type 0 is what the clocks read before the first transition.
        _initialOffset = ReadBigEndian(data, types, 4u);
        _initialDaylight = data[types + 4u] != 0;

        for (nuint i = 0u; i < timeCount; i++)
        {
            nuint type = (nuint)data[indices + i];
            if (type >= typeCount)
                return false;
            nuint entry = types + type * 6u;
            AddTransition(ReadBigEndian(data, times + i * timeSize, timeSize),
                ReadBigEndian(data, entry, 4u), data[entry + 4u] != 0);
        }

        // The footer is the rule for every instant after the last transition.
        if (timeSize == 8u && end + 2u <= data.Length && data[end] == (byte)'\n')
        {
            nuint close = end + 1u;
            while (close < data.Length && data[close] != (byte)'\n')
                close++;
            if (close > end + 1u)
            {
                String footer = Text.FromBytes(&data[end + 1u], close - end - 1u);
                if (ReadPosixRule(footer) is Some rule)
                {
                    _hasRule = true;
                    _rule = rule.Value;
                }
            }
        }

        // With no footer, the names come from the last types used.
        if (!_hasRule)
        {
            _rule.StandardName = Abbreviation(data, types, chars, typeCount, charCount, false);
            _rule.DaylightName = Abbreviation(data, types, chars, typeCount, charCount, true);
            _standardName = _rule.StandardName;
            _daylightName = _rule.DaylightName;
        }
        return true;
    }

    /// How far the data after a header runs, for a header at `at`.
    static nuint BlockSize(byte[] data, nuint at, nuint timeSize)
    {
        nuint isUtCount = (nuint)ReadBigEndian(data, at + 20u, 4u);
        nuint isStdCount = (nuint)ReadBigEndian(data, at + 24u, 4u);
        nuint leapCount = (nuint)ReadBigEndian(data, at + 28u, 4u);
        nuint timeCount = (nuint)ReadBigEndian(data, at + 32u, 4u);
        nuint typeCount = (nuint)ReadBigEndian(data, at + 36u, 4u);
        nuint charCount = (nuint)ReadBigEndian(data, at + 40u, 4u);
        return timeCount * timeSize + timeCount + typeCount * 6u + charCount +
               leapCount * (timeSize + 4u) + isStdCount + isUtCount;
    }

    /// The abbreviation of the last type that is, or is not, daylight time.
    static String Abbreviation(byte[] data, nuint types, nuint chars, nuint typeCount, nuint charCount, bool daylight)
    {
        for (nuint i = typeCount; i > 0u; i--)
        {
            nuint entry = types + (i - 1u) * 6u;
            if ((data[entry + 4u] != 0) != daylight)
                continue;
            nuint start = chars + (nuint)data[entry + 5u];
            nuint stop = start;
            while (stop < chars + charCount && data[stop] != 0)
                stop++;
            return stop > start ? Text.FromBytes(&data[start], stop - start) : "";
        }
        return "";
    }

    // ------------------------------------------------------------ Windows

#if WINDOWS
    /// The years whose rules are read. Before them the first year's rule
    /// stands, and after them the last year's.
    const long FirstRuleYear = 1970;
    const long RuleYears = 100;

    /// The zone Windows keeps under the key `key`, or the one numbered `index`
    /// when that is not negative, named `id` or, when that is empty, by its key.
    static Result<TimeZoneInfo, TimeError> FromWindows(String key, long index, String id)
    {
        long[] values = new long[(nuint)(RuleYears * 17)];
        byte[] names = new byte[1024];
        long written = sl_tz_windows_zone(index < 0 ? key.ToPointer() : null, index,
            FirstRuleYear, RuleYears, &values[0], &names[0], names.Length);
        if (written < 0)
            return Fail(TimeError.NotFound);

        // The key, the standard name, the daylight name and the display name,
        // each ended by a NUL.
        String[] parts = ["", "", "", ""];
        nuint start = 0u;
        for (nuint part = 0u; part < 4u; part++)
        {
            nuint stop = start;
            while (names[stop] != 0)
                stop++;
            parts[part] = Text.FromBytes(&names[start], stop - start);
            start = stop + 1u;
        }

        var made = new TimeZoneInfo(id.IsEmpty ? parts[0] : id);
        for (long i = 0; i < RuleYears; i++)
        {
            var rule = WindowsRule(values, (nuint)(i * 17), parts[1], parts[2]);
            long year = FirstRuleYear + i;

            if (i == 0)
            {
                made._initialOffset = rule.StandardOffset;
            }
            else if (rule.StandardOffset != made._rule.StandardOffset)
            {
                // A new standard offset takes effect with the year.
                made.AddTransition(DaysFromCivil(year, 1, 1) * 86400 - rule.StandardOffset,
                    rule.StandardOffset, false);
            }

            if (rule.HasDaylight)
            {
                long begins = LocalSecondsOf(rule.Start, year) - rule.StandardOffset;
                long ends = LocalSecondsOf(rule.End, year) - rule.DaylightOffset;
                if (begins < ends)
                {
                    made.AddTransition(begins, rule.DaylightOffset, true);
                    made.AddTransition(ends, rule.StandardOffset, false);
                }
                else
                {
                    made.AddTransition(ends, rule.StandardOffset, false);
                    made.AddTransition(begins, rule.DaylightOffset, true);
                }
            }
            made._rule = rule;
        }

        made._hasRule = true;
        made.Describe();
        made._displayName = parts[3];
        return Ok(made);
    }

    /// A year's rule from the seventeen values the runtime wrote at `at`.
    static ZoneRule WindowsRule(long[] values, nuint at, String standardName, String daylightName)
    {
        ZoneRule rule;
        rule.StandardName = standardName;
        rule.DaylightName = daylightName;
        rule.StandardOffset = -(values[at] + values[at + 1u]) * 60;
        rule.DaylightOffset = -(values[at] + values[at + 2u]) * 60;

        // A month of zero is a zone with no daylight time.
        rule.HasDaylight = values[at + 4u] != 0 && values[at + 11u] != 0;
        rule.End = WindowsPoint(values, at + 3u);
        rule.Start = WindowsPoint(values, at + 10u);
        return rule;
    }

    /// A SYSTEMTIME as Windows states a change: the nth weekday of a month
    /// when its year is zero, and a date when it is not.
    static RulePoint WindowsPoint(long[] values, nuint at)
    {
        RulePoint point;
        point.Kind = values[at] == 0 ? 0 : 3;
        point.Month = (int)values[at + 1u];
        point.Weekday = (int)values[at + 2u];
        point.Week = (int)values[at + 3u];
        point.Day = (int)values[at + 3u];
        point.Seconds = values[at + 4u] * 3600 + values[at + 5u] * 60 + values[at + 6u];
        return point;
    }
#endif
}
