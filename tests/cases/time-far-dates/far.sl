// SPDX-License-Identifier: 0BSD
//
// Nanoseconds in a long reach 1677 to 2262. A date past either end is held
// there rather than wrapped, so the 9999 a certificate writes for "never"
// still sorts after today and 1600 before it.
module FarDates;

import Standard.Time;

extern "C" int printf(byte* format, ...);

int Main()
{
    var never = DateTimeOffset.FromUtc(9999, 12, 31, 23, 59, 59);
    var ancient = DateTimeOffset.FromUtc(1600, 1, 1, 0, 0, 0);
    var now = DateTimeOffset.UtcNow;
    var inRange = DateTimeOffset.FromUtc(2200, 1, 1, 0, 0, 0);

    printf("%d %d\n", never.Nanoseconds > now.Nanoseconds ? 1 : 0,
           ancient.Nanoseconds < now.Nanoseconds ? 1 : 0);
    printf("%lld %lld\n", never.Nanoseconds, ancient.Nanoseconds);
    printf("%lld\n", inRange.ToUnixTimeSeconds());

    printf("%lld\n", DateTimeOffset.FromUnixTimeSeconds(253402300799L).Nanoseconds);
    printf("%lld\n", DateTimeOffset.FromUnixTimeMilliseconds(-253402300799000L).Nanoseconds);
    printf("%lld\n", DateTimeOffset.FromUnixTimeSeconds(1700000000L).ToUnixTimeSeconds());
    return 0;
}
