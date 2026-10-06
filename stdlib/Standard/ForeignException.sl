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

extern "C" int sl_foreign_kind(byte* caught);
extern "C" byte* sl_foreign_name(byte* caught);
extern "C" byte* sl_foreign_reason(byte* caught);
extern "C" void sl_foreign_free(byte* caught);

/// What a foreign function threw, caught at the call that a `[Throws]`
/// declaration made.
///
/// **Not an exception in Stainless.** Nothing unwinds through Stainless code:
/// the one call a binding marks `[Throws]` catches what it throws and answers
/// it as a value, a `Result<T, ForeignException>` or, for a call that produces
/// nothing, a `ForeignException?` that is null when it worked.
///
/// ```
/// [Throws]
/// [Selector("readDataOfLength:")]
/// public Result<NSData, ForeignException> ReadDataOfLength(nuint length);
///
/// var read = handle.ReadDataOfLength(64u);
/// if (!read.Ok)
///     Console.WriteLine(read.Error.Name + ": " + read.Error.Reason);
/// ```
public sealed class ForeignException
{
    /// Which language threw it.
    public ForeignExceptionKind Kind { get; }

    /// An `NSException`'s name -- `NSInvalidArgumentException` -- and empty
    /// for anything else.
    public String Name { get; }

    /// An `NSException`'s reason, and empty for anything else.
    public String Reason { get; }

    ForeignException(ForeignExceptionKind kind, String name, String reason)
    {
        Kind = kind;
        Name = name;
        Reason = reason;
    }

    /// What was caught, from the record the call's landing pad left, which
    /// this frees. Called by the code the compiler writes for a `[Throws]`
    /// call and by nothing else.
    public static ForeignException Take(byte* caught)
    {
        var made = new ForeignException((ForeignExceptionKind)sl_foreign_kind(caught),
                                         Text.FromNullTerminated(sl_foreign_name(caught)),
                                         Text.FromNullTerminated(sl_foreign_reason(caught)));
        sl_foreign_free(caught);
        return made;
    }
}
