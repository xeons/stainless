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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Binding that may be thrown away: an overload tried and rejected, a lambda's
/// body bound to learn its result, a guess at what a name is.
/// </summary>
/// <remarks>
/// <para>
/// Binding one expression can change the program as well as describe it: it
/// instantiates generics and queues their bodies, makes closure classes and
/// array types, records a member as written. A trial that is kept keeps all of
/// that. A trial that is discarded takes it all back, so a candidate that lost
/// leaves nothing behind to be emitted.
/// </para>
/// <para>
/// A quiet trial also mutes what it reports, because a complaint from a guess
/// is not about the program. What an instantiation made inside one reports is
/// held rather than muted: it is about the instantiation, which the cache
/// would otherwise hand to the real bind without it. It is reported when the
/// outermost trial is kept, and dropped with the instantiation when it is not.
/// </para>
/// </remarks>
public sealed partial class Binder
{
    private sealed class Trial
    {
        public required Trial? Outer { get; init; }

        /// <summary>What discarding takes back, in the order it was done.</summary>
        public List<Action> Undo { get; } = [];

        /// <summary>What instantiations made in the trial reported.</summary>
        public List<Diagnostic> Owed { get; } = [];

        // Lists only ever appended to while a trial is open: discarding one
        // cuts each back to its length when the trial began.
        public required int Classes { get; init; }
        public required int Interfaces { get; init; }
        public required int Structs { get; init; }
        public required int Functions { get; init; }
        public required int Pending { get; init; }
        public required int MemberCaptures { get; init; }
        public required int ClosureCount { get; init; }
    }

    private Trial? _trial;

    /// <summary>
    /// Opens a trial, discarded when the result is disposed unless
    /// <see cref="TrialScope.Accept"/> was called first.
    /// </summary>
    private TrialScope BeginTrial(bool quiet = true)
    {
        _trial = new Trial
        {
            Outer = _trial,
            Classes = _classes.Count,
            Interfaces = _interfaces.Count,
            Structs = _structs.Count,
            Functions = _functions.Count,
            Pending = _pending.Count,
            MemberCaptures = _memberCaptures.Count,
            ClosureCount = _closureCount,
        };

        return new TrialScope(this, _trial, quiet ? diagnostics.Muted() : null);
    }

    private sealed class TrialScope(Binder binder, Trial trial, DiagnosticBag.Mute? mute)
        : IDisposable
    {
        private bool _accepted;
        private bool _ended;

        /// <summary>Keeps what the trial did.</summary>
        public void Accept() => _accepted = true;

        public void Dispose()
        {
            if (_ended) return;
            _ended = true;

            mute?.Dispose();
            binder.EndTrial(trial, _accepted);
        }
    }

    private void EndTrial(Trial trial, bool accepted)
    {
        if (!ReferenceEquals(_trial, trial))
            throw new InternalCompilerError("a trial was ended out of order");

        _trial = trial.Outer;

        if (accepted)
        {
            if (trial.Outer is { } outer)
            {
                outer.Undo.AddRange(trial.Undo);
                outer.Owed.AddRange(trial.Owed);
            }
            else
            {
                foreach (var owed in trial.Owed) ReportOwed(owed);
            }

            return;
        }

        for (int i = trial.Undo.Count - 1; i >= 0; i--) trial.Undo[i]();

        _classes.RemoveRange(trial.Classes, _classes.Count - trial.Classes);
        _interfaces.RemoveRange(trial.Interfaces, _interfaces.Count - trial.Interfaces);
        _structs.RemoveRange(trial.Structs, _structs.Count - trial.Structs);
        _functions.RemoveRange(trial.Functions, _functions.Count - trial.Functions);
        _pending.RemoveRange(trial.Pending, _pending.Count - trial.Pending);
        _memberCaptures.RemoveRange(
            trial.MemberCaptures, _memberCaptures.Count - trial.MemberCaptures);
        _closureCount = trial.ClosureCount;
    }

    /// <summary>Takes <paramref name="undo"/> back if the trial open now is discarded.</summary>
    private void UndoOnDiscard(Action undo) => _trial?.Undo.Add(undo);

    /// <summary>A table entry that a discarded trial takes back.</summary>
    private void Remember<TKey, TValue>(Dictionary<TKey, TValue> table, TKey key, TValue value)
        where TKey : notnull
    {
        bool had = table.TryGetValue(key, out var old);
        table[key] = value;

        if (had)
            UndoOnDiscard(() => table[key] = old!);
        else
            UndoOnDiscard(() => table.Remove(key));
    }

    /// <summary>
    /// A set member that a discarded trial takes back. False when it was one
    /// already.
    /// </summary>
    private bool Remember<T>(HashSet<T> set, T item)
    {
        if (!set.Add(item)) return false;

        UndoOnDiscard(() => set.Remove(item));
        return true;
    }

    /// <summary>A list entry that a discarded trial takes back.</summary>
    private void Remember<T>(List<T> list, T item)
    {
        list.Add(item);
        UndoOnDiscard(() => list.Remove(item));
    }

    /// <summary>
    /// Keeps what an instantiation reports for the trial it was made in, until
    /// the result is disposed. Outside a trial it is reported, and kept across
    /// a rebind of the body it was made in, because the cache hands the next
    /// round the instantiation without it.
    /// </summary>
    private OwedScope OweToTrial() => new(this, _trial, diagnostics.Holding());

    private readonly struct OwedScope(Binder binder, Trial? trial, DiagnosticBag.Hold hold)
        : IDisposable
    {
        /// <summary>How many errors are held so far.</summary>
        public int ErrorCount => hold.Items.Count(d => d.Severity == Severity.Error);

        public void Dispose()
        {
            hold.Dispose();

            if (trial is not null)
            {
                trial.Owed.AddRange(hold.Items);
                return;
            }

            foreach (var owed in hold.Items) binder.ReportOwed(owed);
        }
    }

    /// <summary>What instantiations reported during the body being bound until settled.</summary>
    private List<Diagnostic>? _owedAcrossRebinds;

    private void ReportOwed(Diagnostic owed)
    {
        diagnostics.Report(owed);
        _owedAcrossRebinds?.Add(owed);
    }

    /// <summary>Notes that a parameter is written, which a discarded trial takes back.</summary>
    private void MarkAssigned(ParameterSymbol parameter)
    {
        if (parameter.IsAssigned) return;

        parameter.IsAssigned = true;
        UndoOnDiscard(() => parameter.IsAssigned = false);
    }

    /// <summary>
    /// A written type, with nothing about it reported: the real resolution,
    /// wherever it is, says what is wrong with it.
    /// </summary>
    private TypeSymbol ResolveTypeQuietly(
        TypeSyntax syntax, FileScope scope, bool allowVoid = false)
    {
        using var trial = BeginTrial();
        var resolved = ResolveType(syntax, scope, allowVoid);
        trial.Accept();
        return resolved;
    }
}
