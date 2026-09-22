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
///     Audio.Play(loaded.Value);
///
/// var heard = Audio.Record(AudioFormat.Voice, 3.0);   // three seconds
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
/// value to print, rather than a link error. `Audio.Available` asks before
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

// =============================================================== the format

/// What the samples are: how fast, how many channels, how wide.
///
/// A struct of three numbers, because that is what every platform's format
/// descriptor holds and what a WAV header carries. Anything a device will not
/// take is reported by `AudioPlayer.Open` rather than refused here -- what a
/// sound card accepts is not knowable from the numbers alone.
public struct AudioFormat
{
    /// Frames per second. 44100 is a CD, 48000 is what most hardware runs at
    /// natively, 8000 is a telephone.
    public uint SampleRate;

    /// 1 for mono, 2 for stereo. More is not supported: the interleaving is
    /// defined for those two and the channel-order conventions past them are
    /// not the same on both platforms.
    public ushort Channels;

    /// 8 or 16. Eight-bit samples are *unsigned* and centred on 128, and
    /// sixteen-bit ones are signed and centred on zero -- which is WAV's rule
    /// and both platforms', however strange it reads.
    public ushort BitsPerSample;

    /// A format written out.
    public static AudioFormat Of(uint sampleRate, ushort channels, ushort bits)
    {
        AudioFormat format;
        format.SampleRate = sampleRate;
        format.Channels = channels;
        format.BitsPerSample = bits;
        return format;
    }

    /// 44.1 kHz, sixteen bits, stereo: what a CD is and what a WAV file
    /// usually holds.
    public static AudioFormat Cd => AudioFormat.Of(44100u, (ushort)2, (ushort)16);

    /// 48 kHz, sixteen bits, stereo: what most sound hardware runs at without
    /// resampling, and what to prefer when nothing else decides.
    public static AudioFormat Studio => AudioFormat.Of(48000u, (ushort)2, (ushort)16);

    /// 16 kHz, sixteen bits, mono: enough for speech and a quarter of the
    /// bytes.
    public static AudioFormat Voice => AudioFormat.Of(16000u, (ushort)1, (ushort)16);

    /// How many bytes one frame takes -- one sample on every channel. This is
    /// the unit everything below counts in, because a buffer cut in the middle
    /// of a frame swaps the channels for the rest of the stream.
    public nuint BytesPerFrame => (nuint)Channels * ((nuint)BitsPerSample / 8u);

    /// How many bytes a second of this takes.
    public nuint BytesPerSecond => BytesPerFrame * (nuint)SampleRate;

    /// Whether this is a shape both backends can be asked for at all.
    public bool IsSupported =>
        SampleRate > 0u && (Channels == 1u || Channels == 2u) &&
        (BitsPerSample == 8u || BitsPerSample == 16u);

    public bool Equals(AudioFormat other) =>
        SampleRate == other.SampleRate && Channels == other.Channels &&
        BitsPerSample == other.BitsPerSample;
}

/// Why a sound did not happen.
public enum AudioError
{
    /// There is no audio library on this machine: no winmm, or no
    /// libasound. `Audio.Available` is how to ask before trying.
    NoBackend,

    /// The format is not one this module handles, or not one the device
    /// would take.
    Format,

    /// There is no sound device, or the one there is refused to open.
    Device,

    /// Something else has the device and will not share it.
    Busy,

    /// The player or recorder has been closed.
    Closed,

    /// The file was not a WAV, or was one this module does not read.
    Malformed,

    /// The file could not be read or written; `Standard.IO` has the detail.
    Io,
}

// =================================================================== a clip

/// Samples in memory, and what they are.
///
/// The unit `Wav` reads and writes and `Audio.Play` takes. It is bytes rather
/// than a typed sample array deliberately: the width is in the format, a
/// conversion on the way in would cost a copy of every sound a program loads,
/// and the platform wants bytes at the end of it anyway. `SampleAt` and
/// `SetSample` are there for a program that does want to look.
public sealed class AudioClip
{
    AudioFormat _format;
    byte[] _samples;

    /// A clip over samples that are already in the right shape. The array is
    /// taken rather than copied, so a caller that goes on writing to it is
    /// writing to the clip.
    public AudioClip(AudioFormat format, byte[] samples)
    {
        _format = format;
        _samples = samples;
    }

    /// Silence, `frames` long.
    ///
    /// Zero is silence for sixteen-bit samples and a hard offset for eight-bit
    /// ones, so this fills with 128 there -- which is what silence is in an
    /// unsigned format, and the kind of detail that otherwise shows up as a
    /// click.
    public static AudioClip Silence(AudioFormat format, nuint frames)
    {
        byte[] samples = new byte[frames * format.BytesPerFrame];
        if (format.BitsPerSample == 8u)
        {
            for (nuint i = 0u; i < samples.Length; i++)
                samples[i] = 128;
        }

        return new AudioClip(format, samples);
    }

    public AudioFormat Format => _format;

    /// The bytes. Not a copy.
    public byte[] Samples => _samples;

    /// How many frames it holds.
    ///
    /// Written out rather than as a ternary: `nuint` is four bytes on a 32-bit
    /// target and eight on a 64-bit one, and the arms of a ternary over an
    /// unsuffixed literal and a `nuint` meet at a type that is neither.
    public nuint FrameCount
    {
        get
        {
            if (_format.BytesPerFrame == 0u)
                return 0u;
            return _samples.Length / _format.BytesPerFrame;
        }
    }

    /// How long it lasts, in seconds.
    public double Duration => _format.SampleRate == 0u
        ? 0.0
        : (double)FrameCount / (double)_format.SampleRate;

    /// One sample, as a number from -32768 to 32767 whatever the width is.
    ///
    /// Eight-bit samples are widened and re-centred on the way out, so a
    /// caller reading a clip need not know which it has. A sample wider than
    /// sixteen bits answers its top sixteen. Out of range answers
    /// zero rather than aborting: a program walking a waveform runs off the
    /// end at the end, and that is not a mistake in it.
    public int SampleAt(nuint frame, nuint channel)
    {
        nuint at = Offset(frame, channel);
        if (at == _samples.Length)
            return 0;

        nuint width = (nuint)_format.BitsPerSample / 8u;
        if (width == 1u)
            return ((int)_samples[at] - 128) * 256;

        // Little-endian, so the top sixteen bits are the last two bytes.
        nuint top = at + width - 2u;
        int low = (int)_samples[top];
        int high = (int)_samples[top + 1u];
        int value = low | (high << 8);

        // Sixteen-bit samples are signed and the bytes are little-endian, so
        // the high bit has to be carried down by hand.
        return value >= 32768 ? value - 65536 : value;
    }

    /// One sample written, taking the same range `SampleAt` answers in and
    /// clamping to it. A sample wider than sixteen bits has its top sixteen
    /// set and the bits below them cleared. Out of range does nothing.
    public void SetSample(nuint frame, nuint channel, int value)
    {
        nuint at = Offset(frame, channel);
        if (at == _samples.Length)
            return;

        if (value < -32768)
            value = -32768;
        if (value > 32767)
            value = 32767;

        // A shift rather than a division, which would truncate toward zero and
        // put -255 to 255 all on the centre.
        nuint width = (nuint)_format.BitsPerSample / 8u;
        if (width == 1u)
        {
            _samples[at] = (byte)((value >> 8) + 128);
            return;
        }

        nuint top = at + width - 2u;
        for (nuint i = at; i < top; i++)
            _samples[i] = 0;

        int stored = value < 0 ? value + 65536 : value;
        _samples[top] = (byte)(stored & 0xFF);
        _samples[top + 1u] = (byte)((stored >> 8) & 0xFF);
    }

    /// Where a sample sits, or `_samples.Length` when it is not in the clip --
    /// a value no index can be, which is what the two callers check.
    nuint Offset(nuint frame, nuint channel)
    {
        if (channel >= (nuint)_format.Channels)
            return _samples.Length;

        nuint width = (nuint)_format.BitsPerSample / 8u;
        if (width == 0u)
            return _samples.Length;

        nuint at = frame * _format.BytesPerFrame + channel * width;
        return at + width > _samples.Length ? _samples.Length : at;
    }
}

// ================================================================ WAV files

/// RIFF/WAVE: the one container everything reads.
///
/// **Uncompressed PCM only.** A WAV may carry ADPCM, mu-law, or an MP3 stream
/// in a WAVE wrapper, and a decoder for any of those belongs somewhere else;
/// this reports `AudioError.Format` and says which tag it found. It does read
/// `WAVE_FORMAT_EXTENSIBLE`, because that is what a modern recorder writes
/// for ordinary PCM and refusing it would refuse half the files on a machine.
public static class Wav
{
    /// The bytes of a `.wav` file, read.
    public static Result<AudioClip, AudioError> Decode(byte[] bytes)
    {
        if (bytes.Length < 44u)
            return Fail(AudioError.Malformed);

        if (!Marks(bytes, 0u, "RIFF") || !Marks(bytes, 8u, "WAVE"))
            return Fail(AudioError.Malformed);

        AudioFormat format = AudioFormat.Of(0u, (ushort)0, (ushort)0);
        bool described = false;
        nuint at = 12u;

        while (at + 8u <= bytes.Length)
        {
            nuint size = (nuint)ReadUInt(bytes, at + 4u);
            nuint body = at + 8u;

            // A chunk that claims more than the file holds is a truncated
            // download, and reading it would walk off the end. Compared with
            // what remains rather than summed, because the sum wraps where
            // `nuint` is four bytes.
            if (size > bytes.Length - body)
                size = bytes.Length - body;

            if (Marks(bytes, at, "fmt ") && size >= 16u)
            {
                ushort tag = ReadUShort(bytes, body);
                format.Channels = ReadUShort(bytes, body + 2u);
                format.SampleRate = ReadUInt(bytes, body + 4u);
                format.BitsPerSample = ReadUShort(bytes, body + 14u);

                // 1 is PCM; 0xFFFE is EXTENSIBLE, whose sub-format GUID starts
                // with the tag it stands for -- so a PCM one begins with 1 and
                // that is what is checked rather than the whole GUID.
                if (tag == 0xFFFEu && size >= 40u)
                    tag = ReadUShort(bytes, body + 24u);

                if (tag != 1u)
                    return Fail(AudioError.Format);

                described = true;
            }
            else if (Marks(bytes, at, "data"))
            {
                if (!described)
                    return Fail(AudioError.Malformed);
                if (!format.IsSupported)
                    return Fail(AudioError.Format);

                // A truncated file can end inside a frame, and a partial frame
                // is one no device will take.
                size -= size % format.BytesPerFrame;

                byte[] samples = new byte[size];
                for (nuint i = 0u; i < size; i++)
                    samples[i] = bytes[body + i];

                return Ok(new AudioClip(format, samples));
            }

            // Chunks are word-aligned, and an odd size is followed by a pad
            // byte that is not counted in it.
            at = body + size + (size % 2u);
        }

        return Fail(AudioError.Malformed);
    }

    /// A clip as the bytes of a `.wav` file: a 44-byte canonical header, the
    /// samples, and the pad byte an odd length is followed by.
    public static byte[] Encode(AudioClip clip)
    {
        var format = clip.Format;
        byte[] samples = clip.Samples;
        nuint pad = samples.Length % 2u;
        byte[] file = new byte[44u + samples.Length + pad];

        WriteMark(file, 0u, "RIFF");
        WriteUInt(file, 4u, (uint)(36u + samples.Length + pad));
        WriteMark(file, 8u, "WAVE");

        WriteMark(file, 12u, "fmt ");
        WriteUInt(file, 16u, 16u);
        WriteUShort(file, 20u, (ushort)1);
        WriteUShort(file, 22u, format.Channels);
        WriteUInt(file, 24u, format.SampleRate);
        WriteUInt(file, 28u, (uint)format.BytesPerSecond);
        WriteUShort(file, 32u, (ushort)format.BytesPerFrame);
        WriteUShort(file, 34u, format.BitsPerSample);

        WriteMark(file, 36u, "data");
        WriteUInt(file, 40u, (uint)samples.Length);

        for (nuint i = 0u; i < samples.Length; i++)
            file[44u + i] = samples[i];

        return file;
    }

    /// A `.wav` on disk, read.
    public static Result<AudioClip, AudioError> FromFile(String path)
    {
        var read = File.ReadAllBytes(path);
        if (!read.Ok)
            return Fail(AudioError.Io);
        return Decode(read.Value);
    }

    /// A clip written to a `.wav` on disk.
    public static Result<bool, AudioError> Save(AudioClip clip, String path)
    {
        if (File.WriteAllBytes(path, Encode(clip)) != IOError.None)
            return Fail(AudioError.Io);
        return Ok(true);
    }

    static bool Marks(byte[] bytes, nuint at, String mark)
    {
        if (at + 4u > bytes.Length)
            return false;

        var wanted = mark.ToPointer();
        for (nuint i = 0u; i < 4u; i++)
        {
            if (bytes[at + i] != wanted[i])
                return false;
        }

        return true;
    }

    static void WriteMark(byte[] bytes, nuint at, String mark)
    {
        var source = mark.ToPointer();
        for (nuint i = 0u; i < 4u; i++)
            bytes[at + i] = source[i];
    }

    static ushort ReadUShort(byte[] bytes, nuint at) =>
        (ushort)((uint)bytes[at] | ((uint)bytes[at + 1u] << 8));

    static uint ReadUInt(byte[] bytes, nuint at) =>
        (uint)bytes[at] | ((uint)bytes[at + 1u] << 8) |
        ((uint)bytes[at + 2u] << 16) | ((uint)bytes[at + 3u] << 24);

    static void WriteUShort(byte[] bytes, nuint at, ushort value)
    {
        bytes[at] = (byte)((uint)value & 0xFFu);
        bytes[at + 1u] = (byte)(((uint)value >> 8) & 0xFFu);
    }

    static void WriteUInt(byte[] bytes, nuint at, uint value)
    {
        bytes[at] = (byte)(value & 0xFFu);
        bytes[at + 1u] = (byte)((value >> 8) & 0xFFu);
        bytes[at + 2u] = (byte)((value >> 16) & 0xFFu);
        bytes[at + 3u] = (byte)((value >> 24) & 0xFFu);
    }
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
        _initialize = (CoInitializeExFn)Find(ole, "CoInitializeEx", &complete);
        _uninitialize = (CoUninitializeFn)Find(ole, "CoUninitialize", &complete);
        _create = (CoCreateInstanceFn)Find(ole, "CoCreateInstance", &complete);

        Ready = complete;
    }

    void* Find(void* library, String name, bool* complete)
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
    public IMMDeviceEnumerator? Enumerator()
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
    public IMMDevice? DefaultEndpoint(int flow)
    {
        var enumerator = Enumerator();
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

        bool found = DefaultEndpoint(flow) != null;

        if (owned)
            LeaveApartment();
        return found;
    }
}

/// A format filled in for WASAPI.
WaveFormatEx Describe(AudioFormat format)
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
AudioError Translate(int code)
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
    var endpoint = found.DefaultEndpoint(flow);
    if (endpoint == null)
        return Fail(AudioError.Device);

    byte* raw = null;
    int code = ((IMMDevice)endpoint).Activate(iidof(IAudioClient), AllContexts, null, &raw);
    if (code < 0 || raw == null)
        return Fail(Translate(code));

    var client = (IAudioClient)raw;
    var described = Describe(format);

    code = client.Initialize(ShareModeShared, AutoConvert,
                             (long)BufferMilliseconds * TicksPerMillisecond, 0,
                             &described, null);
    if (code < 0)
        return Fail(Translate(code));

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

        _open = (PcmOpenFn)Find(alsa, "snd_pcm_open", &complete);
        _setParams = (PcmSetParamsFn)Find(alsa, "snd_pcm_set_params", &complete);
        _writeFrames = (PcmTransferFn)Find(alsa, "snd_pcm_writei", &complete);
        _readFrames = (PcmTransferFn)Find(alsa, "snd_pcm_readi", &complete);
        _drain = (PcmCommandFn)Find(alsa, "snd_pcm_drain", &complete);
        _drop = (PcmCommandFn)Find(alsa, "snd_pcm_drop", &complete);
        _prepare = (PcmCommandFn)Find(alsa, "snd_pcm_prepare", &complete);
        _close = (PcmCommandFn)Find(alsa, "snd_pcm_close", &complete);
        _recover = (PcmRecoverFn)Find(alsa, "snd_pcm_recover", &complete);

        Ready = complete;
    }

    void* Find(void* library, String name, bool* complete)
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
public bool Available() => Devices.Current != null;

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
public Result<bool, AudioError> Play(AudioClip clip)
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

    player.Drain();
    player.Close();
    return Ok(true);
}

/// `seconds` of sound from the default input.
///
/// Blocks for that long. A program that wants to stop early, or to see the
/// sound as it arrives, wants an `AudioRecorder`.
public Result<AudioClip, AudioError> Record(AudioFormat format, double seconds)
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

// ================================================================== playing

/// A sound device, open, taking samples.
///
/// ```csharp
/// var opened = AudioPlayer.Open(AudioFormat.Cd);
/// if (!opened.Ok) { return; }
///
/// var player = opened.Value;
/// player.Write(first);
/// player.Write(second);        // returns when the device has taken them
/// player.Drain();              // and this when it has played them
/// player.Close();
/// ```
///
/// **The device is closed by the destructor**, so a player that goes out of
/// scope releases it whether or not `Close` was called. That matters more here
/// than it does for a file: a sound device left open is one no other program
/// can have.
///
/// **Open it and use it on the same thread.** On Windows the stream is COM,
/// and the apartment is brought up by `Open` on whichever thread called it.
/// Calling `Write` from another thread reaches an in-process object and works
/// in practice; it is outside what this module promises, and a player per
/// thread is the arrangement to prefer.
public sealed class AudioPlayer
{
    AudioFormat _format;
    bool _closed;

#if WINDOWS
    IAudioClient? _client;
    IAudioRenderClient? _render;
    uint _bufferFrames;
    bool _started;
    bool _ownsApartment;

    AudioPlayer(IAudioClient client, IAudioRenderClient render, uint bufferFrames,
                AudioFormat format, bool ownsApartment)
    {
        _client = client;
        _render = render;
        _bufferFrames = bufferFrames;
        _format = format;
        _started = false;
        _ownsApartment = ownsApartment;
        _closed = false;
    }
#else
    void* _device;

    AudioPlayer(void* device, AudioFormat format)
    {
        _device = device;
        _format = format;
        _closed = false;
    }
#endif

    ~AudioPlayer()
    {
        Close();
    }

    /// A device open for this format.
    ///
    /// Fails with `NoBackend` on a machine with no audio library, `Device`
    /// when there is nothing to play through, `Busy` when something else has
    /// the device in exclusive mode, and `Format` when the engine will not
    /// take these numbers -- which is worth telling apart, because the answer
    /// to the last one is to resample rather than to give up.
    public static Result<AudioPlayer, AudioError> Open(AudioFormat format)
    {
        if (!format.IsSupported)
            return Fail(AudioError.Format);

        var backend = Devices.Current;
        if (backend == null)
            return Fail(AudioError.NoBackend);

        var found = (Backend)backend;

#if WINDOWS
        bool owned = false;
        if (!found.EnterApartment(&owned))
            return Fail(AudioError.Device);

        var opened = OpenStream(found, format, FlowRender);
        if (!opened.Ok)
        {
            if (owned)
                found.LeaveApartment();
            return Fail(opened.Error);
        }

        var client = opened.Value;

        uint frames = 0u;
        if (client.GetBufferSize(&frames) < 0)
        {
            if (owned)
                found.LeaveApartment();
            return Fail(AudioError.Device);
        }

        byte* raw = null;
        if (client.GetService(iidof(IAudioRenderClient), &raw) < 0 || raw == null)
        {
            if (owned)
                found.LeaveApartment();
            return Fail(AudioError.Device);
        }

        return Ok(new AudioPlayer(client, (IAudioRenderClient)raw, frames, format, owned));
#else
        void* device = null;
        int code = found.Open(&device, format, false);
        if (code < 0)
        {
            if (device != null)
                found.Close(device);
            return Fail(code == Busy ? AudioError.Busy : AudioError.Device);
        }

        return Ok(new AudioPlayer(device, format));
#endif
    }

    /// The format this was opened for.
    public AudioFormat Format => _format;

    /// Whether the device is still open.
    public bool IsOpen => !_closed;

    /// Samples queued, blocking until the device has room for them.
    ///
    /// Returns when the bytes have been handed over, which is not when they
    /// have been heard -- `Drain` is what waits for that. A length that is not
    /// a whole number of frames is refused rather than truncated, because
    /// truncating swaps the channels for the rest of the stream.
    public Result<bool, AudioError> Write(byte[] samples)
    {
        if (_closed)
            return Fail(AudioError.Closed);
        if (samples.Length % _format.BytesPerFrame != 0u)
            return Fail(AudioError.Format);
        if (samples.Length == 0u)
            return Ok(true);

        var backend = Devices.Current;
        if (backend == null)
            return Fail(AudioError.NoBackend);

        var found = (Backend)backend;

#if WINDOWS
        var held = _client;
        var target = _render;
        if (held == null || target == null)
            return Fail(AudioError.Closed);

        var client = (IAudioClient)held;
        var render = (IAudioRenderClient)target;

        nuint frameSize = _format.BytesPerFrame;
        nuint remaining = samples.Length / frameSize;
        nuint at = 0u;

        while (remaining > 0u)
        {
            uint padding = 0u;
            int code = client.GetCurrentPadding(&padding);
            if (code < 0)
                return Fail(Translate(code));

            uint room = _bufferFrames - padding;
            if (room == 0u)
            {
                // The engine has as much as it will hold. Starting it here
                // rather than at `Open` is what keeps the first buffer full
                // when it does start -- a stream started empty plays a gap.
                if (!_started)
                {
                    if (client.Start() < 0)
                        return Fail(AudioError.Device);
                    _started = true;
                }

                sl_thread_sleep(PollMilliseconds);
                continue;
            }

            uint take = room;
            if ((nuint)take > remaining)
                take = (uint)remaining;

            byte* buffer = null;
            code = render.GetBuffer(take, &buffer);
            if (code < 0 || buffer == null)
                return Fail(Translate(code));

            memcpy(buffer, &samples[at], (nuint)take * frameSize);

            if (render.ReleaseBuffer(take, 0u) < 0)
                return Fail(AudioError.Device);

            at += (nuint)take * frameSize;
            remaining -= (nuint)take;
        }

        if (!_started)
        {
            if (client.Start() < 0)
                return Fail(AudioError.Device);
            _started = true;
        }

        return Ok(true);
#else
        nuint frames = samples.Length / _format.BytesPerFrame;
        nuint done = 0u;

        while (done < frames)
        {
            nint moved = found.WriteFrames(_device, &samples[done * _format.BytesPerFrame],
                                           frames - done);
            if (moved < 0)
            {
                // An underrun is the ordinary consequence of a program that
                // did not write fast enough, and the device carries on once it
                // has been prepared again.
                if (found.Recover(_device, (int)moved) < 0)
                    return Fail(AudioError.Device);
                continue;
            }

            done += (nuint)moved;
        }

        return Ok(true);
#endif
    }

    /// Waits until everything written has been played.
    public void Drain()
    {
        if (_closed)
            return;

        var backend = Devices.Current;
        if (backend == null)
            return;

        var found = (Backend)backend;

#if WINDOWS
        var held = _client;
        if (held == null || !_started)
            return;

        var client = (IAudioClient)held;
        while (true)
        {
            uint padding = 0u;
            if (client.GetCurrentPadding(&padding) < 0)
                return;
            if (padding == 0u)
                return;

            sl_thread_sleep(PollMilliseconds);
        }
#else
        found.Drain(_device);
        found.Prepare(_device);
#endif
    }

    /// Stops at once, dropping whatever has not been played.
    public void Stop()
    {
        if (_closed)
            return;

        var backend = Devices.Current;
        if (backend == null)
            return;

        var found = (Backend)backend;

#if WINDOWS
        var held = _client;
        if (held == null)
            return;

        var client = (IAudioClient)held;
        client.Stop();
        client.Reset();
        _started = false;
#else
        found.Drop(_device);
        found.Prepare(_device);
#endif
    }

    /// Releases the device. Idempotent, and the destructor calls it.
    public void Close()
    {
        if (_closed)
            return;

        Stop();
        _closed = true;

        var backend = Devices.Current;
        if (backend == null)
            return;

        var found = (Backend)backend;

#if WINDOWS
        // Dropped here rather than left to the object's death: a program that
        // calls `Close` and keeps the player has said it is done with the
        // device, and holding the stream open would keep it from anything
        // else. ARC emits the Release on each store.
        _render = null;
        _client = null;

        if (_ownsApartment)
        {
            found.LeaveApartment();
            _ownsApartment = false;
        }
#else
        found.Close(_device);
        _device = null;
#endif
    }
}

// ================================================================ recording

/// A sound device, open, producing samples.
///
/// ```csharp
/// var opened = AudioRecorder.Open(AudioFormat.Voice);
/// if (!opened.Ok) { return; }
///
/// var recorder = opened.Value;
/// recorder.Start();
///
/// byte[] chunk = new byte[16000u];
/// while (listening)
/// {
///     nuint read = recorder.Read(chunk);
///     // ... whatever is being done with it
/// }
///
/// recorder.Close();
/// ```
///
/// **Recording is a thing a user has to be told about.** Windows asks for
/// microphone permission at the system level and a modern Linux desktop may
/// route this through a portal; a program that opens an input without saying
/// so is doing something its user did not ask for, and no library can fix that
/// from underneath.
public sealed class AudioRecorder
{
    AudioFormat _format;
    bool _closed;
    bool _running;

#if WINDOWS
    IAudioClient? _client;
    IAudioCaptureClient? _capture;
    bool _ownsApartment;

    // What a packet held and the caller's buffer had no room for. WASAPI hands
    // over a whole packet or none, so a caller reading in smaller pieces would
    // otherwise lose the rest of every one.
    byte[] _spill;
    nuint _spillAt;

    AudioRecorder(IAudioClient client, IAudioCaptureClient capture,
                  AudioFormat format, bool ownsApartment)
    {
        _client = client;
        _capture = capture;
        _format = format;
        _ownsApartment = ownsApartment;
        _spill = new byte[0u];
        _spillAt = 0u;
        _closed = false;
        _running = false;
    }
#else
    void* _device;

    AudioRecorder(void* device, AudioFormat format)
    {
        _device = device;
        _format = format;
        _closed = false;
        _running = false;
    }
#endif

    ~AudioRecorder()
    {
        Close();
    }

    /// A device open for this format. Fails as `AudioPlayer.Open` does.
    public static Result<AudioRecorder, AudioError> Open(AudioFormat format)
    {
        if (!format.IsSupported)
            return Fail(AudioError.Format);

        var backend = Devices.Current;
        if (backend == null)
            return Fail(AudioError.NoBackend);

        var found = (Backend)backend;

#if WINDOWS
        bool owned = false;
        if (!found.EnterApartment(&owned))
            return Fail(AudioError.Device);

        var opened = OpenStream(found, format, FlowCapture);
        if (!opened.Ok)
        {
            if (owned)
                found.LeaveApartment();
            return Fail(opened.Error);
        }

        var client = opened.Value;

        byte* raw = null;
        if (client.GetService(iidof(IAudioCaptureClient), &raw) < 0 || raw == null)
        {
            if (owned)
                found.LeaveApartment();
            return Fail(AudioError.Device);
        }

        return Ok(new AudioRecorder(client, (IAudioCaptureClient)raw, format, owned));
#else
        void* device = null;
        int code = found.Open(&device, format, true);
        if (code < 0)
        {
            if (device != null)
                found.Close(device);
            return Fail(code == Busy ? AudioError.Busy : AudioError.Device);
        }

        return Ok(new AudioRecorder(device, format));
#endif
    }

    /// The format this was opened for.
    public AudioFormat Format => _format;

    /// Whether the device is still open.
    public bool IsOpen => !_closed;

    /// Whether it is listening now.
    public bool IsRecording => _running;

    /// Starts listening. Sound that arrives before the first `Read` is
    /// buffered, up to about a fifth of a second of it, and dropped after that.
    public Result<bool, AudioError> Start()
    {
        if (_closed)
            return Fail(AudioError.Closed);
        if (_running)
            return Ok(true);

        var backend = Devices.Current;
        if (backend == null)
            return Fail(AudioError.NoBackend);

        var found = (Backend)backend;

#if WINDOWS
        var held = _client;
        if (held == null)
            return Fail(AudioError.Closed);

        int code = ((IAudioClient)held).Start();
        if (code < 0)
            return Fail(Translate(code));
#else
        if (found.Prepare(_device) < 0)
            return Fail(AudioError.Device);
#endif

        _running = true;
        return Ok(true);
    }

    /// Up to `buffer.Length` bytes of sound, and how many arrived.
    ///
    /// Blocks until there is something. Zero means the recorder was stopped or
    /// closed while this was waiting, which is how a loop in another thread
    /// ends. The count is always a whole number of frames.
    public nuint Read(byte[] buffer)
    {
        if (_closed || !_running || buffer.Length == 0u)
            return 0u;

        var backend = Devices.Current;
        if (backend == null)
            return 0u;

        var found = (Backend)backend;

#if WINDOWS
        // Whatever the last packet left over comes first, so the stream stays
        // in order.
        if (_spillAt < _spill.Length)
            return TakeSpill(buffer);

        var held = _capture;
        if (held == null)
            return 0u;

        var capture = (IAudioCaptureClient)held;
        nuint frameSize = _format.BytesPerFrame;

        while (true)
        {
            uint waiting = 0u;
            if (capture.GetNextPacketSize(&waiting) < 0)
                return 0u;

            if (waiting == 0u)
            {
                if (_closed || !_running)
                    return 0u;
                sl_thread_sleep(PollMilliseconds);
                continue;
            }

            byte* data = null;
            uint frames = 0u;
            uint flags = 0u;
            if (capture.GetBuffer(&data, &frames, &flags, null, null) < 0)
                return 0u;

            nuint bytes = (nuint)frames * frameSize;
            byte[] packet = new byte[bytes];

            // A silent packet's bytes are not meaningful and need not even be
            // readable; the flag is the device saying "nothing happened", and
            // a freshly allocated array already says it.
            if ((flags & BufferSilent) == 0u && data != null && bytes > 0u)
                memcpy(&packet[0u], data, bytes);

            capture.ReleaseBuffer(frames);

            _spill = packet;
            _spillAt = 0u;
            return TakeSpill(buffer);
        }
#else
        nuint frames = buffer.Length / _format.BytesPerFrame;
        if (frames == 0u)
            return 0u;

        while (true)
        {
            nint moved = found.ReadFrames(_device, &buffer[0u], frames);
            if (moved >= 0)
                return (nuint)moved * _format.BytesPerFrame;

            // An overrun means the program did not read fast enough and some
            // sound was lost; the device carries on once it is prepared.
            if (found.Recover(_device, (int)moved) < 0)
                return 0u;
        }
#endif
    }

    /// Stops listening. The device stays open, so `Start` may be called again.
    public void Stop()
    {
        if (_closed || !_running)
            return;
        _running = false;

        var backend = Devices.Current;
        if (backend == null)
            return;

        var found = (Backend)backend;

#if WINDOWS
        var held = _client;
        if (held == null)
            return;

        var client = (IAudioClient)held;
        client.Stop();
        client.Reset();
        _spill = new byte[0u];
        _spillAt = 0u;
#else
        found.Drop(_device);
#endif
    }

    /// Releases the device. Idempotent, and the destructor calls it.
    public void Close()
    {
        if (_closed)
            return;

        Stop();
        _closed = true;

        var backend = Devices.Current;
        if (backend == null)
            return;

        var found = (Backend)backend;

#if WINDOWS
        _capture = null;
        _client = null;

        if (_ownsApartment)
        {
            found.LeaveApartment();
            _ownsApartment = false;
        }
#else
        found.Close(_device);
        _device = null;
#endif
    }

#if WINDOWS
    /// As much of what is held over as fits, and how much that was.
    nuint TakeSpill(byte[] buffer)
    {
        nuint available = _spill.Length - _spillAt;
        nuint take = available;
        if (take > buffer.Length)
            take = buffer.Length;

        take = take - (take % _format.BytesPerFrame);
        if (take == 0u)
            return 0u;

        for (nuint i = 0u; i < take; i++)
            buffer[i] = _spill[_spillAt + i];

        _spillAt += take;
        return take;
    }
#endif
}
// ================================================================ synthesis

/// Sound made rather than loaded, which is what a test and a beep need.
///
/// Not a synthesiser. There are two waveforms here because a program that
/// wants to know whether its audio works needs a sound to play, and writing
/// one by hand in every such program is worse than three functions that are
/// obviously correct.
public static class Tone
{
    /// A sine wave: `frequency` hertz for `seconds`, at `amplitude` from 0.0
    /// to 1.0. On every channel.
    public static AudioClip Sine(AudioFormat format, double frequency,
                                 double seconds, double amplitude)
    {
        var clip = AudioClip.Silence(format, (nuint)(seconds * (double)format.SampleRate));
        double step = frequency * 6.28318530717958623200 / (double)format.SampleRate;

        for (nuint frame = 0u; frame < clip.FrameCount; frame++)
        {
            int value = (int)(sin(step * (double)frame) * amplitude * 32767.0);
            for (nuint channel = 0u; channel < (nuint)format.Channels; channel++)
                clip.SetSample(frame, channel, value);
        }

        return clip;
    }

    /// A square wave, which is louder than a sine of the same amplitude and is
    /// what a beep traditionally is.
    public static AudioClip Square(AudioFormat format, double frequency,
                                   double seconds, double amplitude)
    {
        var clip = AudioClip.Silence(format, (nuint)(seconds * (double)format.SampleRate));
        double period = (double)format.SampleRate / frequency;
        int level = (int)(amplitude * 32767.0);

        for (nuint frame = 0u; frame < clip.FrameCount; frame++)
        {
            double phase = (double)frame / period;
            int value = (phase - (double)(long)phase) < 0.5 ? level : -level;
            for (nuint channel = 0u; channel < (nuint)format.Channels; channel++)
                clip.SetSample(frame, channel, value);
        }

        return clip;
    }

    /// Silence, which is the third thing a test needs: a gap between two
    /// tones, and something to compare against.
    public static AudioClip Rest(AudioFormat format, double seconds) =>
        AudioClip.Silence(format, (nuint)(seconds * (double)format.SampleRate));
}
