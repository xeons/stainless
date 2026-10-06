// SPDX-License-Identifier: 0BSD
module Conflict;

// A declaration has one visibility, and each word is written once.
public internal class Both                // SLC0001
{
    private internal int _twice;          // SLC0001
    internal internal int _again;         // SLC0001
    private protected int _narrow;        // SLC0001
    static static int s_count;            // SLC0001
}

public int Main() => 0;
