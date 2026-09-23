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
/// **WASAPI on Windows, ALSA everywhere else, and neither is linked.** Both
/// are reached by name the first time a device is opened, which is what lets
/// this live in the standard library: a program that makes no sound pays
/// nothing, and a machine with no ALSA answers `AudioError.NoBackend` -- a
/// value to print, rather than a link error. `Audio.IsAvailable` asks before
/// anything is tried.
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

#if WINDOWS
// For `Guid` and the `com interface` declarations WASAPI is made of.
import Standard.Com;
#endif

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

/// `WAVEFORMATEX`, which `mmreg.h` declares under `#pragma pack(1)` -- so it
/// is eighteen bytes and not twenty, and the attribute is what says so.
[Packed]
struct WaveFormatEx
{
    public ushort FormatTag;
    public ushort Channels;
    public uint SamplesPerSecond;
    public uint AverageBytesPerSecond;
    public ushort BlockAlign;
    public ushort BitsPerSample;
    public ushort ExtraSize;
}

// -------------------------------------------------------------- interfaces

// WASAPI, declared as what it is. The method order *is* the vtable, so nothing
// here may be reordered or removed -- a method that is not wanted is still
// declared, because slot 7 has to be slot 7. Every interface extends IUnknown
// whether or not it says so, so a declaration's own first method is slot 3,
// and ARC emits the AddRef and Release (§8.5).

/// The way in: the thing that knows which device is the default one.
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
com interface IMMDeviceEnumerator
{
    int EnumAudioEndpoints(int dataFlow, uint stateMask, byte** devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, byte** device);
    int GetDevice(char16* id, byte** device);
    int RegisterEndpointNotificationCallback(byte* client);
    int UnregisterEndpointNotificationCallback(byte* client);
}

/// One endpoint: a speaker, a headset, a microphone.
[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
com interface IMMDevice
{
    int Activate(Guid* interfaceId, uint context, byte* parameters, byte** result);
    int OpenPropertyStore(uint access, byte** store);
    int GetId(char16** id);
    int GetState(uint* state);
}

/// A stream on an endpoint. `Initialize` settles the format and the buffer,
/// and `GetService` hands out whichever half of it this stream is.
[Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")]
com interface IAudioClient
{
    int Initialize(int shareMode, uint streamFlags, long bufferDuration,
                   long periodicity, WaveFormatEx* format, Guid* session);
    int GetBufferSize(uint* frames);
    int GetStreamLatency(long* latency);
    int GetCurrentPadding(uint* frames);
    int IsFormatSupported(int shareMode, WaveFormatEx* format, byte** closest);
    int GetMixFormat(WaveFormatEx** format);
    int GetDevicePeriod(long* defaultPeriod, long* minimumPeriod);
    int Start();
    int Stop();
    int Reset();
    int SetEventHandle(void* signal);
    int GetService(Guid* interfaceId, byte** service);
}

/// The playing half: ask for room, fill it, hand it back.
[Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2")]
com interface IAudioRenderClient
{
    int GetBuffer(uint frames, byte** data);
    int ReleaseBuffer(uint frames, uint flags);
}

/// The listening half. A packet arrives whole, which is why the recorder keeps
/// what a caller's buffer had no room for.
[Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317")]
com interface IAudioCaptureClient
{
    int GetBuffer(byte** data, uint* frames, uint* flags,
                  ulong* devicePosition, ulong* counterPosition);
    int ReleaseBuffer(uint frames);
    int GetNextPacketSize(uint* frames);
}

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

/// ole32's activation half, resolved once.
///
/// **Loaded rather than linked.** A `#pragma comment(lib, "ole32")` here would
/// put an import in every Stainless binary on Windows, including the ones that
/// make no sound; this module is compiled into all of them. WASAPI itself
/// needs no library at all -- it is COM interfaces, and the only entry points
/// are the three below.
///
/// Frozen after construction, exactly as `Standard.Drawing`'s backend is:
/// every field is a function pointer written in the constructor and never
/// again, so there is nothing for two threads to race over.
threadsafe sealed class Backend
{
    CoInitializeExFn _initialize;
    CoUninitializeFn _uninitialize;
    CoCreateInstanceFn _create;

    /// Whether every symbol resolved.
    public bool Ready;

    public Backend()
    {
        Ready = false;

        void* ole = LoadLibraryA("ole32.dll".ToPointer());
        if (ole == null)
            return;

        bool complete = true;
        _initialize = (CoInitializeExFn)FindSymbol(ole, "CoInitializeEx", &complete);
        _uninitialize = (CoUninitializeFn)FindSymbol(ole, "CoUninitialize", &complete);
        _create = (CoCreateInstanceFn)FindSymbol(ole, "CoCreateInstance", &complete);

        Ready = complete;
    }

    void* FindSymbol(void* library, String name, bool* complete)
    {
        void* symbol = GetProcAddress(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    /// COM up on this thread, free-threaded, and whether this call is the one
    /// that has to take it down again.
    ///
    /// A thread already in a single-threaded apartment answers
    /// `RPC_E_CHANGED_MODE`, which is not a failure: COM is up, it is simply
    /// somebody else's, and balancing it here would tear down an apartment
    /// this module did not create. That is the one case `owned` is false and
    /// the call still succeeded.
    public bool EnterApartment(bool* owned)
    {
        *owned = false;
        int code = _initialize(null, MultiThreaded);
        if (code == ChangedMode)
            return true;
        if (code < 0)
            return false;

        *owned = true;
        return true;
    }

    public void LeaveApartment() => _uninitialize();

    /// `CLSID_MMDeviceEnumerator`, written out: a GUID is sixteen bytes and
    /// there is nothing to parse it with that would not be larger than this.
    Guid EnumeratorClassId()
    {
        Guid id;
        id.Data1 = 0xBCDE0395u;
        id.Data2 = 0xE52Fu;
        id.Data3 = 0x467Cu;
        id.Data4[0u] = 0x8E;
        id.Data4[1u] = 0x3D;
        id.Data4[2u] = 0xC4;
        id.Data4[3u] = 0x57;
        id.Data4[4u] = 0x92;
        id.Data4[5u] = 0x91;
        id.Data4[6u] = 0x69;
        id.Data4[7u] = 0x2E;
        return id;
    }

    /// The device enumerator, or null.
    public IMMDeviceEnumerator? CreateDeviceEnumerator()
    {
        Guid classId = EnumeratorClassId();
        byte* raw = null;

        if (_create(&classId, null, AllContexts, iidof(IMMDeviceEnumerator), &raw) < 0)
            return null;
        if (raw == null)
            return null;

        // The cast adopts: the +1 activation handed over becomes the one this
        // reference holds, and ARC emits the release.
        return (IMMDeviceEnumerator)raw;
    }

    /// The default endpoint in that direction, or null.
    public IMMDevice? GetDefaultEndpoint(int flow)
    {
        var enumerator = CreateDeviceEnumerator();
        if (enumerator == null)
            return null;

        byte* raw = null;
        if (((IMMDeviceEnumerator)enumerator).GetDefaultAudioEndpoint(flow, RoleConsole, &raw) < 0)
            return null;
        if (raw == null)
            return null;

        return (IMMDevice)raw;
    }

    /// Whether there is anything to play through. Asking costs an activation,
    /// which is why nothing here caches it: the answer changes when a headset
    /// is plugged in.
    public bool CanPlay => HasEndpoint(FlowRender);

    /// Whether there is anything to record from.
    public bool CanRecord => HasEndpoint(FlowCapture);

    /// The apartment has to be up for `CoCreateInstance` to answer, and this
    /// is a question a program asks before it has opened anything -- so the
    /// two device counts bring COM up and put it back exactly as they found
    /// it.
    bool HasEndpoint(int flow)
    {
        bool owned = false;
        if (!EnterApartment(&owned))
            return false;

        bool found = GetDefaultEndpoint(flow) != null;

        if (owned)
            LeaveApartment();
        return found;
    }
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

/// libasound, resolved once. Frozen after construction, as the Windows one is.
threadsafe sealed class Backend
{
    PcmOpenFn _open;
    PcmSetParamsFn _setParams;
    PcmTransferFn _writeFrames;
    PcmTransferFn _readFrames;
    PcmCommandFn _drain;
    PcmCommandFn _drop;
    PcmCommandFn _prepare;
    PcmCommandFn _start;
    PcmCommandFn _close;
    PcmRecoverFn _recover;

    /// Whether every symbol resolved.
    public bool Ready;

    public Backend()
    {
        Ready = false;

        // The versioned name first: a machine with the runtime package has
        // `libasound.so.2`, and only one with the development package has the
        // unversioned link -- and it is the runtime a program needs.
        void* alsa = dlopen("libasound.so.2".ToPointer(), RtldLazyLocal);
        if (alsa == null)
            alsa = dlopen("libasound.so".ToPointer(), RtldLazyLocal);
        if (alsa == null)
            return;

        bool complete = true;

        _open = (PcmOpenFn)FindSymbol(alsa, "snd_pcm_open", &complete);
        _setParams = (PcmSetParamsFn)FindSymbol(alsa, "snd_pcm_set_params", &complete);
        _writeFrames = (PcmTransferFn)FindSymbol(alsa, "snd_pcm_writei", &complete);
        _readFrames = (PcmTransferFn)FindSymbol(alsa, "snd_pcm_readi", &complete);
        _drain = (PcmCommandFn)FindSymbol(alsa, "snd_pcm_drain", &complete);
        _drop = (PcmCommandFn)FindSymbol(alsa, "snd_pcm_drop", &complete);
        _prepare = (PcmCommandFn)FindSymbol(alsa, "snd_pcm_prepare", &complete);
        _start = (PcmCommandFn)FindSymbol(alsa, "snd_pcm_start", &complete);
        _close = (PcmCommandFn)FindSymbol(alsa, "snd_pcm_close", &complete);
        _recover = (PcmRecoverFn)FindSymbol(alsa, "snd_pcm_recover", &complete);

        Ready = complete;
    }

    void* FindSymbol(void* library, String name, bool* complete)
    {
        void* symbol = dlsym(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    /// ALSA has no count to ask for without enumerating cards, and a machine
    /// with libasound installed has a device far more often than not. Opening
    /// is the honest test, and it is what both callers do next anyway.
    public bool CanPlay => true;

    public bool CanRecord => true;

    /// The device, opened and configured in one step.
    ///
    /// `snd_pcm_set_params` is ALSA's own shorthand for the eight calls the
    /// hardware-parameters API would take, and it settles the access, the
    /// format, the rate and the buffer size together. The latency is in
    /// microseconds and is a request rather than a promise.
    public int Open(void** pcm, AudioFormat format, bool capture)
    {
        int stream = capture ? StreamCapture : StreamPlayback;
        int code = _open(pcm, "default".ToPointer(), stream, 0);
        if (code < 0)
            return code;

        int width = format.BitsPerSample == 8u ? FormatUnsigned8 : FormatSigned16;
        return _setParams(*pcm, width, AccessInterleaved, (uint)format.Channels,
                          format.SampleRate, 1, BufferMilliseconds * 1000u);
    }

    public nint WriteFrames(void* pcm, byte* buffer, nuint frames) =>
        _writeFrames(pcm, buffer, frames);

    public nint ReadFrames(void* pcm, byte* buffer, nuint frames) =>
        _readFrames(pcm, buffer, frames);

    public int Drain(void* pcm) => _drain(pcm);

    public int Drop(void* pcm) => _drop(pcm);

    public int Prepare(void* pcm) => _prepare(pcm);

    public int Start(void* pcm) => _start(pcm);

    public int Close(void* pcm) => _close(pcm);

    /// An underrun or an overrun, recovered from. Silent, because the
    /// alternative is ALSA printing to standard error from inside a library.
    public int Recover(void* pcm, int error) => _recover(pcm, error, 1);
}

#endif
// ================================================================= the door

/// The backend, held.
///
/// A class rather than module-level storage, because a module has no static of
/// its own to keep one in (SL0204) and the loading has to happen exactly once.
/// The functions below are the surface; this is where the handle lives.
static class Devices
{
    static Backend? s_loaded = null;
    static bool s_tried = false;

    /// The backend, loading it on the first call, or null when there is none.
    ///
    /// The first call is not itself synchronized, which is the same stated
    /// limit `Standard.Drawing` has and for the same reason: two threads
    /// reaching it together would each load the library and one of the two
    /// objects would be dropped, which leaks a module handle and nothing else.
    /// A lock here would put `Standard.Threading` underneath a module that
    /// otherwise depends on nothing.
    public static Backend? Current
    {
        get
        {
            if (s_tried)
                return s_loaded;
            s_tried = true;

            var made = new Backend();
            if (made.Ready)
                s_loaded = made;
            return s_loaded;
        }
    }
}

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

        for (nuint i = 0u; i < take; i++)
            samples[filled + i] = chunk[i];

        filled += take;
    }

    recorder.Stop();
    recorder.Close();

    // Short is not an error: a device that stopped early has still
    // produced sound, and a clip of what arrived is more use than nothing.
    if (filled == samples.Length)
        return Ok(new AudioClip(format, samples));

    byte[] trimmed = new byte[filled];
    for (nuint i = 0u; i < filled; i++)
        trimmed[i] = samples[i];
    return Ok(new AudioClip(format, trimmed));
}
