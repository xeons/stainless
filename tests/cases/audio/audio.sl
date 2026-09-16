// SPDX-License-Identifier: 0BSD
module Audio;

import Standard.Console;
import Standard.Convert;
import Standard.Text;
import Standard.Media.Audio;

// Nothing here opens a device. A machine running the suite may have no sound
// card, no ALSA and no speakers, and a test that depended on one would fail for
// a reason that is not about this code -- so what is checked is the part that
// is the same everywhere: the format arithmetic, the sample accessors, the
// tone generator and the WAV container in both directions.
//
// What that deliberately does not prove is that a sound was heard. Only
// playing one proves that, and `samples/audio` is the program that does it.

void Check(String label, String actual, String expected)
{
    if (actual == expected)
    {
        Console.WriteLine(label + " ok");
        return;
    }

    Console.WriteLine(label + " WRONG");
    Console.WriteLine("  got      " + actual);
    Console.WriteLine("  expected " + expected);
}

String Number(long value) => Text.FromInteger(value);

void Formats()
{
    var cd = AudioFormat.Cd;
    Check("cd-frame", Number((long)cd.BytesPerFrame), "4");
    Check("cd-second", Number((long)cd.BytesPerSecond), "176400");
    Check("cd-supported", cd.IsSupported ? "yes" : "no", "yes");

    var voice = AudioFormat.Voice;
    Check("voice-frame", Number((long)voice.BytesPerFrame), "2");
    Check("voice-second", Number((long)voice.BytesPerSecond), "32000");

    var eight = AudioFormat.Of(8000u, (ushort)1, (ushort)8);
    Check("telephone-frame", Number((long)eight.BytesPerFrame), "1");

    // Five channels and twenty-four bits are both real formats and neither is
    // one this module handles; saying so is what `IsSupported` is for.
    var wide = AudioFormat.Of(48000u, (ushort)6, (ushort)24);
    Check("surround-supported", wide.IsSupported ? "yes" : "no", "no");
    Check("equal", cd.Equals(AudioFormat.Of(44100u, (ushort)2, (ushort)16)) ? "yes" : "no", "yes");
}

void Clips()
{
    var format = AudioFormat.Of(8000u, (ushort)2, (ushort)16);
    var clip = AudioClip.Silence(format, 100u);

    Check("silence-frames", Number((long)clip.FrameCount), "100");
    Check("silence-bytes", Number((long)clip.Samples.Length), "400");
    Check("silence-sample", Number((long)clip.SampleAt(0u, 0u)), "0");

    // Sixteen-bit samples are signed and little-endian, and the accessors are
    // what a caller uses rather than reaching for the bytes.
    clip.SetSample(3u, 0u, 1000);
    clip.SetSample(3u, 1u, -1000);
    Check("set-left", Number((long)clip.SampleAt(3u, 0u)), "1000");
    Check("set-right", Number((long)clip.SampleAt(3u, 1u)), "-1000");
    Check("set-bytes", Convert.ToHex(clip.Samples).Substring(24u, 8u), "e80318fc");

    // Clamped rather than wrapped: a sample that wrapped would be a loud click
    // at the opposite polarity, which is the worst possible failure.
    clip.SetSample(4u, 0u, 40000);
    clip.SetSample(4u, 1u, -40000);
    Check("clamp-high", Number((long)clip.SampleAt(4u, 0u)), "32767");
    Check("clamp-low", Number((long)clip.SampleAt(4u, 1u)), "-32768");

    // Out of range is answered rather than aborted, because walking off the
    // end of a waveform is what a loop over one does at the end.
    Check("past-end", Number((long)clip.SampleAt(500u, 0u)), "0");
    Check("no-channel", Number((long)clip.SampleAt(0u, 7u)), "0");

    // Eight-bit samples are unsigned and centred on 128, and the accessors
    // hide that: the same numbers go in and come back, to within the width.
    var narrow = AudioClip.Silence(AudioFormat.Of(8000u, (ushort)1, (ushort)8), 4u);
    Check("eight-silence", Number((long)narrow.Samples[0u]), "128");
    Check("eight-zero", Number((long)narrow.SampleAt(0u, 0u)), "0");
    narrow.SetSample(1u, 0u, 25600);
    Check("eight-set", Number((long)narrow.Samples[1u]), "228");
    Check("eight-read", Number((long)narrow.SampleAt(1u, 0u)), "25600");
}

void Tones()
{
    var format = AudioFormat.Of(8000u, (ushort)1, (ushort)16);

    var sine = Tone.Sine(format, 1000.0, 0.25, 1.0);
    Check("sine-frames", Number((long)sine.FrameCount), "2000");
    Check("sine-start", Number((long)sine.SampleAt(0u, 0u)), "0");

    // 1 kHz at 8 kHz is eight samples a cycle, so the quarter-cycle peak lands
    // exactly on frame two -- which is what makes this checkable at all.
    Check("sine-peak", Number((long)sine.SampleAt(2u, 0u)), "32767");

    var square = Tone.Square(format, 1000.0, 0.25, 0.5);
    Check("square-high", Number((long)square.SampleAt(0u, 0u)), "16383");
    Check("square-low", Number((long)square.SampleAt(5u, 0u)), "-16383");

    var rest = Tone.Rest(format, 0.125);
    Check("rest-frames", Number((long)rest.FrameCount), "1000");
    Check("rest-sample", Number((long)rest.SampleAt(500u, 0u)), "0");
}

void Container()
{
    var format = AudioFormat.Of(22050u, (ushort)2, (ushort)16);
    var original = Tone.Sine(format, 440.0, 0.05, 0.5);

    byte[] file = Wav.Encode(original);
    Check("wav-size", Number((long)file.Length),
          Number((long)(44u + original.Samples.Length)));
    Check("wav-riff", Convert.ToHex(file).Substring(0u, 8u), "52494646");
    Check("wav-wave", Convert.ToHex(file).Substring(16u, 8u), "57415645");

    var read = Wav.Decode(file);
    if (!read.Ok)
    {
        Console.WriteLine("wav-decode WRONG");
        return;
    }

    var back = read.Value;
    Check("wav-rate", Number((long)back.Format.SampleRate), "22050");
    Check("wav-channels", Number((long)back.Format.Channels), "2");
    Check("wav-bits", Number((long)back.Format.BitsPerSample), "16");
    Check("wav-frames", Number((long)back.FrameCount), Number((long)original.FrameCount));

    bool identical = back.Samples.Length == original.Samples.Length;
    for (nuint i = 0u; identical && i < back.Samples.Length; i++)
    {
        if (back.Samples[i] != original.Samples[i])
            identical = false;
    }
    Check("wav-samples", identical ? "yes" : "no", "yes");

    // What a malformed file gets, which is a value rather than a crash.
    var empty = Wav.Decode(new byte[0u]);
    Console.WriteLine(empty.Ok ? "wav-empty WRONG" : "wav-empty refused");

    byte[] wrong = Wav.Encode(original);
    wrong[0u] = 0x58;
    var notRiff = Wav.Decode(wrong);
    Console.WriteLine(notRiff.Ok ? "wav-not-riff WRONG" : "wav-not-riff refused");

    // A compressed WAV is a real file and not one this reads; the format tag
    // is at offset 20 and 85 is MPEG Layer 3.
    byte[] compressed = Wav.Encode(original);
    compressed[20u] = 85;
    var mp3 = Wav.Decode(compressed);
    Console.WriteLine(mp3.Ok ? "wav-compressed WRONG" : "wav-compressed refused");
}

int Main()
{
    Formats();
    Clips();
    Tones();
    Container();
    return 0;
}
