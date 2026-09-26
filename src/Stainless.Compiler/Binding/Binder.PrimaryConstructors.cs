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

using System.Collections;
using System.Reflection;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// <c>class Service(ILogger log, int size)</c>: a primary constructor, whose
/// parameters are in scope through the whole body.
///
/// An initializer and the base's arguments run inside the constructor, so
/// there a parameter is the parameter. Anywhere else it has to outlive the
/// call, so it is copied into a hidden field -- but only if some member body
/// names it, because the field is layout and layout is fixed before any body
/// is bound. Which parameters are named is therefore read off the syntax.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// Gives a type the hidden fields its member bodies need: one per primary
    /// parameter one of them names and no member of the type's own shadows.
    /// They are laid out after every declared field, in parameter order.
    /// </summary>
    private void DeclarePrimaryCaptures(TypeDeclSyntax declaration, NamedTypeSymbol type)
    {
        if (type.PrimaryConstructor is not { } primary) return;

        var names = primary.Parameters
            .Where(p => !p.IsThis)
            .Select(p => p.Name)
            .ToHashSet(StringComparer.Ordinal);

        var named = NamesOutsideTheConstructor(declaration, names);

        foreach (var parameter in primary.Parameters.Where(p => !p.IsThis))
        {
            if (!named.Contains(parameter.Name)) continue;

            // A member of the same name is nearer in a body, so the parameter
            // is never what the body meant.
            if (type.FindStorage(parameter.Name) is not null ||
                type.FindProperty(parameter.Name) is not null ||
                type.FindMethods(parameter.Name).Any())
                continue;

            if (parameter.Mode != ParameterMode.Value)
            {
                diagnostics.Error("SL0787", declaration.Span,
                    $"'{parameter.Name}' is a '{parameter.Mode.ToString().ToLowerInvariant()}' " +
                    $"parameter of the primary constructor of '{type.Name}', and a member body " +
                    "names it, so it would have to be kept after the constructor returns; what " +
                    "it refers to is the caller's and lives no longer than the call. Pass it " +
                    "by value");
                _refusedCaptures.Add((type, parameter.Name));
                continue;
            }

            var field = new FieldSymbol(parameter.Name, parameter.Type, type, type.Fields.Count)
            {
                IsBackingField = true,
                IsPrimaryCapture = true,
            };

            type.Fields.Add(field);
            type.PrimaryCaptures[parameter.Name] = field;
        }
    }

    /// <summary>Parameters that were refused a field, so a use says nothing more.</summary>
    private readonly HashSet<(NamedTypeSymbol, string)> _refusedCaptures = [];

    /// <summary>
    /// Which of <paramref name="names"/> a body other than the primary
    /// constructor's and the initializers' mentions as a bare name.
    ///
    /// A local of the same name counts as a mention; the field it costs is
    /// never read. Walked with a stack rather than by recursion, because an
    /// expression is as deep as the source makes it.
    /// </summary>
    private static HashSet<string> NamesOutsideTheConstructor(
        TypeDeclSyntax declaration, HashSet<string> names)
    {
        var found = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Stack<object>();

        foreach (var member in declaration.Members)
        {
            switch (member)
            {
                case FunctionDeclSyntax { Body: { } body }: pending.Push(body); break;
                case ConstructorDeclSyntax { IsPrimary: false } constructor:
                    pending.Push(constructor.Body);
                    break;
                case DestructorDeclSyntax destructor: pending.Push(destructor.Body); break;
                case PropertyDeclSyntax property:
                    foreach (var accessor in property.Accessors)
                        if (accessor.Body is { } written) pending.Push(written);
                    break;
            }
        }

        while (pending.Count > 0)
        {
            var node = pending.Pop();

            if (node is NameSyntax { Name.Parts: [var only] } && names.Contains(only))
                found.Add(only);

            foreach (var child in ChildrenOf(node))
                pending.Push(child);
        }

        return found;
    }

    /// <summary>Every syntax object directly inside this one.</summary>
    private static IEnumerable<object> ChildrenOf(object node)
    {
        foreach (var property in SyntaxProperties(node.GetType()))
        {
            switch (property.GetValue(node))
            {
                case string:
                    break;

                case IEnumerable many:
                    foreach (var item in many)
                        if (item is not null && IsSyntax(item.GetType()))
                            yield return item;
                    break;

                case { } one when IsSyntax(one.GetType()):
                    yield return one;
                    break;
            }
        }
    }

    private static readonly Dictionary<Type, PropertyInfo[]> s_syntaxProperties = [];

    private static PropertyInfo[] SyntaxProperties(Type type)
    {
        lock (s_syntaxProperties)
        {
            if (!s_syntaxProperties.TryGetValue(type, out var properties))
            {
                properties = type
                    .GetProperties(BindingFlags.Public | BindingFlags.Instance)
                    .Where(p => p.GetIndexParameters().Length == 0 &&
                                p.Name != "EqualityContract" &&
                                !p.PropertyType.IsValueType)
                    .ToArray();
                s_syntaxProperties[type] = properties;
            }

            return properties;
        }
    }

    private static bool IsSyntax(Type type) =>
        type.IsClass && type.Namespace == typeof(SyntaxNode).Namespace;

    /// <summary>
    /// Refuses a constructor of a type with a primary one that does not
    /// chain to it with <c>this(...)</c>: the primary constructor is the only
    /// one that gives the parameters, and the fields they fill, their values.
    /// </summary>
    private void CheckChainsToPrimary(FunctionSymbol constructor)
    {
        if (constructor.ContainingType?.PrimaryConstructor is not { } primary) return;
        if (constructor == primary || _delegated.ContainsKey(constructor)) return;

        diagnostics.Error("SL0785", constructor.Span,
            $"'{constructor.ContainingType.Name}' has a primary constructor, so every other " +
            "constructor has to run it first: write ': this(...)' after the parameters");
    }

    /// <summary>
    /// The primary constructor's copies of what its member bodies read, put
    /// at the head of it -- before the base is built, so a virtual call the
    /// base makes already finds them.
    /// </summary>
    private BoundBlock WithPrimaryCaptures(FunctionSymbol constructor, BoundBlock body)
    {
        if (!constructor.IsPrimaryConstructor) return body;

        var type = constructor.ContainingType!;
        if (type.PrimaryCaptures.Count == 0) return body;

        var span = constructor.Span;
        var self = Receiver(span, constructor.Parameters[0]);
        var copies = new List<BoundStatement>();

        foreach (var parameter in constructor.Parameters.Where(p => !p.IsThis))
            if (type.PrimaryCaptures.TryGetValue(parameter.Name, out var field))
                copies.Add(new BoundExpressionStatement(span, new BoundAssignment(span,
                    new BoundFieldAccess(span, self, field),
                    new BoundParameterAccess(span, parameter))));

        return new BoundBlock(body.Span, [.. copies, .. body.Statements]);
    }

    /// <summary>
    /// A primary constructor parameter named in a member body: the hidden
    /// field it was copied into, read through <c>this</c>.
    /// </summary>
    private BoundExpression? BindPrimaryParameter(string name, SourceSpan span)
    {
        if (_context.Function?.ContainingType is not { } owner) return null;
        if (_refusedCaptures.Contains((owner, name))) return new BoundErrorExpression(span);
        if (!owner.PrimaryCaptures.TryGetValue(name, out var field)) return null;

        if (_context.Function.IsStatic)
        {
            if (TryGiveLocalFunctionThis(_context.Function, span))
                return new BoundErrorExpression(span);

            diagnostics.Error("SL0576", span,
                $"'{name}' is a parameter of the primary constructor of " +
                $"'{owner.Name}', kept by each instance, and " +
                $"'{_context.Function.Name}' is static, so there is no instance here");
            return new BoundErrorExpression(span);
        }

        var receiver = BindImplicitThis(span);
        return receiver is null ? null : new BoundFieldAccess(span, receiver, field);
    }
}
