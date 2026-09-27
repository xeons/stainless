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

using System.Globalization;
using System.Text;
using Stainless.Binding;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Statements, and the blocks and branches they lower to.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ statements

    private void EmitStatement(BoundStatement statement)
    {
        // One location per statement is the granularity a line table wants: an
        // expression spanning several lines still belongs to the statement a
        // debugger stops on, and stepping through sub-expressions would be noise.
        if (debug is not null && _debugScope is { } scope)
            _debugLocation = debug.Location(statement.Span, scope);

        // Code after a return, break or goto goes into a block nothing
        // branches to. Dropped an instruction at a time, it kept the blocks
        // its own branches made, and what they held used values never written.
        if (_blockTerminated && statement is not BoundLabel)
            Label(NextLabel("dead"));

#if DEBUG
        int unsettled = _unsettled.Count;
#endif

        EmitStatementKind(statement);

#if DEBUG
        if (_unsettled.Count != unsettled)
            throw new InternalCompilerError(
                "an owned value was left unconsumed: nothing stored, returned or released it",
                statement.Span);
#endif
    }

    private void EmitStatementKind(BoundStatement statement)
    {
        switch (statement)
        {
            case BoundBlock block: EmitBlock(block); break;
            case BoundLocalDeclaration declaration: EmitLocalDeclaration(declaration); break;
            case BoundDeconstruct taken: EmitDeconstruct(taken); break;
            case BoundExpressionStatement expression: EmitExpressionStatement(expression); break;
            case BoundIf ifStatement: EmitIf(ifStatement); break;
            case BoundWhile whileStatement: EmitWhile(whileStatement); break;
            case BoundDoWhile doWhile: EmitDoWhile(doWhile); break;
            case BoundLabel label: EmitLabel(label); break;
            case BoundGoto jump: EmitGoto(jump); break;
            case BoundFor forStatement: EmitFor(forStatement); break;
            case BoundSwitch switchStatement: EmitSwitch(switchStatement); break;
            case BoundParallel parallel: EmitParallel(parallel); break;
            case BoundParallelFor parallelFor: EmitParallelFor(parallelFor); break;
            case BoundSpawn spawn: EmitSpawn(spawn); break;
            case BoundAsm assembly: EmitAsm(assembly); break;
            case BoundReturn returnStatement: EmitReturn(returnStatement); break;
            case BoundBreak: EmitJump(isBreak: true); break;
            case BoundContinue: EmitJump(isBreak: false); break;
            default: throw Unhandled(statement, statement.Span);
        }
    }

    private void EmitBlock(BoundBlock block)
    {
        int? enclosing = OpenDebugScope(block.Span);

        PushScope();
        foreach (var statement in block.Statements) EmitStatement(statement);
        if (!_blockTerminated) ReleaseCurrentScope();
        PopScopeWithoutRelease();

        _debugScope = enclosing;
    }

    /// <summary>
    /// Describes a <c>{ }</c> as a scope of its own, and answers the scope it
    /// is inside so a caller can put that back.
    /// </summary>
    /// <remarks>
    /// The scope is a field rather than a stack because a block restores what
    /// it found: the nesting is the call stack's already, and a second one
    /// beside it is a second thing to keep in step.
    /// </remarks>
    private int? OpenDebugScope(SourceSpan span)
    {
        int? enclosing = _debugScope;
        bool body = _atFunctionBody;
        _atFunctionBody = false;

        if (!body && debug is not null && _debugScope is { } outer)
            _debugScope = debug.LexicalBlock(span, outer);

        return enclosing;
    }

    private void EmitLocalDeclaration(BoundLocalDeclaration declaration)
    {
        var local = declaration.Local;
        string llvmType = LlvmTypeOf(local.Type);
        string slot = Alloca(llvmType, local.Name);
        _slots[local] = slot;

        if (debug is not null && _debugScope is { } scope)
            DeclareVariable(slot, debug.LocalVariable(
                local.Name, local.Type, declaration.Span, scope));

        if (local.Type.IsManagedSlot())
            StartOwnedSlot(slot, local.Type, "ptr", declaration.Initializer is not null);
        else if (local.Type is StructTypeSymbol { } owning && owning.CarriesReferences())
            StartOwnedSlot(slot, local.Type, StructName(owning), declaration.Initializer is not null);

        // Where a jump may land the slot may still hold what the last run of
        // this declaration left, and the store releases it.
        if (declaration.Initializer is not null)
        {
            var value = EmitOwned(declaration.Initializer);
            if (_hasLabels) MoveInto(slot, value, local.Type);
            else InitializeWith(slot, value, local.Type);
        }
        else if (local.Type is StructTypeSymbol structType && !structType.CarriesReferences())
        {
            Line($"store {StructName(structType)} zeroinitializer, ptr {slot}");
        }

        FlushTemporaries();
    }

    /// <summary>
    /// Gives a declared local's owned slot the null it starts from.
    ///
    /// Where a jump may land, a declaration can run again with the slot still
    /// holding what its last run left, so it releases rather than overwrites:
    /// the initializer's store releases the old value, and a declaration with
    /// none releases it here. Every release in such a function clears the
    /// slot, which keeps it null or owned wherever a jump lands.
    /// </summary>
    private void StartOwnedSlot(string slot, TypeSymbol type, string llvmType, bool initialized)
    {
        ZeroOnEntry(slot, llvmType);
        TrackOwnedLocal(slot, type);

        if (!_hasLabels)
            Line($"store {llvmType} {(llvmType == "ptr" ? "null" : "zeroinitializer")}, ptr {slot}");
        else if (!initialized)
            ReleaseSlot(slot, type);
    }

    private void EmitDeconstruct(BoundDeconstruct statement)
    {
        foreach (var declaration in statement.Declarations)
            EmitLocalDeclaration(declaration);

        EmitExpressionStatement(new BoundExpressionStatement(statement.Span, statement.Expression));
    }

    private void EmitExpressionStatement(BoundExpressionStatement statement)
    {
        EmitDiscarded(statement.Expression);
        FlushTemporaries();
    }

    private void EmitIf(BoundIf statement)
    {
        var condition = EmitExpression(statement.Condition);
        FlushTemporaries();

        string thenLabel = NextLabel("if.then");
        string elseLabel = NextLabel("if.else");
        string endLabel = NextLabel("if.end");

        Terminator($"br i1 {condition.Ref}, label %{thenLabel}, label %{(statement.Else is null ? endLabel : elseLabel)}");

        Label(thenLabel);
        EmitStatement(statement.Then);
        if (!_blockTerminated) Terminator($"br label %{endLabel}");

        if (statement.Else is not null)
        {
            Label(elseLabel);
            EmitStatement(statement.Else);
            if (!_blockTerminated) Terminator($"br label %{endLabel}");
        }

        Label(endLabel);
    }

    private void EmitWhile(BoundWhile statement)
    {
        string conditionLabel = NextLabel("while.cond");
        string bodyLabel = NextLabel("while.body");
        string endLabel = NextLabel("while.end");

        Terminator($"br label %{conditionLabel}");
        Label(conditionLabel);

        var condition = EmitExpression(statement.Condition);
        FlushTemporaries();
        Terminator($"br i1 {condition.Ref}, label %{bodyLabel}, label %{endLabel}");

        Label(bodyLabel);
        _loops.Add((endLabel, _scopes.Count, conditionLabel, _scopes.Count));
        EmitStatement(statement.Body);
        _loops.RemoveAt(_loops.Count - 1);
        if (!_blockTerminated) Terminator($"br label %{conditionLabel}");

        Label(endLabel);
    }

    /// <summary>
    /// <c>do { ... } while (c);</c>.
    ///
    /// The same three blocks a <c>while</c> has, entered at the body rather
    /// than at the condition -- which is the whole of the difference, and is
    /// why the body is not emitted twice. <c>continue</c> goes to the
    /// condition, as C says: it means "ask again", not "start over".
    /// </summary>
    private void EmitDoWhile(BoundDoWhile statement)
    {
        string bodyLabel = NextLabel("do.body");
        string conditionLabel = NextLabel("do.cond");
        string endLabel = NextLabel("do.end");

        Terminator($"br label %{bodyLabel}");
        Label(bodyLabel);

        _loops.Add((endLabel, _scopes.Count, conditionLabel, _scopes.Count));
        EmitStatement(statement.Body);
        _loops.RemoveAt(_loops.Count - 1);
        if (!_blockTerminated) Terminator($"br label %{conditionLabel}");

        Label(conditionLabel);
        var condition = EmitExpression(statement.Condition);
        FlushTemporaries();
        Terminator($"br i1 {condition.Ref}, label %{bodyLabel}, label %{endLabel}");

        Label(endLabel);
    }

    /// <summary>
    /// A <c>goto</c> target.
    ///
    /// LLVM blocks are named at their head, so a label is a block of its own
    /// that the statement before it falls into. It is emitted whether or not
    /// anything reaches it: the binder has already refused a jump with no
    /// label, and a block nothing branches to is dead code LLVM removes.
    /// </summary>
    private void EmitLabel(BoundLabel statement)
    {
        string block = LabelBlock(statement.Label);
        if (!_blockTerminated) Terminator($"br label %{block}");
        Label(block);
        _labelScopes[statement.Label] = [.. _scopes];
    }

    /// <summary>
    /// A jump, by way of a block of its own that releases what the scopes it
    /// leaves were holding.
    ///
    /// Which scopes those are depends on where the label is, and a label
    /// further down has not been emitted yet. So the block is written once the
    /// function is: every scope the jump is in and the label is not.
    /// </summary>
    private void EmitGoto(BoundGoto statement)
    {
        FlushTemporaries();

        string exit = NextLabel("goto");
        _pendingJumps.Add(new PendingJump(exit, statement.Label, [.. _scopes], _debugLocation));
        Terminator($"br label %{exit}");
    }

    /// <summary>The release blocks of every jump in the function, once every label is placed.</summary>
    private void EmitPendingJumps()
    {
        foreach (var jump in _pendingJumps)
        {
            Label(jump.Block);
            _debugLocation = jump.Location;

            var kept = _labelScopes[jump.Label];
            for (int i = jump.Scopes.Count - 1; i >= 0; i--)
            {
                if (kept.Contains(jump.Scopes[i])) continue;

                foreach (var (slot, type) in Enumerable.Reverse(jump.Scopes[i]))
                    ReleaseSlot(slot, type);
            }

            Terminator($"br label %{LabelBlock(jump.Label)}");
        }

        _pendingJumps.Clear();
    }

    private sealed record PendingJump(
        string Block, LabelSymbol Label, List<List<(string Slot, TypeSymbol Type)>> Scopes, int? Location);

    private readonly List<PendingJump> _pendingJumps = [];

    /// <summary>The scopes open where each label was emitted.</summary>
    private readonly Dictionary<LabelSymbol, List<List<(string Slot, TypeSymbol Type)>>> _labelScopes = [];

    /// <summary>
    /// Whether the function being emitted has somewhere a jump lands. Such a
    /// function clears every owned slot as it releases it, because a jump may
    /// run a declaration again or skip one.
    /// </summary>
    private bool _hasLabels;

    /// <summary>
    /// The block name for a source label, one per label per function.
    ///
    /// It is not the source name: two functions may each have a `retry:`, and
    /// a source label may collide with a name the emitter made for itself.
    /// </summary>
    private string LabelBlock(LabelSymbol label)
    {
        if (_labelBlocks.TryGetValue(label, out string? existing)) return existing;
        return _labelBlocks[label] = NextLabel("label." + Mangler.SymbolSafe(label.Name));
    }

    private readonly Dictionary<LabelSymbol, string> _labelBlocks = [];

    private void EmitFor(BoundFor statement)
    {
        // The loop is a scope of its own, because `for (int i = ...)` declares
        // `i` in it: a debugger stopped after the loop MUST NOT be shown one.
        int? enclosing = OpenDebugScope(statement.Span);

        PushScope();
        if (statement.Initializer is not null) EmitStatement(statement.Initializer);

        string conditionLabel = NextLabel("for.cond");
        string bodyLabel = NextLabel("for.body");
        string stepLabel = NextLabel("for.step");
        string endLabel = NextLabel("for.end");

        Terminator($"br label %{conditionLabel}");
        Label(conditionLabel);

        if (statement.Condition is not null)
        {
            var condition = EmitExpression(statement.Condition);
            FlushTemporaries();
            Terminator($"br i1 {condition.Ref}, label %{bodyLabel}, label %{endLabel}");
        }
        else
        {
            Terminator($"br label %{bodyLabel}");
        }

        Label(bodyLabel);
        // `continue` jumps to the step, not the condition, so the loop still advances.
        _loops.Add((endLabel, _scopes.Count, stepLabel, _scopes.Count));
        EmitStatement(statement.Body);
        _loops.RemoveAt(_loops.Count - 1);
        if (!_blockTerminated) Terminator($"br label %{stepLabel}");

        Label(stepLabel);
        if (statement.Step is not null)
        {
            EmitDiscarded(statement.Step);
            FlushTemporaries();
        }
        Terminator($"br label %{conditionLabel}");

        Label(endLabel);
        if (!_blockTerminated) ReleaseCurrentScope();
        PopScopeWithoutRelease();

        _debugScope = enclosing;
    }

    /// <summary>
    /// Emits a switch: one dispatch, then the sections.
    ///
    /// An ordinal switch becomes a single LLVM <c>switch</c>, which is what
    /// makes a jump table possible — LLVM decides between one and a chain of
    /// comparisons from the density of the labels, which is a better judge than
    /// this compiler would be. A String switch has no such instruction and
    /// becomes a chain of calls to the runtime's comparison.
    /// </summary>
    private void EmitSwitch(BoundSwitch statement)
    {
        var value = EmitExpression(statement.Value);
        FlushTemporaries();

        string endLabel = NextLabel("switch.end");
        var bodies = statement.Sections
            .Select(section => section.Entry is { } entry ? LabelBlock(entry) : NextLabel("switch.section"))
            .ToList();

        int defaultIndex = statement.Sections.ToList().FindIndex(s => s.IsDefault);
        string defaultLabel = defaultIndex < 0 ? endLabel : bodies[defaultIndex];

        // A pattern section is reached by asking rather than by jumping: the
        // tests run in order, and the first that says yes wins. It comes first
        // because a pattern switch over a variant is still a chain -- a `when`
        // is not a tag, and there is no table to put one in.
        if (statement.Sections.Any(section => section.Tests.Count > 0))
        {
            // A test's temporaries are released in its own block: the next
            // test's is also reached from here, and the sections from any of
            // them.
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var test in statement.Sections[i].Tests)
                {
                    var asked = EmitExpression(test);
                    FlushTemporaries();
                    string next = NextLabel("switch.test");
                    Terminator($"br i1 {asked.Ref}, label %{bodies[i]}, label %{next}");
                    Label(next);
                }

            Terminator($"br label %{defaultLabel}");

            EmitSwitchBodies(statement, bodies, endLabel);
            return;
        }

        // A switch over a variant asks the tag, which is an ordinary LLVM switch
        // over a byte -- so a jump table stays LLVM's decision here too.
        if (statement.Value.Type is VariantTypeSymbol switched)
        {
            string tag = Emit("i8",
                $"load i8, ptr {Emit("ptr", $"getelementptr inbounds {StructName(switched)}, " +
                                           $"ptr {value.Ref}, i32 0, i32 0")}");

            var caseArms = new List<string>();
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var matched in statement.Sections[i].Cases)
                    caseArms.Add($"i8 {matched.Tag}, label %{bodies[i]}");

            Terminator($"switch i8 {tag}, label %{defaultLabel} " +
                       $"[ {string.Join(" ", caseArms)} ]");

            EmitSwitchBodies(statement, bodies, endLabel);
            return;
        }

        // A reference governor was spilled into a local by the binder, so it is
        // alive across every one of these blocks.
        if (statement.Value.Type.NeedsArc())
        {
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var label in statement.Sections[i].Labels)
                {
                    var text = EmitExpression(label);
                    string same = Emit("i1",
                        $"call i1 @sl_string_equals(ptr {value.Ref}, ptr {text.Ref})");
                    string next = NextLabel("switch.test");
                    Terminator($"br i1 {same}, label %{bodies[i]}, label %{next}");
                    Label(next);
                }

            Terminator($"br label %{defaultLabel}");
        }
        else
        {
            var arms = new List<string>();
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var label in statement.Sections[i].Labels)
                {
                    var constant = EmitExpression(label);
                    arms.Add($"{constant.LlvmType} {constant.Ref}, label %{bodies[i]}");
                }

            Terminator($"switch {value.LlvmType} {value.Ref}, label %{defaultLabel} " +
                       $"[ {string.Join(" ", arms)} ]");
        }

        EmitSwitchBodies(statement, bodies, endLabel);
    }

    /// <summary>
    /// The sections themselves, once something has branched to them. Shared
    /// because a variant switch reaches this point by a different route and
    /// everything after the dispatch is the same.
    /// </summary>
    private void EmitSwitchBodies(
        BoundSwitch statement, IReadOnlyList<string> bodies, string endLabel)
    {
        // `break` lands after the switch; `continue` still belongs to whatever
        // loop encloses it, and unwinds to that loop's depth.
        string continueLabel = _loops.Count > 0 ? _loops[^1].ContinueLabel : endLabel;
        int continueDepth = _loops.Count > 0 ? _loops[^1].ContinueDepth : _scopes.Count;
        _loops.Add((endLabel, _scopes.Count, continueLabel, continueDepth));

        foreach (var (section, label) in statement.Sections.Zip(bodies))
        {
            Label(label);
            if (section.Entry is { } entry) _labelScopes[entry] = [.. _scopes];
            EmitStatement(section.Body);
            if (!_blockTerminated) Terminator($"br label %{endLabel}");
        }

        _loops.RemoveAt(_loops.Count - 1);

        Label(endLabel);
    }

    private void EmitReturn(BoundReturn statement)
    {
        var returnInfo = _returnInfo;

        if (statement.Value is null)
        {
            FlushTemporaries();
            ReleaseScopes(0);
            Terminator("ret void");
            return;
        }

        // Handed to the caller at +1, and a struct field by field: the caller
        // receives a copy that owns what it holds, and this frame is about to
        // release its own. A local this frame owns is handed over as it is,
        // and left out of the releases below.
        string? handedOver = OwnedLocalSlot(statement.Value);
        var value = handedOver is not null
            ? EmitOwnable(statement.Value)
            : EmitOwned(statement.Value);

        if (value.Type is StructTypeSymbol structType)
        {
            if (_sretSlot is not null)
            {
                MemCopy(_sretSlot, value.Ref, structType.Size);
                FlushTemporaries();
                ReleaseScopes(0, handedOver);
                Terminator("ret void");
            }
            else
            {
                // Register-sized: the bytes, read back as the registers they
                // travel in.
                string coerced = LoadCoerced(value.Ref, returnInfo);
                FlushTemporaries();
                ReleaseScopes(0, handedOver);
                Terminator($"ret {returnInfo.LlvmType} {coerced}");
            }
            return;
        }

        // Materialise the value before releasing anything that might own it.
        string slot = Alloca(value.LlvmType, "ret");
        Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");
        FlushTemporaries();
        ReleaseScopes(0, handedOver);
        string result = Emit(value.LlvmType, $"load {value.LlvmType}, ptr {slot}");
        Terminator($"ret {value.LlvmType} {result}");
    }

    private void EmitJump(bool isBreak)
    {
        if (_loops.Count == 0) return;
        var frame = _loops[^1];
        FlushTemporaries();
        ReleaseScopes(isBreak ? frame.BreakDepth : frame.ContinueDepth);
        Terminator($"br label %{(isBreak ? frame.BreakLabel : frame.ContinueLabel)}");
    }
}
