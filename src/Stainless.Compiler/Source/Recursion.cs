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

    /// <summary>
    /// Runs <paramref name="work"/> for every index below
    /// <paramref name="count"/>: on the calling thread, and on whichever of
    /// <see cref="s_helpers"/> are free to help. The caller MUST itself be on a
    /// deep stack, as a compilation is; the pool's own threads would do the
    /// work on a stack too shallow for <see cref="MaxDepth"/>.
    ///
    /// The caller takes indexes too, so this finishes even when every helper is
    /// busy with another compilation, as each test case's is in the suites.
    ///
    /// What one index threw is rethrown after all have run: the lowest index's,
    /// so the same input fails the same way however the threads were scheduled.
    /// </summary>
    public static void ForEachOnDeepStacks(int count, Action<int> work)
    {
        var failures = new System.Runtime.ExceptionServices.ExceptionDispatchInfo?[count];
        int next = -1;
        using var finished = new CountdownEvent(count);

        void Drain()
        {
            int index;
            while ((index = Interlocked.Increment(ref next)) < count)
            {
                try { work(index); }
                catch (Exception e)
                {
                    failures[index] = System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(e);
                }
                finally { finished.Signal(); }
            }
        }

        if (count == 0)
            return;

        for (int i = 1; i < Math.Min(count, s_helpers.Value.Count + 1); i++)
            s_work.Add(Drain);
        Drain();
        finished.Wait();

        foreach (var failure in failures)
            failure?.Throw();
    }

    /// <summary>Work for <see cref="s_helpers"/>, which any of them may take.</summary>
    private static readonly System.Collections.Concurrent.BlockingCollection<Action> s_work = [];

    /// <summary>
    /// A thread per processor but one, each with a deep stack, made the first
    /// time they are needed and kept. Making a thread with a stack this size
    /// is slow on macOS -- slower than the lexing it would do -- so it is done
    /// once per process rather than once per compilation.
    /// </summary>
    private static readonly Lazy<IReadOnlyList<Thread>> s_helpers = new(() =>
    {
        var threads = new List<Thread>();
        for (int i = 1; i < Environment.ProcessorCount; i++)
        {
            var thread = new Thread(
                () =>
                {
                    foreach (var job in s_work.GetConsumingEnumerable())
                        job();
                },
                StackBytes)
            {
                IsBackground = true,
                Name = "Stainless deep stack",
            };
            thread.Start();
            threads.Add(thread);
        }
        return threads;
    });
}
