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

    /// The stream and its capture service, on a thread whose apartment is up.
    static Result<AudioRecorder, AudioError> OpenInApartment(Backend found, AudioFormat format,
                                                             bool owned)
    {
        var opened = OpenStream(found, format, FlowCapture);
        if (!opened.Ok)
            return Fail(opened.Error);

        var client = opened.Value;

        byte* raw = null;
        if (client.GetService(iidof(IAudioCaptureClient), &raw) < 0 || raw == null)
            return Fail(AudioError.Device);

        return Ok(new AudioRecorder(client, (IAudioCaptureClient)raw, format, owned));
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
    ///
    /// @failure AudioError.NoBackend  there is no audio library on this machine
    /// @failure AudioError.Format     the format is not one this module handles,
    ///                                or not one the engine would take
    /// @failure AudioError.Device     there is nothing to record from, or the
    ///                                stream would not open
    /// @failure AudioError.Busy       something else has the device in
    ///                                exclusive mode
    /// @see AudioPlayer.Open
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

        // As in `AudioPlayer.Open`: a failure has released its references
        // before the apartment goes.
        var opened = OpenInApartment(found, format, owned);
        if (!opened.Ok && owned)
            found.LeaveApartment();
        return opened;
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
    ///
    /// @failure AudioError.Device  the device would not start
    /// @failure AudioError.Closed  `Close` has already been called
    /// @see AudioRecorder.Read
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
            return Fail(ToAudioError(code));
#else
        // Started here rather than left to the first read, which is when a
        // prepared capture stream would otherwise begin.
        if (found.Prepare(_device) < 0 || found.Start(_device) < 0)
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
