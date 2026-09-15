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
public variant Result<T, E>
{
    /// It worked, and `Value` is the answer.
    Ok(T Value);

    /// It did not, and `Error` says why. The value is not there to be read --
    /// that is the whole of what a variant buys over a pair.
    Fail(E Error);

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The one reader that needs no proof, because it supplies its own: a
    /// caller with a sensible default has nothing to check.
    public T ValueOr(T fallback)
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

/// Turns a T into an R. The transform half of `Map`.
public closure R Func<T, R>(T value);

/// Answers a question about a T.
public closure bool Predicate<T>(T value);

/// Does something with a T and returns nothing.
public closure void Action<T>(T value);

/// Folds one T into a running A. Two parameters rather than one, because a
/// fold is the one shape that carries something along with it.
public closure A Fold<A, T>(A total, T value);

/// Orders two Ts: negative if `left` comes first, positive if `right` does,
/// zero if neither.
///
/// This is what lets a type be sorted more than one way, and what lets a type
/// that implements no interface be sorted at all.
public closure int Comparer<T>(T left, T right);

// ---------------------------------------------------------- a value, or not

/// Aborts with a message. The same call a container makes when it is asked for
/// something it does not have.
extern "C" void sl_fail(byte* message);

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
///     if (map.IndexOf(key) is Some found) { return values.At(found.Value); }
///     return fallback;
///
/// **Not a replacement for `C?`.** A nullable reference stays what it is: the
/// representation is already free there, and `if (c != null)` narrows without
/// a case to name. This is for everything a null pointer cannot say -- which
/// is also why the names differ: `Optional<T>` is this type, and "an optional"
/// is what the spec calls `C?`.
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
    public bool HasValue()
    {
        if (this is Some)
            return true;
        return false;
    }

    /// True when there is not. The same question the other way round, because
    /// `!x.HasValue()` reads worse than the thing it means.
    public bool IsEmpty()
    {
        if (this is Some)
            return false;
        return true;
    }

    /// The value, aborting when there is none.
    ///
    /// The bargain `Dictionary.Get` and an array index make: asking for
    /// something that is not there is a mistake in the caller rather than a
    /// value to return. Use `ValueOr` where a miss is ordinary, and
    /// `is Some x` where the answer decides what happens next.
    public T Get()
    {
        if (this is Some held)
            return held.Value;

        sl_fail("Optional.Get: there is no value");

        // Unreachable: `sl_fail` ends the program, and an `extern` has no way
        // to say so. The tail has to be some expression of type T.
        return default(T);
    }

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The reader that needs no proof, because it supplies its own -- the same
    /// bargain `Result.ValueOr` makes.
    public T ValueOr(T fallback)
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
    public Optional<T> Or(Optional<T> other)
    {
        if (this is Some)
            return this;
        return other;
    }

    /// The value put through `transform`, or none.
    ///
    ///     Optional<String> name = found.Map(i => people.At(i).Name);
    ///
    /// The transform runs only where there is something to run it on, which is
    /// the point: it is the `if` that would otherwise be written by hand.
    public Optional<R> Map<R>(Func<T, R> transform)
    {
        if (this is Some held)
            return Some(transform(held.Value));
        return None;
    }

    /// `Map` for a transform that answers with an optional of its own, which
    /// would otherwise nest one inside the other.
    public Optional<R> FlatMap<R>(Func<T, Optional<R>> transform)
    {
        if (this is Some held)
            return transform(held.Value);
        return None;
    }

    /// This one when it holds something `keep` accepts, and none otherwise.
    public Optional<T> Filter(Predicate<T> keep)
    {
        if (this is Some held)
        {
            if (keep(held.Value))
                return this;
        }
        return None;
    }

    /// Runs `action` on the value, if there is one.
    public void IfPresent(Action<T> action)
    {
        if (this is Some held)
            action(held.Value);
    }
}
