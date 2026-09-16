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

// Several sounds at once, which is what a game needs and what
// `Standard.Media.Audio` deliberately is not.
//
// A convenience layer over `Win32.XAudio2`. It names xaudio2 itself with a
// pragma, so a program compiling it needs no `-l`.
//
// ```csharp
// var engine = try Mixer.Start();
// var shot = try engine.Load(pcmBytes, 44100u, 1u);
// shot.Play();                       // and again, over the top of itself
// ```
//
// What is added over the raw layer is the bookkeeping that a voice makes
// necessary and nothing else:
//
// - **The samples are kept alive.** XAudio2 reads from the buffer a program
//   submitted until it has finished playing it, and a Stainless array with no
//   reference left is gone long before that. A `Sound` holds its own.
// - **Voices are destroyed in the right order.** A source voice must go before
//   the mastering voice it sends to, and a mastering voice before the engine.
//   That is what the destructors here arrange.
// - **A voice per playing copy.** One source voice plays one sound at a time,
//   so a sound that has to overlap itself needs several. `Sound.Play` takes
//   the first free one.
module Win32.Sound;

import Standard.Text;
import Standard.Collections;
import Standard.Com;
import Win32.Ole32;
import Win32.XAudio2;

#if WINDOWS

#pragma comment(lib, "xaudio2")
#pragma comment(lib, "ole32")

/// `RPC_E_CHANGED_MODE`: this thread's apartment is already up and is a
/// different kind. COM is usable; what must not happen is a `CoUninitialize`
/// balancing a call that did not take.
const int ChangedMode = 0x80010106;

/// How many voices a `Sound` keeps, and therefore how many copies of it can
/// be heard at once. Eight is what a footstep needs and more than a music
/// track ever will.
const nuint VoicesPerSound = 8u;

/// Why a sound did not happen.
public enum SoundError
{
    /// XAudio2 would not start. On Windows 10 and later this means the audio
    /// service is not running; before that it means `xaudio2_9.dll` is not
    /// installed.
    NoEngine,

    /// There is no output device, or the engine could not open one.
    NoDevice,

    /// The format is not one XAudio2 takes: the channels or the rate are
    /// outside its range, or the bit depth is not 8, 16, 24 or 32.
    Format,

    /// A voice could not be created, which in practice means the engine has
    /// run out of them.
    NoVoice,

    /// The buffer was empty, or longer than a voice will take.
    Length,
}

/// The engine and its mastering voice: one per program.
///
/// **Order matters at the end.** The mastering voice is destroyed by this
/// object's destructor, and every `Sound` made from it must be gone first --
/// which is what keeping the engine alive in each `Sound` arranges, since ARC
/// will not drop the mixer while a sound still names it.
public sealed class Mixer
{
    IXAudio2 _engine;
    IXAudio2MasteringVoice _master;
    uint _channels;
    uint _rate;
    bool _ownsApartment;
    bool _closed;

    Mixer(IXAudio2 engine, IXAudio2MasteringVoice master, uint channels, uint rate,
          bool ownsApartment)
    {
        _engine = engine;
        _master = master;
        _channels = channels;
        _rate = rate;
        _ownsApartment = ownsApartment;
        _closed = false;
    }

    ~Mixer()
    {
        Close();
    }

    /// The engine, started, with a mastering voice on the default endpoint.
    ///
    /// **It brings COM up itself.** `XAudio2Create` is an ordinary export and
    /// needs nothing -- but the mastering voice reaches the endpoint through
    /// MMDevice, which is COM, and on a thread with no apartment it fails with
    /// nothing to say why. Rather than make every caller remember, this enters
    /// a free-threaded apartment and leaves it in `Close`. A thread that is
    /// already in a single-threaded one is left alone: COM is up, it is
    /// somebody else's, and tearing it down here would take it from them.
    public static Result<Mixer, SoundError> Start()
    {
        bool owned = false;
        int apartment = CoInitializeEx(null, MultiThreaded);
        if (apartment < 0 && apartment != ChangedMode)
            return Fail(SoundError.NoDevice);
        if (apartment >= 0)
            owned = true;

        byte* raw = null;
        if (XAudio2Create(&raw, 0u, XAUDIO2_DEFAULT_PROCESSOR) < 0 || raw == null)
        {
            if (owned)
                CoUninitialize();
            return Fail(SoundError.NoEngine);
        }

        var engine = (IXAudio2)raw;

        byte* masterRaw = null;
        int code = engine.CreateMasteringVoice(&masterRaw, XAUDIO2_DEFAULT_CHANNELS,
                                               XAUDIO2_DEFAULT_SAMPLERATE, 0u,
                                               null, null, 0);
        if (code < 0 || masterRaw == null)
        {
            if (owned)
                CoUninitialize();
            return Fail(SoundError.NoDevice);
        }

        var master = (IXAudio2MasteringVoice)masterRaw;

        XAUDIO2_VOICE_DETAILS details;
        master.GetVoiceDetails(&details);

        return Ok(new Mixer(engine, master, details.InputChannels,
                            details.InputSampleRate, owned));
    }

    /// How many channels the device has: 2 for a pair of speakers, 6 or 8 for
    /// surround.
    public uint Channels => _channels;

    /// What rate the device mixes at. A sound at a different rate is
    /// resampled by the engine rather than refused.
    public uint SampleRate => _rate;

    /// Whether the engine is still up.
    public bool IsOpen => !_closed;

    /// Everything, quieter. 1.0 is unchanged and 0.0 is silence; above 1.0
    /// amplifies and will clip.
    public bool SetVolume(float volume)
    {
        if (_closed)
            return false;
        return _master.SetVolume(volume, XAUDIO2_COMMIT_NOW) >= 0;
    }

    /// A sound, ready to play, over 16-bit PCM samples.
    ///
    /// The array is kept by the `Sound` and must not be written to while it is
    /// playing -- XAudio2 reads the bytes rather than copying them, which is
    /// what makes submitting one free.
    public Result<Sound, SoundError> Load(byte[] samples, uint sampleRate, uint channels)
    {
        if (_closed)
            return Fail(SoundError.NoEngine);
        if (samples.Length == 0u)
            return Fail(SoundError.Length);
        if (channels == 0u || channels > 8u ||
            sampleRate < XAUDIO2_MIN_SAMPLE_RATE || sampleRate > XAUDIO2_MAX_SAMPLE_RATE)
            return Fail(SoundError.Format);

        WAVEFORMATEX format;
        format.wFormatTag = WAVE_FORMAT_PCM;
        format.nChannels = (ushort)channels;
        format.nSamplesPerSec = sampleRate;
        format.nBlockAlign = (ushort)(channels * 2u);
        format.nAvgBytesPerSec = sampleRate * (uint)format.nBlockAlign;
        format.wBitsPerSample = (ushort)16;
        format.cbSize = (ushort)0;

        var voices = new List<IXAudio2SourceVoice>();
        for (nuint i = 0u; i < VoicesPerSound; i++)
        {
            byte* voiceRaw = null;
            int code = _engine.CreateSourceVoice(&voiceRaw, &format, 0u,
                                                 XAUDIO2_DEFAULT_FREQ_RATIO,
                                                 null, null, null);
            if (code < 0 || voiceRaw == null)
            {
                // Whatever was made before this is destroyed rather than left
                // to the engine: a voice nothing names is a voice nothing can
                // destroy, and the engine keeps it until it shuts down.
                for (nuint made = 0u; made < voices.Count; made++)
                    voices.At(made).DestroyVoice();
                return Fail(SoundError.NoVoice);
            }

            voices.Add((IXAudio2SourceVoice)voiceRaw);
        }

        return Ok(new Sound(this, voices, samples));
    }

    /// Stops the engine and destroys the mastering voice. Idempotent, and the
    /// destructor calls it.
    public void Close()
    {
        if (_closed)
            return;
        _closed = true;

        _engine.StopEngine();
        _master.DestroyVoice();

        if (_ownsApartment)
        {
            CoUninitialize();
            _ownsApartment = false;
        }
    }
}

/// Samples and the voices that play them.
///
/// **Destroying it destroys its voices**, which is why it holds the `Mixer`:
/// ARC will not drop the mastering voice while a sound that sends to it is
/// still alive.
public sealed class Sound
{
    Mixer _mixer;
    List<IXAudio2SourceVoice> _voices;
    byte[] _samples;
    nuint _next;
    bool _closed;

    Sound(Mixer mixer, List<IXAudio2SourceVoice> voices, byte[] samples)
    {
        _mixer = mixer;
        _voices = voices;
        _samples = samples;
        _next = 0u;
        _closed = false;
    }

    ~Sound()
    {
        Close();
    }

    /// How long it lasts, in seconds, at the rate it was loaded with.
    public double Duration
    {
        get
        {
            XAUDIO2_VOICE_DETAILS details;
            _voices.At(0u).GetVoiceDetails(&details);
            if (details.InputSampleRate == 0u || details.InputChannels == 0u)
                return 0.0;

            nuint frames = _samples.Length / (2u * (nuint)details.InputChannels);
            return (double)frames / (double)details.InputSampleRate;
        }
    }

    /// Plays it, over the top of any copy already playing.
    ///
    /// Takes the first voice with nothing queued, or the oldest one if every
    /// voice is busy -- which is what a game wants when the same footstep
    /// happens nine times: the tenth interrupts the first rather than being
    /// dropped.
    public bool Play() => Play(1.0f, 1.0f);

    /// The same, at a volume and a pitch. 1.0 is unchanged for both; a pitch
    /// of 2.0 is an octave up and twice as fast, and the range is capped at
    /// what the voice was created with.
    public bool Play(float volume, float pitch)
    {
        if (_closed)
            return false;

        var voice = Free();

        // Stopped and flushed first: a voice that is still playing refuses a
        // second buffer at the position this one wants.
        voice.Stop(0u, XAUDIO2_COMMIT_NOW);
        voice.FlushSourceBuffers();

        XAUDIO2_BUFFER buffer;
        buffer.Flags = XAUDIO2_END_OF_STREAM;
        buffer.AudioBytes = (uint)_samples.Length;
        buffer.pAudioData = &_samples[0u];
        buffer.PlayBegin = 0u;
        buffer.PlayLength = 0u;
        buffer.LoopBegin = 0u;
        buffer.LoopLength = 0u;
        buffer.LoopCount = 0u;
        buffer.pContext = null;

        if (voice.SubmitSourceBuffer(&buffer, null) < 0)
            return false;

        voice.SetVolume(volume, XAUDIO2_COMMIT_NOW);
        voice.SetFrequencyRatio(pitch, XAUDIO2_COMMIT_NOW);
        return voice.Start(0u, XAUDIO2_COMMIT_NOW) >= 0;
    }

    /// Plays it over and over until `Stop`.
    public bool Loop() => Loop(1.0f);

    /// The same, at a volume.
    public bool Loop(float volume)
    {
        if (_closed)
            return false;

        var voice = Free();
        voice.Stop(0u, XAUDIO2_COMMIT_NOW);
        voice.FlushSourceBuffers();

        XAUDIO2_BUFFER buffer;
        buffer.Flags = 0u;
        buffer.AudioBytes = (uint)_samples.Length;
        buffer.pAudioData = &_samples[0u];
        buffer.PlayBegin = 0u;
        buffer.PlayLength = 0u;
        buffer.LoopBegin = 0u;
        buffer.LoopLength = 0u;
        buffer.LoopCount = XAUDIO2_LOOP_INFINITE;
        buffer.pContext = null;

        if (voice.SubmitSourceBuffer(&buffer, null) < 0)
            return false;

        voice.SetVolume(volume, XAUDIO2_COMMIT_NOW);
        return voice.Start(0u, XAUDIO2_COMMIT_NOW) >= 0;
    }

    /// Stops every copy of it at once.
    public void Stop()
    {
        if (_closed)
            return;

        for (nuint i = 0u; i < _voices.Count; i++)
        {
            _voices.At(i).Stop(0u, XAUDIO2_COMMIT_NOW);
            _voices.At(i).FlushSourceBuffers();
        }
    }

    /// Whether any copy of it is still playing.
    public bool IsPlaying
    {
        get
        {
            if (_closed)
                return false;

            for (nuint i = 0u; i < _voices.Count; i++)
            {
                XAUDIO2_VOICE_STATE state;
                _voices.At(i).GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
                if (state.BuffersQueued > 0u)
                    return true;
            }

            return false;
        }
    }

    /// Destroys the voices. Idempotent, and the destructor calls it.
    public void Close()
    {
        if (_closed)
            return;
        _closed = true;

        for (nuint i = 0u; i < _voices.Count; i++)
        {
            _voices.At(i).Stop(0u, XAUDIO2_COMMIT_NOW);
            _voices.At(i).DestroyVoice();
        }
    }

    /// The first voice with nothing queued, or the next one round if every one
    /// is busy.
    IXAudio2SourceVoice Free()
    {
        for (nuint i = 0u; i < _voices.Count; i++)
        {
            XAUDIO2_VOICE_STATE state;
            _voices.At(i).GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
            if (state.BuffersQueued == 0u)
                return _voices.At(i);
        }

        var oldest = _voices.At(_next);
        _next = (_next + 1u) % _voices.Count;
        return oldest;
    }
}

/// A filter cutoff in hertz, as XAudio2's coefficient.
///
/// `XAUDIO2_FILTER_PARAMETERS.Frequency` is not a frequency: it is
/// `2 * sin(pi * cutoff / sampleRate)`, which is what the one-pole filter
/// actually uses. Getting that wrong gives a filter that does nothing or one
/// that removes everything, and neither says why.
public float FrequencyFromHertz(double cutoff, uint sampleRate)
{
    if (sampleRate == 0u)
        return 1.0f;

    double ratio = 2.0 * Sine(3.14159265358979311600 * cutoff / (double)sampleRate);
    if (ratio > 1.0)
        ratio = 1.0;
    if (ratio < 0.0)
        ratio = 0.0;
    return (float)ratio;
}

extern "C" double sin(double x);

double Sine(double x) => sin(x);

#endif
