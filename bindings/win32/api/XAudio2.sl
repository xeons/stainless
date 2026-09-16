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

// xaudio2_9.dll: the mixer a game plays through.
//
// Declarations and nothing else, spelled as `xaudio2.h` spells them. The method
// order *is* the vtable, so nothing here may be reordered or removed.
//
// **Two kinds of vtable, and the difference is load-bearing.** `IXAudio2` is a
// COM object: it derives from `IUnknown`, it is counted, and ARC releases it.
// A *voice* is not. `IXAudio2Voice` derives from nothing, its own first method
// is slot 0, and a voice ends when `DestroyVoice` is called rather than when a
// count reaches zero -- so the voice interfaces carry `[NoUnknown]`, and
// §8.5 of the spec is what that means. Reaching a voice through an ordinary
// `com interface` would call `SetOutputVoices` where ARC expected `AddRef`.
//
// **Why this and not `Standard.Media.Audio`.** That module opens a device and
// writes samples to it, which is what a program that wants to play a sound
// needs. This is a mixer: many voices at once, each with its own rate, volume,
// filter and effect chain, submixed into buses and out through a mastering
// voice, with a callback when a buffer runs dry. A game wants it and a utility
// does not.
//
// **2.9, in the box.** Windows 10 and later ship `xaudio2_9.dll` and there is
// nothing to redistribute. Windows 7 had 2.7 with a DirectX SDK redistributable
// and a different activation path -- `CoCreateInstance` rather than
// `XAudio2Create` -- and none of that is bound.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l xaudio2`, or `Win32.Sound`, which
// names it with a pragma.
module Win32.XAudio2;

import Standard.Com;

#if WINDOWS

// ================================================================== formats

/// `WAVEFORMATEX`, which `mmreg.h` declares under `#pragma pack(1)` -- so it
/// is eighteen bytes and not twenty, and the attribute is what says so.
///
/// Declared here as well as in `Standard.Media.Audio` because a binding must
/// be usable without the standard library's audio module, and a struct is not
/// a symbol anybody links.
[Packed]
public struct WAVEFORMATEX
{
    public ushort wFormatTag;
    public ushort nChannels;
    public uint nSamplesPerSec;
    public uint nAvgBytesPerSec;
    public ushort nBlockAlign;
    public ushort wBitsPerSample;
    public ushort cbSize;
}

/// `WAVE_FORMAT_PCM`.
public const ushort WAVE_FORMAT_PCM = 1u;

/// `WAVE_FORMAT_IEEE_FLOAT`: 32-bit float samples, which is what XAudio2 mixes
/// in and the format to prefer when the source is being generated rather than
/// loaded.
public const ushort WAVE_FORMAT_IEEE_FLOAT = 3u;

// ================================================================== structs

/// `XAUDIO2_VOICE_DETAILS`: what a voice was made as.
public struct XAUDIO2_VOICE_DETAILS
{
    public uint CreationFlags;
    public uint ActiveFlags;
    public uint InputChannels;
    public uint InputSampleRate;
}

/// `XAUDIO2_SEND_DESCRIPTOR`: one destination in a send list.
public struct XAUDIO2_SEND_DESCRIPTOR
{
    public uint Flags;
    public byte* pOutputVoice;
}

/// `XAUDIO2_VOICE_SENDS`: where a voice's output goes. A voice made with none
/// sends to the mastering voice, which is what most of them want.
public struct XAUDIO2_VOICE_SENDS
{
    public uint SendCount;
    public XAUDIO2_SEND_DESCRIPTOR* pSends;
}

/// `XAUDIO2_EFFECT_DESCRIPTOR`: one XAPO in a chain.
public struct XAUDIO2_EFFECT_DESCRIPTOR
{
    public byte* pEffect;
    public int InitialState;
    public uint OutputChannels;
}

/// `XAUDIO2_EFFECT_CHAIN`.
public struct XAUDIO2_EFFECT_CHAIN
{
    public uint EffectCount;
    public XAUDIO2_EFFECT_DESCRIPTOR* pEffectDescriptors;
}

/// `XAUDIO2_FILTER_PARAMETERS`: a one-pole filter on a voice.
///
/// `Frequency` is not hertz. It is `2 * sin(pi * cutoff / sampleRate)`, which
/// is the coefficient the filter actually uses; `FrequencyFromHertz` in
/// `Win32.Sound` does the conversion.
public struct XAUDIO2_FILTER_PARAMETERS
{
    public int Type;
    public float Frequency;
    public float OneOverQ;
}

/// `XAUDIO2_BUFFER`: a block of samples handed to a source voice.
///
/// **The bytes are not copied.** XAudio2 reads from `pAudioData` until the
/// buffer has been played, so whatever holds those bytes has to outlive the
/// submission -- a Stainless array reference kept somewhere the voice's
/// lifetime covers. `pContext` comes back in the callback and is how a program
/// knows which one finished.
public struct XAUDIO2_BUFFER
{
    public uint Flags;
    public uint AudioBytes;
    public byte* pAudioData;
    public uint PlayBegin;
    public uint PlayLength;
    public uint LoopBegin;
    public uint LoopLength;
    public uint LoopCount;
    public byte* pContext;
}

/// `XAUDIO2_BUFFER_WMA`: the seek table an xWMA stream needs. Declared so the
/// parameter it fills has a type; nothing here decodes xWMA.
public struct XAUDIO2_BUFFER_WMA
{
    public uint* pDecodedPacketCumulativeBytes;
    public uint PacketCount;
}

/// `XAUDIO2_VOICE_STATE`: what a source voice is doing now.
///
/// `BuffersQueued` reaching zero is how a program that is streaming knows to
/// submit more, and `SamplesPlayed` is the position -- in the voice's own
/// sample rate, counting from when the voice started rather than from the
/// current buffer.
public struct XAUDIO2_VOICE_STATE
{
    public byte* pCurrentBufferContext;
    public uint BuffersQueued;
    public ulong SamplesPlayed;
}

/// `XAUDIO2_PERFORMANCE_DATA`: what the engine is costing.
public struct XAUDIO2_PERFORMANCE_DATA
{
    public ulong AudioCyclesSinceLastQuery;
    public ulong TotalCyclesSinceLastQuery;
    public uint MinimumCyclesPerQuantum;
    public uint MaximumCyclesPerQuantum;
    public uint MemoryUsageInBytes;
    public uint CurrentLatencyInSamples;
    public uint GlitchesSinceEngineStarted;
    public uint ActiveSourceVoiceCount;
    public uint TotalSourceVoiceCount;
    public uint ActiveSubmixVoiceCount;
    public uint ActiveResamplerCount;
    public uint ActiveMatrixMixCount;
    public uint ActiveXmaSourceVoices;
    public uint ActiveXmaStreams;
}

/// `XAUDIO2_DEBUG_CONFIGURATION`: what the debug build of the engine reports.
public struct XAUDIO2_DEBUG_CONFIGURATION
{
    public uint TraceMask;
    public uint BreakMask;
    public int LogThreadID;
    public int LogFileline;
    public int LogFunctionName;
    public int LogTiming;
}

// =============================================================== the engine

/// The XAudio2 engine: a real COM object, counted, and released by ARC.
///
/// Everything else in this module hangs off it. `CreateMasteringVoice` first
/// -- nothing is heard without one -- then a source voice per sound.
[Guid("2B02E3CF-2E0B-4EC3-BE45-1B2A3FE7210D")]
public com interface IXAudio2
{
    int RegisterForCallbacks(byte* pCallback);
    void UnregisterForCallbacks(byte* pCallback);

    // `pSourceFormat` decides what the voice takes for the whole of its life;
    // a sound in a different format needs a different voice. `MaxFrequencyRatio`
    // caps how far `SetFrequencyRatio` may go and costs memory, so 2.0 is the
    // usual answer rather than the maximum.
    int CreateSourceVoice(byte** ppSourceVoice, WAVEFORMATEX* pSourceFormat,
                          uint Flags, float MaxFrequencyRatio, byte* pCallback,
                          XAUDIO2_VOICE_SENDS* pSendList,
                          XAUDIO2_EFFECT_CHAIN* pEffectChain);

    int CreateSubmixVoice(byte** ppSubmixVoice, uint InputChannels,
                          uint InputSampleRate, uint Flags, uint ProcessingStage,
                          XAUDIO2_VOICE_SENDS* pSendList,
                          XAUDIO2_EFFECT_CHAIN* pEffectChain);

    // `szDeviceId` null means the default endpoint, which is what a program
    // should pass unless a user has chosen otherwise.
    int CreateMasteringVoice(byte** ppMasteringVoice, uint InputChannels,
                             uint InputSampleRate, uint Flags, char16* szDeviceId,
                             XAUDIO2_EFFECT_CHAIN* pEffectChain, int StreamCategory);

    int StartEngine();
    void StopEngine();

    // An operation set is a batch: calls tagged with the same number take
    // effect together on the next `CommitChanges`, which is how several voices
    // start on the same sample.
    int CommitChanges(uint OperationSet);

    void GetPerformanceData(XAUDIO2_PERFORMANCE_DATA* pPerfData);
    void SetDebugConfiguration(XAUDIO2_DEBUG_CONFIGURATION* pDebugConfiguration,
                               byte* pReserved);
}

// ================================================================== voices

/// Everything every voice can do: slots 0 to 18, and **no IUnknown**.
///
/// A voice is not a COM object. It has no QueryInterface, no AddRef and no
/// Release; it is created by the engine and ends when `DestroyVoice` is
/// called, and until then the engine owns it. `[NoUnknown]` is what says that
/// to the compiler, and ARC leaves such a reference alone -- see §8.5.
///
/// **Destroying a voice that something still sends to is undefined.** Destroy
/// the source voices first, then the submixes, then the mastering voice.
[NoUnknown]
public com interface IXAudio2Voice
{
    void GetVoiceDetails(XAUDIO2_VOICE_DETAILS* pVoiceDetails);
    int SetOutputVoices(XAUDIO2_VOICE_SENDS* pSendList);
    int SetEffectChain(XAUDIO2_EFFECT_CHAIN* pEffectChain);
    int EnableEffect(uint EffectIndex, uint OperationSet);
    int DisableEffect(uint EffectIndex, uint OperationSet);
    void GetEffectState(uint EffectIndex, int* pEnabled);
    int SetEffectParameters(uint EffectIndex, byte* pParameters,
                            uint ParametersByteSize, uint OperationSet);
    int GetEffectParameters(uint EffectIndex, byte* pParameters, uint ParametersByteSize);
    int SetFilterParameters(XAUDIO2_FILTER_PARAMETERS* pParameters, uint OperationSet);
    void GetFilterParameters(XAUDIO2_FILTER_PARAMETERS* pParameters);
    int SetOutputFilterParameters(byte* pDestinationVoice,
                                  XAUDIO2_FILTER_PARAMETERS* pParameters,
                                  uint OperationSet);
    void GetOutputFilterParameters(byte* pDestinationVoice,
                                   XAUDIO2_FILTER_PARAMETERS* pParameters);

    // Amplitude rather than decibels: 1.0 is unchanged, 0.0 is silence, and
    // above 1.0 is amplification that will clip.
    int SetVolume(float Volume, uint OperationSet);
    void GetVolume(float* pVolume);

    int SetChannelVolumes(uint Channels, float* pVolumes, uint OperationSet);
    void GetChannelVolumes(uint Channels, float* pVolumes);

    // The matrix is how a mono source is placed between two speakers, and is
    // the whole of what panning is here.
    int SetOutputMatrix(byte* pDestinationVoice, uint SourceChannels,
                        uint DestinationChannels, float* pLevelMatrix,
                        uint OperationSet);
    void GetOutputMatrix(byte* pDestinationVoice, uint SourceChannels,
                         uint DestinationChannels, float* pLevelMatrix);

    void DestroyVoice();
}

/// A voice that plays submitted buffers: slots 19 and up.
///
/// This is where sound comes from. Everything else in the graph moves it
/// around.
[NoUnknown]
public com interface IXAudio2SourceVoice : IXAudio2Voice
{
    int Start(uint Flags, uint OperationSet);
    int Stop(uint Flags, uint OperationSet);

    // The buffer is queued, not copied. Whatever holds the samples has to
    // outlive the playing.
    int SubmitSourceBuffer(XAUDIO2_BUFFER* pBuffer, XAUDIO2_BUFFER_WMA* pBufferWMA);

    int FlushSourceBuffers();
    int Discontinuity();
    int ExitLoop(uint OperationSet);
    void GetState(XAUDIO2_VOICE_STATE* pVoiceState, uint Flags);

    // Playback rate, and therefore pitch: 2.0 is an octave up and twice as
    // fast. Capped by what the voice was created with.
    int SetFrequencyRatio(float Ratio, uint OperationSet);
    void GetFrequencyRatio(float* pRatio);

    int SetSourceSampleRate(uint NewSourceSampleRate);
}

/// A bus: several voices in, one out. Adds nothing to `IXAudio2Voice`, and is
/// a separate type because the engine's create call is.
[NoUnknown]
public com interface IXAudio2SubmixVoice : IXAudio2Voice
{
}

/// The last voice in the graph, and the one connected to the device. There is
/// one, it is made first, and it is destroyed last.
[NoUnknown]
public com interface IXAudio2MasteringVoice : IXAudio2Voice
{
    int GetChannelMask(uint* pChannelmask);
}

// ============================================================== entry point

public extern "C" __stdcall
{
    // 2.8 and later export this directly; earlier versions were activated
    // through CoCreateInstance, which is not bound.
    int XAudio2Create(byte** ppXAudio2, uint Flags, uint XAudio2Processor);
}

// ================================================================ constants

/// `XAUDIO2_COMMIT_NOW`: take effect at once rather than on a commit.
public const uint XAUDIO2_COMMIT_NOW = 0u;

/// `XAUDIO2_COMMIT_ALL`: commit every pending operation set.
public const uint XAUDIO2_COMMIT_ALL = 0u;

/// `XAUDIO2_INVALID_OPSET`.
public const uint XAUDIO2_INVALID_OPSET = 0xFFFFFFFFu;

/// `XAUDIO2_NO_LOOP_REGION`.
public const uint XAUDIO2_NO_LOOP_REGION = 0u;

/// `XAUDIO2_LOOP_INFINITE`: repeat until stopped.
public const uint XAUDIO2_LOOP_INFINITE = 255u;

/// `XAUDIO2_DEFAULT_CHANNELS` and `XAUDIO2_DEFAULT_SAMPLERATE`: let the engine
/// take the endpoint's own, which is what a mastering voice should be given.
public const uint XAUDIO2_DEFAULT_CHANNELS = 0u;
public const uint XAUDIO2_DEFAULT_SAMPLERATE = 0u;

/// `XAUDIO2_DEFAULT_PROCESSOR`: whichever core the engine chooses.
public const uint XAUDIO2_DEFAULT_PROCESSOR = 0x00000001u;

/// `XAUDIO2_DEBUG_ENGINE`: ask for the debug engine, which reports through
/// `SetDebugConfiguration`. Ignored unless the debug runtime is installed.
public const uint XAUDIO2_DEBUG_ENGINE = 0x0001u;

/// `XAUDIO2_STOP_ENGINE_WHEN_IDLE`: let the engine thread stop when nothing is
/// playing, which matters on a battery.
public const uint XAUDIO2_STOP_ENGINE_WHEN_IDLE = 0x2000u;

/// `XAUDIO2_1024_QUANTUM`: a 21.33 ms processing quantum rather than 10 ms.
public const uint XAUDIO2_1024_QUANTUM = 0x8000u;

// ------------------------------------------------------------- voice flags

/// `XAUDIO2_VOICE_NOPITCH`: no `SetFrequencyRatio` on this voice, and no
/// resampler allocated for it.
public const uint XAUDIO2_VOICE_NOPITCH = 0x0002u;

/// `XAUDIO2_VOICE_NOSRC`: no sample-rate conversion either.
public const uint XAUDIO2_VOICE_NOSRC = 0x0004u;

/// `XAUDIO2_VOICE_USEFILTER`: allocate the filter, which `SetFilterParameters`
/// needs and which costs nothing if it is never set.
public const uint XAUDIO2_VOICE_USEFILTER = 0x0008u;

/// `XAUDIO2_PLAY_TAILS`: on `Stop`, let the effect chain finish its reverb
/// tail rather than cutting it off.
public const uint XAUDIO2_PLAY_TAILS = 0x0020u;

/// `XAUDIO2_END_OF_STREAM`: on a buffer, the last one. The voice's effects run
/// out and `OnStreamEnd` is called.
public const uint XAUDIO2_END_OF_STREAM = 0x0040u;

/// `XAUDIO2_SEND_USEFILTER`: put a filter on this send.
public const uint XAUDIO2_SEND_USEFILTER = 0x0080u;

/// `XAUDIO2_VOICE_NOSAMPLESPLAYED`: `GetState` without the sample count, which
/// is the part that costs.
public const uint XAUDIO2_VOICE_NOSAMPLESPLAYED = 0x0100u;

// ---------------------------------------------------------------- filters

/// `LowPassFilter`: keeps what is below the cutoff. What a sound heard through
/// a wall gets.
public const int LowPassFilter = 0;

/// `BandPassFilter`.
public const int BandPassFilter = 1;

/// `HighPassFilter`.
public const int HighPassFilter = 2;

/// `NotchFilter`.
public const int NotchFilter = 3;

/// `LowPassOnePoleFilter`: cheaper and gentler than the two-pole one.
public const int LowPassOnePoleFilter = 4;

/// `HighPassOnePoleFilter`.
public const int HighPassOnePoleFilter = 5;

// ------------------------------------------------------------------ limits

/// `XAUDIO2_MAX_BUFFER_BYTES`.
public const uint XAUDIO2_MAX_BUFFER_BYTES = 0x80000000u;

/// `XAUDIO2_MAX_QUEUED_BUFFERS`: how many may be submitted to one source voice
/// before it refuses.
public const uint XAUDIO2_MAX_QUEUED_BUFFERS = 64u;

/// `XAUDIO2_MAX_FREQ_RATIO`.
public const float XAUDIO2_MAX_FREQ_RATIO = 1024.0f;

/// `XAUDIO2_DEFAULT_FREQ_RATIO`: what to pass unless the sound is going to be
/// pitched a long way, since the cap costs memory.
public const float XAUDIO2_DEFAULT_FREQ_RATIO = 2.0f;

/// `XAUDIO2_MIN_SAMPLE_RATE` and `XAUDIO2_MAX_SAMPLE_RATE`.
public const uint XAUDIO2_MIN_SAMPLE_RATE = 1000u;
public const uint XAUDIO2_MAX_SAMPLE_RATE = 200000u;

// ---------------------------------------------------------------- results

/// `XAUDIO2_E_INVALID_CALL`.
public const int XAUDIO2_E_INVALID_CALL = 0x88960001;

/// `XAUDIO2_E_XMA_DECODER_ERROR`.
public const int XAUDIO2_E_XMA_DECODER_ERROR = 0x88960002;

/// `XAUDIO2_E_XAPO_CREATION_FAILED`.
public const int XAUDIO2_E_XAPO_CREATION_FAILED = 0x88960003;

/// `XAUDIO2_E_DEVICE_INVALIDATED`: the endpoint went away -- unplugged, or its
/// driver restarted. Everything has to be made again.
public const int XAUDIO2_E_DEVICE_INVALIDATED = 0x88960004;

#endif
