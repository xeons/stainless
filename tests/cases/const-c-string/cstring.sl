// A C string constant: its bytes compiled in, terminated as C's are, and the
// constant their address wherever it is named -- what IOKit's
// `#define kIOServiceClass "IOService"` is.
module ConstCString;

import Standard.Console;

public const byte* ServiceClass = "IOService";
public const byte* Empty = "";

extern "C" nuint strlen(byte* text);

int Main()
{
    Console.WriteLine($"{strlen(ServiceClass)} bytes, {strlen(Empty)} in the empty one");
    Console.WriteLine($"first {(char32)ServiceClass[0]}, last {(char32)ServiceClass[8]}, then {ServiceClass[9]}");

    // Named twice, the same bytes.
    byte* again = ServiceClass;
    Console.WriteLine($"the same address: {again == ServiceClass}");
    return 0;
}
