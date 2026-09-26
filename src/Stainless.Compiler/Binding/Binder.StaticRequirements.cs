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
/// <c>T.Zero</c>: a static member reached through a type parameter.
///
/// A generic body is bound once per instantiation with its type parameters
/// replaced, so <c>T</c> there is already <c>Money</c> and <c>T.Zero</c> is
/// <c>Money.Zero</c>. What a <c>static abstract</c> interface member adds is
/// the promise that there is one, checked where <c>Money</c> says it
/// implements the interface, and the default a <c>static virtual</c> one
/// falls back on when the type supplies nothing.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// Whether an expression in front of a member is a type parameter's name,
    /// which is the only route to an interface's static default.
    /// </summary>
    private bool NamesTypeParameter(ExpressionSyntax target) =>
        target is NameSyntax { Name.Parts.Count: 1, TypeArguments: null } name &&
        _context.Substitution.ContainsKey(name.Name.Parts[0]) &&
        !NamesAValue(name.Name.Parts[0]);

    /// <summary>
    /// The <c>static virtual</c> members of this name with a body, in the
    /// interfaces a type implements: what <c>T.Name</c> reaches when the type
    /// supplies none.
    /// </summary>
    private static List<FunctionSymbol> StaticDefaults(NamedTypeSymbol type, string name) =>
        type.AllInterfaces()
            .SelectMany(i => i.Methods)
            .Where(m => m.IsStatic && m.IsVirtual && m.HasBody && m.Name == name)
            .Distinct()
            .ToList();

    /// <summary>
    /// A static property through a type, or through a type parameter, which
    /// may also find an interface's default.
    /// </summary>
    private PropertySymbol? FindStaticProperty(
        NamedTypeSymbol owner, string member, ExpressionSyntax target)
    {
        if (owner.FindProperty(member) is { Getter.IsStatic: true } declared) return declared;
        if (!NamesTypeParameter(target)) return null;

        return owner.AllInterfaces()
            .Select(i => i.FindProperty(member))
            .FirstOrDefault(p => p is { Getter: { IsStatic: true, IsVirtual: true, HasBody: true } });
    }

    /// <summary>
    /// Refuses a <c>static abstract</c> or <c>static virtual</c> member named
    /// through its interface, as C# does (CS8926).
    ///
    /// A requirement says what each implementing type has, and the interface
    /// is not one of them: an abstract one has no body at all, and a virtual
    /// one's body is only what a type falls back on.
    /// </summary>
    private bool RefuseStaticRequirement(FunctionSymbol reached, NamedTypeSymbol owner, SourceSpan span)
    {
        if (owner is not InterfaceTypeSymbol contract) return false;
        if (reached is not { IsStatic: true, IsVirtual: true }) return false;

        string name = reached.Accessor?.Name ?? reached.Name;
        diagnostics.Error("SL0797", span,
            $"'{contract.Name}.{name}' is 'static {(reached.IsAbstract ? "abstract" : "virtual")}', " +
            "so it is reached through a type parameter constrained to the interface, as " +
            $"'T.{name}' where 'T : {contract.Name}', and not through the interface, which is " +
            "not one of the types that supply it",
            contract);
        return true;
    }
}
