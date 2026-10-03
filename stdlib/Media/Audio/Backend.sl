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

module Standard.Media.Audio;

import Standard.Text;

#if WINDOWS

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

    /// `CLSID_MMDeviceEnumerator`, written out rather than parsed, so there is
    /// no failure to handle for a constant.
    Guid EnumeratorClassId()
    {
        return new Guid(0xBCDE0395u, (ushort)0xE52F, (ushort)0x467C,
            (byte)0x8E, (byte)0x3D, (byte)0xC4, (byte)0x57, (byte)0x92, (byte)0x91, (byte)0x69, (byte)0x2E);
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

#elif MACOS

/// AudioQueue, behind the calls the ALSA backend answers, so the player and the
/// recorder are the same code on both. A write blocks until a buffer is free
/// and a read until one is full, each polling as the Windows path does.
threadsafe sealed class Backend
{
    /// Linked, so always there.
    public bool Ready;

    public Backend()
    {
        Ready = true;
    }

    public bool CanPlay => HasDefaultDevice(DefaultOutputDevice);

    public bool CanRecord => HasDefaultDevice(DefaultInputDevice);

    /// A queue for this format, its buffers allocated; a recording queue's
    /// are handed to it at once, so sound starts filling them on `Start`.
    public int Open(void** pcm, AudioFormat format, bool capture)
    {
        StreamDescription described;
        described.SampleRate = (double)format.SampleRate;
        described.FormatId = FormatLinearPcm;
        described.FormatFlags = FlagPacked | (format.BitsPerSample == 16u ? FlagSignedInteger : 0u);
        described.BytesPerPacket = (uint)format.BytesPerFrame;
        described.FramesPerPacket = 1u;
        described.BytesPerFrame = (uint)format.BytesPerFrame;
        described.ChannelsPerFrame = (uint)format.Channels;
        described.BitsPerChannel = (uint)format.BitsPerSample;
        described.Reserved = 0u;

        var state = (QueueState*)calloc(1u, sizeof(QueueState));
        if (state == null)
            return -1;

        int status = capture
            ? AudioQueueNewInput(&described, MarkBufferRecorded, null, null, null, 0u, &(*state).Queue)
            : AudioQueueNewOutput(&described, MarkBufferPlayed, null, null, null, 0u, &(*state).Queue);
        if (status != 0)
        {
            free((byte*)state);
            return -1;
        }

        nuint frame = format.BytesPerFrame;
        nuint bytes = (nuint)format.BytesPerSecond * (nuint)BufferMilliseconds / 1000u / (nuint)QueueBuffers;
        (*state).FrameSize = (uint)frame;
        (*state).BufferBytes = (uint)(bytes - bytes % frame);

        for (int i = 0; i < QueueBuffers; i++)
        {
            QueueBuffer* buffer = null;
            if (AudioQueueAllocateBuffer((*state).Queue, (*state).BufferBytes, &buffer) != 0)
            {
                AudioQueueDispose((*state).Queue, 1);
                free((byte*)state);
                return -1;
            }

            (*buffer).UserData = (void*)QueueFlagAt(state, i);
            switch (i)
            {
                case 0:
                    (*state).First = buffer;
                    break;
                case 1:
                    (*state).Second = buffer;
                    break;
                default:
                    (*state).Third = buffer;
                    break;
            }

            *QueueFlagAt(state, i) = capture ? 0 : 1;
            if (capture)
                AudioQueueEnqueueBuffer((*state).Queue, buffer, 0u, null);
        }

        *pcm = (void*)state;
        return 0;
    }

    /// Frames played, blocking until a buffer is free for each piece; the
    /// queue starts once all three are full, so it never starts on a gap.
    public nint WriteFrames(void* pcm, byte* samples, nuint frames)
    {
        var state = (QueueState*)pcm;
        nuint total = frames * (nuint)(*state).FrameSize;
        nuint done = 0u;

        while (done < total)
        {
            int index = (*state).Next;
            int* back = QueueFlagAt(state, index);
            if (sl_atomic_load32(back) == 0)
            {
                if (!(*state).Started)
                {
                    if (AudioQueueStart((*state).Queue, null) != 0)
                        return -1;
                    (*state).Started = true;
                }
                sl_thread_sleep(PollMilliseconds);
                continue;
            }

            QueueBuffer* buffer = QueueBufferAt(state, index);
            nuint take = total - done;
            if (take > (nuint)(*state).BufferBytes)
                take = (nuint)(*state).BufferBytes;

            memcpy((*buffer).Data, samples + done, take);
            (*buffer).Size = (uint)take;
            sl_atomic_store32(back, 0);
            if (AudioQueueEnqueueBuffer((*state).Queue, buffer, 0u, null) != 0)
            {
                sl_atomic_store32(back, 1);
                return -1;
            }

            (*state).Next = (index + 1) % QueueBuffers;
            done += take;
        }

        return (nint)frames;
    }

    /// Frames of what was heard, blocking until a buffer holds some; none once
    /// the queue has been stopped and every buffer read.
    public nint ReadFrames(void* pcm, byte* samples, nuint frames)
    {
        var state = (QueueState*)pcm;
        nuint frame = (nuint)(*state).FrameSize;

        while (true)
        {
            int index = (*state).Next;
            int* back = QueueFlagAt(state, index);
            if (sl_atomic_load32(back) == 0)
            {
                if (!(*state).Started)
                    return 0;
                sl_thread_sleep(PollMilliseconds);
                continue;
            }

            QueueBuffer* buffer = QueueBufferAt(state, index);
            nuint left = (nuint)(*buffer).Size - (nuint)(*state).ReadAt;
            nuint take = frames * frame;
            if (take > left)
                take = left - left % frame;

            if (take > 0u)
                memcpy(samples, (*buffer).Data + (nuint)(*state).ReadAt, take);
            (*state).ReadAt += (uint)take;

            // Read to its end: given back to the queue to fill again.
            if ((nuint)(*state).ReadAt + frame > (nuint)(*buffer).Size)
            {
                (*state).ReadAt = 0u;
                (*buffer).Size = 0u;
                sl_atomic_store32(back, 0);
                AudioQueueEnqueueBuffer((*state).Queue, buffer, 0u, null);
                (*state).Next = (index + 1) % QueueBuffers;
            }

            if (take > 0u)
                return (nint)(take / frame);
        }
    }

    /// Returns once every buffer written has been played.
    public int Drain(void* pcm)
    {
        var state = (QueueState*)pcm;
        bool waiting = false;
        for (int i = 0; i < QueueBuffers; i++)
            if (sl_atomic_load32(QueueFlagAt(state, i)) == 0)
                waiting = true;
        if (!waiting)
            return 0;

        if (!(*state).Started)
        {
            if (AudioQueueStart((*state).Queue, null) != 0)
                return -1;
            (*state).Started = true;
        }

        for (int i = 0; i < QueueBuffers; i++)
            while (sl_atomic_load32(QueueFlagAt(state, i)) == 0)
                sl_thread_sleep(PollMilliseconds);

        AudioQueueStop((*state).Queue, 1);
        (*state).Started = false;
        return 0;
    }

    /// Stops at once. Every buffer is AudioQueue's no longer, so a player's
    /// are free and a recorder's are given back by `Prepare`.
    public int Drop(void* pcm)
    {
        var state = (QueueState*)pcm;
        AudioQueueStop((*state).Queue, 1);
        (*state).Started = false;
        for (int i = 0; i < QueueBuffers; i++)
            sl_atomic_store32(QueueFlagAt(state, i), 1);
        (*state).Next = 0;
        (*state).ReadAt = 0u;
        return 0;
    }

    /// Hands a recorder's buffers back to its queue, so `Start` has somewhere
    /// to put sound. A player's need nothing.
    public int Prepare(void* pcm)
    {
        var state = (QueueState*)pcm;
        for (int i = 0; i < QueueBuffers; i++)
        {
            int* back = QueueFlagAt(state, i);
            if (sl_atomic_load32(back) == 0)
                continue;

            QueueBuffer* buffer = QueueBufferAt(state, i);
            (*buffer).Size = 0u;
            sl_atomic_store32(back, 0);
            AudioQueueEnqueueBuffer((*state).Queue, buffer, 0u, null);
        }
        (*state).Next = 0;
        (*state).ReadAt = 0u;
        return 0;
    }

    public int Start(void* pcm)
    {
        var state = (QueueState*)pcm;
        if (AudioQueueStart((*state).Queue, null) != 0)
            return -1;
        (*state).Started = true;
        return 0;
    }

    /// Disposed at once, which waits for any callback in progress, so the
    /// state it writes into can go.
    public int Close(void* pcm)
    {
        var state = (QueueState*)pcm;
        AudioQueueDispose((*state).Queue, 1);
        free((byte*)state);
        return 0;
    }

    /// Nothing AudioQueue reports can be recovered from by asking again.
    public int Recover(void* pcm, int error) => -1;
}

#else

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
