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

using System.Text;

namespace Stainless.Binding;

/// <summary>Which C++ ABI a target uses. There are two, and they share nothing.</summary>
public enum CppAbi
{
    /// <summary>gcc and clang everywhere except a Microsoft target.</summary>
    Itanium,

    /// <summary>MSVC, and clang when it targets MSVC.</summary>
    Microsoft,
}

/// <summary>
/// Produces C++ linker names.
///
/// C++ has no ABI of its own: the platform defines how C-shaped things work and
/// says nothing about mangling, vtables or unwinding, so the compilers filled it
/// in separately. Two schemes resulted, and they agree on nothing at all — not
/// the prefix, not the order of return and parameters, not even whether the
/// return type is encoded. Both have been stable for a decade, which is what
/// makes writing this worth doing: Itanium since long before, and Microsoft's
/// since Visual Studio 2015, whose v140 through v143 toolsets interoperate.
///
/// What is encoded here is the part that is stable: names, namespaces, builtin
/// types and pointers. Nothing here touches templates or the standard library,
/// which is where the churn actually lives.
/// </summary>
public static class CppMangler
{
    /// <summary>
    /// The ABI a target triple implies. Only a Microsoft environment uses the
    /// Microsoft scheme; MinGW on Windows is Itanium like everything else, which
    /// is why the test is on the environment and not on the operating system.
    /// </summary>
    /// <summary>
    /// The ABI of the compiler's default target, which is clang's default and
    /// therefore the host: a Microsoft environment on Windows and Itanium
    /// elsewhere.
    ///
    /// <c>STAINLESS_CPP_ABI</c> overrides it. That exists so the scheme a host
    /// does not use can still be checked against a real compiler — the names
    /// are the whole of the contract, and half of it would otherwise only ever
    /// be exercised on another machine.
    /// </summary>
    public static CppAbi HostAbi =>
        Environment.GetEnvironmentVariable("STAINLESS_CPP_ABI") is { } chosen
            ? chosen.Equals("microsoft", StringComparison.OrdinalIgnoreCase)
                ? CppAbi.Microsoft
                : CppAbi.Itanium
            : OperatingSystem.IsWindows() ? CppAbi.Microsoft : CppAbi.Itanium;

    public static CppAbi AbiFor(string targetTriple) =>
        targetTriple.Contains("msvc", StringComparison.OrdinalIgnoreCase)
            ? CppAbi.Microsoft
            : CppAbi.Itanium;

    /// <summary>
    /// The linker name for a C++ function.
    ///
    /// <paramref name="qualifiers"/> is the enclosing namespace path, outermost
    /// first, and empty for one at global scope.
    /// </summary>
    public static string Mangle(
        CppAbi abi,
        IReadOnlyList<string> qualifiers,
        string name,
        TypeSymbol returnType,
        IReadOnlyList<TypeSymbol> parameters) =>
        abi == CppAbi.Microsoft
            ? MangleMicrosoft(qualifiers, name, returnType, parameters)
            : MangleItanium(qualifiers, name, parameters);

    // ======================================================= Itanium

    /// <summary>
    /// <c>_Z3addii</c> for <c>int add(int, int)</c>.
    ///
    /// The return type is deliberately absent: C++ cannot overload on it, so it
    /// carries no information a linker needs. Only a template's return type is
    /// encoded, and templates are out of scope here.
    /// </summary>
    private static string MangleItanium(
        IReadOnlyList<string> qualifiers, string name, IReadOnlyList<TypeSymbol> parameters)
    {
        var sb = new StringBuilder("_Z");

        // Substitutions are numbered across the whole name and refer back to
        // components already written. A builtin is never a candidate, which is
        // why `f(int, int)` needs none and `f(int*, int*)` does.
        var seen = new List<string>();

        if (qualifiers.Count == 0)
        {
            AppendItaniumSourceName(sb, name);
        }
        else
        {
            // A nested name is bracketed, and every component inside it is a
            // length-prefixed identifier.
            sb.Append('N');

            // Each enclosing scope is itself a candidate, and they are numbered
            // before any parameter is. That is why the repeated `int*` in
            // `geometry::mix(int*, double*, int*)` is S0_ and not S_: the
            // namespace took S_.
            var prefix = new StringBuilder();
            foreach (string qualifier in qualifiers)
            {
                AppendItaniumSourceName(sb, qualifier);
                AppendItaniumSourceName(prefix, qualifier);
                seen.Add(prefix.ToString());
            }

            AppendItaniumSourceName(sb, name);
            sb.Append('E');
        }

        // A function of no arguments takes `void`, spelled as one parameter.
        if (parameters.Count == 0)
        {
            sb.Append('v');
            return sb.ToString();
        }

        foreach (var parameter in parameters) AppendItaniumType(sb, parameter, seen);

        return sb.ToString();
    }

    private static void AppendItaniumSourceName(StringBuilder sb, string name) =>
        sb.Append(name.Length).Append(name);

    private static void AppendItaniumType(StringBuilder sb, TypeSymbol type, List<string> seen)
    {
        if (type is PrimitiveTypeSymbol primitive)
        {
            sb.Append(ItaniumBuiltin(primitive.Kind));
            return;
        }

        string encoded = ItaniumEncoding(type, seen);

        int existing = seen.IndexOf(encoded);
        if (existing >= 0)
        {
            AppendItaniumSubstitution(sb, existing);
            return;
        }

        seen.Add(encoded);
        sb.Append(encoded);
    }

    /// <summary>
    /// The encoding of a substitutable type, which is everything except a
    /// builtin. Written to a scratch buffer so it can be compared against what
    /// has already been emitted before deciding whether to emit it again.
    /// </summary>
    private static string ItaniumEncoding(TypeSymbol type, List<string> seen) => type switch
    {
        PointerTypeSymbol pointer => "P" + ItaniumPointee(pointer.Element, seen),
        NamedTypeSymbol named => ItaniumNamed(named),
        _ => "v",
    };

    private static string ItaniumPointee(TypeSymbol element, List<string> seen)
    {
        if (element is PrimitiveTypeSymbol primitive) return ItaniumBuiltin(primitive.Kind);

        var scratch = new StringBuilder();
        AppendItaniumType(scratch, element, seen);
        return scratch.ToString();
    }

    private static string ItaniumNamed(NamedTypeSymbol type)
    {
        var sb = new StringBuilder();
        var parts = CppNameParts(type);

        if (parts.Count == 1)
        {
            AppendItaniumSourceName(sb, parts[0]);
            return sb.ToString();
        }

        sb.Append('N');
        foreach (string part in parts) AppendItaniumSourceName(sb, part);
        sb.Append('E');
        return sb.ToString();
    }

    /// <summary>
    /// <c>S_</c> for the first substitution, <c>S0_</c> for the second,
    /// <c>S1_</c> for the third. The numbering is base 36 and starts its digits
    /// only at the second entry, which is the one genuinely odd corner of the
    /// scheme.
    /// </summary>
    private static void AppendItaniumSubstitution(StringBuilder sb, int index)
    {
        sb.Append('S');
        if (index > 0) sb.Append(Base36(index - 1));
        sb.Append('_');
    }

    private static string Base36(int value)
    {
        const string Digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        if (value == 0) return "0";

        var sb = new StringBuilder();
        while (value > 0)
        {
            sb.Insert(0, Digits[value % 36]);
            value /= 36;
        }
        return sb.ToString();
    }

    private static string ItaniumBuiltin(PrimitiveKind kind) => kind switch
    {
        PrimitiveKind.Void => "v",
        PrimitiveKind.Bool => "b",
        PrimitiveKind.Char => "c",
        PrimitiveKind.Char16 => "Ds",
        PrimitiveKind.Char32 => "Di",
        PrimitiveKind.SByte => "a",
        PrimitiveKind.Byte => "h",
        PrimitiveKind.Short => "s",
        PrimitiveKind.UShort => "t",
        PrimitiveKind.Int => "i",
        PrimitiveKind.UInt => "j",

        // C++'s `long` is 64-bit on Itanium targets and 32-bit on Microsoft
        // ones, so a fixed-width Stainless `long` is C++'s `long long`, which
        // is 64-bit on both. `nint` is pointer-sized, which is what C++'s
        // `long` happens to be here.
        PrimitiveKind.Long => "x",
        PrimitiveKind.ULong => "y",
        PrimitiveKind.NInt => "l",
        PrimitiveKind.NUInt => "m",

        PrimitiveKind.Float => "f",
        PrimitiveKind.Double => "d",
        _ => "v",
    };

    // ======================================================= Microsoft

    /// <summary>
    /// <c>?add@@YAHHH@Z</c> for <c>int add(int, int)</c>.
    ///
    /// Read it as: `?` name `@` qualifiers `@` `Y` (a free function) `A`
    /// (__cdecl) then the return type, then the parameters, then `@Z`. The
    /// return type *is* encoded here, unlike Itanium, and the qualifiers are
    /// written innermost first, which is the reverse of Itanium's order.
    /// </summary>
    private static string MangleMicrosoft(
        IReadOnlyList<string> qualifiers,
        string name,
        TypeSymbol returnType,
        IReadOnlyList<TypeSymbol> parameters)
    {
        var sb = new StringBuilder("?");
        sb.Append(name).Append('@');

        // Innermost first: `geometry::area` is `?area@geometry@@`.
        for (int i = qualifiers.Count - 1; i >= 0; i--) sb.Append(qualifiers[i]).Append('@');

        sb.Append('@');

        // `Y` is a free function; `A` is __cdecl, which is what x64 has.
        sb.Append("YA");

        var seen = new List<string>();
        AppendMicrosoftType(sb, returnType, seen);

        if (parameters.Count == 0)
        {
            // An empty parameter list is spelled `X` — void — and then the
            // terminator follows directly with no `@`.
            sb.Append("XZ");
            return sb.ToString();
        }

        foreach (var parameter in parameters) AppendMicrosoftType(sb, parameter, seen);

        sb.Append("@Z");
        return sb.ToString();
    }

    private static void AppendMicrosoftType(StringBuilder sb, TypeSymbol type, List<string> seen)
    {
        if (type is PrimitiveTypeSymbol primitive)
        {
            // A builtin is never back-referenced, in either scheme.
            sb.Append(MicrosoftBuiltin(primitive.Kind));
            return;
        }

        string encoded = MicrosoftEncoding(type);

        int existing = seen.IndexOf(encoded);
        if (existing >= 0 && existing < 10)
        {
            sb.Append((char)('0' + existing));
            return;
        }

        if (seen.Count < 10) seen.Add(encoded);
        sb.Append(encoded);
    }

    private static string MicrosoftEncoding(TypeSymbol type) => type switch
    {
        // On x64 every pointer is 64-bit, which is the `E`; `A` is the
        // unqualified form, as opposed to const or volatile.
        PointerTypeSymbol pointer => "PEA" + MicrosoftPointee(pointer.Element),
        NamedTypeSymbol named => MicrosoftNamed(named),
        _ => "X",
    };

    private static string MicrosoftPointee(TypeSymbol element) =>
        element is PrimitiveTypeSymbol primitive
            ? MicrosoftBuiltin(primitive.Kind)
            : MicrosoftEncoding(element);

    /// <summary>
    /// <c>Vwidget@geometry@@</c> — `V` for a class, `U` for a struct, then the
    /// name and its qualifiers innermost first.
    /// </summary>
    private static string MicrosoftNamed(NamedTypeSymbol type)
    {
        var parts = CppNameParts(type);
        var sb = new StringBuilder(type is StructTypeSymbol ? "U" : "V");

        for (int i = parts.Count - 1; i >= 0; i--) sb.Append(parts[i]).Append('@');

        sb.Append('@');
        return sb.ToString();
    }

    private static string MicrosoftBuiltin(PrimitiveKind kind) => kind switch
    {
        PrimitiveKind.Void => "X",
        PrimitiveKind.Bool => "_N",
        PrimitiveKind.Char => "D",
        PrimitiveKind.Char16 => "_S",
        PrimitiveKind.Char32 => "_U",
        PrimitiveKind.SByte => "C",
        PrimitiveKind.Byte => "E",
        PrimitiveKind.Short => "F",
        PrimitiveKind.UShort => "G",
        PrimitiveKind.Int => "H",
        PrimitiveKind.UInt => "I",

        // Microsoft targets are LLP64: `long` is 32 bits there, so a 64-bit
        // Stainless `long` is C++'s `__int64` rather than its `long`.
        PrimitiveKind.Long => "_J",
        PrimitiveKind.ULong => "_K",
        PrimitiveKind.NInt => "_J",
        PrimitiveKind.NUInt => "_K",

        PrimitiveKind.Float => "M",
        PrimitiveKind.Double => "N",
        _ => "X",
    };

    // ======================================================= shared

    /// <summary>
    /// A named type's C++ path: its module read as a namespace, then its own
    /// name. <c>App.Math.Vector</c> is <c>App::Math::Vector</c>.
    /// </summary>
    private static List<string> CppNameParts(NamedTypeSymbol type)
    {
        var parts = type.ModuleName
            .Split('.', StringSplitOptions.RemoveEmptyEntries)
            .ToList();

        parts.Add(type.SimpleName);
        return parts;
    }
}
