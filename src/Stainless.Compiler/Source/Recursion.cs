// Stainless - an experimental systems language.
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

namespace Stainless.Source;

/// <summary>
/// How deep a nested construct may go, and the stack that makes the limit a
/// policy rather than a cliff.
///
/// A recursive-descent parser and a tree-walking binder both recurse once per
/// level of nesting, so a file nested deeply enough ends the process with a
/// stack overflow -- which .NET cannot catch, so there is no diagnostic, no
/// exit code worth reading and nothing to tell the author which file did it.
/// That is the one answer a compiler must never give: every input gets a
/// diagnostic or a program.
///
/// Two things are needed and neither is enough alone. The **limit** turns the
/// crash into a message, and it has to be a fixed number rather than a probe
/// so the same file is refused on every machine. The **stack** is what keeps
/// the limit from having to be small: on a default one, a few hundred nested
/// parentheses are already fatal, which is low enough that generated source
/// could reach it honestly. Reserving a large one is free -- it is address
/// space, committed a page at a time as it is used -- and moves the real
/// ceiling far above the limit, so what a program meets is the message.
/// </summary>
public static class Recursion
{
    /// <summary>
    /// The most levels of nesting a construct may have: expressions inside
    /// expressions, blocks inside blocks, types inside types.
    ///
    /// Far past anything written by hand, and past what a generator produces:
    /// the deepest nesting in this repository's own sources, the standard
    /// library and the tests included, is under twenty. It is a bound on
    /// absurdity, not a budget anything is expected to spend.
    /// </summary>
    public const int MaxDepth = 500;

    /// <summary>The stack a compilation runs on. Reserved, not committed.</summary>
    private const int StackBytes = 64 * 1024 * 1024;

    /// <summary>
    /// Runs <paramref name="work"/> on a thread with a stack deep enough for
    /// <see cref="MaxDepth"/> levels of it, and hands back what it returned.
    ///
    /// An exception is carried across rather than swallowed, so a caller sees
    /// exactly what it would have seen had the work run in place.
    /// </summary>
    public static T OnADeepStack<T>(Func<T> work)
    {
        T result = default!;
        System.Runtime.ExceptionServices.ExceptionDispatchInfo? failure = null;

        var thread = new Thread(
            () =>
            {
                try { result = work(); }
                catch (Exception e)
                {
                    failure = System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(e);
                }
            },
            StackBytes);

        thread.Start();
        thread.Join();

        failure?.Throw();
        return result;
    }
}
