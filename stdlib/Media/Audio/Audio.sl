// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// Sound out of the machine, and sound into it.
///
/// ```csharp
/// var loaded = Wav.FromFile("chime.wav");
/// if (loaded.Ok)
///     Audio.PlayClip(loaded.Value);
///
/// var heard = Audio.RecordClip(AudioFormat.Voice, 3.0);   // three seconds
/// if (heard.Ok)
///     Wav.Save(heard.Value, "heard.wav");
/// ```
///
/// **Interleaved PCM, and nothing else.** 8-bit unsigned or 16-bit signed,
/// one channel or two, at whatever rate the device will take. That is what
/// every platform agrees about and what a WAV file holds; a decoder for a
/// compressed format is a separate piece of work and saying so is better than
/// half of it.
///
/// **WASAPI on Windows, AudioToolbox on macOS and ALSA elsewhere.** WASAPI
/// and ALSA are reached by name the first time a device is opened, which is
/// what lets this live in the standard library: a program that makes no sound
/// pays nothing, and a machine with no ALSA answers `AudioError.NoBackend` --
/// a value to print, rather than a link error. Every Mac has AudioToolbox, so
/// there it is linked, into the programs that compile this module.
/// `Audio.IsAvailable` asks before anything is tried.
///
/// **WASAPI rather than waveOut.** `winmm`'s `waveOut` is four calls and is
/// still present on Windows 11, which makes it tempting and makes it the wrong
/// answer: since Vista it has been an emulation on top of WASAPI, so it adds a
/// buffer of latency to reach the same mixer, and it does not exist inside an
/// app container. What WASAPI costs is an apartment and six COM interfaces;
/// what it buys is the actual system interface, the engine's own rate and
/// channel conversion, and a device that can be asked what it is. A program
/// that wants a game engine's mixing and 3D positioning wants `Win32.XAudio2`,
/// which is bound separately.
///
/// **This blocks.** `AudioPlayer.Write` returns when the device has taken the
/// bytes, which is after it has played what was queued ahead of them; there is
/// no callback and no mixing. A program with a user interface should do its
/// audio on a thread of its own -- `Standard.Threading` is right there -- and
/// a program that wants several sounds at once wants a mixer, which this is
/// not.
module Standard.Media.Audio;

import Standard.Text;
import Standard.Collections;
import Standard.File;
import Standard.IO;

extern "C"
{
    void* memcpy(byte* destination, byte* source, nuint count);
    void sl_thread_sleep(ulong milliseconds);

    // Declared here rather than imported: the sine is the only thing this
    // module wants from `Standard.Math`, and one C declaration is cheaper than
    // a dependency.
    double sin(double x);
}

// ============================================================= the backends

// How long a device's buffer is, and how long a poll waits.
//
// A fifth of a second of slack is enough that a program doing something else
// between writes does not make the device run dry, and little enough that
// `Stop` is not followed by a second of sound nobody wants. The poll is five
// milliseconds because both platforms move in chunks of about ten.
const uint BufferMilliseconds = 200u;
const ulong PollMilliseconds = 5u;

#if WINDOWS

// ------------------------------------------------------------------ values

/// `WAVE_FORMAT_PCM`.
const ushort FormatPcm = 1u;

/// `eRender`: sound leaving the machine.
const int FlowRender = 0;

/// `eCapture`: sound arriving.
const int FlowCapture = 1;

/// `eConsole`: the device a user would call "the" one -- which is what a
/// program with nothing else to go on should ask for. `eCommunications` is the
/// headset a call would use and is a different question.
const int RoleConsole = 0;

/// `AUDCLNT_SHAREMODE_SHARED`: the mixer is in the way, other programs can
/// play at the same time, and the format is converted for us. Exclusive mode
/// takes the device away from everything else and is not what a library should
/// do on its own.
const int ShareModeShared = 0;

/// `AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM` and
/// `AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY`, together.
///
/// **This pair is what lets a caller name its own format.** Shared mode
/// otherwise takes only the engine's mix format -- 48 kHz float, usually --
/// and a caller with a 22 kHz mono clip would have to resample it. With these
/// the engine inserts a channel matrixer and a rate converter, which is the
/// same work done once, correctly, by the part of the system that owns the
/// mixer. Windows 7 and later.
const uint AutoConvert = 0x88000000u;

/// `CLSCTX_ALL`.
const uint AllContexts = 0x17u;

/// `COINIT_MULTITHREADED`.
const uint MultiThreaded = 0x0u;

/// `RPC_E_CHANGED_MODE`: this thread's apartment is already up and is a
/// different kind. COM is usable; what must not happen is a `CoUninitialize`
/// balancing a call that did not take.
const int ChangedMode = 0x80010106;

/// `AUDCLNT_E_DEVICE_IN_USE`.
const int DeviceInUse = 0x8889000A;

/// `AUDCLNT_E_UNSUPPORTED_FORMAT`.
const int UnsupportedFormat = 0x88890008;

/// `AUDCLNT_E_DEVICE_INVALIDATED`: the device was unplugged, or its driver was
/// restarted, while this stream was open.
const int DeviceInvalidated = 0x88890004;

/// `AUDCLNT_BUFFERFLAGS_SILENT`: the packet's bytes are not meaningful and
/// should be treated as silence rather than copied.
const uint BufferSilent = 0x2u;

/// One REFERENCE_TIME is 100 nanoseconds, so a millisecond is ten thousand.
const long TicksPerMillisecond = 10000;

delegate __stdcall int CoInitializeExFn(byte* reserved, uint model);
delegate __stdcall void CoUninitializeFn();
delegate __stdcall int CoCreateInstanceFn(Guid* classId, byte* outer, uint context,
                                          Guid* interfaceId, byte** result);

extern "C" __stdcall
{
    void* LoadLibraryA(byte* name);
    void* GetProcAddress(void* library, byte* name);
}

/// A format filled in for WASAPI.
WaveFormatEx CreateWaveFormat(AudioFormat format)
{
    WaveFormatEx described;
    described.FormatTag = FormatPcm;
    described.Channels = format.Channels;
    described.SamplesPerSecond = format.SampleRate;
    described.AverageBytesPerSecond = (uint)format.BytesPerSecond;
    described.BlockAlign = (ushort)format.BytesPerFrame;
    described.BitsPerSample = format.BitsPerSample;
    described.ExtraSize = (ushort)0;
    return described;
}

/// What an `HRESULT` from WASAPI means here.
AudioError ToAudioError(int code)
{
    if (code == DeviceInUse)
        return AudioError.Busy;
    if (code == UnsupportedFormat)
        return AudioError.Format;
    return AudioError.Device;
}

/// A stream open on an endpoint, in whichever direction.
///
/// The two halves of the module differ only in which flow they ask for and
/// which service they take out, so opening one is written once.
Result<IAudioClient, AudioError> OpenStream(Backend found, AudioFormat format, int flow)
{
    var endpoint = found.GetDefaultEndpoint(flow);
    if (endpoint == null)
        return Fail(AudioError.Device);

    byte* raw = null;
    int code = ((IMMDevice)endpoint).Activate(iidof(IAudioClient), AllContexts, null, &raw);
    if (code < 0 || raw == null)
        return Fail(ToAudioError(code));

    var client = (IAudioClient)raw;
    var described = CreateWaveFormat(format);

    code = client.Initialize(ShareModeShared, AutoConvert,
                             (long)BufferMilliseconds * TicksPerMillisecond, 0,
                             &described, null);
    if (code < 0)
        return Fail(ToAudioError(code));

    return Ok(client);
}

#elif MACOS

// Every Mac has AudioToolbox, so it is linked rather than loaded by name; only
// a program that compiles this module gets it.
#pragma comment(framework, "AudioToolbox")
#pragma comment(framework, "CoreAudio")

/// `kAudioFormatLinearPCM`, `'lpcm'`.
const uint FormatLinearPcm = 0x6C70636Du;

/// `kLinearPCMFormatFlagIsSignedInteger` and `kLinearPCMFormatFlagIsPacked`.
const uint FlagSignedInteger = 4u;
const uint FlagPacked = 8u;

/// `kAudioObjectSystemObject`, and `kAudioObjectUnknown`: no device.
const uint SystemObject = 1u;
const uint UnknownObject = 0u;

/// `kAudioHardwarePropertyDefaultOutputDevice` and `...DefaultInputDevice`,
/// `'dOut'` and `'dIn '`; `kAudioObjectPropertyScopeGlobal`, `'glob'`.
const uint DefaultOutputDevice = 0x644F7574u;
const uint DefaultInputDevice = 0x64496E20u;
const uint ScopeGlobal = 0x676C6F62u;

/// Buffers in flight: one playing, one queued behind it, one being filled.
const int QueueBuffers = 3;

/// The code the player and the recorder take for a device someone else has.
/// AudioQueue shares the device, so nothing here returns it.
const int Busy = -16;

delegate void QueueOutputFn(void* user, void* queue, QueueBuffer* buffer);
delegate void QueueInputFn(void* user, void* queue, QueueBuffer* buffer, void* start,
                           uint packets, void* descriptions);

extern "C"
{
    int AudioQueueNewOutput(StreamDescription* format, QueueOutputFn callback, void* user,
                            void* runLoop, void* mode, uint flags, void** queue);
    int AudioQueueNewInput(StreamDescription* format, QueueInputFn callback, void* user,
                           void* runLoop, void* mode, uint flags, void** queue);
    int AudioQueueAllocateBuffer(void* queue, uint capacity, QueueBuffer** buffer);
    int AudioQueueEnqueueBuffer(void* queue, QueueBuffer* buffer, uint descriptions, void* list);
    int AudioQueueStart(void* queue, void* when);
    int AudioQueueStop(void* queue, byte immediate);
    int AudioQueueDispose(void* queue, byte immediate);
    int AudioObjectGetPropertyData(uint id, PropertyAddress* address, uint qualifierSize,
                                   void* qualifier, uint* size, void* data);

    int sl_atomic_load32(int* cell);
    void sl_atomic_store32(int* cell, int value);
    byte* calloc(nuint count, nuint size);
    void free(byte* block);
}

/// A played buffer, handed back. Called on AudioQueue's thread.
void MarkBufferPlayed(void* user, void* queue, QueueBuffer* buffer) =>
    sl_atomic_store32((int*)(*buffer).UserData, 1);

/// A recorded buffer, handed back full. Called on AudioQueue's thread.
void MarkBufferRecorded(void* user, void* queue, QueueBuffer* buffer, void* start,
                        uint packets, void* descriptions) =>
    sl_atomic_store32((int*)(*buffer).UserData, 1);

/// Whether the system has a default device of this kind. A Mac mini has no
/// input until one is plugged in.
bool HasDefaultDevice(uint selector)
{
    PropertyAddress address;
    address.Selector = selector;
    address.Scope = ScopeGlobal;
    address.Element = 0u;
    uint device = UnknownObject;
    uint size = (uint)sizeof(uint);
    int status = AudioObjectGetPropertyData(SystemObject, &address, 0u, null, &size, (void*)&device);
    return status == 0 && device != UnknownObject;
}

QueueBuffer* QueueBufferAt(QueueState* state, int index) => index switch
{
    0 => (*state).First,
    1 => (*state).Second,
    _ => (*state).Third,
};

int* QueueFlagAt(QueueState* state, int index) => index switch
{
    0 => &(*state).FirstBack,
    1 => &(*state).SecondBack,
    _ => &(*state).ThirdBack,
};

#else

/// `SND_PCM_STREAM_PLAYBACK`.
const int StreamPlayback = 0;

/// `SND_PCM_STREAM_CAPTURE`.
const int StreamCapture = 1;

/// `SND_PCM_FORMAT_U8`.
const int FormatUnsigned8 = 1;

/// `SND_PCM_FORMAT_S16_LE`.
const int FormatSigned16 = 2;

/// `SND_PCM_ACCESS_RW_INTERLEAVED`: read and write whole frames, channels side
/// by side, which is the layout `AudioClip` already holds.
const int AccessInterleaved = 3;

/// `RTLD_LAZY | RTLD_LOCAL`.
const int RtldLazyLocal = 0x00001;

/// `-EBUSY`: something else has the device.
const int Busy = -16;

delegate int PcmOpenFn(void** pcm, byte* name, int stream, int mode);
delegate int PcmSetParamsFn(void* pcm, int format, int access, uint channels,
                            uint rate, int resample, uint latency);
delegate nint PcmTransferFn(void* pcm, byte* buffer, nuint frames);
delegate int PcmCommandFn(void* pcm);
delegate int PcmRecoverFn(void* pcm, int error, int silent);

extern "C"
{
    void* dlopen(byte* name, int flags);
    void* dlsym(void* library, byte* name);
}

#endif
// ================================================================= the door

// The module's own surface. A module-level function keeps its parentheses
// however much it reads like a fact (style 2.1), because a property is a pair
// of accessors reached through an instance and a module has none.

/// Whether there is an audio library on this machine. Loads it, so the first
/// call is where the cost is.
///
/// **Ask before trying.** A game wants to say "no audio device" at startup
/// rather than in the middle of a level, and this is how it finds out.
public bool IsAvailable() => Devices.Current != null;

/// Whether anything can play. False on a machine that has the library and no
/// device, which is what a headless server is.
public bool CanPlay()
{
    var backend = Devices.Current;
    return backend != null && ((Backend)backend).CanPlay;
}

/// Whether anything can record.
public bool CanRecord()
{
    var backend = Devices.Current;
    return backend != null && ((Backend)backend).CanRecord;
}

/// What is behind it, for a program that reports what it found. `""` when
/// there is nothing.
public String BackendName()
{
    if (Devices.Current == null)
        return "";
#if WINDOWS
    return "WASAPI";
#elif MACOS
    return "AudioToolbox";
#else
    return "ALSA";
#endif
}

/// A clip played through to the end.
///
/// The simple door, and the one most programs want: it opens a device,
/// writes the samples, waits for them, and closes. A program playing many
/// sounds should keep an `AudioPlayer` instead, because opening a device takes
/// tens of milliseconds and this does it every time.
///
/// @failure AudioError.NoBackend  there is no audio library on this machine
/// @failure AudioError.Format     the clip's format is not one this module
///                                handles, the device would not take it, or
///                                its samples are not whole frames
/// @failure AudioError.Device     there is nothing to play through, or the
///                                device failed part way
/// @failure AudioError.Busy       something else has the device and will not
///                                share it
/// @see AudioPlayer
public Result<bool, AudioError> PlayClip(AudioClip clip)
{
    var opened = AudioPlayer.Open(clip.Format);
    if (!opened.Ok)
        return Fail(opened.Error);

    var player = opened.Value;
    var written = player.Write(clip.Samples);
    if (!written.Ok)
    {
        player.Close();
        return Fail(written.Error);
    }

    player.DrainBuffer();
    player.Close();
    return Ok(true);
}

/// `seconds` of sound from the default input.
///
/// Blocks for that long. A program that wants to stop early, or to see the
/// sound as it arrives, wants an `AudioRecorder`.
///
/// @failure AudioError.NoBackend  there is no audio library on this machine
/// @failure AudioError.Format     the format is not one this module handles,
///                                or not one the device would take
/// @failure AudioError.Device     there is nothing to record from, or the
///                                device refused to start
/// @failure AudioError.Busy       something else has the device and will not
///                                share it
/// @see AudioRecorder
public Result<AudioClip, AudioError> RecordClip(AudioFormat format, double seconds)
{
    var opened = AudioRecorder.Open(format);
    if (!opened.Ok)
        return Fail(opened.Error);

    var recorder = opened.Value;
    var started = recorder.Start();
    if (!started.Ok)
    {
        recorder.Close();
        return Fail(started.Error);
    }

    nuint wanted = (nuint)(seconds * (double)format.BytesPerSecond);
    wanted = wanted - (wanted % format.BytesPerFrame);

    byte[] samples = new byte[wanted];
    nuint filled = 0u;
    byte[] chunk = new byte[format.BytesPerFrame * (nuint)format.SampleRate / 4u];

    while (filled < wanted)
    {
        nuint read = recorder.Read(chunk);
        if (read == 0u)
            break;

        nuint take = wanted - filled;
        if (take > read)
            take = read;

        chunk[:take].CopyTo(samples[filled:]);

        filled += take;
    }

    recorder.Stop();
    recorder.Close();

    // Short is not an error: a device that stopped early has still
    // produced sound, and a clip of what arrived is more use than nothing.
    if (filled == samples.Length)
        return Ok(new AudioClip(format, samples));

    return Ok(new AudioClip(format, samples[:filled].ToArray()));
}
