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

/// The language's own vocabulary: the markers and types that are rules rather
/// than library features, and so need no import to reach.
module Standard;

// --------------------------------------------------------- shapes of work

// What a lambda becomes, named once.
//
// A `closure` is a method and the object it belongs to, so a bound method and
// a lambda are the same thing and neither needs a declaration to hold it.
// They live here rather than in `Standard.Collections`, and need no import.

/// Turns a T into a TResult. The transform half of `Select`.
///
/// @typeparam T        what goes in
/// @typeparam TResult  what comes out
public closure TResult Func<T, TResult>(T value);

/// Answers a question about a T.
///
/// @typeparam T  what the question is about
public closure bool Predicate<T>(T value);

/// Does something with a T and returns nothing.
///
/// @typeparam T  what is handed to it
public closure void Action<T>(T value);

/// Folds one element into a running total. Two parameters rather than one,
/// because a fold is the one shape that carries something along with it.
///
/// @param total  what has been accumulated so far
/// @param value  the next element to fold in
/// @typeparam TAccumulate  what is carried along, and what the fold answers with
/// @typeparam TSource      what is folded over
public closure TAccumulate Fold<TAccumulate, TSource>(TAccumulate total, TSource value);

/// Orders two Ts: negative if `left` comes first, positive if `right` does,
/// zero if neither.
///
/// This is what lets a type be sorted more than one way, and what lets a type
/// that implements no interface be sorted at all.
///
/// @typeparam T  what is being ordered
public closure int Comparison<T>(T left, T right);

// ---------------------------------------------------------- a value, or not

/// Aborts with a message. The same call a container makes when it is asked for
/// something it does not have.
extern "C" void sl_fail(byte* message);

/// A subscription that does not keep its subscriber alive; see runtime/arc.c.
/// Called only from the accessors and thunks the compiler writes for an event.
extern "C"
{
    byte* sl_weak_cell_new(byte* function, byte* target);
    byte* sl_weak_cell_load(byte* cell, byte** function);
    int   sl_weak_cell_matches(byte* cell, byte* function, byte* target);
    int   sl_weak_cell_is_dead(byte* cell);
    void  sl_release(byte* pointer);
}

// --------------------------------------------------- ordering and hashing

// The compiler lowers `CompareTo` and `GetHashCode` on a primitive, an enum or a
// `String` to one of these, and finds them here by name. A primitive is not a
// class, so `int` cannot be declared to implement `IComparable<int>`;
// recognising the two names instead is what makes `Sort(numbers)` work on a
// `List<int>` without the language growing operator constraints.
//
// None of them is public. Nothing in a program may name one, and the twenty
// short verbs an `import Standard.Collections` already brings in are enough.
//
// Equality is absent: `a == b` is an operator on every one of these types, so
// `Equals` lowers to that and costs nothing.

extern "C" int memcmp(byte* left, byte* right, nuint count);

int CompareLong(long left, long right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

int CompareULong(ulong left, ulong right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

/// Ordering doubles has to answer for NaN, which compares false against
/// everything including itself. A sort needs a total order or it does not
/// terminate, so NaN is placed before every number and equal to itself --
/// the rule .NET settled on, for the same reason.
int CompareDouble(double left, double right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    if (left == right)
        return 0;

    bool leftIsNan = left != left;
    bool rightIsNan = right != right;
    if (leftIsNan && rightIsNan)
        return 0;
    return leftIsNan ? -1 : 1;
}

/// Ordinal, by byte. UTF-8 sorts its code points in the same order as its
/// bytes, so this orders code points too -- but it is not a collation and is
/// not meant to be shown to a person as one.
int CompareText(String left, String right)
{
    // Identity, which `==` on a String does not answer: it compares bytes.
    // Sorting hands the same object to this often enough to be worth a test.
    if ((byte*)left == (byte*)right)
        return 0;

    nuint leftLength = left.ByteLength();
    nuint rightLength = right.ByteLength();
    nuint shared = leftLength < rightLength ? leftLength : rightLength;

    int result = memcmp(left.ToPointer(), right.ToPointer(), shared);
    if (result != 0)
        return result < 0 ? -1 : 1;

    if (leftLength == rightLength)
        return 0;
    return leftLength < rightLength ? -1 : 1;
}

/// splitmix64's finalizer. Every input bit affects every output bit, which is
/// what a table indexed by the low bits needs: without it, keys 0, 8 and 16
/// land in the same bucket of an eight-slot table.
nuint HashInteger(ulong value)
{
    value += 0x9E3779B97F4A7C15;
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9;
    value = (value ^ (value >> 27)) * 0x94D049BB133111EB;
    return (nuint)(value ^ (value >> 31));
}

/// Doubles that compare equal MUST hash equal, so the two values that would
/// break that are normalised first: -0.0 equals 0.0, and every NaN is equal to
/// every other under `CompareDouble`.
nuint HashDouble(double value)
{
    if (value == 0.0)
        return HashInteger(0);
    if (value != value)
        return HashInteger(0x7FF8000000000000);

    ulong bits = *(ulong*)&value;
    return HashInteger(bits);
}

/// FNV-1a over the bytes. Short, no table, and good enough for a hash table.
nuint HashText(String value)
{
    byte* bytes = value.ToPointer();
    nuint length = value.ByteLength();

    ulong hash = 0xCBF29CE484222325;
    for (nuint i = 0u; i < length; i++)
    {
        hash ^= (ulong)bytes[i];
        hash *= 0x100000001B3;
    }

    // Mixed again, because FNV's low bits are the weakest part of it.
    return HashInteger(hash);
}
