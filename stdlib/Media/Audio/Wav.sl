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
    ///
    /// @failure AudioError.Format     a WAVE that is not uncompressed PCM, or
    ///                                whose rate, channel count or width is
    ///                                not one this module handles
    /// @failure AudioError.Malformed  not a RIFF/WAVE at all, or one with no
    ///                                `fmt ` chunk before its `data`
    /// @see Wav.Encode
    public static Result<AudioClip, AudioError> Decode(byte[] bytes)
    {
        if (bytes.Length < 44u)
            return Fail(AudioError.Malformed);

        if (!HasMarkAt(bytes, 0u, "RIFF") || !HasMarkAt(bytes, 8u, "WAVE"))
            return Fail(AudioError.Malformed);

        AudioFormat format = AudioFormat.Create(0u, (ushort)0, (ushort)0);
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

            if (HasMarkAt(bytes, at, "fmt ") && size >= 16u)
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
            else if (HasMarkAt(bytes, at, "data"))
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
    ///
    /// @see Wav.Decode
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
    ///
    /// @failure AudioError.Format     a WAVE that is not uncompressed PCM, or
    ///                                one shaped in a way this module does not
    ///                                handle
    /// @failure AudioError.Malformed  not a RIFF/WAVE at all
    /// @failure AudioError.IO         the file could not be read; the
    ///                                `IOError` behind it is not carried
    /// @see Wav.Save
    public static Result<AudioClip, AudioError> FromFile(String path)
    {
        var read = File.ReadAllBytes(path);
        if (!read.Ok)
            return Fail(AudioError.IO);
        return Decode(read.Value);
    }

    /// A clip written to a `.wav` on disk.
    ///
    /// @failure AudioError.IO  the file could not be written; the `IOError`
    ///                         behind it is not carried
    /// @see Wav.FromFile
    public static Result<bool, AudioError> Save(AudioClip clip, String path)
    {
        if (File.WriteAllBytes(path, Encode(clip)) != IOError.None)
            return Fail(AudioError.IO);
        return Ok(true);
    }

    static bool HasMarkAt(byte[] bytes, nuint at, String mark)
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
