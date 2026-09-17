// SPDX-License-Identifier: 0BSD
//
// A FastTracker 2 module player.
//
// An `.xm` is a few hundred kilobytes of samples and a list of which note to
// play on which channel on which row. That makes it the format a demo wants:
// three minutes of music in thirty kilobytes, where the same as a WAV is
// thirty megabytes.
//
// **This renders a whole song to PCM rather than streaming it.** A pass over
// the order table produces one buffer, which is then handed to whatever plays
// sound and looped. That costs memory proportional to the song -- about twelve
// megabytes for two and a half minutes of 22 kHz stereo -- and it buys a
// player with no thread, no callback and no timing to get wrong.
//
// What is implemented is what modules actually use, and the list is honest
// about where it stops:
//
//   - notes, instruments, multiple samples per instrument, 8- and 16-bit data
//   - forward loops and no loop; **ping-pong loops are not implemented**
//   - volume envelopes with sustain and loop, and fadeout on key-off
//   - effects 0 arpeggio, 1 and 2 portamento, 3 tone portamento, 4 vibrato,
//     A volume slide, B position jump, C set volume, D pattern break,
//     E1 and E2 fine portamento, EC note cut, ED note delay, F speed and tempo
//   - the volume column's set-volume, slides and tone portamento
//
// **Not implemented**: panning envelopes, tremolo, the auto-vibrato an
// instrument can carry, sample offset, retrigger, multi-retrig, tremor, and
// the Amiga frequency table -- linear frequencies only, which is what every
// FT2-written module uses. A module reaching for one of those plays without
// it rather than failing, which is the wrong answer for a tool and the right
// one for a demo.
module Tracker;

import Standard.Text;
import Standard.Collections;
import Standard.File;
import Standard.IO;
import Standard.Math;

// ==================================================================== errors

/// Why a module did not load.
public enum ModuleError
{
    /// The file could not be read.
    Io,

    /// It does not start with `Extended Module: `, so it is not an XM at all.
    NotAModule,

    /// It is an XM this player does not read -- a version before 1.04, whose
    /// pattern format differs.
    Unsupported,

    /// It parsed and has no patterns or no instruments, so there is nothing
    /// to play.
    Empty,
}

// ===================================================================== model

/// One cell of a pattern: what to do on this row, on this channel.
///
/// `Key` is 1 to 96 for C-0 to B-7, 97 for a key-off, and 0 for "nothing
/// here" -- which is not the same as a rest, since a channel with no new note
/// carries on playing the old one.
public struct Note
{
    public byte Key;
    public byte Instrument;
    public byte Volume;
    public byte Effect;
    public byte Parameter;
}

/// One sample: the waveform, and how to play it.
public sealed class Sample
{
    /// Always 16-bit here, whatever the file held: an 8-bit sample is widened
    /// on load, so the mixer has one case instead of two.
    public short[] Data;

    public nuint Length;
    public nuint LoopStart;
    public nuint LoopLength;

    /// 0 none, 1 forward. A 2 in the file means ping-pong and is read as
    /// forward, which is wrong and is better than silence.
    public int LoopKind;

    public int Volume;
    public int Finetune;
    public int RelativeNote;
    public int Panning;

    public Sample()
    {
        Data = new short[0u];
        Length = 0u;
        LoopStart = 0u;
        LoopLength = 0u;
        LoopKind = 0;
        Volume = 64;
        Finetune = 0;
        RelativeNote = 0;
        Panning = 128;
    }
}

/// An instrument: up to sixteen samples, which note picks which, and the
/// envelope that shapes all of them.
public sealed class Instrument
{
    public List<Sample> Samples;

    /// Which sample each of the 96 notes plays.
    public byte[] SampleForNote;

    /// Twelve points at most, as alternating tick and volume.
    public int[] VolumePoints;
    public nuint VolumePointCount;

    public int VolumeSustain;
    public int VolumeLoopStart;
    public int VolumeLoopEnd;

    /// Bit 0 on, bit 1 sustain, bit 2 loop.
    public int VolumeType;

    /// How fast a note fades after a key-off, out of 65536 per tick.
    public int Fadeout;

    public Instrument()
    {
        Samples = new List<Sample>();
        SampleForNote = new byte[96u];
        VolumePoints = new int[24u];
        VolumePointCount = 0u;
        VolumeSustain = 0;
        VolumeLoopStart = 0;
        VolumeLoopEnd = 0;
        VolumeType = 0;
        Fadeout = 0;
    }
}

/// One pattern: rows by channels of `Note`.
public sealed class Pattern
{
    public nuint Rows;
    public Note[] Notes;

    public Pattern(nuint rows, nuint channels)
    {
        Rows = rows;
        Notes = new Note[rows * channels];
    }
}

/// A loaded module.
public sealed class Module
{
    public String Name;
    public nuint Channels;
    public List<Pattern> Patterns;
    public byte[] Order;
    public nuint OrderLength;
    public List<Instrument> Instruments;

    /// Ticks per row, which FastTracker calls the speed.
    public nuint Speed;

    /// Ticks per minute divided by 2.5, which everyone calls the tempo.
    public nuint Tempo;

    public Module()
    {
        Name = "";
        Channels = 0u;
        Patterns = new List<Pattern>();
        Order = new byte[256u];
        OrderLength = 0u;
        Instruments = new List<Instrument>();
        Speed = 6u;
        Tempo = 125u;
    }

    /// How long one pass over the order table lasts, in seconds, ignoring any
    /// jumps the effects make.
    public double Duration
    {
        get
        {
            nuint rows = 0u;
            for (nuint i = 0u; i < OrderLength; i++)
            {
                nuint which = (nuint)Order[i];
                if (which < Patterns.Count)
                    rows += Patterns.At(which).Rows;
            }

            // A tick is 2.5 / tempo seconds, and a row is `Speed` ticks.
            return (double)(rows * Speed) * 2.5 / (double)Tempo;
        }
    }
}

// =================================================================== loading

/// A module read from disk.
public Result<Module, ModuleError> Load(String path)
{
    var read = File.ReadAllBytes(path);
    if (!read.Ok)
        return Fail(ModuleError.Io);
    return Decode(read.Value);
}

/// A module read from bytes.
public Result<Module, ModuleError> Decode(byte[] bytes)
{
    if (bytes.Length < 80u)
        return Fail(ModuleError.NotAModule);

    if (!Marks(bytes, 0u, "Extended Module: "))
        return Fail(ModuleError.NotAModule);

    // 1.04 is what FastTracker 2 wrote and what the pattern format below
    // assumes. An older one packs its patterns differently.
    uint version = ReadU16(bytes, 58u);
    if (version < 0x0104u)
        return Fail(ModuleError.Unsupported);

    var song = new Module();
    song.Name = Trimmed(bytes, 17u, 20u);

    nuint headerSize = (nuint)ReadU32(bytes, 60u);
    song.OrderLength = (nuint)ReadU16(bytes, 64u);
    song.Channels = (nuint)ReadU16(bytes, 68u);
    nuint patternCount = (nuint)ReadU16(bytes, 70u);
    nuint instrumentCount = (nuint)ReadU16(bytes, 72u);
    song.Speed = (nuint)ReadU16(bytes, 76u);
    song.Tempo = (nuint)ReadU16(bytes, 78u);

    if (song.Channels == 0u || song.Channels > 32u || patternCount == 0u)
        return Fail(ModuleError.Empty);
    if (song.Speed == 0u)
        song.Speed = 6u;
    if (song.Tempo == 0u)
        song.Tempo = 125u;

    for (nuint i = 0u; i < 256u; i++)
    {
        song.Order[i] = 0;
        if (80u + i < bytes.Length)
            song.Order[i] = bytes[80u + i];
    }

    nuint at = 60u + headerSize;

    for (nuint index = 0u; index < patternCount; index++)
    {
        if (at + 9u > bytes.Length)
            return Fail(ModuleError.Unsupported);

        nuint patternHeader = (nuint)ReadU32(bytes, at);
        nuint rows = (nuint)ReadU16(bytes, at + 5u);
        nuint packed = (nuint)ReadU16(bytes, at + 7u);

        if (rows == 0u || rows > 256u)
            rows = 64u;

        var pattern = new Pattern(rows, song.Channels);

        // A packed size of zero is a pattern of nothing, which is legal and
        // common: the rows are already blank from the allocation.
        if (packed > 0u)
            Unpack(bytes, at + patternHeader, packed, pattern, song.Channels);

        song.Patterns.Add(pattern);
        at = at + patternHeader + packed;
    }

    for (nuint index = 0u; index < instrumentCount; index++)
    {
        if (at + 29u > bytes.Length)
            break;

        var made = ReadInstrument(bytes, at);
        song.Instruments.Add(made.Instrument);
        at = made.Next;
    }

    if (song.Instruments.Count == 0u)
        return Fail(ModuleError.Empty);

    return Ok(song);
}

/// An instrument and where the next one starts.
struct LoadedInstrument
{
    public Instrument Instrument;
    public nuint Next;
}

LoadedInstrument ReadInstrument(byte[] bytes, nuint at)
{
    var instrument = new Instrument();
    nuint headerSize = (nuint)ReadU32(bytes, at);
    nuint sampleCount = (nuint)ReadU16(bytes, at + 27u);

    LoadedInstrument loaded;
    loaded.Instrument = instrument;

    if (sampleCount == 0u)
    {
        // An instrument with no samples is a placeholder, and its header size
        // is the whole of it.
        loaded.Next = at + (headerSize > 0u ? headerSize : 29u);
        return loaded;
    }

    nuint sampleHeaderSize = (nuint)ReadU32(bytes, at + 29u);

    for (nuint i = 0u; i < 96u; i++)
        instrument.SampleForNote[i] = bytes[at + 33u + i];

    for (nuint i = 0u; i < 24u; i++)
        instrument.VolumePoints[i] = (int)ReadU16(bytes, at + 129u + i * 2u);

    instrument.VolumePointCount = (nuint)bytes[at + 225u];
    instrument.VolumeSustain = (int)bytes[at + 227u];
    instrument.VolumeLoopStart = (int)bytes[at + 228u];
    instrument.VolumeLoopEnd = (int)bytes[at + 229u];
    instrument.VolumeType = (int)bytes[at + 233u];
    instrument.Fadeout = (int)ReadU16(bytes, at + 239u);

    // The sample headers come first, all of them, and then all the data --
    // which is why the loop below cannot read them together.
    nuint headers = at + headerSize;
    nuint data = headers + sampleCount * sampleHeaderSize;

    for (nuint i = 0u; i < sampleCount; i++)
    {
        nuint header = headers + i * sampleHeaderSize;
        var sample = new Sample();

        nuint byteLength = (nuint)ReadU32(bytes, header);
        nuint loopStart = (nuint)ReadU32(bytes, header + 4u);
        nuint loopLength = (nuint)ReadU32(bytes, header + 8u);

        sample.Volume = (int)bytes[header + 12u];
        sample.Finetune = (int)(sbyte)bytes[header + 13u];
        int kind = (int)bytes[header + 14u];
        sample.Panning = (int)bytes[header + 15u];
        sample.RelativeNote = (int)(sbyte)bytes[header + 16u];

        bool wide = (kind & 0x10) != 0;
        sample.LoopKind = kind & 3;
        if (sample.LoopKind > 1)
            sample.LoopKind = 1;

        nuint count = wide ? byteLength / 2u : byteLength;
        sample.Length = count;
        sample.LoopStart = wide ? loopStart / 2u : loopStart;
        sample.LoopLength = wide ? loopLength / 2u : loopLength;

        if (sample.LoopLength == 0u)
            sample.LoopKind = 0;
        if (sample.LoopStart + sample.LoopLength > count)
            sample.LoopKind = 0;

        sample.Data = Decode(bytes, data, byteLength, wide, count);
        data += byteLength;

        instrument.Samples.Add(sample);
    }

    loaded.Next = data;
    return loaded;
}

/// Sample data, un-delta'd and widened to sixteen bits.
///
/// **XM stores a difference per sample, not a value.** Reading it as absolute
/// gives a waveform that looks like the right shape and sounds like noise,
/// which is the kind of bug that takes an afternoon.
short[] Decode(byte[] bytes, nuint at, nuint byteLength, bool wide, nuint count)
{
    short[] data = new short[count];
    if (at + byteLength > bytes.Length)
        return data;

    if (wide)
    {
        int running = 0;
        for (nuint i = 0u; i < count; i++)
        {
            int delta = (int)(short)ReadU16(bytes, at + i * 2u);
            running = running + delta;

            // Wrapped to sixteen bits, which is what the format means by a
            // delta: the accumulator is allowed to go round.
            running = running & 0xFFFF;
            data[i] = (short)(running > 32767 ? running - 65536 : running);
        }

        return data;
    }

    int narrow = 0;
    for (nuint i = 0u; i < count; i++)
    {
        narrow = narrow + (int)(sbyte)bytes[at + i];
        narrow = narrow & 0xFF;
        int value = narrow > 127 ? narrow - 256 : narrow;
        data[i] = (short)(value * 256);
    }

    return data;
}

/// One pattern's packed rows.
///
/// A byte with the top bit set is a mask saying which of the five fields
/// follow; a byte without it *is* the note, and the other four follow whole.
void Unpack(byte[] bytes, nuint at, nuint packed, Pattern pattern, nuint channels)
{
    nuint end = at + packed;
    if (end > bytes.Length)
        end = bytes.Length;

    nuint read = at;

    for (nuint row = 0u; row < pattern.Rows; row++)
    {
        for (nuint channel = 0u; channel < channels; channel++)
        {
            if (read >= end)
                return;

            Note note;
            note.Key = 0;
            note.Instrument = 0;
            note.Volume = 0;
            note.Effect = 0;
            note.Parameter = 0;

            byte mask = bytes[read];
            read++;

            if ((mask & 0x80u) != 0u)
            {
                if ((mask & 0x01u) != 0u && read < end)
                {
                    note.Key = bytes[read];
                    read++;
                }
                if ((mask & 0x02u) != 0u && read < end)
                {
                    note.Instrument = bytes[read];
                    read++;
                }
                if ((mask & 0x04u) != 0u && read < end)
                {
                    note.Volume = bytes[read];
                    read++;
                }
                if ((mask & 0x08u) != 0u && read < end)
                {
                    note.Effect = bytes[read];
                    read++;
                }
                if ((mask & 0x10u) != 0u && read < end)
                {
                    note.Parameter = bytes[read];
                    read++;
                }
            }
            else
            {
                note.Key = mask;
                if (read + 3u < end)
                {
                    note.Instrument = bytes[read];
                    note.Volume = bytes[read + 1u];
                    note.Effect = bytes[read + 2u];
                    note.Parameter = bytes[read + 3u];
                }
                read += 4u;
            }

            pattern.Notes[row * channels + channel] = note;
        }
    }
}

// ================================================================== playing

/// One channel, as it sounds right now.
sealed class Voice
{
    public Instrument? Instrument;
    public Sample? Sample;

    /// Where in the sample, in samples, with the fraction that makes
    /// interpolation possible.
    public double Position;

    /// How far to advance per output sample.
    public double Step;

    public bool Playing;

    /// The note as the period the frequency comes from. Portamento works on
    /// this rather than on the frequency, which is why it is kept.
    public int Period;
    public int TargetPeriod;
    public int Note;

    public int Volume;
    public int Panning;

    public bool KeyOff;
    public int Fadeout;

    public int EnvelopeTick;
    public double EnvelopeValue;

    // What each effect remembers between rows, since a parameter of zero
    // means "the same as last time" for most of them.
    public int PortaSpeed;
    public int PortaUp;
    public int PortaDown;
    public int VolumeSlide;
    public int VibratoSpeed;
    public int VibratoDepth;
    public int VibratoPosition;
    public int Arpeggio;

    public int Effect;
    public int Parameter;

    public Voice()
    {
        Position = 0.0;
        Step = 0.0;
        Playing = false;
        Period = 0;
        TargetPeriod = 0;
        Note = 0;
        Volume = 0;
        Panning = 128;
        KeyOff = false;
        Fadeout = 65536;
        EnvelopeTick = 0;
        EnvelopeValue = 1.0;
        PortaSpeed = 0;
        PortaUp = 0;
        PortaDown = 0;
        VolumeSlide = 0;
        VibratoSpeed = 0;
        VibratoDepth = 0;
        VibratoPosition = 0;
        Arpeggio = 0;
        Effect = 0;
        Parameter = 0;
    }
}

/// The song, rendered to interleaved 16-bit stereo at `rate`.
///
/// One pass over the order table, stopping early if a position jump reaches a
/// place already played -- which is what a song that loops does at its end --
/// or when `maxSeconds` is reached, whichever is first. The buffer is meant to
/// be looped by whatever plays it.
public byte[] Render(Module song, uint rate, double maxSeconds)
{
    nuint channels = song.Channels;
    var voices = new List<Voice>();
    for (nuint i = 0u; i < channels; i++)
        voices.Add(new Voice());

    nuint capacity = (nuint)(maxSeconds * (double)rate) * 4u;
    byte[] output = new byte[capacity];
    nuint written = 0u;

    bool[] visited = new bool[256u];

    nuint speed = song.Speed;
    nuint tempo = song.Tempo;
    nuint order = 0u;
    nuint row = 0u;
    nuint tick = 0u;

    int jumpTo = -1;
    int breakTo = -1;

    while (order < song.OrderLength && written + 4u <= capacity)
    {
        nuint which = (nuint)song.Order[order];
        if (which >= song.Patterns.Count)
        {
            order++;
            continue;
        }

        var pattern = song.Patterns.At(which);
        if (row >= pattern.Rows)
        {
            row = 0u;
            order++;
            continue;
        }

        if (tick == 0u)
        {
            visited[order] = true;
            StartRow(song, pattern, row, voices, channels, rate,
                     &speed, &tempo, &jumpTo, &breakTo);
        }
        else
        {
            for (nuint channel = 0u; channel < channels; channel++)
                TickVoice(voices.At(channel), tick, rate);
        }

        for (nuint channel = 0u; channel < channels; channel++)
            AdvanceEnvelope(voices.At(channel));

        nuint samplesThisTick = (nuint)((double)rate * 2.5 / (double)tempo);
        if (samplesThisTick == 0u)
            samplesThisTick = 1u;

        written = Mix(output, written, capacity, voices, channels, samplesThisTick);

        tick++;
        if (tick < speed)
            continue;

        tick = 0u;
        row++;

        if (jumpTo >= 0 || breakTo >= 0)
        {
            nuint next = jumpTo >= 0 ? (nuint)jumpTo : order + 1u;
            row = breakTo >= 0 ? (nuint)breakTo : 0u;
            jumpTo = -1;
            breakTo = -1;

            // A jump to somewhere already played is the song's own loop, and
            // is where one pass ends.
            if (next < 256u && visited[next])
                break;

            order = next;
            continue;
        }

        if (row >= pattern.Rows)
        {
            row = 0u;
            order++;
        }
    }

    if (written == output.Length)
        return output;

    byte[] trimmed = new byte[written];
    for (nuint i = 0u; i < written; i++)
        trimmed[i] = output[i];
    return trimmed;
}

/// Everything that happens on tick zero of a row: new notes, and the effects
/// that act once.
void StartRow(Module song, Pattern pattern, nuint row, List<Voice> voices,
              nuint channels, uint rate, nuint* speed, nuint* tempo,
              int* jumpTo, int* breakTo)
{
    for (nuint channel = 0u; channel < channels; channel++)
    {
        var voice = voices.At(channel);
        Note note = pattern.Notes[row * channels + channel];

        voice.Effect = (int)note.Effect;
        voice.Parameter = (int)note.Parameter;
        voice.Arpeggio = 0;

        bool tonePorta = note.Effect == 3u || note.Effect == 5u ||
                         (note.Volume >= 0xF0u);

        if (note.Instrument > 0u)
        {
            nuint index = (nuint)note.Instrument - 1u;
            if (index < song.Instruments.Count)
            {
                voice.Instrument = song.Instruments.At(index);
                var instrument = (Instrument)voice.Instrument;

                // An instrument on its own, with no note, resets the volume
                // and the envelope but does not retrigger.
                voice.Volume = 64;
                voice.Fadeout = 65536;
                voice.KeyOff = false;
                voice.EnvelopeTick = 0;

                var sample = voice.Sample;
                if (sample != null)
                {
                    voice.Volume = ((Sample)sample).Volume;
                    voice.Panning = ((Sample)sample).Panning;
                }
            }
        }

        if (note.Key == 97u)
        {
            voice.KeyOff = true;
        }
        else if (note.Key > 0u && note.Key < 97u)
        {
            var instrument = voice.Instrument;
            if (instrument != null)
            {
                var found = (Instrument)instrument;
                nuint key = (nuint)note.Key - 1u;
                nuint which = (nuint)found.SampleForNote[key];

                if (which < found.Samples.Count)
                {
                    var sample = found.Samples.At(which);
                    int realNote = (int)key + sample.RelativeNote;
                    int period = PeriodOf(realNote, sample.Finetune);

                    if (tonePorta && voice.Playing)
                    {
                        // Tone portamento slides to the note rather than
                        // starting it, which is the whole point of it.
                        voice.TargetPeriod = period;
                    }
                    else
                    {
                        voice.Sample = sample;
                        voice.Position = 0.0;
                        voice.Period = period;
                        voice.TargetPeriod = period;
                        voice.Note = realNote;
                        voice.Playing = true;
                        voice.KeyOff = false;
                        voice.Fadeout = 65536;
                        voice.EnvelopeTick = 0;
                        voice.VibratoPosition = 0;
                        voice.Volume = sample.Volume;
                        voice.Panning = sample.Panning;
                    }
                }
            }
        }

        // The volume column. Only the ones a module actually uses; the rest
        // are read as nothing rather than as something wrong.
        int column = (int)note.Volume;
        if (column >= 0x10 && column <= 0x50)
            voice.Volume = column - 0x10;
        else if (column >= 0x60 && column <= 0x6F)
            voice.VolumeSlide = -(column - 0x60);
        else if (column >= 0x70 && column <= 0x7F)
            voice.VolumeSlide = column - 0x70;
        else if (column >= 0xF0)
            voice.PortaSpeed = (column - 0xF0) * 16;

        ApplyRowEffect(voice, speed, tempo, jumpTo, breakTo);
        Retune(voice, rate);
    }
}

/// The effects that act on tick zero.
void ApplyRowEffect(Voice voice, nuint* speed, nuint* tempo, int* jumpTo, int* breakTo)
{
    int effect = voice.Effect;
    int parameter = voice.Parameter;

    if (effect == 0x0 && parameter != 0)
    {
        voice.Arpeggio = parameter;
        return;
    }

    if (effect == 0x1)
    {
        if (parameter != 0)
            voice.PortaUp = parameter;
        return;
    }

    if (effect == 0x2)
    {
        if (parameter != 0)
            voice.PortaDown = parameter;
        return;
    }

    if (effect == 0x3)
    {
        if (parameter != 0)
            voice.PortaSpeed = parameter * 4;
        return;
    }

    if (effect == 0x4)
    {
        int upper = (parameter >> 4) & 0xF;
        int lower = parameter & 0xF;
        if (upper != 0)
            voice.VibratoSpeed = upper;
        if (lower != 0)
            voice.VibratoDepth = lower;
        return;
    }

    if (effect == 0xA)
    {
        if (parameter != 0)
        {
            int up = (parameter >> 4) & 0xF;
            int down = parameter & 0xF;
            voice.VolumeSlide = up > 0 ? up : -down;
        }
        return;
    }

    if (effect == 0xB)
    {
        *jumpTo = parameter;
        return;
    }

    if (effect == 0xC)
    {
        voice.Volume = parameter > 64 ? 64 : parameter;
        return;
    }

    if (effect == 0xD)
    {
        // The row is written as though it were decimal, which it is not.
        *breakTo = ((parameter >> 4) & 0xF) * 10 + (parameter & 0xF);
        return;
    }

    if (effect == 0xE)
    {
        int kind = (parameter >> 4) & 0xF;
        int amount = parameter & 0xF;

        if (kind == 0x1)
            voice.Period = Clamp(voice.Period - amount * 4);
        else if (kind == 0x2)
            voice.Period = Clamp(voice.Period + amount * 4);
        return;
    }

    if (effect == 0xF)
    {
        if (parameter == 0)
            return;

        // Under 32 it is the speed in ticks a row, and at or above it is the
        // tempo in beats. One effect, two meanings, and every tracker agrees
        // about the boundary.
        if (parameter < 0x20)
            *speed = (nuint)parameter;
        else
            *tempo = (nuint)parameter;
    }
}

/// The effects that act on every tick but the first.
void TickVoice(Voice voice, nuint tick, uint rate)
{
    int effect = voice.Effect;

    if (effect == 0x0 && voice.Arpeggio != 0)
    {
        // Three notes a row, cycling: the chord a single voice cannot hold.
        nuint which = tick % 3u;
        int offset = 0;
        if (which == 1u)
            offset = (voice.Arpeggio >> 4) & 0xF;
        else if (which == 2u)
            offset = voice.Arpeggio & 0xF;

        Retune(voice, rate, offset);
        return;
    }

    if (effect == 0x1)
        voice.Period = Clamp(voice.Period - voice.PortaUp * 4);
    else if (effect == 0x2)
        voice.Period = Clamp(voice.Period + voice.PortaDown * 4);
    else if (effect == 0x3 || effect == 0x5)
        SlideToNote(voice);
    else if (effect == 0x4 || effect == 0x6)
        Vibrato(voice);

    if (effect == 0xA || effect == 0x5 || effect == 0x6)
    {
        voice.Volume = voice.Volume + voice.VolumeSlide;
        if (voice.Volume < 0)
            voice.Volume = 0;
        if (voice.Volume > 64)
            voice.Volume = 64;
    }

    if (effect == 0xE)
    {
        int kind = (voice.Parameter >> 4) & 0xF;
        int amount = voice.Parameter & 0xF;

        if (kind == 0xC && (nuint)amount == tick)
            voice.Volume = 0;
        else if (kind == 0xD && (nuint)amount == tick)
            voice.Position = 0.0;
    }

    Retune(voice, rate);
}

void SlideToNote(Voice voice)
{
    if (voice.Period < voice.TargetPeriod)
    {
        voice.Period = voice.Period + voice.PortaSpeed;
        if (voice.Period > voice.TargetPeriod)
            voice.Period = voice.TargetPeriod;
    }
    else if (voice.Period > voice.TargetPeriod)
    {
        voice.Period = voice.Period - voice.PortaSpeed;
        if (voice.Period < voice.TargetPeriod)
            voice.Period = voice.TargetPeriod;
    }
}

void Vibrato(Voice voice)
{
    voice.VibratoPosition = (voice.VibratoPosition + voice.VibratoSpeed) & 63;
    double phase = (double)voice.VibratoPosition * 6.28318530717958623200 / 64.0;
    int depth = (int)(Math.Sin(phase) * (double)voice.VibratoDepth * 4.0);
    voice.Period = Clamp(voice.Period + depth);
}

/// The envelope, one tick on.
void AdvanceEnvelope(Voice voice)
{
    var held = voice.Instrument;
    if (held == null)
    {
        voice.EnvelopeValue = 1.0;
        return;
    }

    var instrument = (Instrument)held;

    if (voice.KeyOff)
    {
        voice.Fadeout = voice.Fadeout - instrument.Fadeout;
        if (voice.Fadeout < 0)
            voice.Fadeout = 0;
    }

    if ((instrument.VolumeType & 1) == 0 || instrument.VolumePointCount == 0u)
    {
        voice.EnvelopeValue = 1.0;
        return;
    }

    voice.EnvelopeValue = EnvelopeAt(instrument, voice.EnvelopeTick);

    // Held at the sustain point until the key is released, then free to run
    // on. That is what makes a held note hold.
    bool sustained = (instrument.VolumeType & 2) != 0 && !voice.KeyOff;
    if (sustained)
    {
        int sustainTick = instrument.VolumePoints[(nuint)(instrument.VolumeSustain * 2)];
        if (voice.EnvelopeTick >= sustainTick)
            return;
    }

    voice.EnvelopeTick++;

    if ((instrument.VolumeType & 4) != 0)
    {
        int endTick = instrument.VolumePoints[(nuint)(instrument.VolumeLoopEnd * 2)];
        int startTick = instrument.VolumePoints[(nuint)(instrument.VolumeLoopStart * 2)];
        if (voice.EnvelopeTick >= endTick)
            voice.EnvelopeTick = startTick;
    }
}

/// The envelope's value at a tick, interpolated between its points.
double EnvelopeAt(Instrument instrument, int tick)
{
    nuint count = instrument.VolumePointCount;
    if (count == 0u)
        return 1.0;

    int firstTick = instrument.VolumePoints[0u];
    if (tick <= firstTick)
        return (double)instrument.VolumePoints[1u] / 64.0;

    for (nuint i = 1u; i < count; i++)
    {
        int x1 = instrument.VolumePoints[i * 2u];
        int y1 = instrument.VolumePoints[i * 2u + 1u];

        if (tick > x1)
            continue;

        int x0 = instrument.VolumePoints[(i - 1u) * 2u];
        int y0 = instrument.VolumePoints[(i - 1u) * 2u + 1u];

        if (x1 == x0)
            return (double)y1 / 64.0;

        double through = (double)(tick - x0) / (double)(x1 - x0);
        return ((double)y0 + ((double)y1 - (double)y0) * through) / 64.0;
    }

    return (double)instrument.VolumePoints[(count - 1u) * 2u + 1u] / 64.0;
}

/// The period a note sounds at, on the linear frequency table.
///
/// The constants are the table's: 7680 is ten octaves of sixteenths of a
/// semitone, and 4608 is where C-4 lands -- which is the note that sounds at
/// 8363 Hz, the rate every tracker measures a sample against.
int PeriodOf(int note, int finetune)
{
    return 7680 - note * 64 - finetune / 2;
}

double FrequencyOf(int period)
{
    return 8363.0 * Math.Pow(2.0, (double)(4608 - period) / 768.0);
}

int Clamp(int period)
{
    if (period < 64)
        return 64;
    if (period > 7680)
        return 7680;
    return period;
}

/// The step the mixer advances by, from the voice's period.
void Retune(Voice voice, uint rate)
{
    Retune(voice, rate, 0);
}

void Retune(Voice voice, uint rate, int semitones)
{
    int period = voice.Period - semitones * 64;
    voice.Step = FrequencyOf(Clamp(period)) / (double)rate;
}

/// One tick's worth of sound from every voice.
nuint Mix(byte[] output, nuint written, nuint capacity, List<Voice> voices,
          nuint channels, nuint frames)
{
    for (nuint frame = 0u; frame < frames; frame++)
    {
        if (written + 4u > capacity)
            return written;

        double left = 0.0;
        double right = 0.0;

        for (nuint channel = 0u; channel < channels; channel++)
        {
            var voice = voices.At(channel);
            if (!voice.Playing)
                continue;

            var held = voice.Sample;
            if (held == null)
                continue;

            var sample = (Sample)held;
            if (sample.Length == 0u)
                continue;

            nuint index = (nuint)voice.Position;
            if (index >= sample.Length)
            {
                voice.Playing = false;
                continue;
            }

            // Linear interpolation between neighbours, which costs one
            // multiply and is the difference between a sample and a buzz.
            nuint next = index + 1u;
            if (next >= sample.Length)
                next = sample.LoopKind == 1 ? sample.LoopStart : index;

            double fraction = voice.Position - (double)index;
            double value = (double)sample.Data[index] * (1.0 - fraction) +
                           (double)sample.Data[next] * fraction;

            double gain = (double)voice.Volume / 64.0 *
                          voice.EnvelopeValue *
                          (double)voice.Fadeout / 65536.0;

            double pan = (double)voice.Panning / 255.0;
            left += value * gain * (1.0 - pan);
            right += value * gain * pan;

            voice.Position = voice.Position + voice.Step;

            if (sample.LoopKind == 1)
            {
                double end = (double)(sample.LoopStart + sample.LoopLength);
                while (voice.Position >= end)
                    voice.Position = voice.Position - (double)sample.LoopLength;
            }
            else if (voice.Position >= (double)sample.Length)
            {
                voice.Playing = false;
            }
        }

        written = Put(output, written, left);
        written = Put(output, written, right);
    }

    return written;
}

/// One sample written, clipped. The headroom is a guess that four channels of
/// full-scale sample will not all line up, which is the same guess every
/// tracker makes.
nuint Put(byte[] output, nuint at, double value)
{
    int sample = (int)(value * 0.55);
    if (sample > 32767)
        sample = 32767;
    if (sample < -32768)
        sample = -32768;

    int stored = sample;
    if (stored < 0)
        stored = stored + 65536;

    output[at] = (byte)(stored & 0xFF);
    output[at + 1u] = (byte)((stored >> 8) & 0xFF);
    return at + 2u;
}

// =================================================================== reading

bool Marks(byte[] bytes, nuint at, String mark)
{
    nuint length = mark.ByteLength();
    if (at + length > bytes.Length)
        return false;

    var wanted = mark.ToPointer();
    for (nuint i = 0u; i < length; i++)
    {
        if (bytes[at + i] != wanted[i])
            return false;
    }

    return true;
}

String Trimmed(byte[] bytes, nuint at, nuint length)
{
    nuint end = at + length;
    if (end > bytes.Length)
        end = bytes.Length;

    while (end > at && (bytes[end - 1u] == 32u || bytes[end - 1u] == 0u))
        end--;

    var builder = new StringBuilder();
    for (nuint i = at; i < end; i++)
    {
        byte c = bytes[i];
        if (c >= 32u && c < 127u)
            builder.Append(Text.FromChar((char32)c));
    }

    return builder.ToText();
}

uint ReadU16(byte[] bytes, nuint at)
{
    if (at + 2u > bytes.Length)
        return 0u;
    return (uint)bytes[at] | ((uint)bytes[at + 1u] << 8);
}

uint ReadU32(byte[] bytes, nuint at)
{
    if (at + 4u > bytes.Length)
        return 0u;
    return (uint)bytes[at] | ((uint)bytes[at + 1u] << 8) |
           ((uint)bytes[at + 2u] << 16) | ((uint)bytes[at + 3u] << 24);
}
