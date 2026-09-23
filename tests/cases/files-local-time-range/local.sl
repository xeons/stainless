// SPDX-License-Identifier: 0BSD
//
// Local time on either side of the epoch. Each check is a round trip, so the
// answer is the same in every zone the machine might be set to.
module LocalTimeRange;

import Standard.Console;
import Standard.Time;

void RoundTrip(String what, int year, int month, int day, int hour, int minute, int second)
{
    var at = DateTimeOffset.FromLocal(year, month, day, hour, minute, second);
    var back = at.LocalDateTime;
    bool same = back.Year == year && back.Month == month && back.Day == day
             && back.Hour == hour && back.Minute == minute && back.Second == second;
    Console.WriteLine($"{what}: {same}");
}

int Main()
{
    RoundTrip("1965", 1965, 6, 1, 12, 0, 0);
    RoundTrip("1900", 1900, 3, 15, 8, 30, 0);
    RoundTrip("2026", 2026, 9, 21, 9, 15, 30);

    // The second before the epoch, which is where `mktime` answers -1 for an
    // instant that is really there.
    var before = DateTimeOffset.FromUnixTimeSeconds(-1);
    var local = before.LocalDateTime;
    var again = DateTimeOffset.FromLocal(local.Year, local.Month, local.Day,
                                  local.Hour, local.Minute, local.Second);
    Console.WriteLine($"second before the epoch: {again.ToUnixTimeSeconds()}");

    // The zone's offset is known before 1970 as well as after.
    var early = DateTimeOffset.FromUtc(1965, 6, 1, 12, 0, 0);
    var offsetDate = early.LocalDateTime;
    Console.WriteLine($"1965 to local: {offsetDate.Year}");
    return 0;
}
