// A section name longer than a PE image keeps. The object file can hold it,
// through its string table, and lld-link then cuts it to eight bytes in the
// executable — `.embedded_logo` becomes `.embedde` — without a word. The bytes
// are unaffected, which is why this is a warning: what breaks is a tool that
// looks for the section by the name the source gave it.
module PeSectionName;

public static class Held
{
    public static readonly byte[] Logo = embed("logo.bin", section: ".embedded_logo");
}

int Main() => (int)Held.Logo.Length;
