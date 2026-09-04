// COM against the real thing.
//
// Everything in tests/cases/com is Stainless on both sides of the vtable, so
// it proves the layout is self-consistent and not that it is COM's. This one
// hands the IID to a Windows factory and calls back through a vtable
// Microsoft built, which is the only way to find out.
//
// IShellItem was chosen because it needs no registry entry, no apartment
// beyond the one CoInitializeEx makes, and no object to be running: the shell
// answers for a path that is on every Windows machine.
module ComShell;

import Standard.Console;
import Standard.Text;
import Standard.Com;

public extern "C" {
    int  CoInitializeEx(byte* reserved, uint flags);
    void CoUninitialize();
    int  SHCreateItemFromParsingName(char16* path, byte* bindContext,
                                     Guid* iid, byte** result);
    void CoTaskMemFree(byte* block);
}

[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
public com interface IShellItem {
    int BindToHandler(byte* bindContext, Guid* handler, Guid* iid, byte** result);
    int GetParent(byte** parent);
    int GetDisplayName(uint kind, char16** name);
    int GetAttributes(uint mask, uint* attributes);
    int Compare(byte* other, uint hint, int* order);
}

const uint ApartmentThreaded = 2u;
const uint NormalDisplay     = 0u;

public void Main() {
    CoInitializeEx(null, ApartmentThreaded);

    byte* raw = null;
    int hr = SHCreateItemFromParsingName(
        "C:\\Windows".ToUtf16().ToPointer(), null, iidof(IShellItem), &raw);

    if (hr < 0) {
        Console.WriteLine("SHCreateItemFromParsingName failed");
        CoUninitialize();
        return;
    }

    // The factory wrote a reference already at +1 through the byte**, and this
    // is where ARC takes charge of it: the cast adopts, and the release at the
    // end of Main is emitted rather than written.
    IShellItem item = (IShellItem)raw;

    char16* name = null;
    if (item.GetDisplayName(NormalDisplay, &name) >= 0) {
        Console.WriteLine("display name: " + Text.FromNullTerminatedUtf16(name));
        CoTaskMemFree((byte*)name);
    }

    uint attributes = 0u;
    item.GetAttributes(0xFFFFFFFFu, &attributes);
    Console.WriteLine("attributes non-zero: " + Text.FromBool(attributes != 0u));

    Console.WriteLine("done");
    CoUninitialize();
}
