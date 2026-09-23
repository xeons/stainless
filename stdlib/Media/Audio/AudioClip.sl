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

// =================================================================== a clip

/// Samples in memory, and what they are.
///
/// The unit `Wav` reads and writes and `Audio.PlayClip` takes. It is bytes rather
/// than a typed sample array deliberately: the width is in the format, a
/// conversion on the way in would cost a copy of every sound a program loads,
/// and the platform wants bytes at the end of it anyway. `GetSample` and
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
    public static AudioClip CreateSilence(AudioFormat format, nuint frames)
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
    ///
    /// @param frame    which frame, counting from zero
    /// @param channel  which channel of it, 0 or 1
    /// @see AudioClip.SetSample
    public int GetSample(nuint frame, nuint channel)
    {
        nuint at = FindSampleOffset(frame, channel);
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

    /// One sample written, taking the same range `GetSample` answers in and
    /// clamping to it. A sample wider than sixteen bits has its top sixteen
    /// set and the bits below them cleared. Out of range does nothing.
    ///
    /// @param frame    which frame, counting from zero
    /// @param channel  which channel of it, 0 or 1
    /// @param value    the sample, -32768 to 32767, clamped to that
    /// @see AudioClip.GetSample
    public void SetSample(nuint frame, nuint channel, int value)
    {
        nuint at = FindSampleOffset(frame, channel);
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
    nuint FindSampleOffset(nuint frame, nuint channel)
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
