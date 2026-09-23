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

Both are structs over a single `long` of nanoseconds, so they cost nothing,
travel in a register, and compare and subtract as the numbers they are.
Sixty-four bits of nanoseconds reaches 292 years either side of 1970, which
is not the reason anything here will go wrong.

## Contents

**Types** &nbsp; [DateTime](#datetime-struct) &middot; [DateTimeOffset](#datetimeoffset-struct) &middot; [Stopwatch](#stopwatch-class) &middot; [TimeError](#timeerror-enum) &middot; [TimeSpan](#timespan-struct)

**Functions** &nbsp; [DaysInMonth](#daysinmonth-function) &middot; [IsLeapYear](#isleapyear-function)

**Constants** &nbsp; [NanosecondsPerDay](#nanosecondsperday-constant) &middot; [NanosecondsPerHour](#nanosecondsperhour-constant) &middot; [NanosecondsPerMicrosecond](#nanosecondspermicrosecond-constant) &middot; [NanosecondsPerMillisecond](#nanosecondspermillisecond-constant) &middot; [NanosecondsPerMinute](#nanosecondsperminute-constant) &middot; [NanosecondsPerSecond](#nanosecondspersecond-constant)

## Types

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

<sub>[stdlib/Time/DateTimeOffset.sl:39](../../stdlib/Time/DateTimeOffset.sl#L39)</sub>

#### UtcNow *property*

```
static DateTimeOffset UtcNow { get; }
```

What time it is now. It can go backwards between two calls; use `Stopwatch`
to measure how long something took.

**See also** &nbsp; [Stopwatch](#stopwatch-class)

<sub>[stdlib/Time/DateTimeOffset.sl:45](../../stdlib/Time/DateTimeOffset.sl#L45)</sub>

#### UnixEpoch *property*

```
static DateTimeOffset UnixEpoch { get; }
```

1970-01-01 00:00:00 UTC, which is where the count starts.

<sub>[stdlib/Time/DateTimeOffset.sl:56](../../stdlib/Time/DateTimeOffset.sl#L56)</sub>

#### FromUnixTimeSeconds *method*

```
static DateTimeOffset FromUnixTimeSeconds(long seconds)
```

An instant from whole seconds since the epoch -- what a `time_t`, a
file timestamp and most C APIs carry.

<sub>[stdlib/Time/DateTimeOffset.sl:68](../../stdlib/Time/DateTimeOffset.sl#L68)</sub>

#### FromUnixTimeMilliseconds *method*

```
static DateTimeOffset FromUnixTimeMilliseconds(long milliseconds)
```

An instant from milliseconds since the epoch, which is what JavaScript
and most JSON APIs use.

<sub>[stdlib/Time/DateTimeOffset.sl:77](../../stdlib/Time/DateTimeOffset.sl#L77)</sub>

#### FromUtc *method*

```
static DateTimeOffset FromUtc(int year, int month, int day, int hour, int minute, int second)
```

A UTC date and time as an instant.

<sub>[stdlib/Time/DateTimeOffset.sl:85](../../stdlib/Time/DateTimeOffset.sl#L85)</sub>

#### FromLocal *method*

```
static DateTimeOffset FromLocal(int year, int month, int day, int hour, int minute, int second)
```

A local date and time as an instant. Ambiguous during the hour a clock
goes back, and impossible during the hour it goes forward; the platform
decides.

**See also** &nbsp; [DateTimeOffset.FromUtc](#fromutc-method)

<sub>[stdlib/Time/DateTimeOffset.sl:99](../../stdlib/Time/DateTimeOffset.sl#L99)</sub>

#### ToUnixTimeSeconds *method*

```
long ToUnixTimeSeconds()
```

Whole seconds since the epoch, rounded toward the epoch. This is what a
file's modification time is, and what most C APIs speak.

<sub>[stdlib/Time/DateTimeOffset.sl:110](../../stdlib/Time/DateTimeOffset.sl#L110)</sub>

#### ToUnixTimeMilliseconds *method*

```
long ToUnixTimeMilliseconds()
```

Whole milliseconds since the epoch, rounded toward the epoch.

<sub>[stdlib/Time/DateTimeOffset.sl:113](../../stdlib/Time/DateTimeOffset.sl#L113)</sub>

#### UtcDateTime *property*

```
DateTime UtcDateTime { get; }
```

This instant as a date and time in UTC.

<sub>[stdlib/Time/DateTimeOffset.sl:116](../../stdlib/Time/DateTimeOffset.sl#L116)</sub>

#### LocalDateTime *property*

```
DateTime LocalDateTime { get; }
```

The same in the machine's local zone, with whatever the platform
believes about daylight saving.

**See also** &nbsp; [DateTimeOffset.UtcDateTime](#utcdatetime-property)

<sub>[stdlib/Time/DateTimeOffset.sl:122](../../stdlib/Time/DateTimeOffset.sl#L122)</sub>

#### FormatIso *method*

```
String FormatIso()
```

ISO 8601, to the second: `2026-09-05T14:30:00Z`.

**See also** &nbsp; [DateTimeOffset.ParseIso](#parseiso-method)

<sub>[stdlib/Time/DateTimeOffset.sl:127](../../stdlib/Time/DateTimeOffset.sl#L127)</sub>

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

- [TimeError.Malformed](#malformed-case) — not that shape: the wrong length, a separator out of place, or something that is not a digit where one belongs
- [TimeError.OutOfRange](#outofrange-case) — that shape, and no real moment -- the 31st of February, a month of 13, an hour of 24

**See also** &nbsp; [DateTimeOffset.FormatIso](#formatiso-method)

<sub>[stdlib/Time/DateTimeOffset.sl:145](../../stdlib/Time/DateTimeOffset.sl#L145)</sub>

#### Offset *property*

```
TimeSpan Offset { get; }
```

How far ahead of UTC the local zone was at this instant. Negative west
of Greenwich.

<sub>[stdlib/Time/DateTimeOffset.sl:152](../../stdlib/Time/DateTimeOffset.sl#L152)</sub>

#### operator - *operator*

```
static TimeSpan operator -(DateTimeOffset later, DateTimeOffset earlier)
```

How long apart two instants are. Negative if the right one is later.

<sub>[stdlib/Time/DateTimeOffset.sl:156](../../stdlib/Time/DateTimeOffset.sl#L156)</sub>

#### operator + *operator*

```
static DateTimeOffset operator +(DateTimeOffset at, TimeSpan span)
```

An instant moved forward by a length of time. Exact nanoseconds, so a
day added is 24 hours and not a calendar day.

<sub>[stdlib/Time/DateTimeOffset.sl:163](../../stdlib/Time/DateTimeOffset.sl#L163)</sub>

#### operator - *operator*

```
static DateTimeOffset operator -(DateTimeOffset at, TimeSpan span)
```

An instant moved back by a length of time.

<sub>[stdlib/Time/DateTimeOffset.sl:171](../../stdlib/Time/DateTimeOffset.sl#L171)</sub>

#### operator == *operator*

```
static bool operator ==(DateTimeOffset left, DateTimeOffset right)
```

Whether the two name the same nanosecond.

<sub>[stdlib/Time/DateTimeOffset.sl:179](../../stdlib/Time/DateTimeOffset.sl#L179)</sub>

#### operator != *operator*

```
static bool operator !=(DateTimeOffset left, DateTimeOffset right)
```

Whether they name different nanoseconds.

<sub>[stdlib/Time/DateTimeOffset.sl:185](../../stdlib/Time/DateTimeOffset.sl#L185)</sub>

#### operator &lt; *operator*

```
static bool operator <(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is the earlier.

<sub>[stdlib/Time/DateTimeOffset.sl:191](../../stdlib/Time/DateTimeOffset.sl#L191)</sub>

#### operator &gt; *operator*

```
static bool operator >(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is the later.

<sub>[stdlib/Time/DateTimeOffset.sl:197](../../stdlib/Time/DateTimeOffset.sl#L197)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is no later than `right`.

<sub>[stdlib/Time/DateTimeOffset.sl:203](../../stdlib/Time/DateTimeOffset.sl#L203)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(DateTimeOffset left, DateTimeOffset right)
```

Whether `left` is no earlier than `right`.

<sub>[stdlib/Time/DateTimeOffset.sl:209](../../stdlib/Time/DateTimeOffset.sl#L209)</sub>

#### Compare *method*

```
static int Compare(DateTimeOffset left, DateTimeOffset right)
```

-1, 0 or 1, for sorting. The operators answer the question a program
usually has; this answers the one a sort has.

<sub>[stdlib/Time/DateTimeOffset.sl:216](../../stdlib/Time/DateTimeOffset.sl#L216)</sub>

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

## Functions

### DaysInMonth *function*

```
int DaysInMonth(int year, int month)
```

How many days a month has, which for February depends on the year.

**Parameters**

- `year` — the year the month is in, in full
- `month` — the month, 1 to 12; anything else has no days

**See also** &nbsp; [Time.IsLeapYear](#isleapyear-function)

<sub>[stdlib/Time/Time.sl:165](../../stdlib/Time/Time.sl#L165)</sub>

### IsLeapYear *function*

```
bool IsLeapYear(int year)
```

Whether a year has 366 days, by the Gregorian rule.

<sub>[stdlib/Time/Time.sl:151](../../stdlib/Time/Time.sl#L151)</sub>

## Constants

### NanosecondsPerDay *constant*

```
const long NanosecondsPerDay = 86400000000000
```

Nanoseconds in a day, which is 24 hours exactly. A calendar day across a
daylight-saving change is not this, and nothing here pretends otherwise:
add a day to a `DateTimeOffset` and you have added 24 hours.

<sub>[stdlib/Time/Time.sl:70](../../stdlib/Time/Time.sl#L70)</sub>

### NanosecondsPerHour *constant*

```
const long NanosecondsPerHour = 3600000000000
```

Nanoseconds in an hour.

<sub>[stdlib/Time/Time.sl:65](../../stdlib/Time/Time.sl#L65)</sub>

### NanosecondsPerMicrosecond *constant*

```
const long NanosecondsPerMicrosecond = 1000
```

Nanoseconds in a microsecond.

<sub>[stdlib/Time/Time.sl:53](../../stdlib/Time/Time.sl#L53)</sub>

### NanosecondsPerMillisecond *constant*

```
const long NanosecondsPerMillisecond = 1000000
```

Nanoseconds in a millisecond.

<sub>[stdlib/Time/Time.sl:56](../../stdlib/Time/Time.sl#L56)</sub>

### NanosecondsPerMinute *constant*

```
const long NanosecondsPerMinute = 60000000000
```

Nanoseconds in a minute.

<sub>[stdlib/Time/Time.sl:62](../../stdlib/Time/Time.sl#L62)</sub>

### NanosecondsPerSecond *constant*

```
const long NanosecondsPerSecond = 1000000000
```

Nanoseconds in a second.

<sub>[stdlib/Time/Time.sl:59](../../stdlib/Time/Time.sl#L59)</sub>

