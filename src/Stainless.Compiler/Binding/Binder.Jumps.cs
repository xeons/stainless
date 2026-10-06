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
/// Labels, <c>goto</c>, <c>goto case</c> and <c>goto default</c>.
///
/// <para>
/// C#'s rule: a jump may leave any number of blocks and may not enter one, so
/// the label it names is in the block the jump is in or in one around it.
/// Where a jump lands is therefore always somewhere the scopes it left are
/// known, and what it releases on the way is exactly those scopes.
/// </para>
/// <para>
/// A label is known only once the whole function is bound, because a jump
/// forwards names one that has not been seen. Each jump is recorded with the
/// blocks it was in and checked at the end.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>The labels and jumps of one function, lambda or local function.</summary>
    private sealed class JumpState
    {
        /// <summary>Every label, by name, made by the label or the first jump to it.</summary>
        public Dictionary<string, LabelSymbol> Labels { get; } = new(StringComparer.Ordinal);

        /// <summary>Every jump whose target is known, checked once the body is bound.</summary>
        public List<Jump> Jumps { get; } = [];

        /// <summary>The switch statements around what is being bound, innermost last.</summary>
        public List<SwitchFrame> Switches { get; } = [];

        /// <summary>
        /// The scope depth the innermost <c>parallel</c> region starts at, or 0
        /// outside one. A label in a scope below it is outside the region.
        /// </summary>
        public int ParallelBase { get; set; }
    }

    /// <summary>A jump, the blocks it is in, and the parallel region it is in.</summary>
    private sealed record Jump(
        BoundGoto Statement, string Written, List<Dictionary<string, LocalSymbol>> Blocks,
        int ParallelBase);

    /// <summary>
    /// A switch a <c>goto case</c> can name a section of. The sections are
    /// found as the switch is bound, so a jump to one further down waits here.
    /// </summary>
    private sealed class SwitchFrame(TypeSymbol governing, bool overVariant, object block)
    {
        public TypeSymbol Governing { get; } = governing;
        public bool OverVariant { get; } = overVariant;

        /// <summary>The scope the switch statement is in, which is where its sections start.</summary>
        public object Block { get; } = block;

        /// <summary>Each constant label, as its bits or its text, and the section it opens.</summary>
        public Dictionary<object, int> Cases { get; } = [];

        public int Default { get; set; } = -1;

        public List<(Jump Jump, object? Key, SourceSpan Span)> Pending { get; } = [];
    }

    private BoundStatement BindLabel(LabelSyntax syntax)
    {
        var label = LabelNamed(syntax.Name);

        if (label.Declared is not null)
        {
            diagnostics.Report(Codes.DuplicateLabel, syntax.Span,
                $"'{syntax.Name}' is already a label in this function; a 'goto' names one " +
                "place, so two of a name would be a jump with two destinations");
            return new BoundBlock(syntax.Span, []);
        }

        label.Declared = syntax.Span;
        label.Block = _context.Locals[^1];

        // A variant narrowed above a label is not narrowed at it: a jump
        // arrives here from elsewhere, and what it proved on the way is not
        // what the fall-through proved.
        _context.VariantFacts = [];
        return new BoundLabel(syntax.Span, label);
    }

    private BoundStatement BindGoto(GotoSyntax syntax)
    {
        var label = LabelNamed(syntax.Label);
        label.IsUsed = true;
        label.FirstUse ??= syntax.LabelSpan;

        var jump = new BoundGoto(syntax.Span, label);
        _context.Jumps.Jumps.Add(new Jump(
            jump, $"goto {syntax.Label}", [.. _context.Locals], _context.Jumps.ParallelBase));
        return jump;
    }

    /// <summary>
    /// <c>goto case value;</c> and <c>goto default;</c>, which name a section
    /// of the innermost switch statement around them.
    /// </summary>
    private BoundStatement BindGotoCase(GotoCaseSyntax syntax)
    {
        string written = syntax.Value is null ? "goto default" : "goto case";

        // Until the switch is bound it is not known which section this is.
        var statement = new BoundGoto(syntax.Span, new LabelSymbol("case"));

        if (_context.Jumps.Switches.Count == 0)
        {
            diagnostics.Report(Codes.GotoCaseOutsideSwitch, syntax.Span,
                $"'{written}' names a section of the switch statement it is in, and this " +
                "is not in one");
            return statement;
        }

        var frame = _context.Jumps.Switches[^1];
        object? key = null;

        if (syntax.Value is not null && frame.OverVariant)
        {
            diagnostics.Report(Codes.GotoCaseTargetNotFound, syntax.Span, NoCaseOfAVariant);
            return statement;
        }

        if (syntax.Value is not null)
        {
            var value = BindConversion(BindExpression(syntax.Value), frame.Governing, syntax.Value.Span);
            if (value.Type.IsError())
                return statement;

            key = FoldSwitchLabel(value) is { } bits ? bits
                : Underlying(value) is BoundStringLiteral text ? text.Value
                : null;

            if (key is null)
            {
                diagnostics.Report(Codes.GotoCaseNotConstant, syntax.Value.Span,
                    "'goto case' names a section by its constant label, and this is not a constant");
                return statement;
            }
        }

        var jump = new Jump(statement, written, [.. _context.Locals], _context.Jumps.ParallelBase);
        frame.Pending.Add((jump, key, syntax.Span));
        return statement;
    }

    private const string NoCaseOfAVariant =
        "'goto case' names a constant label, and a switch over a variant has none; a case's " +
        "section is entered knowing which case the value holds, and a jump there would not know";

    private SwitchFrame OpenSwitchFrame(TypeSymbol governing, bool overVariant)
    {
        var frame = new SwitchFrame(governing, overVariant, _context.Locals[^1]);
        _context.Jumps.Switches.Add(frame);
        return frame;
    }

    /// <summary>Points every <c>goto case</c> in a bound switch at the section it names.</summary>
    private void CloseSwitchFrame(SwitchFrame frame, IReadOnlyList<BoundSwitchSection> sections)
    {
        _context.Jumps.Switches.RemoveAt(_context.Jumps.Switches.Count - 1);

        foreach (var (jump, key, span) in frame.Pending)
        {
            int index = key is null ? frame.Default : frame.Cases.GetValueOrDefault(key, -1);

            if (index < 0 || index >= sections.Count)
            {
                diagnostics.Report(Codes.GotoCaseTargetNotFound, span, key is null
                    ? "this switch has no 'default' section for 'goto default' to run"
                    : "this switch has no 'case' label with that value for 'goto case' to run");
                continue;
            }

            var section = sections[index];
            section.Entry ??= new LabelSymbol(key is null ? "default" : "case")
            {
                Declared = section.Span,
                Block = frame.Block,
                IsUsed = true,
            };

            jump.Statement.Label = section.Entry;
            _context.Jumps.Jumps.Add(jump);
        }
    }

    /// <summary>
    /// A jump with nowhere to land, a jump into a block, a jump out of a
    /// <c>parallel</c> region, and a label nothing lands on. The last is a
    /// warning, because a label costs nothing and deleting the last jump to
    /// one is an ordinary edit.
    /// </summary>
    private void CheckJumps(string owner)
    {
        foreach (var label in _context.Jumps.Labels.Values)
        {
            if (label.Declared is null && label.FirstUse is { } used)
                diagnostics.Report(Codes.LabelNotFound, used,
                    $"there is no label '{label.Name}' in {owner}; a 'goto' names a label in " +
                    "the function it is written in, and nowhere else");
            else if (label.Declared is { } declared && !label.IsUsed)
                diagnostics.Report(Codes.LabelUnused, declared,
                    $"nothing jumps to '{label.Name}'");
        }

        foreach (var jump in _context.Jumps.Jumps)
        {
            if (jump.Statement.Label.Block is not { } block)
                continue;

            int depth = jump.Blocks.IndexOf((Dictionary<string, LocalSymbol>)block);

            if (depth < 0)
                diagnostics.Report(Codes.JumpIntoBlock, jump.Statement.Span,
                    $"'{jump.Written}' names a label inside a block the jump is not in; a " +
                    "jump may leave blocks but not enter one, because what the block declared " +
                    "before the label would never have been made");
            else if (depth < jump.ParallelBase)
                diagnostics.Report(Codes.JumpOutOfParallelBlock, jump.Statement.Span,
                    $"'{jump.Written}' leaves the 'parallel' block it is in; the work queued in " +
                    "a block has to finish there, so there is nothing a jump out of it could " +
                    "mean. Leave with a flag the block sets");
        }
    }

    /// <summary>The label of that name in this function, made on first mention.</summary>
    private LabelSymbol LabelNamed(string name)
    {
        if (_context.Jumps.Labels.TryGetValue(name, out var existing)) return existing;
        return _context.Jumps.Labels[name] = new LabelSymbol(name);
    }
}
