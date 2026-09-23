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

// =============================================================== the format

/// What the samples are: how fast, how many channels, how wide.
///
/// A struct of three numbers, because that is what every platform's format
/// descriptor holds and what a WAV header carries. Anything a device will not
/// take is reported by `AudioPlayer.Open` rather than refused here -- what a
/// sound card accepts is not knowable from the numbers alone.
///
/// @see AudioPlayer.Open
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
    ///
    /// @param sampleRate  frames per second: 44100 for a CD, 8000 for a
    ///                    telephone
    /// @param channels    1 for mono, 2 for stereo, and nothing else
    /// @param bits        8 or 16, the width of one sample
    public static AudioFormat Create(uint sampleRate, ushort channels, ushort bits)
    {
        AudioFormat format;
        format.SampleRate = sampleRate;
        format.Channels = channels;
        format.BitsPerSample = bits;
        return format;
    }

    /// 44.1 kHz, sixteen bits, stereo: what a CD is and what a WAV file
    /// usually holds.
    public static AudioFormat Cd => AudioFormat.Create(44100u, (ushort)2, (ushort)16);

    /// 48 kHz, sixteen bits, stereo: what most sound hardware runs at without
    /// resampling, and what to prefer when nothing else decides.
    public static AudioFormat Studio => AudioFormat.Create(48000u, (ushort)2, (ushort)16);

    /// 16 kHz, sixteen bits, mono: enough for speech and a quarter of the
    /// bytes.
    public static AudioFormat Voice => AudioFormat.Create(16000u, (ushort)1, (ushort)16);

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
