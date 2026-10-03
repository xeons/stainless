# Standard.Time

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Time, of the two kinds that must not be confused.

A `DateTimeOffset` is a point on the wall clock: a date and a time of
day. It can jump, because a user sets the clock, NTP corrects it, or a
laptop wakes up. Never subtract two of them to find out how long
something took.

A `TimeSpan` is a length of time, and `Stopwatch` reads a monotonic
counter that only ever goes forward. That pair is what a measurement
wants.

**On Linux and macOS the monotonic counter stops while the machine
sleeps**, so a span measured across a suspend leaves the suspend out. That
is the clock a timed wait and a sleep are measured on, so a `Stopwatch`
around one agrees with it.

Both are structs over a single `long` of nanoseconds, so they cost nothing,
travel in a register, and compare and subtract as the numbers they are.
Sixty-four bits of nanoseconds reaches 292 years either side of 1970, which
is not the reason anything here will go wrong.

## Contents

**Types** &nbsp; [DateOnly](#dateonly-struct) &middot; [DateTime](#datetime-struct) &middot; [DateTimeOffset](#datetimeoffset-struct) &middot; [Stopwatch](#stopwatch-class) &middot; [TimeError](#timeerror-enum) &middot; [TimeOnly](#timeonly-struct) &middot; [TimeSpan](#timespan-struct) &middot; [TimeZoneInfo](#timezoneinfo-class)

**Functions** &nbsp; [DaysInMonth](#daysinmonth-function) &middot; [IsLeapYear](#isleapyear-function)

**Constants** &nbsp; [NanosecondsPerDay](#nanosecondsperday-constant) &middot; [NanosecondsPerHour](#nanosecondsperhour-constant) &middot; [NanosecondsPerMicrosecond](#nanosecondspermicrosecond-constant) &middot; [NanosecondsPerMillisecond](#nanosecondspermillisecond-constant) &middot; [NanosecondsPerMinute](#nanosecondsperminute-constant) &middot; [NanosecondsPerSecond](#nanosecondspersecond-constant)

## Types

### DateOnly *struct*

```
struct DateOnly : IEquatable<DateOnly>, IComparable<DateOnly>, IHashable
```

A date and no time: C#'s `System.DateOnly`.

    var due = new DateOnly(2026, 9, 30).AddMonths(1);  // 2026-10-30

From 0001-01-01 to 9999-12-31 in the Gregorian calendar, as C#'s. A date
outside that, or a day its month does not have, aborts where C# throws.
Written and read as ISO 8601, `2026-09-30`, rather than in a culture's form.

<sub>[stdlib/Time/DateOnly.sl:64](../../stdlib/Time/DateOnly.sl#L64)</sub>

#### MinValue *property*

```
static DateOnly MinValue { get; }
```

0001-01-01.

<sub>[stdlib/Time/DateOnly.sl:77](../../stdlib/Time/DateOnly.sl#L77)</sub>

#### MaxValue *property*

```
static DateOnly MaxValue { get; }
```

9999-12-31.

<sub>[stdlib/Time/DateOnly.sl:80](../../stdlib/Time/DateOnly.sl#L80)</sub>

#### FromDayNumber *method*

```
static DateOnly FromDayNumber(int dayNumber)
```

The date `dayNumber` days after 0001-01-01. Aborts outside the range.

<sub>[stdlib/Time/DateOnly.sl:83](../../stdlib/Time/DateOnly.sl#L83)</sub>

#### FromDateTime *method*

```
static DateOnly FromDateTime(DateTime when)
```

The date part of `when`.

<sub>[stdlib/Time/DateOnly.sl:93](../../stdlib/Time/DateOnly.sl#L93)</sub>

#### DayNumber *property*

```
int DayNumber { get; }
```

Days since 0001-01-01.

<sub>[stdlib/Time/DateOnly.sl:96](../../stdlib/Time/DateOnly.sl#L96)</sub>

#### Year *property*

```
int Year { get; }
```

The year, 1 to 9999.

<sub>[stdlib/Time/DateOnly.sl:101](../../stdlib/Time/DateOnly.sl#L101)</sub>

#### Month *property*

```
int Month { get; }
```

The month, 1 to 12.

<sub>[stdlib/Time/DateOnly.sl:104](../../stdlib/Time/DateOnly.sl#L104)</sub>

#### Day *property*

```
int Day { get; }
```

The day of the month, 1 to 31.

<sub>[stdlib/Time/DateOnly.sl:107](../../stdlib/Time/DateOnly.sl#L107)</sub>

#### DayOfWeek *property*

```
int DayOfWeek { get; }
```

The day of the week, 0 for Sunday through 6 for Saturday, as
`DateTime.DayOfWeek` counts. 0001-01-01 was a Monday.

<sub>[stdlib/Time/DateOnly.sl:111](../../stdlib/Time/DateOnly.sl#L111)</sub>

#### DayOfYear *property*

```
int DayOfYear { get; }
```

The day of the year, 1 to 366.

<sub>[stdlib/Time/DateOnly.sl:114](../../stdlib/Time/DateOnly.sl#L114)</sub>

#### AddDays *method*

```
DateOnly AddDays(int days)
```

`days` later, or earlier when negative. Aborts outside the range.

<sub>[stdlib/Time/DateOnly.sl:118](../../stdlib/Time/DateOnly.sl#L118)</sub>

#### AddMonths *method*

```
DateOnly AddMonths(int months)
```

`months` later, the day kept or, where the month is shorter, its last.

<sub>[stdlib/Time/DateOnly.sl:121](../../stdlib/Time/DateOnly.sl#L121)</sub>

#### AddYears *method*

```
DateOnly AddYears(int years)
```

`years` later, 29 February becoming the 28th in a year without one.

<sub>[stdlib/Time/DateOnly.sl:131](../../stdlib/Time/DateOnly.sl#L131)</sub>

#### ToDateTime *method*

```
DateTime ToDateTime(TimeOnly time)
```

The date and `time` together.

<sub>[stdlib/Time/DateOnly.sl:134](../../stdlib/Time/DateOnly.sl#L134)</sub>

#### Deconstruct *method*

```
void Deconstruct(out int year, out int month, out int day)
```

The year, month and day.

<sub>[stdlib/Time/DateOnly.sl:150](../../stdlib/Time/DateOnly.sl#L150)</sub>

#### ToString *method*

```
String ToString()
```

`2026-09-30`.

<sub>[stdlib/Time/DateOnly.sl:159](../../stdlib/Time/DateOnly.sl#L159)</sub>

#### Parse *method*

```
static Result<DateOnly, TimeError> Parse(String text)
```

Reads `yyyy-MM-dd`.

**Fails with**

- [TimeError.Malformed](#malformed-case) -- not that shape
- [TimeError.OutOfRange](#outofrange-case) -- that shape and no real date

<sub>[stdlib/Time/DateOnly.sl:166](../../stdlib/Time/DateOnly.sl#L166)</sub>

#### Equals *method*

```
bool Equals(DateOnly other)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:181](../../stdlib/Time/DateOnly.sl#L181)</sub>

#### CompareTo *method*

```
int CompareTo(DateOnly other)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:182](../../stdlib/Time/DateOnly.sl#L182)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:183](../../stdlib/Time/DateOnly.sl#L183)</sub>

#### operator == *operator*

```
static bool operator ==(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:185](../../stdlib/Time/DateOnly.sl#L185)</sub>

#### operator != *operator*

```
static bool operator !=(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:186](../../stdlib/Time/DateOnly.sl#L186)</sub>

#### operator &lt; *operator*

```
static bool operator <(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:187](../../stdlib/Time/DateOnly.sl#L187)</sub>

#### operator &gt; *operator*

```
static bool operator >(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:188](../../stdlib/Time/DateOnly.sl#L188)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:189](../../stdlib/Time/DateOnly.sl#L189)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(DateOnly left, DateOnly right)
```

*No documentation.*

<sub>[stdlib/Time/DateOnly.sl:190](../../stdlib/Time/DateOnly.sl#L190)</sub>

### DateTime *struct*

```
struct DateTime
```

An instant broken into the parts a person reads.

Made by `UtcDateTime` or `LocalDateTime`, which is what says which zone the numbers are
in -- the struct itself does not carry that, because a date with no zone is
exactly as ambiguous as it sounds.

<sub>[stdlib/Time/DateTime.sl:31](../../stdlib/Time/DateTime.sl#L31)</sub>

#### Year *field*

```
int Year
```

The year, in full. Zero means the instant was outside what the platform
can name, and every other field is zero with it -- that is how this
struct reports a failure, since it has no other way to.

<sub>[stdlib/Time/DateTime.sl:36](../../stdlib/Time/DateTime.sl#L36)</sub>

#### Month *field*

```
int Month
```

The month, 1 to 12.

<sub>[stdlib/Time/DateTime.sl:39](../../stdlib/Time/DateTime.sl#L39)</sub>

#### Day *field*

```
int Day
```

The day of the month, 1 to 31.

<sub>[stdlib/Time/DateTime.sl:42](../../stdlib/Time/DateTime.sl#L42)</sub>

#### Hour *field*

```
int Hour
```

The hour, 0 to 23.

<sub>[stdlib/Time/DateTime.sl:45](../../stdlib/Time/DateTime.sl#L45)</sub>

#### Minute *field*

```
int Minute
```

The minute, 0 to 59.

<sub>[stdlib/Time/DateTime.sl:48](../../stdlib/Time/DateTime.sl#L48)</sub>

#### Second *field*

```
int Second
```

The second, 0 to 60 -- 60 because a leap second is a real reading of a
real clock.

<sub>[stdlib/Time/DateTime.sl:52](../../stdlib/Time/DateTime.sl#L52)</sub>

#### Nanosecond *field*

```
int Nanosecond
```

Nanoseconds within the second, 0 to 999,999,999.

<sub>[stdlib/Time/DateTime.sl:55](../../stdlib/Time/DateTime.sl#L55)</sub>

#### DayOfWeek *field*

```
int DayOfWeek
```

The day of the week, 0 for Sunday through 6 for Saturday.

<sub>[stdlib/Time/DateTime.sl:58](../../stdlib/Time/DateTime.sl#L58)</sub>

#### DayOfYear *field*

```
int DayOfYear
```

The day of the year, 1 to 366.

<sub>[stdlib/Time/DateTime.sl:61](../../stdlib/Time/DateTime.sl#L61)</sub>

#### FormatDate *method*

```
String FormatDate()
```

The date alone: `2026-09-05`.

<sub>[stdlib/Time/DateTime.sl:64](../../stdlib/Time/DateTime.sl#L64)</sub>

#### FormatTime *method*

```
String FormatTime()
```

The time of day alone: `14:30:00`.

<sub>[stdlib/Time/DateTime.sl:76](../../stdlib/Time/DateTime.sl#L76)</sub>

### DateTimeOffset *struct*

```
struct DateTimeOffset
```

A point on the wall clock, as nanoseconds since 1970-01-01 UTC.

    var started = DateTimeOffset.UtcNow;
    var waited = DateTimeOffset.UtcNow - started;

Subtracting two instants gives a `TimeSpan`, and adding a `TimeSpan` to one
gives another instant. Adding two instants is not defined, because the sum
of two dates is not a date -- which is exactly the thing a free function
named `Add` could not say.

<sub>[stdlib/Time/DateTimeOffset.sl:35](../../stdlib/Time/DateTimeOffset.sl#L35)</sub>

#### Nanoseconds *field*

```
long Nanoseconds
```

Nanoseconds since 1970-01-01 UTC, negative before it. The whole of the
value, and the thing to hand a C API that wants an epoch count.

A `long` of nanoseconds reaches from 1677 to 2262. An instant outside
that is held at the nearer end rather than wrapped, so the year 9999
that a certificate writes for "never" compares as later than any real
date.

<sub>[stdlib/Time/DateTimeOffset.sl:44](../../stdlib/Time/DateTimeOffset.sl#L44)</sub>

#### UtcNow *property*

```
static DateTimeOffset UtcNow { get; }
```

What time it is now. It can go backwards between two calls; use `Stopwatch`
to measure how long something took.

**See also** &nbsp; [Stopwatch](#stopwatch-class)

<sub>[stdlib/Time/DateTimeOffset.sl:50](../../stdlib/Time/DateTimeOffset.sl#L50)</sub>

#### UnixEpoch *property*

```
static DateTimeOffset UnixEpoch { get; }
```

1970-01-01 00:00:00 UTC, which is where the count starts.

<sub>[stdlib/Time/DateTimeOffset.sl:61](../../stdlib/Time/DateTimeOffset.sl#L61)</sub>

#### FromUnixTimeSeconds *method*

```
static DateTimeOffset FromUnixTimeSeconds(long seconds)
```

An instant from whole seconds since the epoch -- what a `time_t`, a
file timestamp and most C APIs carry.

<sub>[stdlib/Time/DateTimeOffset.sl:73](../../stdlib/Time/DateTimeOffset.sl#L73)</sub>

#### FromUnixTimeMilliseconds *method*

```
static DateTimeOffset FromUnixTimeMilliseconds(long milliseconds)
```

An instant from milliseconds since the epoch, which is what JavaScript
and most JSON APIs use.

<sub>[stdlib/Time/DateTimeOffset.sl:82](../../stdlib/Time/DateTimeOffset.sl#L82)</sub>

#### FromUtc *method*

```
static DateTimeOffset FromUtc(int year, int month, int day, int hour, int minute, int second)
```

A UTC date and time as an instant.

<sub>[stdlib/Time/DateTimeOffset.sl:90](../../stdlib/Time/DateTimeOffset.sl#L90)</sub>

#### FromLocal *method*

```
static DateTimeOffset FromLocal(int year, int month, int day, int hour, int minute, int second)
```

A local date and time as an instant. Ambiguous during the hour a clock
goes back, and impossible during the hour it goes forward; the platform
decides.

**See also** &nbsp; [DateTimeOffset.FromUtc](#fromutc-method)

<sub>[stdlib/Time/DateTimeOffset.sl:104](../../stdlib/Time/DateTimeOffset.sl#L104)</sub>

#### ToUnixTimeSeconds *method*

```
long ToUnixTimeSeconds()
```

Whole seconds since the epoch, rounded toward the epoch. This is what a
file's modification time is, and what most C APIs speak.

<sub>[stdlib/Time/DateTimeOffset.sl:115](../../stdlib/Time/DateTimeOffset.sl#L115)</sub>

#### ToUnixTimeMilliseconds *method*

```
long ToUnixTimeMilliseconds()
```

Whole milliseconds since the epoch, rounded toward the epoch.

<sub>[stdlib/Time/DateTimeOffset.sl:118](../../stdlib/Time/DateTimeOffset.sl#L118)</sub>

#### UtcDateTime *property*

```
DateTime UtcDateTime { get; }
```

This instant as a date and time in UTC.

<sub>[stdlib/Time/DateTimeOffset.sl:121](../../stdlib/Time/DateTimeOffset.sl#L121)</sub>

#### LocalDateTime *property*

```
DateTime LocalDateTime { get; }
```

The same in the machine's local zone, with whatever the platform
believes about daylight saving.

**See also** &nbsp; [DateTimeOffset.UtcDateTime](#utcdatetime-property)

<sub>[stdlib/Time/DateTimeOffset.sl:127](../../stdlib/Time/DateTimeOffset.sl#L127)</sub>

#### FormatIso *method*

```
String FormatIso()
```

ISO 8601, to the second: `2026-09-05T14:30:00Z`.

**See also** &nbsp; [DateTimeOffset.ParseIso](#parseiso-method)

<sub>[stdlib/Time/DateTimeOffset.sl:132](../../stdlib/Time/DateTimeOffset.sl#L132)</sub>

#### ParseIso *method*

```
static Result<DateTimeOffset, TimeError> ParseIso(String text)
```

`2026-09-05T14:30:00Z` back to an instant.

A `Result` rather than a nullable, because a `DateTimeOffset` is a
struct and a struct is never null (SL0271) -- and because "that is not
a date" and "that is not a real date" are worth telling apart.

Deliberately strict: exactly the shape `FormatIso` writes, so a round
trip is exact and anything else is refused rather than half-read.

**Fails with**

- [TimeError.Malformed](#malformed-case) -- not that shape: the wrong length, a separator out of place, or something that is not a digit where one belongs
- [TimeError.OutOfRange](#outofrange-case) -- that shape, and no real moment -- the 31st of February, a month of 13, an hour of 24

**See also** &nbsp; [DateTimeOffset.FormatIso](#formatiso-method)

<sub>[stdlib/Time/DateTimeOffset.sl:150](../../stdlib/Time/DateTimeOffset.sl#L150)</sub>

#### FormatHttpDate *method*

```
String FormatHttpDate()
```

RFC 9110's HTTP-date, the IMF-fixdate form every sender writes:
`Sun, 06 Nov 1994 08:49:37 GMT`.

**See also** &nbsp; [DateTimeOffset.ParseHttpDate](#parsehttpdate-method)

<sub>[stdlib/Time/DateTimeOffset.sl:159](../../stdlib/Time/DateTimeOffset.sl#L159)</sub>

#### ParseHttpDate *method*

```
static Result<DateTimeOffset, TimeError> ParseHttpDate(String text)
```

An HTTP-date back to an instant, in any of the three forms RFC 9110
requires a recipient to read: IMF-fixdate, the obsolete RFC 850 form
`Sunday, 06-Nov-94 08:49:37 GMT`, and C's asctime,
`Sun Nov  6 08:49:37 1994`.

Strict about the shape, as `ParseIso` is: a month's name in the wrong
case, a zone other than `GMT`, or a missing field is refused. The day's
name is checked for being one, not for being the right one.

**Fails with**

- [TimeError.Malformed](#malformed-case) -- none of the three shapes
- [TimeError.OutOfRange](#outofrange-case) -- the right shape, and no real moment

**See also** &nbsp; [DateTimeOffset.FormatHttpDate](#formathttpdate-method)

<sub>[stdlib/Time/DateTimeOffset.sl:173](../../stdlib/Time/DateTimeOffset.sl#L173)</sub>

#### Offset *property*

```
TimeSpan Offset { get; }
```

How far ahead of UTC the local zone was at this instant. Negative west
of Greenwich.

<sub>[stdlib/Time/DateTimeOffset.sl:178](../../stdlib/Time/DateTimeOffset.sl#L178)</sub>

#### operator - *operator*

```
static TimeSpan operator -(DateTimeOffset later, DateTimeOffset earlier)
```

How long apart two instants are. Negative if the right one is later.

<sub>[stdlib/Time/DateTimeOffset.sl:182](../../stdlib/Time/DateTimeOffset.sl#L182)</sub>

#### operator + *operator*

```
static DateTimeOffset operator +(DateTimeOffset at, TimeSpan span)
```

An instant moved forward by a length of time. Exact nanoseconds, so a
day added is 24 hours and not a calendar day.

<sub>[stdlib/Time/DateTimeOffset.sl:189](../../stdlib/Time/DateTimeOffset.sl#L189)</sub>

#### operator - *operator*

```
static DateTimeOffset operator -(DateTimeOffset at, TimeSpan span)
```

An instant moved back by a length of time.

<sub>[stdlib/Time/DateTimeOffset.sl:197](../../stdlib/Time/DateTimeOffset.sl#L197)</sub>

#### operator == *operator*

```
static bool operator ==(DateTimeOffset left, DateTimeOffset right)
```

Whether the two name the same nanosecond.

<sub>[stdlib/Time/DateTimeOffset.sl:205](../../stdlib/Time/DateTimeOffset.sl#L205)</sub>

#### operator != *operator*

```
static bool operator !=(DateTimeOffset left, DateTimeOffset right)
```

Whether they name different nanoseconds.

<sub>[stdlib/Time/DateTimeOffset.sl:211](../../stdlib/Time/DateTimeOffset.sl#L211)</sub>

#### operator &lt; *operator*

```
static bool operator <(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is the earlier.

<sub>[stdlib/Time/DateTimeOffset.sl:217](../../stdlib/Time/DateTimeOffset.sl#L217)</sub>

#### operator &gt; *operator*

```
static bool operator >(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is the later.

<sub>[stdlib/Time/DateTimeOffset.sl:223](../../stdlib/Time/DateTimeOffset.sl#L223)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is no later than `right`.

<sub>[stdlib/Time/DateTimeOffset.sl:229](../../stdlib/Time/DateTimeOffset.sl#L229)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is no earlier than `right`.

<sub>[stdlib/Time/DateTimeOffset.sl:235](../../stdlib/Time/DateTimeOffset.sl#L235)</sub>

#### Compare *method*

```
static int Compare(DateTimeOffset left, DateTimeOffset right)
```

-1, 0 or 1, for sorting. The operators answer the question a program
usually has; this answers the one a sort has.

<sub>[stdlib/Time/DateTimeOffset.sl:242](../../stdlib/Time/DateTimeOffset.sl#L242)</sub>

### Stopwatch *class*

```
class Stopwatch
```

A stopwatch over the monotonic counter.

This is the only correct way to measure a duration: the wall clock can jump
while you are timing, and a measurement that came out negative because NTP
stepped the clock is a bug nobody finds.

    var clock = new Stopwatch();
    DoTheWork();
    Console.WriteLine(clock.Elapsed.Format());

<sub>[stdlib/Time/Stopwatch.sl:35](../../stdlib/Time/Stopwatch.sl#L35)</sub>

#### Elapsed *property*

```
TimeSpan Elapsed { get; }
```

How long since it was made, or since `Restart`.

<sub>[stdlib/Time/Stopwatch.sl:44](../../stdlib/Time/Stopwatch.sl#L44)</sub>

#### Restart *method*

```
TimeSpan Restart()
```

Starts again from now, returning what had passed until this moment.

<sub>[stdlib/Time/Stopwatch.sl:47](../../stdlib/Time/Stopwatch.sl#L47)</sub>

#### GetTimestamp *method*

```
static TimeSpan GetTimestamp()
```

A reading of the monotonic counter, for code that would rather keep
the number than an object. Meaningless on its own; subtract two.

<sub>[stdlib/Time/Stopwatch.sl:57](../../stdlib/Time/Stopwatch.sl#L57)</sub>

### TimeError *enum*

```
enum TimeError
```

Why a moment could not be read.

<sub>[stdlib/Time/TimeError.sl:25](../../stdlib/Time/TimeError.sl#L25)</sub>

#### None *case*

```
None
```

Nothing went wrong. Present so the enum has a zero value; a `Result`
says success by being `Ok`, so this is not what a failure carries.

<sub>[stdlib/Time/TimeError.sl:29](../../stdlib/Time/TimeError.sl#L29)</sub>

#### Malformed *case*

```
Malformed
```

Not the shape `FormatIso` writes -- the wrong length, or a separator
in the wrong place, or something that is not a digit where one belongs.

<sub>[stdlib/Time/TimeError.sl:33](../../stdlib/Time/TimeError.sl#L33)</sub>

#### OutOfRange *case*

```
OutOfRange
```

The right shape and not a real moment: the 31st of February, a month of
13, an hour of 24.

<sub>[stdlib/Time/TimeError.sl:37](../../stdlib/Time/TimeError.sl#L37)</sub>

#### NotFound *case*

```
NotFound
```

No time zone of that name, or none with a readable definition.

<sub>[stdlib/Time/TimeError.sl:40](../../stdlib/Time/TimeError.sl#L40)</sub>

#### Invalid *case*

```
Invalid
```

A wall-clock time the zone skips, as when its clocks go forward.

<sub>[stdlib/Time/TimeError.sl:43](../../stdlib/Time/TimeError.sl#L43)</sub>

### TimeOnly *struct*

```
struct TimeOnly : IEquatable<TimeOnly>, IComparable<TimeOnly>, IHashable
```

A time of day and no date: C#'s `System.TimeOnly`.

    var opens = new TimeOnly(9, 30);
    var closes = opens.Add(TimeSpan.FromHours(8));   // 17:30

To the nanosecond, from midnight to one nanosecond before the next.
Adding wraps round midnight, and a part out of range aborts where C#
throws. Written and read as `HH:mm:ss`, with a fraction when there is one.

<sub>[stdlib/Time/TimeOnly.sl:34](../../stdlib/Time/TimeOnly.sl#L34)</sub>

#### MinValue *property*

```
static TimeOnly MinValue { get; }
```

Midnight.

<sub>[stdlib/Time/TimeOnly.sl:60](../../stdlib/Time/TimeOnly.sl#L60)</sub>

#### MaxValue *property*

```
static TimeOnly MaxValue { get; }
```

One nanosecond before midnight.

<sub>[stdlib/Time/TimeOnly.sl:63](../../stdlib/Time/TimeOnly.sl#L63)</sub>

#### FromTimeSpan *method*

```
static TimeOnly FromTimeSpan(TimeSpan span)
```

The time `span` after midnight. Aborts unless it is within one day.

<sub>[stdlib/Time/TimeOnly.sl:66](../../stdlib/Time/TimeOnly.sl#L66)</sub>

#### FromDateTime *method*

```
static TimeOnly FromDateTime(DateTime when)
```

The time part of `when`.

<sub>[stdlib/Time/TimeOnly.sl:76](../../stdlib/Time/TimeOnly.sl#L76)</sub>

#### ToTimeSpan *method*

```
TimeSpan ToTimeSpan()
```

How long after midnight it is.

<sub>[stdlib/Time/TimeOnly.sl:82](../../stdlib/Time/TimeOnly.sl#L82)</sub>

#### Hour *property*

```
int Hour { get; }
```

The hour, 0 to 23.

<sub>[stdlib/Time/TimeOnly.sl:85](../../stdlib/Time/TimeOnly.sl#L85)</sub>

#### Minute *property*

```
int Minute { get; }
```

The minute, 0 to 59.

<sub>[stdlib/Time/TimeOnly.sl:88](../../stdlib/Time/TimeOnly.sl#L88)</sub>

#### Second *property*

```
int Second { get; }
```

The second, 0 to 59.

<sub>[stdlib/Time/TimeOnly.sl:91](../../stdlib/Time/TimeOnly.sl#L91)</sub>

#### Millisecond *property*

```
int Millisecond { get; }
```

The millisecond, 0 to 999.

<sub>[stdlib/Time/TimeOnly.sl:94](../../stdlib/Time/TimeOnly.sl#L94)</sub>

#### Microsecond *property*

```
int Microsecond { get; }
```

The microsecond within the millisecond, 0 to 999.

<sub>[stdlib/Time/TimeOnly.sl:97](../../stdlib/Time/TimeOnly.sl#L97)</sub>

#### Nanosecond *property*

```
int Nanosecond { get; }
```

The nanosecond within the microsecond, 0 to 999.

<sub>[stdlib/Time/TimeOnly.sl:100](../../stdlib/Time/TimeOnly.sl#L100)</sub>

#### Ticks *property*

```
long Ticks { get; }
```

Hundreds of nanoseconds since midnight, as C# counts ticks.

<sub>[stdlib/Time/TimeOnly.sl:103](../../stdlib/Time/TimeOnly.sl#L103)</sub>

#### Add *method*

```
TimeOnly Add(TimeSpan span)
```

`span` later, round midnight as often as it takes.

<sub>[stdlib/Time/TimeOnly.sl:106](../../stdlib/Time/TimeOnly.sl#L106)</sub>

#### Add *method*

```
TimeOnly Add(TimeSpan span, out int wrappedDays)
```

`span` later, and how many midnights were passed: negative going back.

<sub>[stdlib/Time/TimeOnly.sl:113](../../stdlib/Time/TimeOnly.sl#L113)</sub>

#### AddHours *method*

```
TimeOnly AddHours(double hours)
```

`hours` later, round midnight.

<sub>[stdlib/Time/TimeOnly.sl:130](../../stdlib/Time/TimeOnly.sl#L130)</sub>

#### AddMinutes *method*

```
TimeOnly AddMinutes(double minutes)
```

`minutes` later, round midnight.

<sub>[stdlib/Time/TimeOnly.sl:134](../../stdlib/Time/TimeOnly.sl#L134)</sub>

#### IsBetween *method*

```
bool IsBetween(TimeOnly start, TimeOnly end)
```

Whether this is from `start` up to but not including `end`, going round
midnight when `end` is earlier than `start`.

<sub>[stdlib/Time/TimeOnly.sl:139](../../stdlib/Time/TimeOnly.sl#L139)</sub>

#### Deconstruct *method*

```
void Deconstruct(out int hour, out int minute, out int second)
```

The hour, minute and second.

<sub>[stdlib/Time/TimeOnly.sl:145](../../stdlib/Time/TimeOnly.sl#L145)</sub>

#### ToString *method*

```
String ToString()
```

`HH:mm:ss`, and the fraction of a second when there is one.

<sub>[stdlib/Time/TimeOnly.sl:153](../../stdlib/Time/TimeOnly.sl#L153)</sub>

#### Parse *method*

```
static Result<TimeOnly, TimeError> Parse(String text)
```

Reads `HH:mm`, `HH:mm:ss` or `HH:mm:ss.fffffffff`.

**Fails with**

- [TimeError.Malformed](#malformed-case) -- not one of those shapes
- [TimeError.OutOfRange](#outofrange-case) -- that shape and no real time

<sub>[stdlib/Time/TimeOnly.sl:171](../../stdlib/Time/TimeOnly.sl#L171)</sub>

#### Equals *method*

```
bool Equals(TimeOnly other)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:203](../../stdlib/Time/TimeOnly.sl#L203)</sub>

#### CompareTo *method*

```
int CompareTo(TimeOnly other)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:204](../../stdlib/Time/TimeOnly.sl#L204)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:206](../../stdlib/Time/TimeOnly.sl#L206)</sub>

#### operator - *operator*

```
static TimeSpan operator -(TimeOnly later, TimeOnly earlier)
```

How long from `earlier` to `later`, going forward round midnight, so
never negative.

<sub>[stdlib/Time/TimeOnly.sl:210](../../stdlib/Time/TimeOnly.sl#L210)</sub>

#### operator == *operator*

```
static bool operator ==(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:216](../../stdlib/Time/TimeOnly.sl#L216)</sub>

#### operator != *operator*

```
static bool operator !=(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:217](../../stdlib/Time/TimeOnly.sl#L217)</sub>

#### operator &lt; *operator*

```
static bool operator <(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:218](../../stdlib/Time/TimeOnly.sl#L218)</sub>

#### operator &gt; *operator*

```
static bool operator >(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:219](../../stdlib/Time/TimeOnly.sl#L219)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:220](../../stdlib/Time/TimeOnly.sl#L220)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(TimeOnly left, TimeOnly right)
```

*No documentation.*

<sub>[stdlib/Time/TimeOnly.sl:221](../../stdlib/Time/TimeOnly.sl#L221)</sub>

### TimeSpan *struct*

```
struct TimeSpan
```

A length of time, positive or negative.

Made by naming the unit -- `TimeSpan.FromSeconds(30)` -- because a bare
number of nanoseconds at a call site says nothing about which unit was
meant, and this is the mistake that is silent when it happens.

    var timeout = TimeSpan.FromSeconds(30);
    if (waited > timeout) { ... }

<sub>[stdlib/Time/TimeSpan.sl:34](../../stdlib/Time/TimeSpan.sl#L34)</sub>

#### Nanoseconds *field*

```
long Nanoseconds
```

The length in nanoseconds, which is the whole of the value. Readable
and writable because a struct's fields are, but a `From` method is what
says which unit was meant.

<sub>[stdlib/Time/TimeSpan.sl:39](../../stdlib/Time/TimeSpan.sl#L39)</sub>

#### FromNanoseconds *method*

```
static TimeSpan FromNanoseconds(long value)
```

A length in nanoseconds. The others are this times a factor, so this is
the one that cannot overflow on the way in.

<sub>[stdlib/Time/TimeSpan.sl:43](../../stdlib/Time/TimeSpan.sl#L43)</sub>

#### FromMicroseconds *method*

```
static TimeSpan FromMicroseconds(long value)
```

A length in whole microseconds.

<sub>[stdlib/Time/TimeSpan.sl:51](../../stdlib/Time/TimeSpan.sl#L51)</sub>

#### FromMilliseconds *method*

```
static TimeSpan FromMilliseconds(long value)
```

A length in whole milliseconds.

<sub>[stdlib/Time/TimeSpan.sl:57](../../stdlib/Time/TimeSpan.sl#L57)</sub>

#### FromSeconds *method*

```
static TimeSpan FromSeconds(long value)
```

A length in whole seconds.

<sub>[stdlib/Time/TimeSpan.sl:63](../../stdlib/Time/TimeSpan.sl#L63)</sub>

#### FromMinutes *method*

```
static TimeSpan FromMinutes(long value)
```

A length in whole minutes.

<sub>[stdlib/Time/TimeSpan.sl:69](../../stdlib/Time/TimeSpan.sl#L69)</sub>

#### FromHours *method*

```
static TimeSpan FromHours(long value)
```

A length in whole hours.

<sub>[stdlib/Time/TimeSpan.sl:75](../../stdlib/Time/TimeSpan.sl#L75)</sub>

#### FromDays *method*

```
static TimeSpan FromDays(long value)
```

A length in whole days of 24 hours each. Past about 106,751 days the
multiplication overflows a `long` of nanoseconds, silently.

<sub>[stdlib/Time/TimeSpan.sl:82](../../stdlib/Time/TimeSpan.sl#L82)</sub>

#### TotalMicroseconds *property*

```
double TotalMicroseconds { get; }
```

The whole length as microseconds.

<sub>[stdlib/Time/TimeSpan.sl:93](../../stdlib/Time/TimeSpan.sl#L93)</sub>

#### TotalMilliseconds *property*

```
double TotalMilliseconds { get; }
```

The whole length as milliseconds.

<sub>[stdlib/Time/TimeSpan.sl:96](../../stdlib/Time/TimeSpan.sl#L96)</sub>

#### TotalSeconds *property*

```
double TotalSeconds { get; }
```

The whole length as seconds.

<sub>[stdlib/Time/TimeSpan.sl:99](../../stdlib/Time/TimeSpan.sl#L99)</sub>

#### TotalMinutes *property*

```
double TotalMinutes { get; }
```

The whole length as minutes.

<sub>[stdlib/Time/TimeSpan.sl:102](../../stdlib/Time/TimeSpan.sl#L102)</sub>

#### TotalHours *property*

```
double TotalHours { get; }
```

The whole length as hours.

<sub>[stdlib/Time/TimeSpan.sl:105](../../stdlib/Time/TimeSpan.sl#L105)</sub>

#### TotalDays *property*

```
double TotalDays { get; }
```

The whole length as 24-hour days. A calendar day across a
daylight-saving change is not this.

<sub>[stdlib/Time/TimeSpan.sl:109](../../stdlib/Time/TimeSpan.sl#L109)</sub>

#### IsNegative *property*

```
bool IsNegative { get; }
```

True when the length is below zero, which is what subtracting a later
instant from an earlier one gives.

<sub>[stdlib/Time/TimeSpan.sl:113](../../stdlib/Time/TimeSpan.sl#L113)</sub>

#### operator + *operator*

```
static TimeSpan operator +(TimeSpan left, TimeSpan right)
```

Arithmetic, as arithmetic. Adding two lengths of time is what `+` means
everywhere else, and spelling it `Time.Add(a, b)` only hid that.

<sub>[stdlib/Time/TimeSpan.sl:117](../../stdlib/Time/TimeSpan.sl#L117)</sub>

#### operator - *operator*

```
static TimeSpan operator -(TimeSpan left, TimeSpan right)
```

One length less another. The result may be negative.

<sub>[stdlib/Time/TimeSpan.sl:123](../../stdlib/Time/TimeSpan.sl#L123)</sub>

#### operator - *operator*

```
static TimeSpan operator -(TimeSpan span)
```

The same length the other way round.

<sub>[stdlib/Time/TimeSpan.sl:129](../../stdlib/Time/TimeSpan.sl#L129)</sub>

#### operator * *operator*

```
static TimeSpan operator *(TimeSpan span, long times)
```

Scaling by a count: half a timeout, or three retries' worth of one.

<sub>[stdlib/Time/TimeSpan.sl:135](../../stdlib/Time/TimeSpan.sl#L135)</sub>

#### operator * *operator*

```
static TimeSpan operator *(long times, TimeSpan span)
```

The same scaling with the operands the other way round.

<sub>[stdlib/Time/TimeSpan.sl:141](../../stdlib/Time/TimeSpan.sl#L141)</sub>

#### operator / *operator*

```
static TimeSpan operator /(TimeSpan span, long parts)
```

A length split into `parts`, truncated toward zero. Dividing by zero
ends the program, as integer division does.

<sub>[stdlib/Time/TimeSpan.sl:148](../../stdlib/Time/TimeSpan.sl#L148)</sub>

#### operator == *operator*

```
static bool operator ==(TimeSpan left, TimeSpan right)
```

Whether the two lengths are equal, to the nanosecond.

<sub>[stdlib/Time/TimeSpan.sl:154](../../stdlib/Time/TimeSpan.sl#L154)</sub>

#### operator != *operator*

```
static bool operator !=(TimeSpan left, TimeSpan right)
```

Whether the two lengths differ.

<sub>[stdlib/Time/TimeSpan.sl:160](../../stdlib/Time/TimeSpan.sl#L160)</sub>

#### operator &lt; *operator*

```
static bool operator <(TimeSpan left, TimeSpan right)
```

Whether `left` is the shorter. Signed, so a negative length is below a positive one.

<sub>[stdlib/Time/TimeSpan.sl:166](../../stdlib/Time/TimeSpan.sl#L166)</sub>

#### operator &gt; *operator*

```
static bool operator >(TimeSpan left, TimeSpan right)
```

Whether `left` is the longer.

<sub>[stdlib/Time/TimeSpan.sl:172](../../stdlib/Time/TimeSpan.sl#L172)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(TimeSpan left, TimeSpan right)
```

Whether `left` is no longer than `right`.

<sub>[stdlib/Time/TimeSpan.sl:178](../../stdlib/Time/TimeSpan.sl#L178)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(TimeSpan left, TimeSpan right)
```

Whether `left` is at least as long as `right`.

<sub>[stdlib/Time/TimeSpan.sl:184](../../stdlib/Time/TimeSpan.sl#L184)</sub>

#### Compare *method*

```
static int Compare(TimeSpan left, TimeSpan right)
```

-1, 0 or 1, for sorting. The operators answer the question a program
usually has; this answers the one a sort has.

<sub>[stdlib/Time/TimeSpan.sl:191](../../stdlib/Time/TimeSpan.sl#L191)</sub>

#### Format *method*

```
String Format()
```

`1h02m03.004s`, with the leading units dropped when they are zero --
the way a log line wants it.

<sub>[stdlib/Time/TimeSpan.sl:202](../../stdlib/Time/TimeSpan.sl#L202)</sub>

### TimeZoneInfo *class*

```
sealed class TimeZoneInfo : IEquatable<TimeZoneInfo>, IHashable
```

A time zone, and the rules that move its clocks: C#'s `System.TimeZoneInfo`.

    if (TimeZoneInfo.FindSystemTimeZoneById("Europe/Paris") is Ok paris)
        var there = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, paris.Value);

On Linux and macOS the zones are the IANA database's, read from
`/usr/share/zoneinfo` (or `TZDIR`), and named as it names them. On Windows
they are the system's, named by their registry keys, and an IANA name finds
the zone it maps to where Windows carries ICU to map it.

`DateTimeOffset` here is an instant with no offset of its own, so a time
converted into a zone is the `DateTime` its clocks read, where C# answers
with a `DateTimeOffset` carrying the offset. A wall-clock time the zone
skips is `TimeError.Invalid`, where C# throws; one it passes twice is read
as standard time, as C# reads it.

<sub>[stdlib/Time/TimeZoneInfo.sl:58](../../stdlib/Time/TimeZoneInfo.sl#L58)</sub>

#### Utc *property*

```
static TimeZoneInfo Utc { get; }
```

Coordinated Universal Time.

<sub>[stdlib/Time/TimeZoneInfo.sl:96](../../stdlib/Time/TimeZoneInfo.sl#L96)</sub>

#### Local *property*

```
static TimeZoneInfo Local { get; }
```

The zone this machine is set to, or UTC when it cannot say.

<sub>[stdlib/Time/TimeZoneInfo.sl:110](../../stdlib/Time/TimeZoneInfo.sl#L110)</sub>

#### FindSystemTimeZoneById *method*

```
static Result<TimeZoneInfo, TimeError> FindSystemTimeZoneById(String id)
```

The zone named `id`: an IANA name on Linux and macOS, a registry key
name on Windows, and an IANA name there too where Windows can map it.

**Fails with**

- [TimeError.NotFound](#notfound-case) -- no zone of that name

<sub>[stdlib/Time/TimeZoneInfo.sl:149](../../stdlib/Time/TimeZoneInfo.sl#L149)</sub>

#### GetSystemTimeZones *method*

```
static List<TimeZoneInfo> GetSystemTimeZones()
```

Every zone the system knows, by offset and then by name.

<sub>[stdlib/Time/TimeZoneInfo.sl:174](../../stdlib/Time/TimeZoneInfo.sl#L174)</sub>

#### CreateCustomTimeZone *method*

```
static TimeZoneInfo CreateCustomTimeZone(String id, TimeSpan baseUtcOffset, String displayName, String standardName)
```

A zone of one offset and no daylight time.

<sub>[stdlib/Time/TimeZoneInfo.sl:207](../../stdlib/Time/TimeZoneInfo.sl#L207)</sub>

#### TryConvertIanaIdToWindowsId *method*

```
static bool TryConvertIanaIdToWindowsId(String ianaId, out String windowsId)
```

The Windows key name an IANA name maps to, where Windows carries ICU
to ask. Never, elsewhere.

<sub>[stdlib/Time/TimeZoneInfo.sl:220](../../stdlib/Time/TimeZoneInfo.sl#L220)</sub>

#### TryConvertWindowsIdToIanaId *method*

```
static bool TryConvertWindowsIdToIanaId(String windowsId, out String ianaId)
```

The IANA name a Windows key name maps to, where Windows carries ICU to
ask. Never, elsewhere.

<sub>[stdlib/Time/TimeZoneInfo.sl:225](../../stdlib/Time/TimeZoneInfo.sl#L225)</sub>

#### ConvertTime *method*

```
static DateTime ConvertTime(DateTimeOffset instant, TimeZoneInfo destination)
```

What the clocks in `destination` read at `instant`.

<sub>[stdlib/Time/TimeZoneInfo.sl:239](../../stdlib/Time/TimeZoneInfo.sl#L239)</sub>

#### ConvertTime *method*

```
static Result<DateTime, TimeError> ConvertTime(DateTime wallClock, TimeZoneInfo source, TimeZoneInfo destination)
```

What the clocks in `destination` read when those in `source` read
`wallClock`.

**Fails with**

- [TimeError.Invalid](#invalid-case) -- `source` skips that time

<sub>[stdlib/Time/TimeZoneInfo.sl:246](../../stdlib/Time/TimeZoneInfo.sl#L246)</sub>

#### ConvertTimeToUtc *method*

```
static Result<DateTimeOffset, TimeError> ConvertTimeToUtc(DateTime wallClock, TimeZoneInfo source)
```

The instant at which the clocks in `source` read `wallClock`.

**Fails with**

- [TimeError.Invalid](#invalid-case) -- `source` skips that time

<sub>[stdlib/Time/TimeZoneInfo.sl:257](../../stdlib/Time/TimeZoneInfo.sl#L257)</sub>

#### ConvertTimeFromUtc *method*

```
static DateTime ConvertTimeFromUtc(DateTime utc, TimeZoneInfo destination)
```

What the clocks in `destination` read when UTC reads `utc`.

<sub>[stdlib/Time/TimeZoneInfo.sl:269](../../stdlib/Time/TimeZoneInfo.sl#L269)</sub>

#### ConvertTimeBySystemTimeZoneId *method*

```
static Result<DateTime, TimeError> ConvertTimeBySystemTimeZoneId(DateTimeOffset instant, String id)
```

What the clocks in the zone named `id` read at `instant`.

**Fails with**

- [TimeError.NotFound](#notfound-case) -- no zone of that name

<sub>[stdlib/Time/TimeZoneInfo.sl:279](../../stdlib/Time/TimeZoneInfo.sl#L279)</sub>

#### Id *property*

```
String Id { get; }
```

What it is called: an IANA name or a Windows key name.

<sub>[stdlib/Time/TimeZoneInfo.sl:289](../../stdlib/Time/TimeZoneInfo.sl#L289)</sub>

#### DisplayName *property*

```
String DisplayName { get; }
```

How a person would recognise it, with its offset.

<sub>[stdlib/Time/TimeZoneInfo.sl:292](../../stdlib/Time/TimeZoneInfo.sl#L292)</sub>

#### StandardName *property*

```
String StandardName { get; }
```

What standard time there is called.

<sub>[stdlib/Time/TimeZoneInfo.sl:295](../../stdlib/Time/TimeZoneInfo.sl#L295)</sub>

#### DaylightName *property*

```
String DaylightName { get; }
```

What daylight time there is called.

<sub>[stdlib/Time/TimeZoneInfo.sl:298](../../stdlib/Time/TimeZoneInfo.sl#L298)</sub>

#### HasIanaId *property*

```
bool HasIanaId { get; }
```

Whether `Id` is an IANA name.

<sub>[stdlib/Time/TimeZoneInfo.sl:301](../../stdlib/Time/TimeZoneInfo.sl#L301)</sub>

#### BaseUtcOffset *property*

```
TimeSpan BaseUtcOffset { get; }
```

How far ahead of UTC standard time is, as the zone keeps it now.

<sub>[stdlib/Time/TimeZoneInfo.sl:304](../../stdlib/Time/TimeZoneInfo.sl#L304)</sub>

#### SupportsDaylightSavingTime *property*

```
bool SupportsDaylightSavingTime { get; }
```

Whether its clocks have changed for daylight time since 1970, which
is as far back as every platform's data reaches: India's clocks did
in the 1940s, and India's zone is still one that does not.

<sub>[stdlib/Time/TimeZoneInfo.sl:322](../../stdlib/Time/TimeZoneInfo.sl#L322)</sub>

#### GetUtcOffset *method*

```
TimeSpan GetUtcOffset(DateTimeOffset instant)
```

How far ahead of UTC the clocks are at `instant`.

<sub>[stdlib/Time/TimeZoneInfo.sl:338](../../stdlib/Time/TimeZoneInfo.sl#L338)</sub>

#### GetUtcOffset *method*

```
TimeSpan GetUtcOffset(DateTime wallClock)
```

How far ahead of UTC the clocks are when they read `wallClock`:
standard time where they read it twice, and the offset before the
change where they skip it.

<sub>[stdlib/Time/TimeZoneInfo.sl:344](../../stdlib/Time/TimeZoneInfo.sl#L344)</sub>

#### IsDaylightSavingTime *method*

```
bool IsDaylightSavingTime(DateTimeOffset instant)
```

Whether the clocks keep daylight time at `instant`.

<sub>[stdlib/Time/TimeZoneInfo.sl:353](../../stdlib/Time/TimeZoneInfo.sl#L353)</sub>

#### IsDaylightSavingTime *method*

```
bool IsDaylightSavingTime(DateTime wallClock)
```

Whether the clocks keep daylight time when they read `wallClock`.

<sub>[stdlib/Time/TimeZoneInfo.sl:356](../../stdlib/Time/TimeZoneInfo.sl#L356)</sub>

#### IsAmbiguousTime *method*

```
bool IsAmbiguousTime(DateTime wallClock)
```

Whether the clocks read `wallClock` twice, as they do when they go back.

<sub>[stdlib/Time/TimeZoneInfo.sl:363](../../stdlib/Time/TimeZoneInfo.sl#L363)</sub>

#### IsInvalidTime *method*

```
bool IsInvalidTime(DateTime wallClock)
```

Whether the clocks never read `wallClock`, as when they go forward.

<sub>[stdlib/Time/TimeZoneInfo.sl:366](../../stdlib/Time/TimeZoneInfo.sl#L366)</sub>

#### ToString *method*

```
String ToString()
```

The display name.

<sub>[stdlib/Time/TimeZoneInfo.sl:369](../../stdlib/Time/TimeZoneInfo.sl#L369)</sub>

#### Equals *method*

```
bool Equals(TimeZoneInfo other)
```

*No documentation.*

<sub>[stdlib/Time/TimeZoneInfo.sl:371](../../stdlib/Time/TimeZoneInfo.sl#L371)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Time/TimeZoneInfo.sl:373](../../stdlib/Time/TimeZoneInfo.sl#L373)</sub>

## Functions

### DaysInMonth *function*

```
int DaysInMonth(int year, int month)
```

How many days a month has, which for February depends on the year.

**Parameters**

- `year` -- the year the month is in, in full
- `month` -- the month, 1 to 12; anything else has no days

**See also** &nbsp; [Time.IsLeapYear](#isleapyear-function)

<sub>[stdlib/Time/Time.sl:185](../../stdlib/Time/Time.sl#L185)</sub>

### IsLeapYear *function*

```
bool IsLeapYear(int year)
```

Whether a year has 366 days, by the Gregorian rule.

<sub>[stdlib/Time/Time.sl:171](../../stdlib/Time/Time.sl#L171)</sub>

## Constants

### NanosecondsPerDay *constant*

```
const long NanosecondsPerDay = 86400000000000
```

Nanoseconds in a day, which is 24 hours exactly. A calendar day across a
daylight-saving change is not this, and nothing here pretends otherwise:
add a day to a `DateTimeOffset` and you have added 24 hours.

<sub>[stdlib/Time/Time.sl:77](../../stdlib/Time/Time.sl#L77)</sub>

### NanosecondsPerHour *constant*

```
const long NanosecondsPerHour = 3600000000000
```

Nanoseconds in an hour.

<sub>[stdlib/Time/Time.sl:72](../../stdlib/Time/Time.sl#L72)</sub>

### NanosecondsPerMicrosecond *constant*

```
const long NanosecondsPerMicrosecond = 1000
```

Nanoseconds in a microsecond.

<sub>[stdlib/Time/Time.sl:60](../../stdlib/Time/Time.sl#L60)</sub>

### NanosecondsPerMillisecond *constant*

```
const long NanosecondsPerMillisecond = 1000000
```

Nanoseconds in a millisecond.

<sub>[stdlib/Time/Time.sl:63](../../stdlib/Time/Time.sl#L63)</sub>

### NanosecondsPerMinute *constant*

```
const long NanosecondsPerMinute = 60000000000
```

Nanoseconds in a minute.

<sub>[stdlib/Time/Time.sl:69](../../stdlib/Time/Time.sl#L69)</sub>

### NanosecondsPerSecond *constant*

```
const long NanosecondsPerSecond = 1000000000
```

Nanoseconds in a second.

<sub>[stdlib/Time/Time.sl:66](../../stdlib/Time/Time.sl#L66)</sub>

