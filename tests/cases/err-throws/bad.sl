// SPDX-License-Identifier: 0BSD
module Bad;

// `[Throws]` is for a function another language defines, declared answering
// what a call answers once it has caught what was thrown.

/// Foreign, but answering what the C function itself does.
[Throws]
extern "C" int Plain(int number);

/// A result returned in memory, which a call that threw leaves unwritten.
public struct Wide
{
    public long A;
    public long B;
    public long C;
}

[Throws]
extern "C" Result<Wide, ForeignException> MakeWide();

int Main() => 0;
