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

<sub>[stdlib/Media/Audio/AudioClip.sl:38](../../stdlib/Media/Audio/AudioClip.sl#L38)</sub>

#### CreateSilence *method*

```
static AudioClip CreateSilence(AudioFormat format, nuint frames)
```

Silence, `frames` long.

Zero is silence for sixteen-bit samples and a hard offset for eight-bit
ones, so this fills with 128 there -- which is what silence is in an
unsigned format, and the kind of detail that otherwise shows up as a
click.

<sub>[stdlib/Media/Audio/AudioClip.sl:58](../../stdlib/Media/Audio/AudioClip.sl#L58)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

*No documentation.*

<sub>[stdlib/Media/Audio/AudioClip.sl:70](../../stdlib/Media/Audio/AudioClip.sl#L70)</sub>

#### Samples *property*

```
byte[] Samples { get; }
```

The bytes. Not a copy.

<sub>[stdlib/Media/Audio/AudioClip.sl:73](../../stdlib/Media/Audio/AudioClip.sl#L73)</sub>

#### FrameCount *property*

```
nuint FrameCount { get; }
```

How many frames it holds.

Written out rather than as a ternary: `nuint` is four bytes on a 32-bit
target and eight on a 64-bit one, and the arms of a ternary over an
unsuffixed literal and a `nuint` meet at a type that is neither.

<sub>[stdlib/Media/Audio/AudioClip.sl:80](../../stdlib/Media/Audio/AudioClip.sl#L80)</sub>

#### Duration *property*

```
double Duration { get; }
```

How long it lasts, in seconds.

<sub>[stdlib/Media/Audio/AudioClip.sl:91](../../stdlib/Media/Audio/AudioClip.sl#L91)</sub>

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

<sub>[stdlib/Media/Audio/AudioClip.sl:106](../../stdlib/Media/Audio/AudioClip.sl#L106)</sub>

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

<sub>[stdlib/Media/Audio/AudioClip.sl:135](../../stdlib/Media/Audio/AudioClip.sl#L135)</sub>

### AudioError *enum*

```
enum AudioError
```

Why a sound did not happen.

<sub>[stdlib/Media/Audio/AudioError.sl:30](../../stdlib/Media/Audio/AudioError.sl#L30)</sub>

#### NoBackend *case*

```
NoBackend
```

There is no audio library on this machine: no winmm, or no
libasound. `Audio.IsAvailable` is how to ask before trying.

<sub>[stdlib/Media/Audio/AudioError.sl:34](../../stdlib/Media/Audio/AudioError.sl#L34)</sub>

#### Format *case*

```
Format
```

The format is not one this module handles, or not one the device
would take.

<sub>[stdlib/Media/Audio/AudioError.sl:38](../../stdlib/Media/Audio/AudioError.sl#L38)</sub>

#### Device *case*

```
Device
```

There is no sound device, or the one there is refused to open.

<sub>[stdlib/Media/Audio/AudioError.sl:41](../../stdlib/Media/Audio/AudioError.sl#L41)</sub>

#### Busy *case*

```
Busy
```

Something else has the device and will not share it.

<sub>[stdlib/Media/Audio/AudioError.sl:44](../../stdlib/Media/Audio/AudioError.sl#L44)</sub>

#### Closed *case*

```
Closed
```

The player or recorder has been closed.

<sub>[stdlib/Media/Audio/AudioError.sl:47](../../stdlib/Media/Audio/AudioError.sl#L47)</sub>

#### Malformed *case*

```
Malformed
```

The file was not a WAV, or was one this module does not read.

<sub>[stdlib/Media/Audio/AudioError.sl:50](../../stdlib/Media/Audio/AudioError.sl#L50)</sub>

#### IO *case*

```
IO
```

The file could not be read or written; `Standard.IO` has the detail.

<sub>[stdlib/Media/Audio/AudioError.sl:53](../../stdlib/Media/Audio/AudioError.sl#L53)</sub>

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

<sub>[stdlib/Media/Audio/AudioFormat.sl:39](../../stdlib/Media/Audio/AudioFormat.sl#L39)</sub>

#### SampleRate *field*

```
uint SampleRate
```

Frames per second. 44100 is a CD, 48000 is what most hardware runs at
natively, 8000 is a telephone.

<sub>[stdlib/Media/Audio/AudioFormat.sl:43](../../stdlib/Media/Audio/AudioFormat.sl#L43)</sub>

#### Channels *field*

```
ushort Channels
```

1 for mono, 2 for stereo. More is not supported: the interleaving is
defined for those two and the channel-order conventions past them are
not the same on both platforms.

<sub>[stdlib/Media/Audio/AudioFormat.sl:48](../../stdlib/Media/Audio/AudioFormat.sl#L48)</sub>

#### BitsPerSample *field*

```
ushort BitsPerSample
```

8 or 16. Eight-bit samples are *unsigned* and centred on 128, and
sixteen-bit ones are signed and centred on zero -- which is WAV's rule
and both platforms', however strange it reads.

<sub>[stdlib/Media/Audio/AudioFormat.sl:53](../../stdlib/Media/Audio/AudioFormat.sl#L53)</sub>

#### Create *method*

```
static AudioFormat Create(uint sampleRate, ushort channels, ushort bits)
```

A format written out.

**Parameters**

- `sampleRate` — frames per second: 44100 for a CD, 8000 for a telephone
- `channels` — 1 for mono, 2 for stereo, and nothing else
- `bits` — 8 or 16, the width of one sample

<sub>[stdlib/Media/Audio/AudioFormat.sl:61](../../stdlib/Media/Audio/AudioFormat.sl#L61)</sub>

#### Cd *property*

```
static AudioFormat Cd { get; }
```

44.1 kHz, sixteen bits, stereo: what a CD is and what a WAV file
usually holds.

<sub>[stdlib/Media/Audio/AudioFormat.sl:72](../../stdlib/Media/Audio/AudioFormat.sl#L72)</sub>

#### Studio *property*

```
static AudioFormat Studio { get; }
```

48 kHz, sixteen bits, stereo: what most sound hardware runs at without
resampling, and what to prefer when nothing else decides.

<sub>[stdlib/Media/Audio/AudioFormat.sl:76](../../stdlib/Media/Audio/AudioFormat.sl#L76)</sub>

#### Voice *property*

```
static AudioFormat Voice { get; }
```

16 kHz, sixteen bits, mono: enough for speech and a quarter of the
bytes.

<sub>[stdlib/Media/Audio/AudioFormat.sl:80](../../stdlib/Media/Audio/AudioFormat.sl#L80)</sub>

#### BytesPerFrame *property*

```
nuint BytesPerFrame { get; }
```

How many bytes one frame takes -- one sample on every channel. This is
the unit everything below counts in, because a buffer cut in the middle
of a frame swaps the channels for the rest of the stream.

<sub>[stdlib/Media/Audio/AudioFormat.sl:85](../../stdlib/Media/Audio/AudioFormat.sl#L85)</sub>

#### BytesPerSecond *property*

```
nuint BytesPerSecond { get; }
```

How many bytes a second of this takes.

<sub>[stdlib/Media/Audio/AudioFormat.sl:88](../../stdlib/Media/Audio/AudioFormat.sl#L88)</sub>

#### IsSupported *property*

```
bool IsSupported { get; }
```

Whether this is a shape both backends can be asked for at all.

<sub>[stdlib/Media/Audio/AudioFormat.sl:91](../../stdlib/Media/Audio/AudioFormat.sl#L91)</sub>

#### Equals *method*

```
bool Equals(AudioFormat other)
```

*No documentation.*

<sub>[stdlib/Media/Audio/AudioFormat.sl:95](../../stdlib/Media/Audio/AudioFormat.sl#L95)</sub>

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

<sub>[stdlib/Media/Audio/AudioPlayer.sl:54](../../stdlib/Media/Audio/AudioPlayer.sl#L54)</sub>

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

<sub>[stdlib/Media/Audio/AudioPlayer.sl:129](../../stdlib/Media/Audio/AudioPlayer.sl#L129)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Media/Audio/AudioPlayer.sl:166](../../stdlib/Media/Audio/AudioPlayer.sl#L166)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Media/Audio/AudioPlayer.sl:169](../../stdlib/Media/Audio/AudioPlayer.sl#L169)</sub>

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

<sub>[stdlib/Media/Audio/AudioPlayer.sl:183](../../stdlib/Media/Audio/AudioPlayer.sl#L183)</sub>

#### DrainBuffer *method*

```
void DrainBuffer()
```

Waits until everything written has been played.

<sub>[stdlib/Media/Audio/AudioPlayer.sl:287](../../stdlib/Media/Audio/AudioPlayer.sl#L287)</sub>

#### Stop *method*

```
void Stop()
```

Stops at once, dropping whatever has not been played.

<sub>[stdlib/Media/Audio/AudioPlayer.sl:321](../../stdlib/Media/Audio/AudioPlayer.sl#L321)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Media/Audio/AudioPlayer.sl:348](../../stdlib/Media/Audio/AudioPlayer.sl#L348)</sub>

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

<sub>[stdlib/Media/Audio/AudioRecorder.sl:55](../../stdlib/Media/Audio/AudioRecorder.sl#L55)</sub>

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

<sub>[stdlib/Media/Audio/AudioRecorder.sl:128](../../stdlib/Media/Audio/AudioRecorder.sl#L128)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:165](../../stdlib/Media/Audio/AudioRecorder.sl#L165)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:168](../../stdlib/Media/Audio/AudioRecorder.sl#L168)</sub>

#### IsRecording *property*

```
bool IsRecording { get; }
```

Whether it is listening now.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:171](../../stdlib/Media/Audio/AudioRecorder.sl#L171)</sub>

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

<sub>[stdlib/Media/Audio/AudioRecorder.sl:179](../../stdlib/Media/Audio/AudioRecorder.sl#L179)</sub>

#### Read *method*

```
nuint Read(byte[] buffer)
```

Up to `buffer.Length` bytes of sound, and how many arrived.

Blocks until there is something. Zero means the recorder was stopped or
closed while this was waiting, which is how a loop in another thread
ends. The count is always a whole number of frames.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:216](../../stdlib/Media/Audio/AudioRecorder.sl#L216)</sub>

#### Stop *method*

```
void Stop()
```

Stops listening. The device stays open, so `Start` may be called again.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:295](../../stdlib/Media/Audio/AudioRecorder.sl#L295)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Media/Audio/AudioRecorder.sl:323](../../stdlib/Media/Audio/AudioRecorder.sl#L323)</sub>

### Tone *class*

```
class Tone
```

Sound made rather than loaded, which is what a test and a beep need.

Not a synthesiser. There are two waveforms here because a program that
wants to know whether its audio works needs a sound to play, and writing
one by hand in every such program is worse than three functions that are
obviously correct.

<sub>[stdlib/Media/Audio/Tone.sl:37](../../stdlib/Media/Audio/Tone.sl#L37)</sub>

#### CreateSine *method*

```
static AudioClip CreateSine(AudioFormat format, double frequency, double seconds, double amplitude)
```

A sine wave: `frequency` hertz for `seconds`, at `amplitude` from 0.0
to 1.0. On every channel.

<sub>[stdlib/Media/Audio/Tone.sl:41](../../stdlib/Media/Audio/Tone.sl#L41)</sub>

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

<sub>[stdlib/Media/Audio/Tone.sl:65](../../stdlib/Media/Audio/Tone.sl#L65)</sub>

#### CreateRest *method*

```
static AudioClip CreateRest(AudioFormat format, double seconds)
```

Silence, which is the third thing a test needs: a gap between two
tones, and something to compare against.

<sub>[stdlib/Media/Audio/Tone.sl:85](../../stdlib/Media/Audio/Tone.sl#L85)</sub>

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

<sub>[stdlib/Media/Audio/Wav.sl:38](../../stdlib/Media/Audio/Wav.sl#L38)</sub>

#### Decode *method*

```
static Result<AudioClip, AudioError> Decode(byte[] bytes)
```

The bytes of a `.wav` file, read.

**Fails with**

- [AudioError.Format](#format-case) — a WAVE that is not uncompressed PCM, or whose rate, channel count or width is not one this module handles
- [AudioError.Malformed](#malformed-case) — not a RIFF/WAVE at all, or one with no `fmt ` chunk before its `data`

**See also** &nbsp; [Wav.Encode](#encode-method)

<sub>[stdlib/Media/Audio/Wav.sl:48](../../stdlib/Media/Audio/Wav.sl#L48)</sub>

#### Encode *method*

```
static byte[] Encode(AudioClip clip)
```

A clip as the bytes of a `.wav` file: a 44-byte canonical header, the
samples, and the pad byte an odd length is followed by.

**See also** &nbsp; [Wav.Decode](#decode-method)

<sub>[stdlib/Media/Audio/Wav.sl:120](../../stdlib/Media/Audio/Wav.sl#L120)</sub>

#### FromFile *method*

```
static Result<AudioClip, AudioError> FromFile(String path)
```

A `.wav` on disk, read.

**Fails with**

- [AudioError.Format](#format-case) — a WAVE that is not uncompressed PCM, or one shaped in a way this module does not handle
- [AudioError.Malformed](#malformed-case) — not a RIFF/WAVE at all
- [AudioError.IO](#io-case) — the file could not be read; the `IOError` behind it is not carried

**See also** &nbsp; [Wav.Save](#save-method)

<sub>[stdlib/Media/Audio/Wav.sl:158](../../stdlib/Media/Audio/Wav.sl#L158)</sub>

#### Save *method*

```
static Result<bool, AudioError> Save(AudioClip clip, String path)
```

A clip written to a `.wav` on disk.

**Fails with**

- [AudioError.IO](#io-case) — the file could not be written; the `IOError` behind it is not carried

**See also** &nbsp; [Wav.FromFile](#fromfile-method)

<sub>[stdlib/Media/Audio/Wav.sl:171](../../stdlib/Media/Audio/Wav.sl#L171)</sub>

## Functions

### BackendName *function*

```
String BackendName()
```

What is behind it, for a program that reports what it found. `""` when
there is nothing.

<sub>[stdlib/Media/Audio/Audio.sl:650](../../stdlib/Media/Audio/Audio.sl#L650)</sub>

### CanPlay *function*

```
bool CanPlay()
```

Whether anything can play. False on a machine that has the library and no
device, which is what a headless server is.

<sub>[stdlib/Media/Audio/Audio.sl:635](../../stdlib/Media/Audio/Audio.sl#L635)</sub>

### CanRecord *function*

```
bool CanRecord()
```

Whether anything can record.

<sub>[stdlib/Media/Audio/Audio.sl:642](../../stdlib/Media/Audio/Audio.sl#L642)</sub>

### IsAvailable *function*

```
bool IsAvailable()
```

Whether there is an audio library on this machine. Loads it, so the first
call is where the cost is.

**Ask before trying.** A game wants to say "no audio device" at startup
rather than in the middle of a level, and this is how it finds out.

<sub>[stdlib/Media/Audio/Audio.sl:631](../../stdlib/Media/Audio/Audio.sl#L631)</sub>

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

<sub>[stdlib/Media/Audio/Audio.sl:677](../../stdlib/Media/Audio/Audio.sl#L677)</sub>

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

<sub>[stdlib/Media/Audio/Audio.sl:709](../../stdlib/Media/Audio/Audio.sl#L709)</sub>

