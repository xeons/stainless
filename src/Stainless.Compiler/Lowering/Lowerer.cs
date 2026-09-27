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

/// <summary>
/// Rewrites what binding made -- what the program means -- into the smaller
/// core the emitter handles.
///
/// Binding checks a construct and says what it is; this says how it runs. A
/// construct that has a lowering never reaches the emitter, and the verifier
/// checks the lowered tree for any that did. The semantic program is left as
/// it was: lowering makes new bodies, and a new program that holds them.
/// </summary>
public sealed partial class Lowerer : BoundTreeRewriter
{
    /// <summary>Numbers the locals a lowering introduces, so nested ones do not collide.</summary>
    private int _synthetic;

    private Lowerer()
    {
    }

    public static BoundProgram Lower(BoundProgram program)
    {
        if (program.IsLowered)
            return program;

        var lowerer = new Lowerer();
        var functions = new List<BoundFunction>(program.Functions.Count);

        foreach (var function in program.Functions)
        {
            var body = function.NeedsLowering ? lowerer.Rewrite(function.Body) : function.Body;
            functions.Add(ReferenceEquals(body, function.Body)
                ? function
                : new BoundFunction(function.Symbol, AsBlock(body)));
        }

        var initializers = new Dictionary<StaticSymbol, BoundExpression>();
        foreach (var shared in program.Statics)
            if (shared.Initializer is { } initializer)
                initializers[shared] = lowerer.Rewrite(initializer);

        var lowered = program with
        {
            Functions = functions,
            LoweredInitializers = initializers,
            IsLowered = true,
        };

        if (BoundTreeVerifier.IsEnabled)
            BoundTreeVerifier.Verify(lowered, BoundTreeForm.Lowered);

        return lowered;
    }

    /// <summary>Every construct lowering takes away, and where it goes instead.</summary>
    public override BoundStatement Rewrite(BoundStatement statement) => statement switch
    {
        BoundSwitch chosen => LowerSwitch(chosen),
        BoundForEach loop => LowerForEach(loop),
        _ => LowerDropping(statement) ?? base.Rewrite(statement),
    };

    /// <inheritdoc cref="Rewrite(BoundStatement)"/>
    public override BoundExpression Rewrite(BoundExpression expression) => expression switch
    {
        BoundSemanticExpression semantic => LowerSemantic(semantic),
        BoundSequence sequence => Sequence(sequence, Rewrite(sequence.Value)),
        _ => base.Rewrite(expression),
    };

    private BoundExpression LowerSemantic(BoundSemanticExpression expression) => expression switch
    {
        BoundIsPattern matched => LowerIsPattern(matched),
        BoundSwitchExpression chosen => LowerSwitchExpression(chosen),
        BoundConditionalAccess asked => LowerConditionalAccess(asked),
        BoundNullFallback fallback => LowerNullFallback(fallback),
        BoundCompoundAssignment compound => LowerCompoundAssignment(compound, discarded: false),
        BoundPropertyAssignment written => LowerPropertyAssignment(written),
        BoundPropertyIncrement stepped => LowerPropertyIncrement(stepped, discarded: false),
        BoundWith copied => LowerWith(copied),
        BoundObjectInitializer initialized => LowerObjectInitializer(initialized),
        _ => throw new Source.InternalCompilerError(
            $"lowering has no case for {expression.GetType().Name}", expression.Span),
    };

    private static BoundBlock AsBlock(BoundStatement statement) =>
        statement as BoundBlock ?? throw new Source.InternalCompilerError(
            "lowering made a function body that is not a block", statement.Span);

    /// <summary>A local of lowering's own. A '$' cannot begin a source identifier.</summary>
    internal LocalSymbol Synthetic(string hint, TypeSymbol type, bool isConst = false) =>
        new($"${hint}.{_synthetic++}", type, isConst);
}
