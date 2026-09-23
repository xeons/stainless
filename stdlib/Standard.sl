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

/// What an operation produced, or why it did not.
///
/// This is the language's answer to an exception. Stainless does not unwind, so
/// a function that can fail says so in its return type and the caller cannot
/// quietly ignore it: `Value` is unreadable until the compiler has seen `Ok`
/// checked, and `Error` unreadable until it has seen it fail.
///
/// ```
/// Result<Config, IOError> Load(String path) {
///     var text = File.ReadAllText(path);
///     if (!text.Ok) { return Fail(text.Error); }
///     return Ok(Parse(text.Value));
/// }
/// ```
///
/// It is an ordinary variant, and every rule it appears to have is a rule
/// variants have. `Ok` and `Fail` are its two cases, so `r.Ok` asks the tag;
/// `Value` and `Error` are the fields those cases carry, so reading one needs
/// the compiler to have established which case is there; and both are written
/// without type arguments because a case takes its variant from where it is
/// going, the way a lambda takes its type from what it is assigned to.
///
/// Being a variant is also what makes it small. Only one case is ever present,
/// so the payloads overlap: a `Result<String, IOError>` is a tag and one
/// pointer, not a flag and both halves. Nothing allocates either way.
///
/// @typeparam T       what the call produces when it worked
/// @typeparam TError  why it did not, usually an enum so that a failure has a name rather than
///                    a number
public variant Result<T, TError>
{
    /// It worked, and `Value` is the answer.
    Ok(T Value);

    /// It did not, and `Error` says why. The value is not there to be read --
    /// that is the whole of what a variant buys over a pair.
    Fail(TError Error);

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The one reader that needs no proof, because it supplies its own: a
    /// caller with a sensible default has nothing to check.
    public T GetValueOrDefault(T fallback)
    {
        switch (this)
        {
            case Ok ok: return ok.Value;
            case Fail:  return fallback;
        }
    }
}

// --------------------------------------------------------- shapes of work

// What a lambda becomes, named once.
//
// A `closure` is a method and the object it belongs to, so a bound method and
// a lambda are the same thing and neither needs a declaration to hold it.
// They live here rather than in `Standard.Collections`, and need no import.

/// Turns a T into an R. The transform half of `Select`.
///
/// @typeparam T  what goes in
/// @typeparam R  what comes out
public closure R Func<T, R>(T value);

/// Answers a question about a T.
///
/// @typeparam T  what the question is about
public closure bool Predicate<T>(T value);

/// Does something with a T and returns nothing.
///
/// @typeparam T  what is handed to it
public closure void Action<T>(T value);

/// Folds one T into a running A. Two parameters rather than one, because a
/// fold is the one shape that carries something along with it.
///
/// @param total  what has been accumulated so far
/// @param value  the next element to fold in
/// @typeparam A  what is carried along, and what the fold answers with
/// @typeparam T  what is folded over
public closure A Fold<A, T>(A total, T value);

/// Orders two Ts: negative if `left` comes first, positive if `right` does,
/// zero if neither.
///
/// This is what lets a type be sorted more than one way, and what lets a type
/// that implements no interface be sorted at all.
///
/// @typeparam T  what is being ordered
public closure int Comparer<T>(T left, T right);

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

/// A value, or none -- for the types `T?` cannot describe.
///
/// `C?` is a nullable reference: the null is the pointer, so it costs nothing
/// and the compiler narrows it. A value type has no spare bit to be null with,
/// so `nuint?` is refused (SL0271), and what stood in was a magic number --
/// `IndexOf` answering with the largest `nuint` there is and every caller
/// agreeing to read that as "not there".
///
/// This is that, said properly. It is an ordinary variant, so it costs a tag
/// beside the value and nothing else: no allocation, and the payload is only
/// read where the compiler has established the case.
///
///     if (map.IndexOf(key) is Some found) { return values[found.Value]; }
///     return fallback;
///
/// **Not a replacement for `C?`.** A nullable reference stays what it is: the
/// representation is already free there, and `if (c != null)` narrows without
/// a case to name. This is for everything a null pointer cannot say -- which
/// is also why the names differ: `Optional<T>` is this type, and "an optional"
/// is what the spec calls `C?`.
///
/// @typeparam T  what it may hold -- a value type, usually, since a reference already has `C?`
public variant Optional<T>
{
    /// There is no value. Carries nothing, so there is nothing to read by
    /// mistake.
    None;

    /// There is one, and `Some` carries it. Reached with `is Some x`, which
    /// takes the value and names it in the same step.
    Some(T Value);

    /// True when there is a value. The reader for a caller that is about to
    /// ask a second question anyway; `is Some x` is the one that gets at it.
    public bool HasValue
    {
        get
        {
            if (this is Some)
                return true;
            return false;
        }
    }

    /// True when there is not. The same question the other way round, because
    /// `!x.HasValue` reads worse than the thing it means.
    public bool IsEmpty
    {
        get
        {
            if (this is Some)
                return false;
            return true;
        }
    }

    /// The value, aborting when there is none.
    ///
    /// The bargain `Dictionary.GetValue` and an array index make: asking for
    /// something that is not there is a mistake in the caller rather than a
    /// value to return. Use `GetValueOrDefault` where a miss is ordinary, and
    /// `is Some x` where the answer decides what happens next.
    ///
    /// @see Optional.GetValueOrDefault
    public T GetValue()
    {
        if (this is Some held)
            return held.Value;

        sl_fail("Optional.GetValue: there is no value");

        // Unreachable: `sl_fail` ends the program, and an `extern` has no way
        // to say so. The tail has to be some expression of type T.
        return default(T);
    }

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The reader that needs no proof, because it supplies its own -- the same
    /// bargain `Result.GetValueOrDefault` makes.
    ///
    /// @param fallback  what to answer when there is nothing held
    /// @see Optional.GetValue
    public T GetValueOrDefault(T fallback)
    {
        if (this is Some held)
            return held.Value;
        return fallback;
    }

    /// This one if it holds anything, and `other` if it does not.
    ///
    /// `other` is a value rather than something that produces one on demand.
    /// A lambda would allocate a closure to save an evaluation, which is the
    /// wrong way round at the sizes this is used at.
    public Optional<T> Coalesce(Optional<T> other)
    {
        if (this is Some)
            return this;
        return other;
    }

    /// The value put through `transform`, or none.
    ///
    ///     Optional<String> name = found.Select(i => people[i].Name);
    ///
    /// The transform runs only where there is something to run it on, which is
    /// the point: it is the `if` that would otherwise be written by hand.
    ///
    /// @typeparam R  what `transform` produces
    public Optional<R> Select<R>(Func<T, R> transform)
    {
        if (this is Some held)
            return Some(transform(held.Value));
        return None;
    }

    /// `Select` for a transform that answers with an optional of its own, which
    /// would otherwise nest one inside the other.
    ///
    /// @typeparam R  what the transform's own optional holds
    public Optional<R> SelectMany<R>(Func<T, Optional<R>> transform)
    {
        if (this is Some held)
            return transform(held.Value);
        return None;
    }

    /// This one when it holds something `keep` accepts, and none otherwise.
    public Optional<T> Where(Predicate<T> keep)
    {
        if (this is Some held)
        {
            if (keep(held.Value))
                return this;
        }
        return None;
    }

    /// Runs `action` on the value, if there is one.
    public void InvokeIfPresent(Action<T> action)
    {
        if (this is Some held)
            action(held.Value);
    }
}

// --------------------------------------------------- ordering and hashing

// The compiler lowers `CompareTo` and `HashCode` on a primitive, an enum or a
// `String` to one of these, and finds them here by name. A primitive is not a
// class, so `int` cannot be declared to implement `IComparable<int>`;
// recognising the two names instead is what makes `Sort(numbers)` work on a
// `List<int>` without the language growing operator constraints.
//
// None of them is public. Nothing in a program may name one, and the twenty
// short verbs an `import Standard.Collections` already brings in are enough.
//
// Equality is absent: `a == b` is an operator on every one of these types, so
// `EqualTo` lowers to that and costs nothing.

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
