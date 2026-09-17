// SPDX-License-Identifier: 0BSD
module Bad;

// Every way of asking what a [NoUnknown] reference really is. Each is a
// QueryInterface, and such a vtable has no QueryInterface to call and no IID
// to call it with -- so each is refused where it is written, rather than
// emitted against an IID nothing defines.

[NoUnknown]
public com interface IVoice
{
    void Play();
}

[NoUnknown]
public com interface ISourceVoice
{
    void Queue();
}

[Guid("7e9fb0d3-919f-4307-ab2e-9b1860310c93")]
public com interface ICounted
{
    int Step();
}

int Main()
{
    var voice = (IVoice)(byte*)null;
    var counted = (ICounted)(byte*)null;

    // The cast, which was already refused.
    var source = (ISourceVoice)voice;

    // 'is' from either side.
    if (voice is ISourceVoice)
        return 1;
    if (counted is IVoice)
        return 2;

    // And a pattern, which is the same test spelled in a switch.
    return voice switch
    {
        ISourceVoice => 3,
        _ => 0,
    };
}
