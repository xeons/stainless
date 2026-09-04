// Windows time, which is two clocks with different epochs and different rules.
//
// Everything here is a fixed instant rather than "now", so the expected output
// is the same on every machine and in every time zone.
module Win32Time;

import Standard.Console;
import Win32;
import Win32.Time;

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
    ulong epoch = Time.FromCalendar(At(1970u, 1u, 1u, 0u, 0u, 0u));
    Console.WriteLine("unix epoch in ticks: " + Text.FromInteger((long)epoch));
    Console.WriteLine("matches the constant: "
        + Text.FromBool(epoch == Time.UnixEpochTicks));
    Console.WriteLine("as unix seconds: " + Text.FromInteger(Time.ToUnixSeconds(epoch)));

    // A calendar date through ticks and back.
    var moment = At(2026u, 9u, 3u, 21u, 47u, 12u);
    ulong ticks = Time.FromCalendar(moment);
    Console.WriteLine("formatted: " + Time.Format(moment));
    Console.WriteLine("round trip: " + Time.Format(Time.ToCalendar(ticks)));
    Console.WriteLine("unix seconds: " + Text.FromInteger(Time.ToUnixSeconds(ticks)));
    Console.WriteLine("and back: "
        + Time.Format(Time.ToCalendar(Time.FromUnixSeconds(Time.ToUnixSeconds(ticks)))));

    // The two halves of a FILETIME, joined and split.
    var file = Time.FromTicks(ticks);
    Console.WriteLine("halves rejoin: " + Text.FromBool(Time.Ticks(file) == ticks));

    // Padding, which is what makes a formatted time sort as text.
    Console.WriteLine("padded: " + Time.Format(At(2001u, 2u, 3u, 4u, 5u, 6u)));

    // A date Windows will not accept: month 13.
    Console.WriteLine("month 13 is refused: "
        + Text.FromBool(Time.FromCalendar(At(2026u, 13u, 1u, 0u, 0u, 0u)) == 0u));

    // The counter is monotonic, and its frequency is fixed while the machine
    // runs. Neither number is printed, because both are machine-specific.
    Console.WriteLine("frequency is positive: " + Text.FromBool(Time.Frequency() > 0));
    long first = Time.Counter();
    long second = Time.Counter();
    Console.WriteLine("counter does not go backwards: " + Text.FromBool(second >= first));

    var watch = new Stopwatch();
    Console.WriteLine("a fresh stopwatch reads under a second: "
        + Text.FromBool(watch.Seconds() < 1.0));
    return 0;
}
