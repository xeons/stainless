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

namespace Stainless.Syntax;

/// <summary>
/// A record as it was written, before its positional parameters became
/// members: kept so that the binder can finish it again once it knows its
/// base is a record too.
/// </summary>
public sealed record RecordSource(
    TypeDeclSyntax Written,
    IReadOnlyList<ParameterSyntax> Positional,
    IReadOnlyList<ExpressionSyntax>? BaseArguments,
    SourceSpan BaseArgumentsSpan);

/// <summary>
/// The members a record's positional parameters stand for.
///
/// The parser makes the form for a record whose base is not one, since it
/// cannot tell; the binder makes the derived form, in place of that one, for a
/// record whose base turns out to be a record.
/// </summary>
public static class Records
{
    /// <summary>
    /// Whether another record is exactly this one's type, which is what makes
    /// an <c>A</c> and a <c>B : A</c> with the same fields unequal. Its
    /// parameter is <c>IHashable</c>, which every record is, so that each level
    /// overrides one signature without knowing which record is the root.
    /// </summary>
    public const string SameTypeName = "$SameRecordType";

    /// <summary>The copy <c>with</c> makes, dispatched so a derived record copies whole.</summary>
    public const string CloneName = "$Clone";

    /// <summary>
    /// The declaration with its generated members. <paramref name="recordBase"/>
    /// is the base as written, when it is a record whose positional
    /// parameters are <paramref name="inherited"/>.
    /// </summary>
    public static TypeDeclSyntax Complete(
        RecordSource source, TypeSyntax? recordBase = null, IReadOnlyCollection<string>? inherited = null)
    {
        var declared = source.Written;
        var positional = source.Positional;
        var span = declared.Span;
        var self = SelfType(declared);
        var own = positional
            .Where(p => inherited is null || !inherited.Contains(p.Name))
            .ToList();

        var constructor = ConstructorFor(declared.Name, positional, own);
        if (source.BaseArguments is { } given)
            constructor = constructor with
            {
                // The record's own properties first: the base is built once
                // they have their values.
                Body = new BlockSyntax(constructor.Body.Span,
                [
                    .. constructor.Body.Statements,
                    new ExpressionStatementSyntax(source.BaseArgumentsSpan,
                        new CallSyntax(source.BaseArgumentsSpan,
                            new BaseSyntax(source.BaseArgumentsSpan), given)),
                ]),
            };

        var members = new List<Declaration>(declared.Members);
        members.AddRange(PropertiesFor(own));
        members.Add(constructor);
        members.Add(EqualsFor(self, positional[0].Span, own, derived: recordBase is not null));
        members.Add(GetHashCodeFor(positional[0].Span, own, derived: recordBase is not null));
        members.Add(SameTypeFor(self, span, derived: recordBase is not null));
        if (recordBase is not null)
            members.Add(EqualsOverBaseFor(self, positional[0].Span, recordBase));
        members.Add(EqualityOperatorFor(self, positional, TokenKind.EqualsEquals));
        members.Add(EqualityOperatorFor(self, positional, TokenKind.BangEquals));

        // One the body wrote with as many parameters takes its place, as in C#,
        // and so does the base's when this one would take exactly its parameters.
        bool written = declared.Members.Any(m => m is FunctionDeclSyntax
            { Name: "Deconstruct" } mine && mine.Parameters.Count == positional.Count);
        bool inheritedWhole = own.Count == 0 && inherited?.Count == positional.Count;
        if (!written && !inheritedWhole)
            members.Add(DeconstructFor(positional));

        // The two interfaces those members satisfy, so that a record is a
        // dictionary key and a set element without anybody saying so. Written
        // out in full, so that a record needs no import to be one. A derived
        // record has IHashable from its base already.
        var implements = new List<TypeSyntax>(declared.Implements)
        {
            Interface(span, ["Standard", "Collections", "IEquatable"], self),
        };
        if (recordBase is null)
            implements.Add(Interface(span, ["Standard", "Collections", "IHashable"]));

        return declared with
        {
            Members = members,
            Implements = implements,
            RecordParameters = positional.Select(parameter => parameter.Name).ToList(),
            Record = source,
        };
    }

    /// <summary>A bare name as a type.</summary>
    private static NamedTypeSyntax Named(SourceSpan span, string name) =>
        new(span, new QualifiedName(span, [name]));

    /// <summary>The record's own type, with its type parameters when it has them.</summary>
    private static NamedTypeSyntax SelfType(TypeDeclSyntax declared) =>
        new(declared.Span, new QualifiedName(declared.Span, [declared.Name]),
            [.. declared.TypeParameters.Select(p => Named(declared.Span, p))]);

    /// <summary>One of the interfaces a record implements, named in full.</summary>
    private static NamedTypeSyntax Interface(
        SourceSpan span, string[] parts, params TypeSyntax[] arguments) =>
        new(span, new QualifiedName(span, parts), arguments);

    /// <summary>A reference to <c>this.Name</c>.</summary>
    private static MemberAccessSyntax Mine(SourceSpan span, string name) =>
        new(span, new ThisSyntax(span), name);

    /// <summary>A reference to a parameter or local by name.</summary>
    private static NameSyntax Local(SourceSpan span, string name) =>
        new(span, new QualifiedName(span, [name]));

    private static ExpressionSyntax Call(
        SourceSpan span, ExpressionSyntax target, string name, params ExpressionSyntax[] arguments) =>
        new CallSyntax(span, new MemberAccessSyntax(span, target, name), arguments);

    private static ExpressionSyntax Both(ExpressionSyntax? left, ExpressionSyntax right) =>
        left is null ? right : new BinarySyntax(right.Span, left, TokenKind.AmpAmp, right);

    private static Modifiers Dispatch(bool derived) => derived ? Modifiers.Override : Modifiers.Virtual;

    /// <summary>
    /// <c>bool Equals(T other)</c>: the same type exactly, and every field
    /// equal to the matching one. A derived record asks its base for the
    /// fields the base declared, and the base asks whether the types match.
    /// </summary>
    private static FunctionDeclSyntax EqualsFor(
        TypeSyntax self, SourceSpan span, List<ParameterSyntax> own, bool derived)
    {
        var other = Local(span, "other");

        ExpressionSyntax? test = derived
            ? Call(span, new BaseSyntax(span), "Equals", other)
            : Both(Call(span, new ThisSyntax(span), SameTypeName, other),
                   Call(span, other, SameTypeName, new ThisSyntax(span)));

        foreach (var parameter in own)
            test = Both(test, Call(span, Mine(span, parameter.Name), "Equals",
                new MemberAccessSyntax(span, other, parameter.Name)));

        return new FunctionDeclSyntax(
            span, Modifiers.Public | Modifiers.Virtual, LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.BoolKeyword), "Equals", [], [],
            [new ParameterSyntax(span, self, "other")], false,
            new BlockSyntax(span, [new ReturnSyntax(span, test)]));
    }

    /// <summary>
    /// <c>override bool Equals(Base other)</c>: a derived record reached as its
    /// base still compares everything it has.
    /// </summary>
    private static FunctionDeclSyntax EqualsOverBaseFor(TypeSyntax self, SourceSpan span, TypeSyntax recordBase)
    {
        var other = Local(span, "other");
        var test = Both(
            new IsPatternSyntax(span, other, new TypePatternSyntax(span, self, null, span)),
            Call(span, new ThisSyntax(span), "Equals", new CastSyntax(span, self, other)));

        return new FunctionDeclSyntax(
            span, Modifiers.Public | Modifiers.Override, LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.BoolKeyword), "Equals", [], [],
            [new ParameterSyntax(span, recordBase, "other")], false,
            new BlockSyntax(span, [new ReturnSyntax(span, test)]));
    }

    /// <summary><c>bool $SameRecordType(IHashable other) => other is T;</c></summary>
    private static FunctionDeclSyntax SameTypeFor(TypeSyntax self, SourceSpan span, bool derived)
    {
        var test = new IsPatternSyntax(span, Local(span, "other"),
            new TypePatternSyntax(span, self, null, span));

        return new FunctionDeclSyntax(
            span, Modifiers.Protected | Dispatch(derived), LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.BoolKeyword), SameTypeName, [], [],
            [new ParameterSyntax(span, Interface(span, ["Standard", "Collections", "IHashable"]), "other")],
            false, new BlockSyntax(span, [new ReturnSyntax(span, test)]));
    }

    /// <summary>
    /// <c>nuint GetHashCode()</c>: the fields' hashes folded together, the
    /// base's first where there is one.
    ///
    /// Each field's own hash is already mixed -- that is what
    /// <c>Standard.HashInteger</c> does for it -- so the fold only has to keep
    /// the fields apart, and multiplying by an odd number does that.
    /// </summary>
    private static FunctionDeclSyntax GetHashCodeFor(SourceSpan span, List<ParameterSyntax> own, bool derived)
    {
        ExpressionSyntax? hash = derived ? Call(span, new BaseSyntax(span), "GetHashCode") : null;

        foreach (var parameter in own)
        {
            var one = Call(span, Mine(span, parameter.Name), "GetHashCode");
            hash = hash is null
                ? one
                : new BinarySyntax(span,
                    new BinarySyntax(span, hash, TokenKind.Star,
                        new LiteralSyntax(span, TokenKind.IntLiteral, 31UL, "31u")),
                    TokenKind.Plus, one);
        }

        hash ??= new LiteralSyntax(span, TokenKind.IntLiteral, 0UL, "0u");

        return new FunctionDeclSyntax(
            span, Modifiers.Public | Dispatch(derived), LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.NUIntKeyword), "GetHashCode", [], [],
            [], false, new BlockSyntax(span, [new ReturnSyntax(span, hash)]));
    }

    /// <summary>
    /// <c>a == b</c> and <c>a != b</c>, both over <c>Equals</c>.
    ///
    /// Neither takes a nullable, so neither has C#'s problem of an operator
    /// that must answer for a null operand: comparing a <c>T?</c> is a
    /// different expression and the compiler says so.
    /// </summary>
    private static FunctionDeclSyntax EqualityOperatorFor(
        TypeSyntax type, IReadOnlyList<ParameterSyntax> positional, TokenKind which)
    {
        var span = positional[0].Span;

        var test = Call(span, Local(span, "left"), "Equals", Local(span, "right"));
        if (which == TokenKind.BangEquals)
            test = new UnarySyntax(span, TokenKind.Bang, test);

        return new FunctionDeclSyntax(
            span, Modifiers.Public | Modifiers.Static, LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.BoolKeyword),
            OperatorNames.For(which), [], [],
            [new ParameterSyntax(span, type, "left"), new ParameterSyntax(span, type, "right")],
            false, new BlockSyntax(span, [new ReturnSyntax(span, test)]))
        {
            IsOperator = true,
            OperatorToken = which,
        };
    }

    /// <summary>
    /// One <c>public T Name { get; init; }</c> per positional parameter the
    /// base does not already have: readable by anyone, set while the record is
    /// made, fixed after it.
    /// </summary>
    private static List<Declaration> PropertiesFor(List<ParameterSyntax> own)
    {
        var properties = new List<Declaration>(own.Count);

        foreach (var parameter in own)
        {
            var getter = new AccessorSyntax(parameter.Span, Modifiers.None, true, null);
            var setter = new AccessorSyntax(parameter.Span, Modifiers.None, false, null)
            {
                IsInit = true,
            };
            properties.Add(new PropertyDeclSyntax(
                parameter.Span, Modifiers.Public, parameter.Type, parameter.Name,
                [getter, setter], []));
        }

        return properties;
    }

    /// <summary>
    /// <c>void Deconstruct(out T1 X, out T2 Y)</c>, which is what lets
    /// <c>var (x, y) = point;</c> take a record apart.
    /// </summary>
    private static FunctionDeclSyntax DeconstructFor(IReadOnlyList<ParameterSyntax> positional)
    {
        var span = positional[0].Span;
        var statements = new List<StatementSyntax>(positional.Count);
        var parameters = new List<ParameterSyntax>(positional.Count);

        foreach (var parameter in positional)
        {
            statements.Add(new ExpressionStatementSyntax(span,
                new AssignmentSyntax(span, Local(span, parameter.Name), TokenKind.Equals,
                    Mine(span, parameter.Name))));
            parameters.Add(new ParameterSyntax(
                parameter.Span, parameter.Type, parameter.Name, ParameterMode.Out));
        }

        return new FunctionDeclSyntax(
            span, Modifiers.Public, LinkageKind.Stainless,
            new PrimitiveTypeSyntax(span, TokenKind.VoidKeyword), "Deconstruct", [], [],
            parameters, false, new BlockSyntax(span, statements));
    }

    /// <summary>
    /// The constructor the parameters describe, assigning each the record
    /// declares to the property of the same name. One the base has is the
    /// base's to set, through the arguments written after its name.
    /// </summary>
    /// <remarks>
    /// <c>this.X = X</c> rather than <c>X = X</c>: the parameter and the
    /// property share a name, which is what makes the form read well and what
    /// makes the qualification necessary.
    /// </remarks>
    private static ConstructorDeclSyntax ConstructorFor(
        string name, IReadOnlyList<ParameterSyntax> positional, List<ParameterSyntax> own)
    {
        var statements = new List<StatementSyntax>(own.Count);

        foreach (var parameter in own)
        {
            var span = parameter.Span;
            statements.Add(new ExpressionStatementSyntax(span,
                new AssignmentSyntax(span, Mine(span, parameter.Name), TokenKind.Equals,
                    Local(span, parameter.Name))));
        }

        var first = positional[0].Span;
        return new ConstructorDeclSyntax(
            first, Modifiers.Public, name, positional, new BlockSyntax(first, statements));
    }
}
