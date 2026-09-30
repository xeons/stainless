// Stainless - an experimental general-purpose language.
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

module Standard;

/// Arrays of plain data as bytes. C#'s `System.Buffer`.
///
///     short[] samples = [1, -1];
///     var bytes = new byte[Buffer.ByteLength(samples)];
///     Buffer.BlockCopy(samples, 0u, bytes, 0u, bytes.Length);
///
/// Every element type is `unmanaged` (section 4.3): a value with no counted
/// reference anywhere in it, so moving its bytes cannot put a count out of
/// step. .NET asks for an array of primitives and checks it as the program
/// runs; the constraint checks it as the program is compiled, and also admits
/// a struct of primitives.
///
/// Offsets and counts are in bytes and are `nuint`. Every range is checked
/// against the array before a byte moves, and one that runs past the end
/// aborts, as an index out of range does. The bytes are in the machine's own
/// order.
public static class Buffer
{
    /// Copies `count` bytes from `srcOffset` bytes into `src` to `dstOffset`
    /// bytes into `dst`. The two arrays may be of different types, and may be
    /// the same array with overlapping ranges: the bytes land as they were
    /// before the copy began.
    ///
    /// A byte copied into a `bool`, an enum or a pointer need not be one of its
    /// values; the element types SHOULD be numbers or structs of them.
    ///
    /// @param src        where the bytes come from
    /// @param srcOffset  the first byte copied, counted from the start of `src`
    /// @param dst        where they go
    /// @param dstOffset  where the first lands, counted from the start of `dst`
    /// @param count      how many bytes to copy
    /// @typeparam TSource       the element type of `src`, which must be plain data
    /// @typeparam TDestination  the element type of `dst`, which must be plain data
    public static void BlockCopy<TSource, TDestination>(TSource[] src, nuint srcOffset,
        TDestination[] dst, nuint dstOffset, nuint count)
        where TSource : unmanaged
        where TDestination : unmanaged
    {
        nuint srcLength = ByteLength(src);
        nuint dstLength = ByteLength(dst);
        if (srcOffset > srcLength || count > srcLength - srcOffset)
            sl_fail("Buffer.BlockCopy: the source range runs past the array");
        if (dstOffset > dstLength || count > dstLength - dstOffset)
            sl_fail("Buffer.BlockCopy: the destination range runs past the array");
        if (count == 0u)
            return;

        memmove((byte*)&dst[0u] + dstOffset, (byte*)&src[0u] + srcOffset, count);
    }

    /// How many bytes the elements of `array` take.
    ///
    /// @param array  the array to measure
    /// @typeparam T  the element type, which must be plain data
    /// @returns the length times the size of one element
    public static nuint ByteLength<T>(T[] array) where T : unmanaged =>
        array.Length * sizeof(T);

    /// The byte at `index` bytes into `array`. Aborts when it is past the end.
    ///
    /// @param array  the array to read
    /// @param index  which byte, counted from the start
    /// @typeparam T  the element type, which must be plain data
    public static byte GetByte<T>(T[] array, nuint index) where T : unmanaged
    {
        if (index >= ByteLength(array))
            sl_fail("Buffer.GetByte: the index is past the end of the array");
        return ((byte*)&array[0u])[index];
    }

    /// Sets the byte at `index` bytes into `array`. Aborts when it is past the
    /// end.
    ///
    /// A byte written into a `bool`, an enum or a pointer need not leave one of
    /// its values; the element type SHOULD be a number or a struct of them.
    ///
    /// @param array  the array to write
    /// @param index  which byte, counted from the start
    /// @param value  what it becomes
    /// @typeparam T  the element type, which must be plain data
    public static void SetByte<T>(T[] array, nuint index, byte value) where T : unmanaged
    {
        if (index >= ByteLength(array))
            sl_fail("Buffer.SetByte: the index is past the end of the array");
        ((byte*)&array[0u])[index] = value;
    }

    /// Copies `sourceBytesToCopy` bytes from `source` to `destination`, which
    /// may overlap. Aborts when that is more than `destinationSizeInBytes`.
    ///
    /// Nothing else is checked, as nothing can be: both pointers MUST be valid
    /// for the bytes named, and the destination MUST NOT hold a counted
    /// reference.
    ///
    /// @param source                  where the bytes come from
    /// @param destination             where they go
    /// @param destinationSizeInBytes  how many bytes `destination` has room for
    /// @param sourceBytesToCopy       how many bytes to copy
    public static void MemoryCopy(void* source, void* destination, nuint destinationSizeInBytes,
        nuint sourceBytesToCopy)
    {
        if (sourceBytesToCopy > destinationSizeInBytes)
            sl_fail("Buffer.MemoryCopy: the destination is too small");
        if (sourceBytesToCopy == 0u)
            return;

        memmove((byte*)destination, (byte*)source, sourceBytesToCopy);
    }
}
