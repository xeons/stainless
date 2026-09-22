// SPDX-License-Identifier: 0BSD
module Wav32;

import Standard.Console;
import Standard.Media.Audio;

// A chunk size near the top of a `uint` MUST NOT wrap the chunk's end back
// inside the file where `nuint` is four bytes wide. If it did, the walk would
// return to an earlier chunk and never finish.

void PutMark(byte[] bytes, nuint at, String mark)
{
    var source = mark.ToPointer();
    for (nuint i = 0u; i < 4u; i++)
        bytes[at + i] = source[i];
}

void PutUInt(byte[] bytes, nuint at, uint value)
{
    bytes[at] = (byte)(value & 0xFFu);
    bytes[at + 1u] = (byte)((value >> 8) & 0xFFu);
    bytes[at + 2u] = (byte)((value >> 16) & 0xFFu);
    bytes[at + 3u] = (byte)((value >> 24) & 0xFFu);
}

int Main()
{
    byte[] file = new byte[56u];
    PutMark(file, 0u, "RIFF");
    PutUInt(file, 4u, 48u);
    PutMark(file, 8u, "WAVE");
    PutMark(file, 12u, "junk");
    PutUInt(file, 16u, 0xFFFFFFF8u);

    var read = Wav.Decode(file);
    Console.WriteLine(read.Ok ? "wav-wrapped WRONG" : "wav-wrapped refused");
    return 0;
}
