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

// Deciding whether two spellings name one source file.
//
// Its own file because nothing here needs a process, a target or a binding. A
// test of it compiles this and nothing else.
module Debugger;

import Standard.Text;
import Standard.Path;

/// Whether two paths name the same source file, allowing for the shapes debug
/// information puts them in.
///
/// It is a heuristic, not a fact about paths, which is why it is not named
/// after `Standard.Path.IsSamePath` -- and why a caller wanting the fact MUST
/// use that instead.
///
/// Two things it allows for. Separators are mixed: a `DW_AT_decl_file` on
/// Windows reads `C:\p\obj\stdlib/Text.sl`, one from each half of a join.
/// Roots differ: the compiler records the path it was given, which is relative
/// when the build ran in the project's directory, and an editor holds an
/// absolute one.
///
/// So a suffix beginning at a separator counts. A suffix and not a file name:
/// matching on the name alone would make `src/Text.sl` and `tests/Text.sl` one
/// file.
public bool IsTheSameSourceFile(String left, String right)
{
    if (Standard.Path.IsSamePath(left, right))
        return true;

    nuint a = left.ByteLength();
    nuint b = right.ByteLength();
    if (a == b)
        return false;
    return a > b ? PathEndsWithTail(left, right) : PathEndsWithTail(right, left);
}

/// Whether `full` ends with `tail` at a separator boundary. `tail` is strictly
/// the shorter of the two.
bool PathEndsWithTail(String full, String tail)
{
    nuint a = full.ByteLength();
    nuint b = tail.ByteLength();
    if (b == 0u)
        return false;

    if (!Standard.Path.IsSamePath(full.Substring(a - b, b), tail))
        return false;

    byte before = full.GetByteAt(a - b - 1u);
    return before == (byte)47 || before == (byte)92;
}
