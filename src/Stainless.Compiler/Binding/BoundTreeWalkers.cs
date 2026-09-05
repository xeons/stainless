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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>Finds the statics an initializer reads, so they can be ordered first.</summary>
internal sealed class StaticReferenceWalker
{
    public HashSet<StaticSymbol> Found { get; } = [];

    public void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case null: return;

            case BoundStaticAccess access: Found.Add(access.Static); break;

            case BoundFieldAccess field: Visit(field.Receiver); break;

            case BoundCall call:
                Visit(call.Receiver);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundIndirectCall call:
                Visit(call.Target);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundUnary unary: Visit(unary.Operand); break;
            case BoundBinary binary: Visit(binary.Left); Visit(binary.Right); break;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Visit(conditional.WhenTrue);
                Visit(conditional.WhenFalse);
                break;

            case BoundAssignment assignment: Visit(assignment.Target); Visit(assignment.Value); break;

            case BoundPropertyAssignment written:
                Visit(written.Receiver); Visit(written.Value);
                break;

            case BoundConversion conversion: Visit(conversion.Operand); break;
            case BoundTypeTest test: Visit(test.Value); break;

            case BoundNew created:
                foreach (var argument in created.Arguments) Visit(argument);
                break;

            case BoundDereference dereference: Visit(dereference.Operand); break;
            case BoundAddressOf address: Visit(address.Operand); break;
            case BoundNewArray array: Visit(array.Length); break;
            case BoundArrayLength length: Visit(length.Array); break;
            case BoundIndex index: Visit(index.Target); Visit(index.Index); break;
        }
    }
}

/// <summary>
/// Finds what a <c>parallel for</c> body reaches outside itself.
///
/// Anything declared within the body belongs to one iteration and is ignored.
/// Everything else is captured by address, so the chunks share the parent's
/// storage rather than a copy — which is the point for an array being written
/// through, and a race for a variable being assigned. Assignments are collected
/// separately so the binder can reject exactly those.
/// </summary>
internal sealed class CaptureWalker(LocalSymbol loopVariable)
{
    private readonly HashSet<object> _declared = [loopVariable];
    private readonly HashSet<object> _seen = [];
    private readonly List<object> _captures = [];

    public IReadOnlyList<object> Captures => _captures;

    public List<(object Symbol, SourceSpan Span, string Name)> Assignments { get; } = [];

    private void Capture(object symbol)
    {
        if (_declared.Contains(symbol) || !_seen.Add(symbol)) return;
        _captures.Add(symbol);
    }

    private void Assigned(BoundExpression target)
    {
        switch (target)
        {
            case BoundLocalAccess local when !_declared.Contains(local.Local):
                Assignments.Add((local.Local, local.Span, local.Local.Name));
                break;

            case BoundParameterAccess parameter when !_declared.Contains(parameter.Parameter):
                Assignments.Add((parameter.Parameter, parameter.Span, parameter.Parameter.Name));
                break;
        }
    }

    public void Visit(BoundStatement? statement)
    {
        switch (statement)
        {
            case null: return;

            case BoundBlock block:
                foreach (var inner in block.Statements) Visit(inner);
                break;

            case BoundLocalDeclaration declaration:
                _declared.Add(declaration.Local);
                Visit(declaration.Initializer);
                break;

            case BoundExpressionStatement expression: Visit(expression.Expression); break;

            case BoundIf branch:
                Visit(branch.Condition); Visit(branch.Then); Visit(branch.Else);
                break;

            case BoundWhile loop:
                Visit(loop.Condition); Visit(loop.Body);
                break;

            case BoundFor loop:
                foreach (var local in loop.Locals) _declared.Add(local);
                Visit(loop.Initializer); Visit(loop.Condition); Visit(loop.Step); Visit(loop.Body);
                break;

            case BoundParallel nested: Visit(nested.Body); break;

            case BoundSpawn spawn:
                Visit(spawn.Target); Visit(spawn.Call);
                break;

            case BoundParallelFor nested:
                _declared.Add(nested.Variable);
                Visit(nested.Start); Visit(nested.Limit); Visit(nested.Stride); Visit(nested.Body);
                break;

            case BoundReturn returned: Visit(returned.Value); break;
        }
    }

    public void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case null: return;

            case BoundLocalAccess local: Capture(local.Local); break;
            case BoundParameterAccess parameter: Capture(parameter.Parameter); break;
            case BoundThis self: Capture(self.Parameter); break;

            case BoundFieldAccess field: Visit(field.Receiver); break;

            case BoundCall call:
                Visit(call.Receiver);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundIndirectCall call:
                Visit(call.Target);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundUnary unary: Visit(unary.Operand); break;

            case BoundBinary binary:
                Visit(binary.Left); Visit(binary.Right);
                break;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Visit(conditional.WhenTrue);
                Visit(conditional.WhenFalse);
                break;

            case BoundAssignment assignment:
                Assigned(assignment.Target);
                Visit(assignment.Target); Visit(assignment.Value);
                break;

            // A property write goes through a method, so it changes the object
            // rather than the captured variable naming it; only the reads count.
            case BoundPropertyAssignment written:
                Visit(written.Receiver); Visit(written.Value);
                break;

            case BoundConversion conversion: Visit(conversion.Operand); break;
            case BoundTypeTest test: Visit(test.Value); break;

            case BoundNew created:
                foreach (var argument in created.Arguments) Visit(argument);
                break;

            case BoundDereference dereference: Visit(dereference.Operand); break;
            case BoundAddressOf address: Visit(address.Operand); break;
            case BoundNewArray array: Visit(array.Length); break;
            case BoundArrayLength length: Visit(length.Array); break;

            case BoundIndex index:
                Visit(index.Target); Visit(index.Index);
                break;
        }
    }
}
