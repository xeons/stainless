// SPDX-License-Identifier: 0BSD
module NoUnknown;

import Standard.Console;
import Standard.Text;

// `[NoUnknown]` describes the other thing a C library hands out: a bare array
// of function pointers, with no QueryInterface, no AddRef and no Release. The
// first method declared is slot 0, and nothing is counted -- the library says
// how the object dies, which here is `Destroy`.
//
// XAudio2's voices are the reason it exists: `IXAudio2Voice` derives from
// nothing, and reaching one through an ordinary `com interface` would call
// `SetOutputVoices` where ARC expected `AddRef`.

extern "C"
{
    byte* make_voice(int which);
    int voice_is_alive(int which);
}

[NoUnknown]
public com interface IVoice
{
    int Volume();
    void SetVolume(int level);
    int Mix(int left, int right);
    void Destroy();
}

String Number(long value) => Text.FromInteger(value);

// A parameter, to show that passing one emits no AddRef: the C side would
// print nothing here either way, and what proves it is that the voice is still
// alive afterwards.
int Loudest(IVoice left, IVoice right)
{
    int first = left.Volume();
    int second = right.Volume();
    return first > second ? first : second;
}

// And a return, which is the other place a count would have been taken.
IVoice Pick(int which) => (IVoice)make_voice(which);

int Main()
{
    var first = Pick(0);
    var second = Pick(1);

    Console.WriteLine("slot 0 volume = " + Number((long)first.Volume()));
    Console.WriteLine("slot 1 volume = " + Number((long)second.Volume()));
    Console.WriteLine("loudest       = " + Number((long)Loudest(first, second)));

    first.SetVolume(10);
    Console.WriteLine("after set     = " + Number((long)first.Volume()));
    Console.WriteLine("mix           = " + Number((long)first.Mix(2, 4)));

    // Copying the reference copies a pointer and counts nothing, so both names
    // reach the same voice.
    var alias = first;
    alias.SetVolume(11);
    Console.WriteLine("through alias = " + Number((long)first.Volume()));

    // Still alive: nothing has released it, because there is nothing to
    // release it with.
    Console.WriteLine("alive before  = " + Number((long)voice_is_alive(0)));

    first.Destroy();
    Console.WriteLine("alive after   = " + Number((long)voice_is_alive(0)));
    Console.WriteLine("slot 1 still  = " + Number((long)second.Volume()));

    Console.WriteLine("end of Main");
    return 0;
}
