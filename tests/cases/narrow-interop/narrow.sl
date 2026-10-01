// SPDX-License-Identifier: 0BSD
//
// Narrow integers across the C boundary, with every bit the ABI leaves
// undefined set to garbage. Apple arm64 and x86-64 System V widen a narrow
// integer to 32 bits where it is produced -- the caller for an argument, the
// callee for a result -- and the other side reads the register whole, so a
// missing signext or zeroext hands over garbage there. Win64 and AAPCS64
// elsewhere widen nothing, and the reader MUST look at the width alone.
// narrow.c plays C on both sides of that, within the rules.
module NarrowInterop;

import Standard.Console;

// C producing: each returns a register holding the value, with garbage in
// every bit the ABI does not define.
extern "C" sbyte c_give_sbyte();
extern "C" byte c_give_byte();
extern "C" short c_give_short();
extern "C" ushort c_give_ushort();
extern "C" bool c_give_bool();
extern "C" char16 c_give_char16();

// C reading: each takes the register whole and answers the value when the
// bits the ABI requires of a caller held, and 999999 when they did not.
extern "C" long c_seen_sbyte(sbyte v);
extern "C" long c_seen_byte(byte v);
extern "C" long c_seen_short(short v);
extern "C" long c_seen_ushort(ushort v);
extern "C" long c_seen_bool(bool v);
extern "C" long c_seen_char16(char16 v);

extern "C" int c_opaque(int v);
extern "C" sbyte* c_sbyte_cell();
extern "C" short* c_short_cell();
extern "C" void c_call_stainless();

// Stainless reading what C passes with garbage above it.
export "C" long sl_take_sbyte(sbyte v) => (long)v;
export "C" long sl_take_byte(byte v) => (long)v;
export "C" long sl_take_short(short v) => (long)v;
export "C" long sl_take_ushort(ushort v) => (long)v;
export "C" long sl_take_bool(bool v) => v ? (long)1 : (long)0;
export "C" long sl_take_char16(char16 v) => (long)(ushort)v;
export "C" long sl_take_mixed(sbyte a, byte b, short c, ushort d) =>
    (long)a * 1000000 + (long)b * 10000 + (long)c * 10 + (long)d;

int Main()
{
    Console.WriteLine($"C gave sbyte {(long)c_give_sbyte()}");
    Console.WriteLine($"C gave byte {(long)c_give_byte()}");
    Console.WriteLine($"C gave short {(long)c_give_short()}");
    Console.WriteLine($"C gave ushort {(long)c_give_ushort()}");
    Console.WriteLine($"C gave bool {c_give_bool()}");
    Console.WriteLine($"C gave char16 {(long)(ushort)c_give_char16()}");

    // A truncation costs nothing in a register, so each of these leaves the
    // source's upper bits behind unless the call widens what it passes.
    Console.WriteLine($"C saw sbyte {c_seen_sbyte((sbyte)c_opaque(0x12345680))}");
    Console.WriteLine($"C saw byte {c_seen_byte((byte)c_opaque(0x123456F0))}");
    Console.WriteLine($"C saw short {c_seen_short((short)c_opaque(0x12348001))}");
    Console.WriteLine($"C saw ushort {c_seen_ushort((ushort)c_opaque(0x1234F00D))}");
    Console.WriteLine($"C saw bool {c_seen_bool((c_opaque(0x12345601) & 0xFF) == 1)}");
    Console.WriteLine($"C saw char16 {c_seen_char16((char16)(ushort)c_opaque(0x1234BEEF))}");

    // Loaded from memory, a narrow value is widened by whatever the load
    // does, which for a byte is usually with zeros: a negative one needs the
    // call to sign-extend it.
    Console.WriteLine($"C saw sbyte from memory {c_seen_sbyte(*c_sbyte_cell())}");
    Console.WriteLine($"C saw short from memory {c_seen_short(*c_short_cell())}");

    c_call_stainless();
    return 0;
}
