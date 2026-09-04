// Windows time, which is two clocks with different epochs and different rules.
//
// Everything here is a fixed instant rather than "now", so the expected output
// is the same on every machine and in every time zone.
module Win32Time;

import Standard.Console;
import Win32;
import Win32.Kernel32;
import Win32.Clock;

SystemTime At(ushort year, ushort month, ushort day,
              ushort hour, ushort minute, ushort second) {
    SystemTime time;
    time.Year = year;
    time.Month = month;
    time.DayOfWeek = 0u;
    time.Day = day;
    time.Hour = hour;
    time.Minute = minute;
    time.Second = second;
    time.Milliseconds = 0u;
    return time;
}

int Main() {
    // The Unix epoch, whose distance from Windows's own 1601 epoch is the one
    // constant everything else here depends on.
    ulong epoch = Clock.FromCalendar(At(1970u, 1u, 1u, 0u, 0u, 0u));
    Console.WriteLine("unix epoch in ticks: " + Text.FromInteger((long)epoch));
    Console.WriteLine("matches the constant: "
        + Text.FromBool(epoch == Clock.UnixEpochTicks));
    Console.WriteLine("as unix seconds: " + Text.FromInteger(Clock.ToUnixSeconds(epoch)));

    // A calendar date through ticks and back.
    var moment = At(2026u, 9u, 3u, 21u, 47u, 12u);
    ulong ticks = Clock.FromCalendar(moment);
    Console.WriteLine("formatted: " + Clock.Format(moment));
    Console.WriteLine("round trip: " + Clock.Format(Clock.ToCalendar(ticks)));
    Console.WriteLine("unix seconds: " + Text.FromInteger(Clock.ToUnixSeconds(ticks)));
    Console.WriteLine("and back: "
        + Clock.Format(Clock.ToCalendar(Clock.FromUnixSeconds(Clock.ToUnixSeconds(ticks)))));

    // The two halves of a FILETIME, joined and split.
    var file = Clock.FromTicks(ticks);
    Console.WriteLine("halves rejoin: " + Text.FromBool(Clock.Ticks(file) == ticks));

    // Padding, which is what makes a formatted time sort as text.
    Console.WriteLine("padded: " + Clock.Format(At(2001u, 2u, 3u, 4u, 5u, 6u)));

    // A date Windows will not accept: month 13.
    Console.WriteLine("month 13 is refused: "
        + Text.FromBool(Clock.FromCalendar(At(2026u, 13u, 1u, 0u, 0u, 0u)) == 0u));

    // The counter is monotonic, and its frequency is fixed while the machine
    // runs. Neither number is printed, because both are machine-specific.
    Console.WriteLine("frequency is positive: " + Text.FromBool(Clock.Frequency() > 0));
    long first = Clock.Counter();
    long second = Clock.Counter();
    Console.WriteLine("counter does not go backwards: " + Text.FromBool(second >= first));

    var watch = new Stopwatch();
    Console.WriteLine("a fresh stopwatch reads under a second: "
        + Text.FromBool(watch.Seconds() < 1.0));
    return 0;
}
