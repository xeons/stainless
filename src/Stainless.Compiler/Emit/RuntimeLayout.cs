// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using Stainless.Binding;

namespace Stainless.Emit;

/// <summary>
/// Where each field of the runtime's structs sits, for the emitter to reach.
///
/// <para>
/// Every one of these was a number written into a <c>getelementptr</c> --
/// <c>i64 24</c> for an array's length, <c>i64 72</c> for a vtable -- and every
/// one of them was right only because a pointer was eight bytes. They are
/// counted in words here instead, from the declarations in
/// <c>runtime/stainless.h</c>, so that a 32-bit target gets 12 and 36 without
/// anything else changing.
/// </para>
///
/// <para>
/// <b>Every field in these structs is one word.</b> That is not a coincidence
/// to be relied on blindly -- it is what the runtime declares: a <c>size_t</c>
/// or a pointer, and nothing else, in every struct the emitter reaches into.
/// The one exception is <c>SlAttributeValue.number</c>, which is an
/// <c>int64_t</c> and which the emitter never indexes.
/// </para>
/// </summary>
internal static class RuntimeLayout
{
    private static int Word => TargetPlatform.Current.PointerWidth;

    // ------------------------------------------------------- SlObject

    /// <summary>The strong count, at the start of every reference type.</summary>
    public const int Strong = 0;

    /// <summary>The weak count.</summary>
    public static int Weak => Word;

    /// <summary>The TypeInfo pointer, which a virtual call loads first.</summary>
    public static int TypeInfo => Word * 2;

    // -------------------------------------------------------- SlArray

    /// <summary><c>SlArray.length</c>, straight after the object header.</summary>
    public static int ArrayLength => Word * 3;

    // ------------------------------------------------------- SlString

    /// <summary><c>SlString.byteLength</c>, in the same slot an array's
    /// length occupies.</summary>
    public static int StringByteLength => Word * 3;

    // ----------------------------------------------------- SlTypeInfo

    /// <summary><c>size</c>: header and fields, in bytes.</summary>
    public const int TypeInfoSize = 0;

    /// <summary><c>destroy</c>.</summary>
    public static int TypeInfoDestroy => Word;

    /// <summary><c>name</c>.</summary>
    public static int TypeInfoName => Word * 2;

    /// <summary><c>interfaces</c>: the table an interface dispatch indexes.</summary>
    public static int TypeInfoInterfaces => Word * 3;

    /// <summary><c>fieldCount</c>.</summary>
    public static int TypeInfoFieldCount => Word * 4;

    /// <summary><c>fields</c>.</summary>
    public static int TypeInfoFields => Word * 5;

    /// <summary><c>attributeCount</c>.</summary>
    public static int TypeInfoAttributeCount => Word * 6;

    /// <summary><c>attributes</c>.</summary>
    public static int TypeInfoAttributes => Word * 7;

    /// <summary>
    /// <c>base</c>: the class this one derives from.
    ///
    /// Nothing emitted reads it -- a downcast asks <c>sl_is_instance</c>, which
    /// walks the chain in C -- but it is counted here so the fields after it
    /// are not counted from a number nobody can check.
    /// </summary>
    public static int TypeInfoBase => Word * 8;

    /// <summary><c>vtable</c>: what a virtual call indexes.</summary>
    public static int TypeInfoVTable => Word * 9;

    /// <summary><c>com</c>: a com class's tear-off table.</summary>
    public static int TypeInfoCom => Word * 10;

    /// <summary><c>propertyCount</c>.</summary>
    public static int TypeInfoPropertyCount => Word * 11;

    /// <summary><c>properties</c>.</summary>
    public static int TypeInfoProperties => Word * 12;

    // -------------------------------------------------------- tear-off

    /// <summary>
    /// A com tear-off's second word: how far into the object the tear-off
    /// sits, so a method reached through it can find the object again.
    /// </summary>
    public static int TearOffOwner => Word;
}
