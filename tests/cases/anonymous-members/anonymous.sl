// Nameless `struct { }` and `union { }` members, as C has them.
//
// The Windows headers lean on these constantly: `SYSTEM_INFO`, `OVERLAPPED` and
// `LARGE_INTEGER` all begin with one. Without them a binding has to invent both
// a type name and a member name, which changes every access path away from the
// one the header documents.
//
// Every number here was read off clang for the same declarations.
module AnonymousMembers;

import Standard.Console;

/// `SYSTEM_INFO`'s opening, which is a union of a whole `DWORD` and two halves,
/// both nameless.
public struct SystemInfo {
    public union {
        public uint OemId;
        public struct {
            public ushort Architecture;
            public ushort Reserved;
        }
    }
    public uint  PageSize;
    public void* MinimumApplicationAddress;
}

/// `LARGE_INTEGER`: the same 64 bits read whole or in halves.
public union LargeInteger {
    public struct {
        public uint Low;
        public int  High;
    }
    public long Quad;
}

/// Nesting one inside another, and a named member beside them, so that lookup
/// has to go more than one level and still prefer the shallower name.
public struct Layers {
    public int Depth;
    public struct {
        public int Middle;
        public union {
            public int  AsInt;
            public byte AsByte;
        }
    }
}

void Show(String name, nuint value) {
    Console.WriteLine(name + " = " + Text.FromInteger(value));
}

int Main() {
    // --- layout ------------------------------------------------------------
    Show("sizeof(SystemInfo)", sizeof(SystemInfo));
    Show("offsetof(PageSize)", offsetof(SystemInfo, PageSize));
    Show("sizeof(LargeInteger)", sizeof(LargeInteger));
    Show("alignof(LargeInteger)", alignof(LargeInteger));
    Show("sizeof(Layers)", sizeof(Layers));

    // --- a member of a nameless member reads as the parent's own ------------
    SystemInfo info;
    info.OemId = 0u;
    info.Architecture = 9u;
    info.PageSize = 4096u;

    Console.WriteLine("architecture: " + Text.FromInteger((long)info.Architecture));
    Console.WriteLine("page size: " + Text.FromInteger((long)info.PageSize));

    // The union means both names reach the same bytes.
    Console.WriteLine("the whole word sees it: "
        + Text.FromBool((info.OemId & 0xFFFFu) == (uint)info.Architecture));

    // --- halves and whole ---------------------------------------------------
    LargeInteger big;
    big.Quad = 0;
    big.High = 1;
    big.Low = 5u;
    Console.WriteLine("quad: " + Text.FromInteger(big.Quad));
    Console.WriteLine("rebuilt: "
        + Text.FromBool(big.Quad == ((long)big.High << 32) + (long)big.Low));

    // --- two levels down ----------------------------------------------------
    Layers layers;
    layers.Depth = 1;
    layers.Middle = 2;
    layers.AsInt = 0;
    layers.AsByte = 3u;
    Console.WriteLine("depth " + Text.FromInteger((long)layers.Depth)
        + ", middle " + Text.FromInteger((long)layers.Middle)
        + ", byte " + Text.FromInteger((long)layers.AsByte)
        + ", int " + Text.FromInteger((long)layers.AsInt));
    return 0;
}
