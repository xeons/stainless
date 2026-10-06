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
/// <c>[Throws]</c>: a foreign function whose exception is answered as a value.
///
/// <para>
/// <b>The one call catches, and nothing unwinds through Stainless.</b> The
/// function is declared answering <c>Result&lt;T, ForeignException&gt;</c>, or
/// <c>ForeignException?</c> when the foreign call produces nothing. Its
/// symbol keeps the foreign call's own result, and a wrapper is declared beside
/// it that a program calls instead: its body makes the foreign call -- which
/// the emitter writes as an <c>invoke</c> whose landing pad records what was
/// thrown -- and answers <c>Ok</c> or <c>Fail</c> from what it found.
/// </para>
/// </summary>
public sealed partial class Binder
{
    private const string CaughtLocal = "caught$";
    private const string ValueLocal = "value$";

    /// <summary>Reads <c>[Throws]</c> on a function, and declares its wrapper.</summary>
    private void DeclareThrowing(FunctionSymbol symbol, FunctionDeclSyntax declaration, FileScope scope)
    {
        var span = declaration.Span;
        string? refused = null;
        var written = symbol.ReturnType;
        TypeSymbol? native = FindThrowingNativeResult(written);

        if (symbol.ContainingType is null ? !symbol.Linkage.IsImport() : !(symbol.IsMessage && IsDescribedOnly(symbol.ContainingType)))
            refused = "it says a foreign function's exception is answered as a value, and " +
                      $"'{symbol.Name}' is not a function another language defines";
        else if (TargetPlatform.Current.IsWindows)
            refused = "Windows raises a C++ exception through its own structured handling, which a " +
                      "'[Throws]' call does not catch yet";
        else if (native is null)
            refused = $"'{symbol.Name}' has to be declared answering 'Result<T, ForeignException>', " +
                      "or 'ForeignException?' when the foreign call produces nothing, which is what a " +
                      "call answers once it has caught what was thrown";
        else if (native is StructTypeSymbol or TupleTypeSymbol)
            refused = $"'{native.Name}' is returned in memory, which a call that threw would leave " +
                      "unwritten; a '[Throws]' function returns a value that fits in a register";
        else if (symbol.ReturnsSelf || symbol.IsVariadic || symbol.Parameters.Any(p => p.IsByReference))
            refused = $"'{symbol.Name}' returns its own type, takes '...' or takes a parameter by " +
                      "reference, none of which a '[Throws]' wrapper passes on";

        if (refused is not null)
        {
            diagnostics.Report(Codes.AttributeNotAllowedHere, span,
                $"'[Throws]' cannot be written here: {refused}");

            // The foreign call's own result, so that nothing after this
            // reports the declared one as though C returned it.
            if (native is not null)
                symbol.ReturnType = native;
            return;
        }

        symbol.ReturnType = native!;

        var wrapper = new FunctionSymbol
        {
            Name = symbol.Name + "$try",
            ModuleName = symbol.ModuleName,
            ReturnType = written,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Function,
            IsPublic = true,
            Span = span,
            Scope = scope,
            WrapsThrowing = symbol,
            Body = CreateThrowingBody(span, native!.IsVoid()),
        };

        int index = 0;
        foreach (var parameter in symbol.Parameters)
            wrapper.Parameters.Add(new ParameterSymbol(parameter.IsThis ? "self$" : parameter.Name,
                                                       parameter.Type, index++));

        symbol.ThrowsWrapper = wrapper;
        scope.Module.Functions.Add(wrapper);
    }

    /// <summary>
    /// What the foreign call itself hands back when <paramref name="written"/>
    /// is what a <c>[Throws]</c> function may answer: the <c>T</c> of a
    /// <c>Result&lt;T, ForeignException&gt;</c>, or nothing for a
    /// <c>ForeignException?</c>. Null for anything else.
    /// </summary>
    private static TypeSymbol? FindThrowingNativeResult(TypeSymbol written)
    {
        static bool IsForeignException(TypeSymbol type) =>
            type is ClassTypeSymbol { QualifiedName: "Standard.ForeignException" };

        if (written is OptionalTypeSymbol { Element: var element } && IsForeignException(element))
            return PrimitiveTypeSymbol.Void;

        if (written is NamedTypeSymbol { Template: { Name: "Result", Module.Name: "Standard" }, TypeArguments: [var value, var error] } &&
            IsForeignException(error))
            return value;

        return null;
    }

    /// <summary>
    /// The wrapper's body, as source it could have been written as:
    /// <code>
    /// byte* caught$ = null;
    /// var value$ = &lt;the foreign call&gt;;
    /// if (caught$ != null)
    ///     return Fail(Standard.ForeignException.Take(caught$));
    /// return Ok(value$);
    /// </code>
    /// For a foreign call that produces nothing, the exception or null.
    /// </summary>
    private static BlockSyntax CreateThrowingBody(SourceSpan span, bool producesNothing)
    {
        ExpressionSyntax Named(string name) => new NameSyntax(span, new QualifiedName(span, [name]));
        ExpressionSyntax Call(ExpressionSyntax callee, params ExpressionSyntax[] arguments) =>
            new CallSyntax(span, callee, arguments);

        var nothing = new LiteralSyntax(span, TokenKind.NullKeyword, null);
        var take = Call(new MemberAccessSyntax(span,
                            new MemberAccessSyntax(span, Named("Standard"), "ForeignException"), "Take"),
                        Named(CaughtLocal));
        var caughtSomething = new BinarySyntax(span, Named(CaughtLocal), TokenKind.BangEquals, nothing);
        var bytePointer = new PointerTypeSyntax(span, new PrimitiveTypeSyntax(span, TokenKind.ByteKeyword));

        List<StatementSyntax> statements =
        [
            new LocalDeclSyntax(span, bytePointer, CaughtLocal, nothing, false),
        ];

        if (producesNothing)
        {
            statements.Add(new ExpressionStatementSyntax(span, new ForeignCallSyntax(span, CaughtLocal)));
            statements.Add(new IfSyntax(span, caughtSomething, new ReturnSyntax(span, take), null));
            statements.Add(new ReturnSyntax(span, nothing));
        }
        else
        {
            statements.Add(new LocalDeclSyntax(span, null, ValueLocal, new ForeignCallSyntax(span, CaughtLocal), false));
            statements.Add(new IfSyntax(span, caughtSomething,
                                        new ReturnSyntax(span, Call(Named("Fail"), take)), null));
            statements.Add(new ReturnSyntax(span, Call(Named("Ok"), Named(ValueLocal))));
        }

        return new BlockSyntax(span, statements);
    }

    /// <summary>The foreign call inside a wrapper, made with the wrapper's own parameters.</summary>
    private BoundExpression BindForeignCall(ForeignCallSyntax syntax)
    {
        var wrapper = _context.Function;
        if (wrapper?.WrapsThrowing is not { } native || LookupLocal(syntax.Caught) is not { } caught)
            throw new InvalidOperationException("a foreign call outside a [Throws] wrapper");

        var parameters = wrapper.Parameters;
        bool instance = native.Parameters.Count > 0 && native.Parameters[0].IsThis;
        BoundExpression? receiver = instance ? new BoundParameterAccess(syntax.Span, parameters[0]) : null;
        var arguments = parameters.Skip(instance ? 1 : 0)
            .Select(p => (BoundExpression)new BoundParameterAccess(syntax.Span, p))
            .ToList();

        ClassTypeSymbol? classReceiver = null;
        if (native.IsMessage)
        {
            RequireDarwin(syntax.Span);
            if (native.IsStatic)
                classReceiver = native.ContainingType as ClassTypeSymbol;
        }

        return new BoundCall(syntax.Span, native, receiver, arguments)
        {
            ClassReceiver = classReceiver,
            CatchesForeign = caught,
        };
    }

    /// <summary>
    /// A call to a <c>[Throws]</c> function, made to its wrapper: the receiver,
    /// if there is one, becomes the wrapper's first argument.
    /// </summary>
    private static BoundExpression CallThrowingWrapper(
        SourceSpan span, FunctionSymbol wrapper, BoundExpression? receiver,
        List<BoundExpression> arguments, IReadOnlyList<int>? order)
    {
        if (receiver is null)
            return new BoundCall(span, wrapper, null, arguments) { EvaluationOrder = order };

        IReadOnlyList<int>? shifted = order is null ? null : [0, .. order.Select(i => i + 1)];
        return new BoundCall(span, wrapper, null, [receiver, .. arguments]) { EvaluationOrder = shifted };
    }
}
