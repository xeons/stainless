// A binding's half: handles that are told apart, and names for what the API
// calls things.
//
// `struct HWND__;` is C's incomplete type. Nothing here knows what a window is
// and nothing ever will, so the only thing that can be done with one is point
// at it -- which is the whole of what a handle is. `HWND__*` and `HDC__*` are
// different types because they point at different things, so a mix-up is caught
// and costs nothing at run time: neither type is laid out, emitted, or present
// in the binary at all.
module Platform;

public struct HWND__;
public struct HDC__;
public struct HKEY__;

public using HWND = HWND__*;
public using HDC  = HDC__*;
public using HKEY = HKEY__*;

/// A weak alias over a primitive. It is the type it names, so this costs
/// nothing and converts nothing; what it buys is a signature that says what it
/// is for.
public using Result = int;
public using Bytes  = byte*;

/// An alias may name another alias.
public using Status = Result;

/// And a compound type, which is where the reading is worst without one.
public using Callback = ClickHandler;
public delegate int ClickHandler(int x, int y);

public const Result Ok = 0;
public const Result Failed = -1;

/// The handles are made from integers here, since there is no real window to
/// ask for. What matters is that the types stay apart on the way through.
public HWND WindowAt(nuint slot) { return (HWND)slot; }
public HDC  DeviceAt(nuint slot) { return (HDC)slot; }

public nuint SlotOf(HWND window) { return (nuint)window; }

public Status Check(HWND window, HDC device) {
    if (window == null) { return Failed; }
    if (device == null) { return Failed; }
    return Ok;
}
