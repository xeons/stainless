/* SPDX-License-Identifier: 0BSD */
#include <stdint.h>
#include <stdio.h>

/* Apple arm64 and x86-64 System V widen a narrow integer to 32 bits where it
   is produced and leave bits 32 to 63 undefined. Win64 and AAPCS64 elsewhere
   leave every bit above the width undefined. */
#if defined(__APPLE__) || (defined(__x86_64__) && !defined(_WIN32))
#define WIDENED_TO_32 1
#else
#define WIDENED_TO_32 0
#endif

static const uint64_t garbage = 0xA5C3E1F0B4D29687ull;

/* `value` in a register as a producer may legally leave it: the bits the ABI
   defines are right, and every other bit is garbage. */
static uint64_t dirty(int64_t value, int width, int is_signed)
{
    uint64_t mask = (1ull << width) - 1;
    uint64_t low = (uint64_t)value & mask;
    if (WIDENED_TO_32)
    {
        uint32_t widened = is_signed ? (uint32_t)(int32_t)value : (uint32_t)low;
        return (garbage & 0xFFFFFFFF00000000ull) | widened;
    }
    return (garbage & ~mask) | low;
}

/* Whether a register a caller produced holds what the ABI requires of it. */
static int widened(uint64_t raw, int width, int is_signed)
{
    if (!WIDENED_TO_32)
        return 1;
    uint32_t low = (uint32_t)raw;
    uint32_t mask = (1u << width) - 1;
    uint32_t sign = 1u << (width - 1);
    uint32_t expected = is_signed && (low & sign) ? (low | ~mask) : (low & mask);
    return low == expected;
}

/* Declared in narrow.sl as returning the narrow type. */
uint64_t c_give_sbyte(void) { return dirty(-100, 8, 1); }
uint64_t c_give_byte(void) { return dirty(200, 8, 0); }
uint64_t c_give_short(void) { return dirty(-30000, 16, 1); }
uint64_t c_give_ushort(void) { return dirty(60000, 16, 0); }
uint64_t c_give_bool(void) { return dirty(1, 8, 0); }
uint64_t c_give_char16(void) { return dirty(0x263A, 16, 0); }

/* Declared in narrow.sl as taking the narrow type. */
int64_t c_seen_sbyte(uint64_t raw) { return widened(raw, 8, 1) ? (int8_t)raw : 999999; }
int64_t c_seen_byte(uint64_t raw) { return widened(raw, 8, 0) ? (uint8_t)raw : 999999; }
int64_t c_seen_short(uint64_t raw) { return widened(raw, 16, 1) ? (int16_t)raw : 999999; }
int64_t c_seen_ushort(uint64_t raw) { return widened(raw, 16, 0) ? (uint16_t)raw : 999999; }
int64_t c_seen_bool(uint64_t raw) { return widened(raw, 8, 0) ? (uint8_t)raw : 999999; }
int64_t c_seen_char16(uint64_t raw) { return widened(raw, 16, 0) ? (uint16_t)raw : 999999; }

int32_t c_opaque(int32_t v) { return v; }

static int8_t sbyte_cell = -128;
static int16_t short_cell = -32767;
int8_t *c_sbyte_cell(void) { return &sbyte_cell; }
int16_t *c_short_cell(void) { return &short_cell; }

int64_t sl_take_sbyte(int8_t v);
int64_t sl_take_byte(uint8_t v);
int64_t sl_take_short(int16_t v);
int64_t sl_take_ushort(uint16_t v);
int64_t sl_take_bool(_Bool v);
int64_t sl_take_char16(uint16_t v);
int64_t sl_take_mixed(int8_t a, uint8_t b, int16_t c, uint16_t d);

typedef int64_t (*Wide1)(uint64_t);
typedef int64_t (*Wide4)(uint64_t, uint64_t, uint64_t, uint64_t);

/* Called through pointers that pass whole registers, and volatile so that the
   optimiser cannot put the real prototype back. */
void c_call_stainless(void)
{
    Wide1 volatile sbyte_ = (Wide1)sl_take_sbyte;
    Wide1 volatile byte_ = (Wide1)sl_take_byte;
    Wide1 volatile short_ = (Wide1)sl_take_short;
    Wide1 volatile ushort_ = (Wide1)sl_take_ushort;
    Wide1 volatile bool_ = (Wide1)sl_take_bool;
    Wide1 volatile char16_ = (Wide1)sl_take_char16;
    Wide4 volatile mixed = (Wide4)sl_take_mixed;

    printf("Stainless saw sbyte %lld\n", (long long)sbyte_(dirty(-77, 8, 1)));
    printf("Stainless saw byte %lld\n", (long long)byte_(dirty(250, 8, 0)));
    printf("Stainless saw short %lld\n", (long long)short_(dirty(-12345, 16, 1)));
    printf("Stainless saw ushort %lld\n", (long long)ushort_(dirty(54321, 16, 0)));
    printf("Stainless saw bool %lld\n", (long long)bool_(dirty(1, 8, 0)));
    printf("Stainless saw char16 %lld\n", (long long)char16_(dirty(0x2603, 16, 0)));
    printf("Stainless saw mixed %lld\n",
           (long long)mixed(dirty(-5, 8, 1), dirty(7, 8, 0), dirty(-3, 16, 1), dirty(9, 16, 0)));
    fflush(stdout);
}
