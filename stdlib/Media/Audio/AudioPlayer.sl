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
import Standard.Collections;
import Standard.File;
import Standard.IO;

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
/// player.DrainBuffer();       // and this when it has played them
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

    /// The stream and its render service, on a thread whose apartment is up.
    static Result<AudioPlayer, AudioError> OpenInApartment(Backend found, AudioFormat format,
                                                           bool owned)
    {
        var opened = OpenStream(found, format, FlowRender);
        if (!opened.Ok)
            return Fail(opened.Error);

        var client = opened.Value;

        uint frames = 0u;
        if (client.GetBufferSize(&frames) < 0)
            return Fail(AudioError.Device);

        byte* raw = null;
        if (client.GetService(iidof(IAudioRenderClient), &raw) < 0 || raw == null)
            return Fail(AudioError.Device);

        return Ok(new AudioPlayer(client, (IAudioRenderClient)raw, frames, format, owned));
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
    ///
    /// @failure AudioError.NoBackend  there is no audio library on this machine
    /// @failure AudioError.Format     the format is not one this module handles,
    ///                                or not one the engine would take
    /// @failure AudioError.Device     there is nothing to play through, or the
    ///                                stream would not open
    /// @failure AudioError.Busy       something else has the device in
    ///                                exclusive mode
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

        // The references are taken in a function of their own so that a
        // failure has released them before the apartment goes.
        var opened = OpenInApartment(found, format, owned);
        if (!opened.Ok && owned)
            found.LeaveApartment();
        return opened;
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
    /// have been heard -- `DrainBuffer` is what waits for that. A length that is not
    /// a whole number of frames is refused rather than truncated, because
    /// truncating swaps the channels for the rest of the stream.
    ///
    /// @failure AudioError.Format  the length is not a whole number of frames
    /// @failure AudioError.Device  the device failed or went away while this
    ///                             was writing to it
    /// @failure AudioError.Closed  `Close` has already been called
    /// @see AudioPlayer.DrainBuffer
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
                return Fail(ToAudioError(code));

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
                return Fail(ToAudioError(code));

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
    public void DrainBuffer()
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
