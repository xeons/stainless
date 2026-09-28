// SPDX-License-Identifier: 0BSD
//
// TimeZoneInfo by IANA name, which every platform reads: from the zoneinfo
// files on Linux, and through ICU on Windows. Only offsets and wall clocks are
// printed, since the names a zone goes by differ from one system to another.
module TimeZones;

import Standard.Console;
import Standard.Time;

String Wall(DateTime t) => t.FormatDate() + " " + t.FormatTime();

DateTime At(int year, int month, int day, int hour, int minute) =>
    new DateOnly(year, month, day).ToDateTime(new TimeOnly(hour, minute));

String Yes(bool value) => value ? "yes" : "no";

void Describe(String id)
{
    if (TimeZoneInfo.FindSystemTimeZoneById(id) is not Ok found)
    {
        Console.WriteLine(id + " not found");
        return;
    }

    var zone = found.Value;
    var summer = DateTimeOffset.FromUtc(2026, 7, 1, 12, 0, 0);
    var winter = DateTimeOffset.FromUtc(2026, 1, 15, 12, 0, 0);
    Console.WriteLine(zone.Id + " base " + zone.BaseUtcOffset.Format() + " dst " + Yes(zone.SupportsDaylightSavingTime) +
        " iana " + Yes(zone.HasIanaId));
    Console.WriteLine("  july " + Wall(TimeZoneInfo.ConvertTime(summer, zone)) + " " + zone.GetUtcOffset(summer).Format() +
        " " + Yes(zone.IsDaylightSavingTime(summer)) + ", january " + Wall(TimeZoneInfo.ConvertTime(winter, zone)) + " " +
        zone.GetUtcOffset(winter).Format() + " " + Yes(zone.IsDaylightSavingTime(winter)));
}

int Main()
{
    Describe("UTC");
    Describe("America/New_York");
    Describe("Australia/Sydney");
    Describe("Asia/Kolkata");
    Describe("Europe/Paris");
    Describe("Nowhere/Special");

    if (TimeZoneInfo.FindSystemTimeZoneById("America/New_York") is not Ok newYork)
        return 1;
    var zone = newYork.Value;

    // Clocks go forward at 02:00 on 8 March 2026, and back at 02:00 on 1 November.
    var gap = At(2026, 3, 8, 2, 30);
    var overlap = At(2026, 11, 1, 1, 30);
    Console.WriteLine("gap " + Yes(zone.IsInvalidTime(gap)) + " " + Yes(TimeZoneInfo.ConvertTimeToUtc(gap, zone) is Fail) +
        ", overlap " + Yes(zone.IsAmbiguousTime(overlap)) + " " +
        (TimeZoneInfo.ConvertTimeToUtc(overlap, zone) is Ok utc ? utc.Value.FormatIso() : "?") + ", ordinary " +
        Yes(zone.IsAmbiguousTime(At(2026, 7, 4, 9, 0))) + " " + Yes(zone.IsInvalidTime(At(2026, 7, 4, 9, 0))));

    // Either side of the change, a minute apart.
    var before = DateTimeOffset.FromUtc(2026, 3, 8, 6, 59, 0);
    var after = DateTimeOffset.FromUtc(2026, 3, 8, 7, 0, 0);
    Console.WriteLine("change " + Wall(TimeZoneInfo.ConvertTime(before, zone)) + " " +
        Wall(TimeZoneInfo.ConvertTime(after, zone)));

    // Years the rules do not run out in.
    var far = DateTimeOffset.FromUtc(2090, 7, 1, 0, 0, 0);
    var past = DateTimeOffset.FromUtc(1975, 1, 1, 0, 0, 0);
    Console.WriteLine("far " + zone.GetUtcOffset(far).Format() + " past " + zone.GetUtcOffset(past).Format());

    if (TimeZoneInfo.FindSystemTimeZoneById("Europe/Paris") is Ok paris &&
        TimeZoneInfo.ConvertTime(At(2026, 7, 4, 9, 0), zone, paris.Value) is Ok there)
        Console.WriteLine("paris " + Wall(there.Value));

    var utcClock = At(2026, 12, 25, 12, 0);
    Console.WriteLine("from utc " + Wall(TimeZoneInfo.ConvertTimeFromUtc(utcClock, zone)) + " " +
        (TimeZoneInfo.ConvertTimeBySystemTimeZoneId(DateTimeOffset.FromUtc(2026, 12, 25, 12, 0, 0), "Asia/Kolkata") is Ok kolkata
            ? Wall(kolkata.Value) : "?"));

    var mars = TimeZoneInfo.CreateCustomTimeZone("Mars", TimeSpan.FromHours(5), "(UTC+05:00) Mars", "Mars Time");
    Console.WriteLine(mars.DisplayName + " " + mars.GetUtcOffset(far).Format() + " " + Yes(mars.SupportsDaylightSavingTime) +
        " " + Yes(TimeZoneInfo.GetSystemTimeZones().Count > 50u));
    return 0;
}
