# Standard.Media.Audio

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Sound out of the machine, and sound into it.

```csharp
var loaded = Wav.FromFile("chime.wav");
if (loaded.Ok)
    Audio.PlayClip(loaded.Value);

var heard = Audio.RecordClip(AudioFormat.Voice, 3.0);   // three seconds
if (heard.Ok)
    Wav.Save(heard.Value, "heard.wav");
```

**Interleaved PCM, and nothing else.** 8-bit unsigned or 16-bit signed,
one channel or two, at whatever rate the device will take. That is what
every platform agrees about and what a WAV file holds; a decoder for a
compressed format is a separate piece of work and saying so is better than
half of it.

**WASAPI on Windows, ALSA everywhere else, and neither is linked.** Both
are reached by name the first time a device is opened, which is what lets
this live in the standard library: a program that makes no sound pays
nothing, and a machine with no ALSA answers `AudioError.NoBackend` -- a
value to print, rather than a link error. `Audio.IsAvailable` asks before
anything is tried.

**WASAPI rather than waveOut.** `winmm`'s `waveOut` is four calls and is
still present on Windows 11, which makes it tempting and makes it the wrong
answer: since Vista it has been an emulation on top of WASAPI, so it adds a
buffer of latency to reach the same mixer, and it does not exist inside an
app container. What WASAPI costs is an apartment and six COM interfaces;
what it buys is the actual system interface, the engine's own rate and
channel conversion, and a device that can be asked what it is. A program
that wants a game engine's mixing and 3D positioning wants `Win32.XAudio2`,
which is bound separately.

**This blocks.** `AudioPlayer.Write` returns when the device has taken the
bytes, which is after it has played what was queued ahead of them; there is
no callback and no mixing. A program with a user interface should do its
audio on a thread of its own -- `Standard.Threading` is right there -- and
a program that wants several sounds at once wants a mixer, which this is
not.

## Contents

**Types** &nbsp; [AudioClip](#audioclip-class) &middot; [AudioError](#audioerror-enum) &middot; [AudioFormat](#audioformat-struct) &middot; [AudioPlayer](#audioplayer-class) &middot; [AudioRecorder](#audiorecorder-class) &middot; [Tone](#tone-class) &middot; [Wav](#wav-class)

**Functions** &nbsp; [BackendName](#backendname-function) &middot; [CanPlay](#canplay-function) &middot; [CanRecord](#canrecord-function) &middot; [IsAvailable](#isavailable-function) &middot; [PlayClip](#playclip-function) &middot; [RecordClip](#recordclip-function)

## Types

### AudioClip *class*

```
sealed class AudioClip
```

Samples in memory, and what they are.

The unit `Wav` reads and writes and `Audio.PlayClip` takes. It is bytes rather
than a typed sample array deliberately: the width is in the format, a
conversion on the way in would cost a copy of every sound a program loads,
and the platform wants bytes at the end of it anyway. `GetSample` and
`SetSample` are there for a program that does want to look.

<sub>[stdlib/Audio.sl:192](../../stdlib/Audio.sl#L192)</sub>

#### CreateSilence *method*

```
static AudioClip CreateSilence(AudioFormat format, nuint frames)
```

Silence, `frames` long.

Zero is silence for sixteen-bit samples and a hard offset for eight-bit
ones, so this fills with 128 there -- which is what silence is in an
unsigned format, and the kind of detail that otherwise shows up as a
click.

<sub>[stdlib/Audio.sl:212](../../stdlib/Audio.sl#L212)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

*No documentation.*

<sub>[stdlib/Audio.sl:224](../../stdlib/Audio.sl#L224)</sub>

#### Samples *property*

```
byte[] Samples { get; }
```

The bytes. Not a copy.

<sub>[stdlib/Audio.sl:227](../../stdlib/Audio.sl#L227)</sub>

#### FrameCount *property*

```
nuint FrameCount { get; }
```

How many frames it holds.

Written out rather than as a ternary: `nuint` is four bytes on a 32-bit
target and eight on a 64-bit one, and the arms of a ternary over an
unsuffixed literal and a `nuint` meet at a type that is neither.

<sub>[stdlib/Audio.sl:234](../../stdlib/Audio.sl#L234)</sub>

#### Duration *property*

```
double Duration { get; }
```

How long it lasts, in seconds.

<sub>[stdlib/Audio.sl:245](../../stdlib/Audio.sl#L245)</sub>

#### GetSample *method*

```
int GetSample(nuint frame, nuint channel)
```

One sample, as a number from -32768 to 32767 whatever the width is.

Eight-bit samples are widened and re-centred on the way out, so a
caller reading a clip need not know which it has. A sample wider than
sixteen bits answers its top sixteen. Out of range answers
zero rather than aborting: a program walking a waveform runs off the
end at the end, and that is not a mistake in it.

**Parameters**

- `frame` — which frame, counting from zero
- `channel` — which channel of it, 0 or 1

**See also** &nbsp; [AudioClip.SetSample](#setsample-method)

<sub>[stdlib/Audio.sl:260](../../stdlib/Audio.sl#L260)</sub>

#### SetSample *method*

```
void SetSample(nuint frame, nuint channel, int value)
```

One sample written, taking the same range `GetSample` answers in and
clamping to it. A sample wider than sixteen bits has its top sixteen
set and the bits below them cleared. Out of range does nothing.

**Parameters**

- `frame` — which frame, counting from zero
- `channel` — which channel of it, 0 or 1
- `value` — the sample, -32768 to 32767, clamped to that

**See also** &nbsp; [AudioClip.GetSample](#getsample-method)

<sub>[stdlib/Audio.sl:289](../../stdlib/Audio.sl#L289)</sub>

### AudioError *enum*

```
enum AudioError
```

Why a sound did not happen.

<sub>[stdlib/Audio.sl:157](../../stdlib/Audio.sl#L157)</sub>

#### NoBackend *case*

```
NoBackend
```

There is no audio library on this machine: no winmm, or no
libasound. `Audio.IsAvailable` is how to ask before trying.

<sub>[stdlib/Audio.sl:161](../../stdlib/Audio.sl#L161)</sub>

#### Format *case*

```
Format
```

The format is not one this module handles, or not one the device
would take.

<sub>[stdlib/Audio.sl:165](../../stdlib/Audio.sl#L165)</sub>

#### Device *case*

```
Device
```

There is no sound device, or the one there is refused to open.

<sub>[stdlib/Audio.sl:168](../../stdlib/Audio.sl#L168)</sub>

#### Busy *case*

```
Busy
```

Something else has the device and will not share it.

<sub>[stdlib/Audio.sl:171](../../stdlib/Audio.sl#L171)</sub>

#### Closed *case*

```
Closed
```

The player or recorder has been closed.

<sub>[stdlib/Audio.sl:174](../../stdlib/Audio.sl#L174)</sub>

#### Malformed *case*

```
Malformed
```

The file was not a WAV, or was one this module does not read.

<sub>[stdlib/Audio.sl:177](../../stdlib/Audio.sl#L177)</sub>

#### Io *case*

```
Io
```

The file could not be read or written; `Standard.IO` has the detail.

<sub>[stdlib/Audio.sl:180](../../stdlib/Audio.sl#L180)</sub>

### AudioFormat *struct*

```
struct AudioFormat
```

What the samples are: how fast, how many channels, how wide.

A struct of three numbers, because that is what every platform's format
descriptor holds and what a WAV header carries. Anything a device will not
take is reported by `AudioPlayer.Open` rather than refused here -- what a
sound card accepts is not knowable from the numbers alone.

**See also** &nbsp; [AudioPlayer.Open](#open-method)

<sub>[stdlib/Audio.sl:95](../../stdlib/Audio.sl#L95)</sub>

#### SampleRate *field*

```
uint SampleRate
```

Frames per second. 44100 is a CD, 48000 is what most hardware runs at
natively, 8000 is a telephone.

<sub>[stdlib/Audio.sl:99](../../stdlib/Audio.sl#L99)</sub>

#### Channels *field*

```
ushort Channels
```

1 for mono, 2 for stereo. More is not supported: the interleaving is
defined for those two and the channel-order conventions past them are
not the same on both platforms.

<sub>[stdlib/Audio.sl:104](../../stdlib/Audio.sl#L104)</sub>

#### BitsPerSample *field*

```
ushort BitsPerSample
```

8 or 16. Eight-bit samples are *unsigned* and centred on 128, and
sixteen-bit ones are signed and centred on zero -- which is WAV's rule
and both platforms', however strange it reads.

<sub>[stdlib/Audio.sl:109](../../stdlib/Audio.sl#L109)</sub>

#### Create *method*

```
static AudioFormat Create(uint sampleRate, ushort channels, ushort bits)
```

A format written out.

**Parameters**

- `sampleRate` — frames per second: 44100 for a CD, 8000 for a telephone
- `channels` — 1 for mono, 2 for stereo, and nothing else
- `bits` — 8 or 16, the width of one sample

<sub>[stdlib/Audio.sl:117](../../stdlib/Audio.sl#L117)</sub>

#### Cd *property*

```
static AudioFormat Cd { get; }
```

44.1 kHz, sixteen bits, stereo: what a CD is and what a WAV file
usually holds.

<sub>[stdlib/Audio.sl:128](../../stdlib/Audio.sl#L128)</sub>

#### Studio *property*

```
static AudioFormat Studio { get; }
```

48 kHz, sixteen bits, stereo: what most sound hardware runs at without
resampling, and what to prefer when nothing else decides.

<sub>[stdlib/Audio.sl:132](../../stdlib/Audio.sl#L132)</sub>

#### Voice *property*

```
static AudioFormat Voice { get; }
```

16 kHz, sixteen bits, mono: enough for speech and a quarter of the
bytes.

<sub>[stdlib/Audio.sl:136](../../stdlib/Audio.sl#L136)</sub>

#### BytesPerFrame *property*

```
nuint BytesPerFrame { get; }
```

How many bytes one frame takes -- one sample on every channel. This is
the unit everything below counts in, because a buffer cut in the middle
of a frame swaps the channels for the rest of the stream.

<sub>[stdlib/Audio.sl:141](../../stdlib/Audio.sl#L141)</sub>

#### BytesPerSecond *property*

```
nuint BytesPerSecond { get; }
```

How many bytes a second of this takes.

<sub>[stdlib/Audio.sl:144](../../stdlib/Audio.sl#L144)</sub>

#### IsSupported *property*

```
bool IsSupported { get; }
```

Whether this is a shape both backends can be asked for at all.

<sub>[stdlib/Audio.sl:147](../../stdlib/Audio.sl#L147)</sub>

#### Equals *method*

```
bool Equals(AudioFormat other)
```

*No documentation.*

<sub>[stdlib/Audio.sl:151](../../stdlib/Audio.sl#L151)</sub>

### AudioPlayer *class*

```
sealed class AudioPlayer
```

A sound device, open, taking samples.

```csharp
var opened = AudioPlayer.Open(AudioFormat.Cd);
if (!opened.Ok) { return; }

var player = opened.Value;
player.Write(first);
player.Write(second);        // returns when the device has taken them
player.DrainBuffer();       // and this when it has played them
player.Close();
```

**The device is closed by the destructor**, so a player that goes out of
scope releases it whether or not `Close` was called. That matters more here
than it does for a file: a sound device left open is one no other program
can have.

**Open it and use it on the same thread.** On Windows the stream is COM,
and the apartment is brought up by `Open` on whichever thread called it.
Calling `Write` from another thread reaches an in-process object and works
in practice; it is outside what this module promises, and a player per
thread is the arrangement to prefer.

<sub>[stdlib/Audio.sl:1226](../../stdlib/Audio.sl#L1226)</sub>

#### Open *method*

```
static Result<AudioPlayer, AudioError> Open(AudioFormat format)
```

A device open for this format.

Fails with `NoBackend` on a machine with no audio library, `Device`
when there is nothing to play through, `Busy` when something else has
the device in exclusive mode, and `Format` when the engine will not
take these numbers -- which is worth telling apart, because the answer
to the last one is to resample rather than to give up.

**Fails with**

- [AudioError.NoBackend](#nobackend-case) — there is no audio library on this machine
- [AudioError.Format](#format-case) — the format is not one this module handles, or not one the engine would take
- [AudioError.Device](#device-case) — there is nothing to play through, or the stream would not open
- [AudioError.Busy](#busy-case) — something else has the device in exclusive mode

<sub>[stdlib/Audio.sl:1301](../../stdlib/Audio.sl#L1301)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Audio.sl:1338](../../stdlib/Audio.sl#L1338)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Audio.sl:1341](../../stdlib/Audio.sl#L1341)</sub>

#### Write *method*

```
Result<bool, AudioError> Write(byte[] samples)
```

Samples queued, blocking until the device has room for them.

Returns when the bytes have been handed over, which is not when they
have been heard -- `DrainBuffer` is what waits for that. A length that is not
a whole number of frames is refused rather than truncated, because
truncating swaps the channels for the rest of the stream.

**Fails with**

- [AudioError.Format](#format-case) — the length is not a whole number of frames
- [AudioError.Device](#device-case) — the device failed or went away while this was writing to it
- [AudioError.Closed](#closed-case) — `Close` has already been called

**See also** &nbsp; [AudioPlayer.DrainBuffer](#drainbuffer-method)

<sub>[stdlib/Audio.sl:1355](../../stdlib/Audio.sl#L1355)</sub>

#### DrainBuffer *method*

```
void DrainBuffer()
```

Waits until everything written has been played.

<sub>[stdlib/Audio.sl:1459](../../stdlib/Audio.sl#L1459)</sub>

#### Stop *method*

```
void Stop()
```

Stops at once, dropping whatever has not been played.

<sub>[stdlib/Audio.sl:1493](../../stdlib/Audio.sl#L1493)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Audio.sl:1520](../../stdlib/Audio.sl#L1520)</sub>

### AudioRecorder *class*

```
sealed class AudioRecorder
```

A sound device, open, producing samples.

```csharp
var opened = AudioRecorder.Open(AudioFormat.Voice);
if (!opened.Ok) { return; }

var recorder = opened.Value;
recorder.Start();

byte[] chunk = new byte[16000u];
while (listening)
{
    nuint read = recorder.Read(chunk);
    // ... whatever is being done with it
}

recorder.Close();
```

**Recording is a thing a user has to be told about.** Windows asks for
microphone permission at the system level and a modern Linux desktop may
route this through a portal; a program that opens an input without saying
so is doing something its user did not ask for, and no library can fix that
from underneath.

<sub>[stdlib/Audio.sl:1580](../../stdlib/Audio.sl#L1580)</sub>

#### Open *method*

```
static Result<AudioRecorder, AudioError> Open(AudioFormat format)
```

A device open for this format. Fails as `AudioPlayer.Open` does.

**Fails with**

- [AudioError.NoBackend](#nobackend-case) — there is no audio library on this machine
- [AudioError.Format](#format-case) — the format is not one this module handles, or not one the engine would take
- [AudioError.Device](#device-case) — there is nothing to record from, or the stream would not open
- [AudioError.Busy](#busy-case) — something else has the device in exclusive mode

**See also** &nbsp; [AudioPlayer.Open](#open-method)

<sub>[stdlib/Audio.sl:1653](../../stdlib/Audio.sl#L1653)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Audio.sl:1690](../../stdlib/Audio.sl#L1690)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Audio.sl:1693](../../stdlib/Audio.sl#L1693)</sub>

#### IsRecording *property*

```
bool IsRecording { get; }
```

Whether it is listening now.

<sub>[stdlib/Audio.sl:1696](../../stdlib/Audio.sl#L1696)</sub>

#### Start *method*

```
Result<bool, AudioError> Start()
```

Starts listening. Sound that arrives before the first `Read` is
buffered, up to about a fifth of a second of it, and dropped after that.

**Fails with**

- [AudioError.Device](#device-case) — the device would not start
- [AudioError.Closed](#closed-case) — `Close` has already been called

**See also** &nbsp; [AudioRecorder.Read](#read-method)

<sub>[stdlib/Audio.sl:1704](../../stdlib/Audio.sl#L1704)</sub>

#### Read *method*

```
nuint Read(byte[] buffer)
```

Up to `buffer.Length` bytes of sound, and how many arrived.

Blocks until there is something. Zero means the recorder was stopped or
closed while this was waiting, which is how a loop in another thread
ends. The count is always a whole number of frames.

<sub>[stdlib/Audio.sl:1741](../../stdlib/Audio.sl#L1741)</sub>

#### Stop *method*

```
void Stop()
```

Stops listening. The device stays open, so `Start` may be called again.

<sub>[stdlib/Audio.sl:1820](../../stdlib/Audio.sl#L1820)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Audio.sl:1848](../../stdlib/Audio.sl#L1848)</sub>

### Tone *class*

```
class Tone
```

Sound made rather than loaded, which is what a test and a beep need.

Not a synthesiser. There are two waveforms here because a program that
wants to know whether its audio works needs a sound to play, and writing
one by hand in every such program is worse than three functions that are
obviously correct.

<sub>[stdlib/Audio.sl:1906](../../stdlib/Audio.sl#L1906)</sub>

#### CreateSine *method*

```
static AudioClip CreateSine(AudioFormat format, double frequency, double seconds, double amplitude)
```

A sine wave: `frequency` hertz for `seconds`, at `amplitude` from 0.0
to 1.0. On every channel.

<sub>[stdlib/Audio.sl:1910](../../stdlib/Audio.sl#L1910)</sub>

#### CreateSquare *method*

```
static AudioClip CreateSquare(AudioFormat format, double frequency, double seconds, double amplitude)
```

A square wave, which is louder than a sine of the same amplitude and is
what a beep traditionally is.

**Parameters**

- `format` — what the samples are to be
- `frequency` — in hertz
- `seconds` — how long it lasts
- `amplitude` — 0.0 to 1.0, where 1.0 is as loud as the format goes

**See also** &nbsp; [Tone.CreateSine](#createsine-method)

<sub>[stdlib/Audio.sl:1934](../../stdlib/Audio.sl#L1934)</sub>

#### CreateRest *method*

```
static AudioClip CreateRest(AudioFormat format, double seconds)
```

Silence, which is the third thing a test needs: a gap between two
tones, and something to compare against.

<sub>[stdlib/Audio.sl:1954](../../stdlib/Audio.sl#L1954)</sub>

### Wav *class*

```
class Wav
```

RIFF/WAVE: the one container everything reads.

**Uncompressed PCM only.** A WAV may carry ADPCM, mu-law, or an MP3 stream
in a WAVE wrapper, and a decoder for any of those belongs somewhere else;
this reports `AudioError.Format` and says which tag it found. It does read
`WAVE_FORMAT_EXTENSIBLE`, because that is what a modern recorder writes
for ordinary PCM and refusing it would refuse half the files on a machine.

<sub>[stdlib/Audio.sl:343](../../stdlib/Audio.sl#L343)</sub>

#### Decode *method*

```
static Result<AudioClip, AudioError> Decode(byte[] bytes)
```

The bytes of a `.wav` file, read.

**Fails with**

- [AudioError.Format](#format-case) — a WAVE that is not uncompressed PCM, or whose rate, channel count or width is not one this module handles
- [AudioError.Malformed](#malformed-case) — not a RIFF/WAVE at all, or one with no `fmt ` chunk before its `data`

**See also** &nbsp; [Wav.Encode](#encode-method)

<sub>[stdlib/Audio.sl:353](../../stdlib/Audio.sl#L353)</sub>

#### Encode *method*

```
static byte[] Encode(AudioClip clip)
```

A clip as the bytes of a `.wav` file: a 44-byte canonical header, the
samples, and the pad byte an odd length is followed by.

**See also** &nbsp; [Wav.Decode](#decode-method)

<sub>[stdlib/Audio.sl:425](../../stdlib/Audio.sl#L425)</sub>

#### FromFile *method*

```
static Result<AudioClip, AudioError> FromFile(String path)
```

A `.wav` on disk, read.

**Fails with**

- [AudioError.Format](#format-case) — a WAVE that is not uncompressed PCM, or one shaped in a way this module does not handle
- [AudioError.Malformed](#malformed-case) — not a RIFF/WAVE at all
- [AudioError.Io](#io-case) — the file could not be read; the `IOError` behind it is not carried

**See also** &nbsp; [Wav.Save](#save-method)

<sub>[stdlib/Audio.sl:463](../../stdlib/Audio.sl#L463)</sub>

#### Save *method*

```
static Result<bool, AudioError> Save(AudioClip clip, String path)
```

A clip written to a `.wav` on disk.

**Fails with**

- [AudioError.Io](#io-case) — the file could not be written; the `IOError` behind it is not carried

**See also** &nbsp; [Wav.FromFile](#fromfile-method)

<sub>[stdlib/Audio.sl:476](../../stdlib/Audio.sl#L476)</sub>

## Functions

### BackendName *function*

```
String BackendName()
```

What is behind it, for a program that reports what it found. `""` when
there is nothing.

<sub>[stdlib/Audio.sl:1091](../../stdlib/Audio.sl#L1091)</sub>

### CanPlay *function*

```
bool CanPlay()
```

Whether anything can play. False on a machine that has the library and no
device, which is what a headless server is.

<sub>[stdlib/Audio.sl:1076](../../stdlib/Audio.sl#L1076)</sub>

### CanRecord *function*

```
bool CanRecord()
```

Whether anything can record.

<sub>[stdlib/Audio.sl:1083](../../stdlib/Audio.sl#L1083)</sub>

### IsAvailable *function*

```
bool IsAvailable()
```

Whether there is an audio library on this machine. Loads it, so the first
call is where the cost is.

**Ask before trying.** A game wants to say "no audio device" at startup
rather than in the middle of a level, and this is how it finds out.

<sub>[stdlib/Audio.sl:1072](../../stdlib/Audio.sl#L1072)</sub>

### PlayClip *function*

```
Result<bool, AudioError> PlayClip(AudioClip clip)
```

A clip played through to the end.

The simple door, and the one most programs want: it opens a device,
writes the samples, waits for them, and closes. A program playing many
sounds should keep an `AudioPlayer` instead, because opening a device takes
tens of milliseconds and this does it every time.

**Fails with**

- [AudioError.NoBackend](#nobackend-case) — there is no audio library on this machine
- [AudioError.Format](#format-case) — the clip's format is not one this module handles, the device would not take it, or its samples are not whole frames
- [AudioError.Device](#device-case) — there is nothing to play through, or the device failed part way
- [AudioError.Busy](#busy-case) — something else has the device and will not share it

**See also** &nbsp; [AudioPlayer](#audioplayer-class)

<sub>[stdlib/Audio.sl:1118](../../stdlib/Audio.sl#L1118)</sub>

### RecordClip *function*

```
Result<AudioClip, AudioError> RecordClip(AudioFormat format, double seconds)
```

`seconds` of sound from the default input.

Blocks for that long. A program that wants to stop early, or to see the
sound as it arrives, wants an `AudioRecorder`.

**Fails with**

- [AudioError.NoBackend](#nobackend-case) — there is no audio library on this machine
- [AudioError.Format](#format-case) — the format is not one this module handles, or not one the device would take
- [AudioError.Device](#device-case) — there is nothing to record from, or the device refused to start
- [AudioError.Busy](#busy-case) — something else has the device and will not share it

**See also** &nbsp; [AudioRecorder](#audiorecorder-class)

<sub>[stdlib/Audio.sl:1150](../../stdlib/Audio.sl#L1150)</sub>

