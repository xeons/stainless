// SPDX-License-Identifier: 0BSD
module Conflict;

// A declaration has one visibility, and each word is written once.
public internal class Both                // SL0109
{
    private internal int _twice;          // SL0109
    internal internal int _again;         // SL0109
    private protected int _narrow;        // SL0109
    static static int s_count;            // SL0109
}

public int Main() => 0;
