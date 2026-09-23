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
    /// @typeparam TResult  what `transform` produces
    public Optional<TResult> Select<TResult>(Func<T, TResult> transform)
    {
        if (this is Some held)
            return Some(transform(held.Value));
        return None;
    }

    /// `Select` for a transform that answers with an optional of its own, which
    /// would otherwise nest one inside the other.
    ///
    /// @typeparam TResult  what the transform's own optional holds
    public Optional<TResult> SelectMany<TResult>(Func<T, Optional<TResult>> transform)
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
