# Standard.Time

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Time, of the two kinds that must not be confused.

An `Instant` is a point on the wall clock: a date and a time of day. It can
jump, because a user sets the clock, NTP corrects it, or a laptop wakes up.
Never subtract two of them to find out how long something took.

A `Duration` is a length of time, and `Clock` reads a monotonic counter that
only ever goes forward. That pair is what a measurement wants.

Both are structs over a single `long` of nanoseconds, so they cost nothing,
travel in a register, and compare and subtract as the numbers they are.
Sixty-four bits of nanoseconds reaches 292 years either side of 1970, which
is not the reason anything here will go wrong.

## Contents

**Types** &nbsp; [Clock](#clock-class) &middot; [DateTime](#datetime-struct) &middot; [Duration](#duration-struct) &middot; [Instant](#instant-struct) &middot; [TimeError](#timeerror-enum)

**Functions** &nbsp; [DaysInMonth](#daysinmonth-function) &middot; [IsLeapYear](#isleapyear-function)

**Constants** &nbsp; [NanosecondsPerDay](#nanosecondsperday-constant) &middot; [NanosecondsPerHour](#nanosecondsperhour-constant) &middot; [NanosecondsPerMicrosecond](#nanosecondspermicrosecond-constant) &middot; [NanosecondsPerMillisecond](#nanosecondspermillisecond-constant) &middot; [NanosecondsPerMinute](#nanosecondsperminute-constant) &middot; [NanosecondsPerSecond](#nanosecondspersecond-constant)

## Types

### Clock *class*

```
class Clock
```

A stopwatch over the monotonic counter.

This is the only correct way to measure a duration: the wall clock can jump
while you are timing, and a measurement that came out negative because NTP
stepped the clock is a bug nobody finds.

    var clock = new Clock();
    DoTheWork();
    Console.WriteLine(clock.Elapsed().Format());

<sub>[stdlib/Time.sl:630](../../stdlib/Time.sl#L630)</sub>

#### Elapsed *method*

```
Duration Elapsed()
```

How long since it was made, or since `Restart`.

<sub>[stdlib/Time.sl:638](../../stdlib/Time.sl#L638)</sub>

#### Restart *method*

```
Duration Restart()
```

Starts again from now, returning what had passed until this moment.

<sub>[stdlib/Time.sl:643](../../stdlib/Time.sl#L643)</sub>

#### Monotonic *method*

```
static Duration Monotonic()
```

A reading of the monotonic counter, for code that would rather keep
the number than an object. Meaningless on its own; subtract two.

<sub>[stdlib/Time.sl:652](../../stdlib/Time.sl#L652)</sub>

### DateTime *struct*

```
struct DateTime
```

An instant broken into the parts a person reads.

Made by `ToUtc` or `ToLocal`, which is what says which zone the numbers are
in -- the struct itself does not carry that, because a date with no zone is
exactly as ambiguous as it sounds.

<sub>[stdlib/Time.sl:426](../../stdlib/Time.sl#L426)</sub>

#### Year *field*

```
int Year
```

The year, in full. Zero means the instant was outside what the platform
can name, and every other field is zero with it -- that is how this
struct reports a failure, since it has no other way to.

<sub>[stdlib/Time.sl:430](../../stdlib/Time.sl#L430)</sub>

#### Month *field*

```
int Month
```

The month, 1 to 12.

<sub>[stdlib/Time.sl:433](../../stdlib/Time.sl#L433)</sub>

#### Day *field*

```
int Day
```

The day of the month, 1 to 31.

<sub>[stdlib/Time.sl:436](../../stdlib/Time.sl#L436)</sub>

#### Hour *field*

```
int Hour
```

The hour, 0 to 23.

<sub>[stdlib/Time.sl:439](../../stdlib/Time.sl#L439)</sub>

#### Minute *field*

```
int Minute
```

The minute, 0 to 59.

<sub>[stdlib/Time.sl:442](../../stdlib/Time.sl#L442)</sub>

#### Second *field*

```
int Second
```

The second, 0 to 60 -- 60 because a leap second is a real reading of a
real clock.

<sub>[stdlib/Time.sl:446](../../stdlib/Time.sl#L446)</sub>

#### Nanosecond *field*

```
int Nanosecond
```

Nanoseconds within the second, 0 to 999,999,999.

<sub>[stdlib/Time.sl:449](../../stdlib/Time.sl#L449)</sub>

#### DayOfWeek *field*

```
int DayOfWeek
```

The day of the week, 0 for Sunday through 6 for Saturday.

<sub>[stdlib/Time.sl:452](../../stdlib/Time.sl#L452)</sub>

#### DayOfYear *field*

```
int DayOfYear
```

The day of the year, 1 to 366.

<sub>[stdlib/Time.sl:455](../../stdlib/Time.sl#L455)</sub>

#### FormatDate *method*

```
String FormatDate()
```

The date alone: `2026-09-05`.

<sub>[stdlib/Time.sl:458](../../stdlib/Time.sl#L458)</sub>

#### FormatTime *method*

```
String FormatTime()
```

The time of day alone: `14:30:00`.

<sub>[stdlib/Time.sl:469](../../stdlib/Time.sl#L469)</sub>

### Duration *struct*

```
struct Duration
```

A length of time, positive or negative.

Made by naming the unit -- `Duration.FromSeconds(30)` -- because a bare
number of nanoseconds at a call site says nothing about which unit was
meant, and this is the mistake that is silent when it happens.

    var timeout = Duration.FromSeconds(30);
    if (waited > timeout) { ... }

<sub>[stdlib/Time.sl:79](../../stdlib/Time.sl#L79)</sub>

#### Nanoseconds *field*

```
long Nanoseconds
```

The length in nanoseconds, which is the whole of the value. Readable
and writable because a struct's fields are, but a `From` method is what
says which unit was meant.

<sub>[stdlib/Time.sl:83](../../stdlib/Time.sl#L83)</sub>

#### FromNanoseconds *method*

```
static Duration FromNanoseconds(long value)
```

A length in nanoseconds. The others are this times a factor, so this is
the one that cannot overflow on the way in.

<sub>[stdlib/Time.sl:87](../../stdlib/Time.sl#L87)</sub>

#### FromMicroseconds *method*

```
static Duration FromMicroseconds(long value)
```

A length in whole microseconds.

<sub>[stdlib/Time.sl:94](../../stdlib/Time.sl#L94)</sub>

#### FromMilliseconds *method*

```
static Duration FromMilliseconds(long value)
```

A length in whole milliseconds.

<sub>[stdlib/Time.sl:99](../../stdlib/Time.sl#L99)</sub>

#### FromSeconds *method*

```
static Duration FromSeconds(long value)
```

A length in whole seconds.

<sub>[stdlib/Time.sl:104](../../stdlib/Time.sl#L104)</sub>

#### FromMinutes *method*

```
static Duration FromMinutes(long value)
```

A length in whole minutes.

<sub>[stdlib/Time.sl:109](../../stdlib/Time.sl#L109)</sub>

#### FromHours *method*

```
static Duration FromHours(long value)
```

A length in whole hours.

<sub>[stdlib/Time.sl:114](../../stdlib/Time.sl#L114)</sub>

#### FromDays *method*

```
static Duration FromDays(long value)
```

A length in whole days of 24 hours each. Past about 106,751 days the
multiplication overflows a `long` of nanoseconds, silently.

<sub>[stdlib/Time.sl:120](../../stdlib/Time.sl#L120)</sub>

#### TotalMilliseconds *method*

```
long TotalMilliseconds()
```

Whole units, truncated toward zero. 1,500,000ns is 1 millisecond.

<sub>[stdlib/Time.sl:125](../../stdlib/Time.sl#L125)</sub>

#### TotalSeconds *method*

```
long TotalSeconds()
```

Whole seconds, truncated toward zero.

<sub>[stdlib/Time.sl:128](../../stdlib/Time.sl#L128)</sub>

#### TotalMinutes *method*

```
long TotalMinutes()
```

Whole minutes, truncated toward zero.

<sub>[stdlib/Time.sl:131](../../stdlib/Time.sl#L131)</sub>

#### TotalHours *method*

```
long TotalHours()
```

Whole hours, truncated toward zero.

<sub>[stdlib/Time.sl:134](../../stdlib/Time.sl#L134)</sub>

#### TotalDays *method*

```
long TotalDays()
```

Whole 24-hour days, truncated toward zero.

<sub>[stdlib/Time.sl:137](../../stdlib/Time.sl#L137)</sub>

#### AsSeconds *method*

```
double AsSeconds()
```

The same length with fractions kept, for a measurement being reported
rather than counted.

<sub>[stdlib/Time.sl:141](../../stdlib/Time.sl#L141)</sub>

#### AsMilliseconds *method*

```
double AsMilliseconds()
```

The same length in milliseconds, fractions kept.

<sub>[stdlib/Time.sl:144](../../stdlib/Time.sl#L144)</sub>

#### IsNegative *method*

```
bool IsNegative()
```

True when the length is below zero, which is what subtracting a later
instant from an earlier one gives.

<sub>[stdlib/Time.sl:148](../../stdlib/Time.sl#L148)</sub>

#### operator + *operator*

```
static Duration operator +(Duration left, Duration right)
```

Arithmetic, as arithmetic. Adding two lengths of time is what `+` means
everywhere else, and spelling it `Time.Add(a, b)` only hid that.

<sub>[stdlib/Time.sl:152](../../stdlib/Time.sl#L152)</sub>

#### operator - *operator*

```
static Duration operator -(Duration left, Duration right)
```

One length less another. The result may be negative.

<sub>[stdlib/Time.sl:157](../../stdlib/Time.sl#L157)</sub>

#### operator - *operator*

```
static Duration operator -(Duration span)
```

The same length the other way round.

<sub>[stdlib/Time.sl:162](../../stdlib/Time.sl#L162)</sub>

#### operator * *operator*

```
static Duration operator *(Duration span, long times)
```

Scaling by a count: half a timeout, or three retries' worth of one.

<sub>[stdlib/Time.sl:167](../../stdlib/Time.sl#L167)</sub>

#### operator * *operator*

```
static Duration operator *(long times, Duration span)
```

The same scaling with the operands the other way round.

<sub>[stdlib/Time.sl:172](../../stdlib/Time.sl#L172)</sub>

#### operator / *operator*

```
static Duration operator /(Duration span, long parts)
```

A length split into `parts`, truncated toward zero. Dividing by zero
ends the program, as integer division does.

<sub>[stdlib/Time.sl:178](../../stdlib/Time.sl#L178)</sub>

#### operator == *operator*

```
static bool operator ==(Duration left, Duration right)
```

Whether the two lengths are equal, to the nanosecond.

<sub>[stdlib/Time.sl:183](../../stdlib/Time.sl#L183)</sub>

#### operator != *operator*

```
static bool operator !=(Duration left, Duration right)
```

Whether the two lengths differ.

<sub>[stdlib/Time.sl:188](../../stdlib/Time.sl#L188)</sub>

#### operator &lt; *operator*

```
static bool operator <(Duration left, Duration right)
```

Whether `left` is the shorter. Signed, so a negative length is below a positive one.

<sub>[stdlib/Time.sl:193](../../stdlib/Time.sl#L193)</sub>

#### operator &gt; *operator*

```
static bool operator >(Duration left, Duration right)
```

Whether `left` is the longer.

<sub>[stdlib/Time.sl:198](../../stdlib/Time.sl#L198)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(Duration left, Duration right)
```

Whether `left` is no longer than `right`.

<sub>[stdlib/Time.sl:203](../../stdlib/Time.sl#L203)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(Duration left, Duration right)
```

Whether `left` is at least as long as `right`.

<sub>[stdlib/Time.sl:208](../../stdlib/Time.sl#L208)</sub>

#### Compare *method*

```
static int Compare(Duration left, Duration right)
```

-1, 0 or 1, for sorting. The operators answer the question a program
usually has; this answers the one a sort has.

<sub>[stdlib/Time.sl:214](../../stdlib/Time.sl#L214)</sub>

#### Format *method*

```
String Format()
```

`1h02m03.004s`, with the leading units dropped when they are zero --
the way a log line wants it.

<sub>[stdlib/Time.sl:222](../../stdlib/Time.sl#L222)</sub>

### Instant *struct*

```
struct Instant
```

A point on the wall clock, as nanoseconds since 1970-01-01 UTC.

    var started = Instant.Now();
    var waited = Instant.Now() - started;

Subtracting two instants gives a `Duration`, and adding a `Duration` to one
gives another instant. Adding two instants is not defined, because the sum
of two dates is not a date -- which is exactly the thing a free function
named `Add` could not say.

<sub>[stdlib/Time.sl:271](../../stdlib/Time.sl#L271)</sub>

#### Nanoseconds *field*

```
long Nanoseconds
```

Nanoseconds since 1970-01-01 UTC, negative before it. The whole of the
value, and the thing to hand a C API that wants an epoch count.

<sub>[stdlib/Time.sl:274](../../stdlib/Time.sl#L274)</sub>

#### Now *method*

```
static Instant Now()
```

What time it is now. It can go backwards between two calls; use `Clock`
to measure how long something took.

<sub>[stdlib/Time.sl:278](../../stdlib/Time.sl#L278)</sub>

#### Epoch *method*

```
static Instant Epoch()
```

1970-01-01 00:00:00 UTC, which is where the count starts.

<sub>[stdlib/Time.sl:285](../../stdlib/Time.sl#L285)</sub>

#### FromUnixSeconds *method*

```
static Instant FromUnixSeconds(long seconds)
```

An instant from whole seconds since the epoch -- what a `time_t`, a
file timestamp and most C APIs carry.

<sub>[stdlib/Time.sl:293](../../stdlib/Time.sl#L293)</sub>

#### FromUnixMilliseconds *method*

```
static Instant FromUnixMilliseconds(long milliseconds)
```

An instant from milliseconds since the epoch, which is what JavaScript
and most JSON APIs use.

<sub>[stdlib/Time.sl:301](../../stdlib/Time.sl#L301)</sub>

#### FromUtc *method*

```
static Instant FromUtc(int year, int month, int day, int hour, int minute, int second)
```

A UTC date and time as an instant.

<sub>[stdlib/Time.sl:308](../../stdlib/Time.sl#L308)</sub>

#### FromLocal *method*

```
static Instant FromLocal(int year, int month, int day, int hour, int minute, int second)
```

A local date and time as an instant. Ambiguous during the hour a clock
goes back, and impossible during the hour it goes forward; the platform
decides.

<sub>[stdlib/Time.sl:319](../../stdlib/Time.sl#L319)</sub>

#### ToUnixSeconds *method*

```
long ToUnixSeconds()
```

Whole seconds since the epoch, rounded toward the epoch. This is what a
file's modification time is, and what most C APIs speak.

<sub>[stdlib/Time.sl:329](../../stdlib/Time.sl#L329)</sub>

#### ToUnixMilliseconds *method*

```
long ToUnixMilliseconds()
```

Whole milliseconds since the epoch, rounded toward the epoch.

<sub>[stdlib/Time.sl:332](../../stdlib/Time.sl#L332)</sub>

#### ToUtc *method*

```
DateTime ToUtc()
```

This instant as a date and time in UTC.

<sub>[stdlib/Time.sl:335](../../stdlib/Time.sl#L335)</sub>

#### ToLocal *method*

```
DateTime ToLocal()
```

The same in the machine's local zone, with whatever the platform
believes about daylight saving.

<sub>[stdlib/Time.sl:339](../../stdlib/Time.sl#L339)</sub>

#### FormatIso *method*

```
String FormatIso()
```

ISO 8601, to the second: `2026-09-05T14:30:00Z`.

<sub>[stdlib/Time.sl:342](../../stdlib/Time.sl#L342)</sub>

#### ParseIso *method*

```
static Result<Instant, TimeError> ParseIso(String text)
```

`2026-09-05T14:30:00Z` back to an instant.

A `Result` rather than a nullable, because an `Instant` is a struct and
a struct is never null (SL0271) -- and because "that is not a date" and
"that is not a real date" are worth telling apart.

Deliberately strict: exactly the shape `FormatIso` writes, so a round
trip is exact and anything else is refused rather than half-read.

<sub>[stdlib/Time.sl:352](../../stdlib/Time.sl#L352)</sub>

#### ZoneOffsetSeconds *method*

```
long ZoneOffsetSeconds()
```

How far ahead of UTC the local zone was at this instant, in seconds.
Negative west of Greenwich.

<sub>[stdlib/Time.sl:358](../../stdlib/Time.sl#L358)</sub>

#### operator - *operator*

```
static Duration operator -(Instant later, Instant earlier)
```

How long apart two instants are. Negative if the right one is later.

<sub>[stdlib/Time.sl:361](../../stdlib/Time.sl#L361)</sub>

#### operator + *operator*

```
static Instant operator +(Instant at, Duration span)
```

An instant moved forward by a length of time. Exact nanoseconds, so a
day added is 24 hours and not a calendar day.

<sub>[stdlib/Time.sl:367](../../stdlib/Time.sl#L367)</sub>

#### operator - *operator*

```
static Instant operator -(Instant at, Duration span)
```

An instant moved back by a length of time.

<sub>[stdlib/Time.sl:374](../../stdlib/Time.sl#L374)</sub>

#### operator == *operator*

```
static bool operator ==(Instant left, Instant right)
```

Whether the two name the same nanosecond.

<sub>[stdlib/Time.sl:381](../../stdlib/Time.sl#L381)</sub>

#### operator != *operator*

```
static bool operator !=(Instant left, Instant right)
```

Whether they name different nanoseconds.

<sub>[stdlib/Time.sl:386](../../stdlib/Time.sl#L386)</sub>

#### operator &lt; *operator*

```
static bool operator <(Instant left, Instant right)
```

Whether `left` is the earlier.

<sub>[stdlib/Time.sl:391](../../stdlib/Time.sl#L391)</sub>

#### operator &gt; *operator*

```
static bool operator >(Instant left, Instant right)
```

Whether `left` is the later.

<sub>[stdlib/Time.sl:396](../../stdlib/Time.sl#L396)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(Instant left, Instant right)
```

Whether `left` is no later than `right`.

<sub>[stdlib/Time.sl:401](../../stdlib/Time.sl#L401)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(Instant left, Instant right)
```

Whether `left` is no earlier than `right`.

<sub>[stdlib/Time.sl:406](../../stdlib/Time.sl#L406)</sub>

#### Compare *method*

```
static int Compare(Instant left, Instant right)
```

-1, 0 or 1, for sorting. The operators answer the question a program
usually has; this answers the one a sort has.

<sub>[stdlib/Time.sl:412](../../stdlib/Time.sl#L412)</sub>

### TimeError *enum*

```
enum TimeError
```

Why a moment could not be read.

<sub>[stdlib/Time.sl:561](../../stdlib/Time.sl#L561)</sub>

#### None *case*

```
None
```

Nothing went wrong. Present so the enum has a zero value; a `Result`
says success by being `Ok`, so this is not what a failure carries.

<sub>[stdlib/Time.sl:564](../../stdlib/Time.sl#L564)</sub>

#### Malformed *case*

```
Malformed
```

Not the shape `FormatIso` writes -- the wrong length, or a separator
in the wrong place, or something that is not a digit where one belongs.

<sub>[stdlib/Time.sl:568](../../stdlib/Time.sl#L568)</sub>

#### OutOfRange *case*

```
OutOfRange
```

The right shape and not a real moment: the 31st of February, a month of
13, an hour of 24.

<sub>[stdlib/Time.sl:572](../../stdlib/Time.sl#L572)</sub>

## Functions

### DaysInMonth *function*

```
int DaysInMonth(int year, int month)
```

How many days a month has, which for February depends on the year.

<sub>[stdlib/Time.sl:519](../../stdlib/Time.sl#L519)</sub>

### IsLeapYear *function*

```
bool IsLeapYear(int year)
```

Whether a year has 366 days, by the Gregorian rule.

<sub>[stdlib/Time.sl:512](../../stdlib/Time.sl#L512)</sub>

## Constants

### NanosecondsPerDay *constant*

```
const long NanosecondsPerDay = 86400000000000
```

Nanoseconds in a day, which is 24 hours exactly. A calendar day across a
daylight-saving change is not this, and nothing here pretends otherwise:
add a day to an `Instant` and you have added 24 hours.

<sub>[stdlib/Time.sl:67](../../stdlib/Time.sl#L67)</sub>

### NanosecondsPerHour *constant*

```
const long NanosecondsPerHour = 3600000000000
```

Nanoseconds in an hour.

<sub>[stdlib/Time.sl:62](../../stdlib/Time.sl#L62)</sub>

### NanosecondsPerMicrosecond *constant*

```
const long NanosecondsPerMicrosecond = 1000
```

Nanoseconds in a microsecond.

<sub>[stdlib/Time.sl:50](../../stdlib/Time.sl#L50)</sub>

### NanosecondsPerMillisecond *constant*

```
const long NanosecondsPerMillisecond = 1000000
```

Nanoseconds in a millisecond.

<sub>[stdlib/Time.sl:53](../../stdlib/Time.sl#L53)</sub>

### NanosecondsPerMinute *constant*

```
const long NanosecondsPerMinute = 60000000000
```

Nanoseconds in a minute.

<sub>[stdlib/Time.sl:59](../../stdlib/Time.sl#L59)</sub>

### NanosecondsPerSecond *constant*

```
const long NanosecondsPerSecond = 1000000000
```

Nanoseconds in a second.

<sub>[stdlib/Time.sl:56](../../stdlib/Time.sl#L56)</sub>

