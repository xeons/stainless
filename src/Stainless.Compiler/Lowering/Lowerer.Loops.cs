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

using Stainless.Binding;

namespace Stainless.Lowering;

/// <summary><c>foreach</c>, as the loop it runs.</summary>
public sealed partial class Lowerer
{
    /// <summary>
    /// The collection held once, then an indexed <c>for</c> over an array or
    /// a slice, or <c>while ($e.MoveNext()) { var x = $e.Current; ... }</c>
    /// over anything else. Putting <c>MoveNext</c> in the condition is what
    /// makes <c>continue</c> advance the enumerator rather than spin on the
    /// same element.
    /// </summary>
    private BoundStatement LowerForEach(BoundForEach loop)
    {
        var span = loop.Span;
        var collection = Rewrite(loop.Collection);
        var sequence = Synthetic("sequence", collection.Type);
        var statements = new List<BoundStatement>
        {
            new BoundLocalDeclaration(loop.Collection.Span, sequence, collection),
        };
        var outer = new BoundBlock(span, statements);
        outer.Locals.Add(sequence);

        if (loop.GetEnumerator is not { } getEnumerator)
        {
            var index = Synthetic("index", PrimitiveTypeSymbol.NUInt);
            var initializer = new BoundLocalDeclaration(span, index,
                new BoundLiteral(span, PrimitiveTypeSymbol.NUInt, 0UL));

            var condition = new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                new BoundLocalAccess(span, index),
                BoundBinaryOp.Less,
                new BoundArrayLength(span, PrimitiveTypeSymbol.NUInt, new BoundLocalAccess(span, sequence)));

            var step = new BoundAssignment(span,
                new BoundLocalAccess(span, index),
                new BoundBinary(span, PrimitiveTypeSymbol.NUInt,
                    new BoundLocalAccess(span, index),
                    BoundBinaryOp.Add,
                    new BoundLiteral(span, PrimitiveTypeSymbol.NUInt, 1UL)));

            var item = new BoundIndex(span, loop.Element.Type,
                new BoundLocalAccess(span, sequence), new BoundLocalAccess(span, index));

            var indexed = new BoundFor(span, initializer, condition, step, ForEachPass(loop, item));
            indexed.Locals.Add(index);
            statements.Add(indexed);
            return outer;
        }

        var enumerator = Synthetic("enumerator", getEnumerator.ReturnType);
        statements.Add(new BoundLocalDeclaration(span, enumerator,
            new BoundCall(span, getEnumerator, new BoundLocalAccess(span, sequence), [])));
        outer.Locals.Add(enumerator);

        statements.Add(new BoundWhile(span,
            new BoundCall(span, loop.MoveNext!, new BoundLocalAccess(span, enumerator), []),
            ForEachPass(loop, new BoundCall(span, loop.Current!, new BoundLocalAccess(span, enumerator), []))));
        return outer;
    }

    /// <summary>One pass: the variable given the element, taken apart if it is, then the body.</summary>
    private BoundBlock ForEachPass(BoundForEach loop, BoundExpression element)
    {
        var statements = new List<BoundStatement>
        {
            new BoundLocalDeclaration(loop.Span, loop.Variable,
                Rewrite(Replace(loop.Value, loop.Element, element))),
        };

        var pass = new BoundBlock(loop.Span, statements);
        pass.Locals.Add(loop.Variable);

        if (loop.Deconstruction is { } taken)
        {
            var parts = Rewrite(taken);
            if (parts is BoundDeconstruct declared)
                pass.Locals.AddRange(declared.Declarations.Select(d => d.Local));
            statements.Add(parts);
        }

        statements.Add(Rewrite(loop.Body));
        return pass;
    }

    /// <summary>An expression with what a placeholder stands for put in its place.</summary>
    private static BoundExpression Replace(BoundExpression expression, BoundPlaceholder placeholder, BoundExpression value) =>
        new PlaceholderReplacer(placeholder, value).Rewrite(expression);

    private sealed class PlaceholderReplacer(BoundPlaceholder placeholder, BoundExpression value) : BoundTreeRewriter
    {
        public override BoundExpression Rewrite(BoundExpression expression) =>
            ReferenceEquals(expression, placeholder) ? value : base.Rewrite(expression);
    }
}
