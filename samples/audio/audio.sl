// SPDX-License-Identifier: 0BSD
//
// Sound, which is the one thing a test suite cannot check for you.
//
//     stainless run samples/audio/audio.sl              -- play a short scale
//     stainless run samples/audio/audio.sl -- record    -- and record three seconds
//
// The scale is synthesised rather than loaded, so there is no file to ship and
// nothing to go missing. `record` writes `heard.wav` beside the working
// directory and plays it straight back, which is the only way to see that both
// halves of the module work on a machine.
module AudioSample;

import Standard.Console;
import Standard.Env;
import Standard.Text;
import Standard.Media.Audio;

// A major scale in semitones from the root, which is what makes the tones
// sound like something rather than like a test.
int[] GetMajorScale() => [0, 2, 4, 5, 7, 9, 11, 12];

double ComputeNoteFrequency(int semitones)
{
    // Twelve-tone equal temperament from A above middle C: each semitone is
    // the twelfth root of two.
    double ratio = 1.0;
    for (int i = 0; i < semitones; i++)
        ratio = ratio * 1.05946309435929530;
    return 440.0 * ratio;
}

int PlayScale()
{
    var format = AudioFormat.Cd;
    var opened = AudioPlayer.Open(format);
    if (!opened.Ok)
    {
        Console.WriteLine("could not open a device: " + DescribeAudioError(opened.Error));
        return 1;
    }

    var player = opened.Value;
    Console.WriteLine("playing a scale through " + Audio.BackendName());

    foreach (int step in GetMajorScale())
    {
        var tone = Tone.CreateSine(format, ComputeNoteFrequency(step), 0.18, 0.25);
        var written = player.Write(tone.Samples);
        if (!written.Ok)
        {
            Console.WriteLine("write failed: " + DescribeAudioError(written.Error));
            player.Close();
            return 1;
        }
    }

    // Without this the program would end -- and the destructor would close the
    // device -- while the last few notes were still queued.
    player.DrainBuffer();
    player.Close();
    Console.WriteLine("done");
    return 0;
}

int RecordAndPlayBack()
{
    var format = AudioFormat.Voice;
    Console.WriteLine("recording three seconds through " + Audio.BackendName() + "...");

    var heard = Audio.RecordClip(format, 3.0);
    if (!heard.Ok)
    {
        Console.WriteLine("could not record: " + DescribeAudioError(heard.Error));
        return 1;
    }

    var clip = heard.Value;

    // The peak is what says a microphone was actually reached: a device that
    // opened and produced nothing gives a clip of the right length and zero
    // here, which reads as success everywhere else.
    int peak = 0;
    for (nuint frame = 0u; frame < clip.FrameCount; frame++)
    {
        int value = clip.GetSample(frame, 0u);
        if (value < 0)
            value = -value;
        if (value > peak)
            peak = value;
    }

    Console.WriteLine("captured " + Text.FromInteger((long)clip.FrameCount) +
                      " frames, peak " + Text.FromInteger((long)peak) + " of 32767");

    var saved = Wav.Save(clip, "heard.wav");
    if (!saved.Ok)
    {
        Console.WriteLine("could not write heard.wav");
        return 1;
    }

    Console.WriteLine("wrote heard.wav; playing it back");
    var played = Audio.PlayClip(clip);
    if (!played.Ok)
    {
        Console.WriteLine("playback failed: " + DescribeAudioError(played.Error));
        return 1;
    }

    return 0;
}

String DescribeAudioError(AudioError error)
{
    switch (error)
    {
        case AudioError.NoBackend: return "there is no audio library on this machine";
        case AudioError.Format: return "the device would not take that format";
        case AudioError.Device: return "there is no sound device";
        case AudioError.Busy: return "something else has the device";
        case AudioError.Closed: return "the device was closed";
        case AudioError.Malformed: return "that was not a WAV file";
        case AudioError.Io: return "the file could not be read or written";
    }

    return "something went wrong";
}

int Main()
{
    if (!Audio.IsAvailable())
    {
        Console.WriteLine("no audio library here; nothing to do");
        return 1;
    }

    if (Env.ArgumentCount() > 0u && Env.GetArgument(0u) == "record")
        return RecordAndPlayBack();

    return PlayScale();
}
