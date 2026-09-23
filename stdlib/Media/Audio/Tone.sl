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
    public static AudioClip CreateSine(AudioFormat format, double frequency,
                                 double seconds, double amplitude)
    {
        var clip = AudioClip.CreateSilence(format, (nuint)(seconds * (double)format.SampleRate));
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
    ///
    /// @param format     what the samples are to be
    /// @param frequency  in hertz
    /// @param seconds    how long it lasts
    /// @param amplitude  0.0 to 1.0, where 1.0 is as loud as the format goes
    /// @see Tone.CreateSine
    public static AudioClip CreateSquare(AudioFormat format, double frequency,
                                   double seconds, double amplitude)
    {
        var clip = AudioClip.CreateSilence(format, (nuint)(seconds * (double)format.SampleRate));
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
    public static AudioClip CreateRest(AudioFormat format, double seconds) =>
        AudioClip.CreateSilence(format, (nuint)(seconds * (double)format.SampleRate));
}
