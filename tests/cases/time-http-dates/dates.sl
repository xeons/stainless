// SPDX-License-Identifier: 0BSD
// RFC 9110's HTTP-date: written as IMF-fixdate, and read in all three of its
// forms, with every malformation refused rather than half-read.
module TimeHttpDates;

import Standard.Console;
import Standard.Time;

void ShowParsed(String text)
{
    var parsed = DateTimeOffset.ParseHttpDate(text);
    if (parsed.Ok)
        Console.WriteLine("\"" + text + "\" -> " + parsed.Value.FormatIso());
    else
        Console.WriteLine("\"" + text + "\" -> " + $"{parsed.Error}");
}

int Main()
{
    Console.WriteLine(DateTimeOffset.FromUtc(1994, 11, 6, 8, 49, 37).FormatHttpDate());
    Console.WriteLine(DateTimeOffset.FromUtc(2026, 2, 28, 23, 5, 9).FormatHttpDate());
    Console.WriteLine(DateTimeOffset.UnixEpoch.FormatHttpDate());

    // The three forms of one instant.
    ShowParsed("Sun, 06 Nov 1994 08:49:37 GMT");
    ShowParsed("Sunday, 06-Nov-94 08:49:37 GMT");
    ShowParsed("Sun Nov  6 08:49:37 1994");
    ShowParsed("Sun Nov 16 08:49:37 1994");

    // Two-digit years: 70 and later are the 1900s.
    ShowParsed("Thursday, 01-Jan-70 00:00:00 GMT");
    ShowParsed("Friday, 31-Dec-69 23:59:59 GMT");

    // A round trip.
    var now = DateTimeOffset.FromUtc(2031, 7, 4, 12, 0, 1);
    ShowParsed(now.FormatHttpDate());

    // Refused.
    ShowParsed("");
    ShowParsed("Sun, 06 Nov 1994 08:49:37 UTC");
    ShowParsed("Sun, 06 nov 1994 08:49:37 GMT");
    ShowParsed("Xyz, 06 Nov 1994 08:49:37 GMT");
    ShowParsed("Sun, 6 Nov 1994 08:49:37 GMT");
    ShowParsed("Sun, 31 Feb 1994 08:49:37 GMT");
    ShowParsed("Sun, 06 Nov 1994 24:00:00 GMT");
    ShowParsed("Sun, 06 Nov 1994 08-49-37 GMT");
    ShowParsed("Someday, 06-Nov-94 08:49:37 GMT");
    ShowParsed("Sunday, 06-Nov-1994 08:49:37 GMT");
    ShowParsed("Sun Nov 6 08:49:37 1994");
    return 0;
}
