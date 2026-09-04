// The consuming half: an imported alias is a name like any other.
module App;

import Standard.Console;
import Standard.Text;
import Platform;

/// A local alias over an imported one.
using Slot = nuint;

/// And one that names an imported alias directly, so the chain crosses a module.
using Code = Status;

int Doubled(int x, int y) { return (x + y) * 2; }

int Main() {
    // An alias is the type it names, so this is the same `nuint` throughout.
    Slot slot = (Slot)7;

    HWND window = WindowAt(slot);
    HDC  device = DeviceAt((nuint)3);

    Console.WriteLine("slot: " + Text.FromInteger(SlotOf(window)));

    Code status = Check(window, device);
    Console.WriteLine("status: " + Text.FromInteger(status));

    // Null is a pointer of any of these types, and each stays its own.
    HWND none = null;
    Console.WriteLine("none: " + Text.FromInteger(Check(none, device)));

    // A weak alias converts nothing, because there is nothing to convert: a
    // `Result` is an `int` and an `int` is a `Result`.
    Result r = 5;
    int plain = r;
    Console.WriteLine("weak: " + Text.FromInteger(plain + status));

    // An alias over a delegate names the same function pointer.
    Callback handler = Doubled;
    Console.WriteLine("callback: " + Text.FromInteger(handler(3, 4)));

    // The qualified spelling reaches an alias exactly as it reaches a type.
    Platform.HDC other = DeviceAt((nuint)9);
    Console.WriteLine("other: " + Text.FromInteger(Check(window, other)));

    return 0;
}
