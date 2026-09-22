# Standard.Media.Audio

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Sound out of the machine, and sound into it.

```csharp
var loaded = Wav.FromFile("chime.wav");
if (loaded.Ok)
    Audio.Play(loaded.Value);

var heard = Audio.Record(AudioFormat.Voice, 3.0);   // three seconds
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
value to print, rather than a link error. `Audio.Available` asks before
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

**Functions** &nbsp; [Available](#available-function) &middot; [BackendName](#backendname-function) &middot; [CanPlay](#canplay-function) &middot; [CanRecord](#canrecord-function) &middot; [Play](#play-function) &middot; [Record](#record-function)

## Types

### AudioClip *class*

```
sealed class AudioClip
```

Samples in memory, and what they are.

The unit `Wav` reads and writes and `Audio.Play` takes. It is bytes rather
than a typed sample array deliberately: the width is in the format, a
conversion on the way in would cost a copy of every sound a program loads,
and the platform wants bytes at the end of it anyway. `SampleAt` and
`SetSample` are there for a program that does want to look.

<sub>[stdlib/Audio.sl:185](../../stdlib/Audio.sl#L185)</sub>

#### Silence *method*

```
static AudioClip Silence(AudioFormat format, nuint frames)
```

Silence, `frames` long.

Zero is silence for sixteen-bit samples and a hard offset for eight-bit
ones, so this fills with 128 there -- which is what silence is in an
unsigned format, and the kind of detail that otherwise shows up as a
click.

<sub>[stdlib/Audio.sl:205](../../stdlib/Audio.sl#L205)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

*No documentation.*

<sub>[stdlib/Audio.sl:217](../../stdlib/Audio.sl#L217)</sub>

#### Samples *property*

```
byte[] Samples { get; }
```

The bytes. Not a copy.

<sub>[stdlib/Audio.sl:220](../../stdlib/Audio.sl#L220)</sub>

#### FrameCount *property*

```
nuint FrameCount { get; }
```

How many frames it holds.

Written out rather than as a ternary: `nuint` is four bytes on a 32-bit
target and eight on a 64-bit one, and the arms of a ternary over an
unsuffixed literal and a `nuint` meet at a type that is neither.

<sub>[stdlib/Audio.sl:227](../../stdlib/Audio.sl#L227)</sub>

#### Duration *property*

```
double Duration { get; }
```

How long it lasts, in seconds.

<sub>[stdlib/Audio.sl:238](../../stdlib/Audio.sl#L238)</sub>

#### SampleAt *method*

```
int SampleAt(nuint frame, nuint channel)
```

One sample, as a number from -32768 to 32767 whatever the width is.

Eight-bit samples are widened and re-centred on the way out, so a
caller reading a clip need not know which it has. A sample wider than
sixteen bits answers its top sixteen. Out of range answers
zero rather than aborting: a program walking a waveform runs off the
end at the end, and that is not a mistake in it.

<sub>[stdlib/Audio.sl:249](../../stdlib/Audio.sl#L249)</sub>

#### SetSample *method*

```
void SetSample(nuint frame, nuint channel, int value)
```

One sample written, taking the same range `SampleAt` answers in and
clamping to it. A sample wider than sixteen bits has its top sixteen
set and the bits below them cleared. Out of range does nothing.

<sub>[stdlib/Audio.sl:273](../../stdlib/Audio.sl#L273)</sub>

### AudioError *enum*

```
enum AudioError
```

Why a sound did not happen.

<sub>[stdlib/Audio.sl:150](../../stdlib/Audio.sl#L150)</sub>

#### NoBackend *case*

```
NoBackend
```

There is no audio library on this machine: no winmm, or no
libasound. `Audio.Available` is how to ask before trying.

<sub>[stdlib/Audio.sl:154](../../stdlib/Audio.sl#L154)</sub>

#### Format *case*

```
Format
```

The format is not one this module handles, or not one the device
would take.

<sub>[stdlib/Audio.sl:158](../../stdlib/Audio.sl#L158)</sub>

#### Device *case*

```
Device
```

There is no sound device, or the one there is refused to open.

<sub>[stdlib/Audio.sl:161](../../stdlib/Audio.sl#L161)</sub>

#### Busy *case*

```
Busy
```

Something else has the device and will not share it.

<sub>[stdlib/Audio.sl:164](../../stdlib/Audio.sl#L164)</sub>

#### Closed *case*

```
Closed
```

The player or recorder has been closed.

<sub>[stdlib/Audio.sl:167](../../stdlib/Audio.sl#L167)</sub>

#### Malformed *case*

```
Malformed
```

The file was not a WAV, or was one this module does not read.

<sub>[stdlib/Audio.sl:170](../../stdlib/Audio.sl#L170)</sub>

#### Io *case*

```
Io
```

The file could not be read or written; `Standard.IO` has the detail.

<sub>[stdlib/Audio.sl:173](../../stdlib/Audio.sl#L173)</sub>

### AudioFormat *struct*

```
struct AudioFormat
```

What the samples are: how fast, how many channels, how wide.

A struct of three numbers, because that is what every platform's format
descriptor holds and what a WAV header carries. Anything a device will not
take is reported by `AudioPlayer.Open` rather than refused here -- what a
sound card accepts is not knowable from the numbers alone.

<sub>[stdlib/Audio.sl:93](../../stdlib/Audio.sl#L93)</sub>

#### SampleRate *field*

```
uint SampleRate
```

Frames per second. 44100 is a CD, 48000 is what most hardware runs at
natively, 8000 is a telephone.

<sub>[stdlib/Audio.sl:97](../../stdlib/Audio.sl#L97)</sub>

#### Channels *field*

```
ushort Channels
```

1 for mono, 2 for stereo. More is not supported: the interleaving is
defined for those two and the channel-order conventions past them are
not the same on both platforms.

<sub>[stdlib/Audio.sl:102](../../stdlib/Audio.sl#L102)</sub>

#### BitsPerSample *field*

```
ushort BitsPerSample
```

8 or 16. Eight-bit samples are *unsigned* and centred on 128, and
sixteen-bit ones are signed and centred on zero -- which is WAV's rule
and both platforms', however strange it reads.

<sub>[stdlib/Audio.sl:107](../../stdlib/Audio.sl#L107)</sub>

#### Of *method*

```
static AudioFormat Of(uint sampleRate, ushort channels, ushort bits)
```

A format written out.

<sub>[stdlib/Audio.sl:110](../../stdlib/Audio.sl#L110)</sub>

#### Cd *property*

```
static AudioFormat Cd { get; }
```

44.1 kHz, sixteen bits, stereo: what a CD is and what a WAV file
usually holds.

<sub>[stdlib/Audio.sl:121](../../stdlib/Audio.sl#L121)</sub>

#### Studio *property*

```
static AudioFormat Studio { get; }
```

48 kHz, sixteen bits, stereo: what most sound hardware runs at without
resampling, and what to prefer when nothing else decides.

<sub>[stdlib/Audio.sl:125](../../stdlib/Audio.sl#L125)</sub>

#### Voice *property*

```
static AudioFormat Voice { get; }
```

16 kHz, sixteen bits, mono: enough for speech and a quarter of the
bytes.

<sub>[stdlib/Audio.sl:129](../../stdlib/Audio.sl#L129)</sub>

#### BytesPerFrame *property*

```
nuint BytesPerFrame { get; }
```

How many bytes one frame takes -- one sample on every channel. This is
the unit everything below counts in, because a buffer cut in the middle
of a frame swaps the channels for the rest of the stream.

<sub>[stdlib/Audio.sl:134](../../stdlib/Audio.sl#L134)</sub>

#### BytesPerSecond *property*

```
nuint BytesPerSecond { get; }
```

How many bytes a second of this takes.

<sub>[stdlib/Audio.sl:137](../../stdlib/Audio.sl#L137)</sub>

#### IsSupported *property*

```
bool IsSupported { get; }
```

Whether this is a shape both backends can be asked for at all.

<sub>[stdlib/Audio.sl:140](../../stdlib/Audio.sl#L140)</sub>

#### Equals *method*

```
bool Equals(AudioFormat other)
```

*No documentation.*

<sub>[stdlib/Audio.sl:144](../../stdlib/Audio.sl#L144)</sub>

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
player.Drain();              // and this when it has played them
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

<sub>[stdlib/Audio.sl:1170](../../stdlib/Audio.sl#L1170)</sub>

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

<sub>[stdlib/Audio.sl:1237](../../stdlib/Audio.sl#L1237)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Audio.sl:1274](../../stdlib/Audio.sl#L1274)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Audio.sl:1277](../../stdlib/Audio.sl#L1277)</sub>

#### Write *method*

```
Result<bool, AudioError> Write(byte[] samples)
```

Samples queued, blocking until the device has room for them.

Returns when the bytes have been handed over, which is not when they
have been heard -- `Drain` is what waits for that. A length that is not
a whole number of frames is refused rather than truncated, because
truncating swaps the channels for the rest of the stream.

<sub>[stdlib/Audio.sl:1285](../../stdlib/Audio.sl#L1285)</sub>

#### Drain *method*

```
void Drain()
```

Waits until everything written has been played.

<sub>[stdlib/Audio.sl:1389](../../stdlib/Audio.sl#L1389)</sub>

#### Stop *method*

```
void Stop()
```

Stops at once, dropping whatever has not been played.

<sub>[stdlib/Audio.sl:1423](../../stdlib/Audio.sl#L1423)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Audio.sl:1450](../../stdlib/Audio.sl#L1450)</sub>

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

<sub>[stdlib/Audio.sl:1510](../../stdlib/Audio.sl#L1510)</sub>

#### Open *method*

```
static Result<AudioRecorder, AudioError> Open(AudioFormat format)
```

A device open for this format. Fails as `AudioPlayer.Open` does.

<sub>[stdlib/Audio.sl:1574](../../stdlib/Audio.sl#L1574)</sub>

#### Format *property*

```
AudioFormat Format { get; }
```

The format this was opened for.

<sub>[stdlib/Audio.sl:1611](../../stdlib/Audio.sl#L1611)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the device is still open.

<sub>[stdlib/Audio.sl:1614](../../stdlib/Audio.sl#L1614)</sub>

#### IsRecording *property*

```
bool IsRecording { get; }
```

Whether it is listening now.

<sub>[stdlib/Audio.sl:1617](../../stdlib/Audio.sl#L1617)</sub>

#### Start *method*

```
Result<bool, AudioError> Start()
```

Starts listening. Sound that arrives before the first `Read` is
buffered, up to about a fifth of a second of it, and dropped after that.

<sub>[stdlib/Audio.sl:1621](../../stdlib/Audio.sl#L1621)</sub>

#### Read *method*

```
nuint Read(byte[] buffer)
```

Up to `buffer.Length` bytes of sound, and how many arrived.

Blocks until there is something. Zero means the recorder was stopped or
closed while this was waiting, which is how a loop in another thread
ends. The count is always a whole number of frames.

<sub>[stdlib/Audio.sl:1658](../../stdlib/Audio.sl#L1658)</sub>

#### Stop *method*

```
void Stop()
```

Stops listening. The device stays open, so `Start` may be called again.

<sub>[stdlib/Audio.sl:1737](../../stdlib/Audio.sl#L1737)</sub>

#### Close *method*

```
void Close()
```

Releases the device. Idempotent, and the destructor calls it.

<sub>[stdlib/Audio.sl:1765](../../stdlib/Audio.sl#L1765)</sub>

### Tone *class*

```
class Tone
```

Sound made rather than loaded, which is what a test and a beep need.

Not a synthesiser. There are two waveforms here because a program that
wants to know whether its audio works needs a sound to play, and writing
one by hand in every such program is worse than three functions that are
obviously correct.

<sub>[stdlib/Audio.sl:1823](../../stdlib/Audio.sl#L1823)</sub>

#### Sine *method*

```
static AudioClip Sine(AudioFormat format, double frequency, double seconds, double amplitude)
```

A sine wave: `frequency` hertz for `seconds`, at `amplitude` from 0.0
to 1.0. On every channel.

<sub>[stdlib/Audio.sl:1827](../../stdlib/Audio.sl#L1827)</sub>

#### Square *method*

```
static AudioClip Square(AudioFormat format, double frequency, double seconds, double amplitude)
```

A square wave, which is louder than a sine of the same amplitude and is
what a beep traditionally is.

<sub>[stdlib/Audio.sl:1845](../../stdlib/Audio.sl#L1845)</sub>

#### Rest *method*

```
static AudioClip Rest(AudioFormat format, double seconds)
```

Silence, which is the third thing a test needs: a gap between two
tones, and something to compare against.

<sub>[stdlib/Audio.sl:1865](../../stdlib/Audio.sl#L1865)</sub>

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

<sub>[stdlib/Audio.sl:327](../../stdlib/Audio.sl#L327)</sub>

#### Decode *method*

```
static Result<AudioClip, AudioError> Decode(byte[] bytes)
```

The bytes of a `.wav` file, read.

<sub>[stdlib/Audio.sl:330](../../stdlib/Audio.sl#L330)</sub>

#### Encode *method*

```
static byte[] Encode(AudioClip clip)
```

A clip as the bytes of a `.wav` file: a 44-byte canonical header, the
samples, and the pad byte an odd length is followed by.

<sub>[stdlib/Audio.sl:400](../../stdlib/Audio.sl#L400)</sub>

#### FromFile *method*

```
static Result<AudioClip, AudioError> FromFile(String path)
```

A `.wav` on disk, read.

<sub>[stdlib/Audio.sl:430](../../stdlib/Audio.sl#L430)</sub>

#### Save *method*

```
static Result<bool, AudioError> Save(AudioClip clip, String path)
```

A clip written to a `.wav` on disk.

<sub>[stdlib/Audio.sl:439](../../stdlib/Audio.sl#L439)</sub>

## Functions

### Available *function*

```
bool Available()
```

Whether there is an audio library on this machine. Loads it, so the first
call is where the cost is.

**Ask before trying.** A game wants to say "no audio device" at startup
rather than in the middle of a level, and this is how it finds out.

<sub>[stdlib/Audio.sl:1035](../../stdlib/Audio.sl#L1035)</sub>

### BackendName *function*

```
String BackendName()
```

What is behind it, for a program that reports what it found. `""` when
there is nothing.

<sub>[stdlib/Audio.sl:1054](../../stdlib/Audio.sl#L1054)</sub>

### CanPlay *function*

```
bool CanPlay()
```

Whether anything can play. False on a machine that has the library and no
device, which is what a headless server is.

<sub>[stdlib/Audio.sl:1039](../../stdlib/Audio.sl#L1039)</sub>

### CanRecord *function*

```
bool CanRecord()
```

Whether anything can record.

<sub>[stdlib/Audio.sl:1046](../../stdlib/Audio.sl#L1046)</sub>

### Play *function*

```
Result<bool, AudioError> Play(AudioClip clip)
```

A clip played through to the end.

The simple door, and the one most programs want: it opens a device,
writes the samples, waits for them, and closes. A program playing many
sounds should keep an `AudioPlayer` instead, because opening a device takes
tens of milliseconds and this does it every time.

<sub>[stdlib/Audio.sl:1071](../../stdlib/Audio.sl#L1071)</sub>

### Record *function*

```
Result<AudioClip, AudioError> Record(AudioFormat format, double seconds)
```

`seconds` of sound from the default input.

Blocks for that long. A program that wants to stop early, or to see the
sound as it arrives, wants an `AudioRecorder`.

<sub>[stdlib/Audio.sl:1094](../../stdlib/Audio.sl#L1094)</sub>

