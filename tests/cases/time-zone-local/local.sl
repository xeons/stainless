// SPDX-License-Identifier: 0BSD
//
// TimeZoneInfo.Local, which reads TZ when it is set and otherwise follows
// /etc/localtime to the zone it names. The machine's own zone is whatever it
// is, so the first half prints only what is true of any of them; TZ is then
// set, and the answer is known.
//
// Linux and macOS only: Windows reads its zone from the registry and ignores
// TZ.
module TimeZoneLocal;

import Standard.Console;
import Standard.Env;
import Standard.Time;

String Yes(bool value) => value ? "yes" : "no";

void Machine()
{
    var local = TimeZoneInfo.Local;
    var now = DateTimeOffset.UtcNow;

    // The link names a zone the database has, and the two agree about now.
    bool named = local.Id != "Local" && !local.Id.IsEmpty;
    bool found = TimeZoneInfo.FindSystemTimeZoneById(local.Id) is Ok same &&
                 same.Value.GetUtcOffset(now).Format() == local.GetUtcOffset(now).Format();
    Console.WriteLine("machine zone named: " + Yes(named));
    Console.WriteLine("machine zone found again: " + Yes(found));
}

void Told(String zone)
{
    SetEnvironmentVariable("TZ", zone);
    var local = TimeZoneInfo.Local;
    var summer = DateTimeOffset.FromUtc(2026, 7, 1, 12, 0, 0);
    var winter = DateTimeOffset.FromUtc(2026, 1, 15, 12, 0, 0);
    Console.WriteLine("TZ=" + zone + ": " + local.Id + " winter " + local.GetUtcOffset(winter).Format() +
        " summer " + local.GetUtcOffset(summer).Format());
}

int Main()
{
    Machine();
    Told("Europe/Berlin");
    Told(":America/New_York");
    Told("Asia/Tokyo");
    return 0;
}
