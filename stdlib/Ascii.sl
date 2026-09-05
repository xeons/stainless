// Stainless - an experimental systems language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Asking what a byte is, when the answer is allowed to be an ASCII one.
//
// Every function here works on one byte and says nothing about Unicode. That
// is not a limitation being apologised for -- it is the whole point. A byte
// above 127 in UTF-8 is part of a character rather than a character, so a
// question like "is this a digit" has exactly one honest answer at the byte
// level, and it is this one. Anything that needs to ask about a character
// should decode first, with `String.CodePointAt`.
//
// This is a module of its own rather than more of `Standard.Text` because
// `Standard.Text` is imported into every module whether a program asks or not,
// and `IsDigit` is far too good a name to take from every program in the world.
module Standard.Ascii;

/// True for space, tab, newline, vertical tab, form feed and carriage return.
public bool IsWhiteSpace(byte value) {
    return value == 32 || (value >= 9 && value <= 13);
}

/// True for `0`-`9`.
public bool IsDigit(byte value) {
    return value >= 48 && value <= 57;
}

/// True for `0`-`9`, `a`-`f` and `A`-`F`.
public bool IsHexDigit(byte value) {
    return IsDigit(value)
        || (value >= 97 && value <= 102)
        || (value >= 65 && value <= 70);
}

/// True for `A`-`Z` and `a`-`z`.
public bool IsLetter(byte value) {
    return IsUpper(value) || IsLower(value);
}

/// True for a letter or a digit.
public bool IsLetterOrDigit(byte value) {
    return IsLetter(value) || IsDigit(value);
}

/// True for `A`-`Z`.
public bool IsUpper(byte value) {
    return value >= 65 && value <= 90;
}

/// True for `a`-`z`.
public bool IsLower(byte value) {
    return value >= 97 && value <= 122;
}

/// True for a byte below 128, which is the only range where any of this is
/// also true of the character.
public bool IsAscii(byte value) {
    return value < 128;
}

/// True for a control character: below 32, or DEL.
public bool IsControl(byte value) {
    return value < 32 || value == 127;
}

/// The uppercase of an ASCII letter, or the byte unchanged.
public byte ToUpper(byte value) {
    if (IsLower(value)) { return (byte)(value - 32); }
    return value;
}

/// The lowercase of an ASCII letter, or the byte unchanged.
public byte ToLower(byte value) {
    if (IsUpper(value)) { return (byte)(value + 32); }
    return value;
}

/// What a hexadecimal digit is worth, or -1 when it is not one.
public int HexValue(byte value) {
    if (IsDigit(value)) { return (int)value - 48; }
    if (value >= 97 && value <= 102) { return (int)value - 87; }
    if (value >= 65 && value <= 70) { return (int)value - 55; }
    return -1;
}

/// The lowercase hexadecimal digit for a value from 0 to 15.
public byte HexDigit(int value) {
    if (value < 10) { return (byte)(48 + value); }
    return (byte)(87 + value);
}

/// The uppercase hexadecimal digit for a value from 0 to 15.
public byte HexDigitUpper(int value) {
    if (value < 10) { return (byte)(48 + value); }
    return (byte)(55 + value);
}
