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

using System.Text;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Produces linker symbol names. The scheme is documented in docs/abi.md and is
/// deliberately length-prefixed so it needs no separators and never collides
/// with a C identifier (which cannot contain the leading "_SL" plus digits shape
/// this produces for any realistic name).
/// </summary>
public static class Mangler
{
    /// <summary>
    /// A C name with the convention's decoration, which is the whole of what a
    /// convention changes about linking.
    ///
    /// <para>
    /// Microsoft's rules, and they are the ones every x86 Windows library was
    /// built with: <c>__cdecl</c> takes a leading underscore, <c>__stdcall</c>
    /// takes one and a <c>@</c> and the number of bytes its arguments occupy,
    /// <c>__fastcall</c> takes a leading <c>@</c> instead, and
    /// <c>__vectorcall</c> takes <c>@@</c> and the count with no prefix.
    /// </para>
    ///
    /// <para>
    /// The byte count is what makes a mismatch a link error rather than a
    /// corrupted stack: <c>__stdcall</c> has the callee remove the arguments, so
    /// a caller and a callee that disagree about how many there are would
    /// otherwise run on and unbalance the stack. Encoding the count in the name
    /// means the linker refuses first.
    /// </para>
    ///
    /// <para>
    /// The leading underscore for plain <c>__cdecl</c> is not written here:
    /// LLVM applies the target's own symbol prefix to every global. It is only
    /// spelled out when a decoration is added, because then the whole name has
    /// to be given at once -- which is what the <c>\1</c> prefix in the emitted
    /// IR says.
    /// </para>
    /// </summary>
    /// <summary>
    /// True when the convention changed the name, so the whole symbol has to be
    /// given to LLVM rather than letting it add the target's own prefix.
    /// </summary>
    public static bool IsDecorated(FunctionSymbol function) =>
        function.Linkage is LinkageKind.ExternC or LinkageKind.ExportC &&
        Decorated(function) != function.Name;

    public static string Decorated(FunctionSymbol function)
    {
        var target = TargetPlatform.Current;
        var convention = function.CallingConvention;

        // Decoration is Microsoft's, and it reaches no further than PE does.
        // clang gives an i386 ELF `__stdcall` the convention and the plain
        // name both, which is what gcc has always done -- so a 32-bit Linux
        // build went looking for `_add_stdcall@8`, found nothing, and said so
        // at link time. It is the one thing about a convention that is the
        // object format's question rather than the architecture's.
        if (!target.IsWindows) return function.Name;

        // Which conventions are anything but a note to the reader is the
        // architecture's question. x86 has all of them; there is one on every
        // 64-bit target, and `__vectorcall` is the only name that still means
        // something on x86-64, where Microsoft defines it. ARM64 has no second
        // convention at all, so there is nothing to tell apart.
        bool decorates = target.Architecture switch
        {
            TargetArch.X86 => true,
            TargetArch.X64 => convention == Syntax.CallingConvention.Vectorcall,
            _ => false,
        };

        if (!decorates) return function.Name;

        if (convention is Syntax.CallingConvention.Default or Syntax.CallingConvention.Cdecl)
            return function.Name;

        int bytes = ArgumentBytes(function, target.PointerWidth);

        return convention switch
        {
            Syntax.CallingConvention.Stdcall => $"_{function.Name}@{bytes}",
            Syntax.CallingConvention.Fastcall => $"@{function.Name}@{bytes}",
            Syntax.CallingConvention.Vectorcall => $"{function.Name}@@{bytes}",
            _ => function.Name,
        };
    }

    /// <summary>
    /// How many bytes the arguments occupy, each rounded up to a whole stack
    /// slot. A struct counts its own size rounded the same way, because it is
    /// pushed whole.
    /// </summary>
    private static int ArgumentBytes(FunctionSymbol function, int slot)
    {
        int total = 0;
        foreach (var parameter in function.Parameters)
        {
            if (parameter.IsThis) continue;

            // A `ref`, an `in` and an `out` are each one pointer.
            int size = parameter.IsByReference ? slot : parameter.Type.Size;
            total += (size + slot - 1) / slot * slot;
        }
        return total;
    }

    public static string Mangle(FunctionSymbol function)
    {
        // C linkage means "use exactly this name" in both directions -- except
        // that on x86 a convention decorates it, and the decoration is part of
        // the name the linker looks for. A C++ name is mangled by CppMangler and
        // stamped on the symbol, so it never reaches here.
        if (function.Linkage is LinkageKind.ExternC or LinkageKind.ExportC)
            return Decorated(function);

        var sb = new StringBuilder("_SL");

        foreach (string segment in function.ModuleName.Split('.', StringSplitOptions.RemoveEmptyEntries))
            AppendIdentifier(sb, segment);

        // An instantiated generic's simple name is `Box<int>`, which a linker
        // symbol may not contain.
        if (function.ContainingType is not null)
            AppendIdentifier(sb, SymbolSafe(function.ContainingType.SimpleName));

        AppendIdentifier(sb, function.Kind switch
        {
            FunctionKind.Constructor => "ctor",
            FunctionKind.Destructor => "dtor",
            FunctionKind.StaticConstructor => "cctor",
            _ => function.Name,
        });

        // An instantiated generic carries its type arguments, so two
        // instantiations never collide even when their parameters match.
        if (function.TypeArguments.Count > 0)
        {
            sb.Append('G').Append(function.TypeArguments.Count);
            foreach (var argument in function.TypeArguments) AppendType(sb, argument);
        }

        var valueParameters = function.Parameters.Where(p => !p.IsThis).ToList();
        if (valueParameters.Count == 0) sb.Append('v');
        else foreach (var parameter in valueParameters) AppendType(sb, parameter.Type);

        if (function.IsVariadic) sb.Append('z');

        sb.Append('E');
        AppendType(sb, function.ReturnType);
        return sb.ToString();
    }

    /// <summary>The symbol holding a class's static <c>TypeInfo</c> record.</summary>
    public static string TypeInfoSymbol(ClassTypeSymbol type) =>
        "_SLti" + Sanitize(type.QualifiedName);

    /// <summary>
    /// The hook the runtime calls when a class's last reference goes.
    ///
    /// Here rather than in the emitter because two things need to agree on it:
    /// the emitter, which defines it, and the metadata writer, which tells
    /// another compilation what to call when a class derived there hands the
    /// object back.
    /// </summary>
    public static string DestroySymbol(ClassTypeSymbol type) =>
        "_SLdestroy_" + SymbolSafe(type.QualifiedName);

    private static void AppendIdentifier(StringBuilder sb, string identifier)
    {
        sb.Append(identifier.Length);
        sb.Append(identifier);
    }

    private static void AppendType(StringBuilder sb, TypeSymbol type)
    {
        switch (type)
        {
            case PrimitiveTypeSymbol primitive:
                sb.Append(PrimitiveCode(primitive.Kind));
                break;

            case PointerTypeSymbol pointer:
                sb.Append('P');
                AppendType(sb, pointer.Element);
                break;

            case ArrayTypeSymbol array:
                sb.Append('A');
                AppendType(sb, array.Element);
                break;

            case OptionalTypeSymbol optional:
                sb.Append('O');
                AppendType(sb, optional.Element);
                break;

            case WeakTypeSymbol weak:
                sb.Append('W');
                AppendType(sb, weak.Element);
                break;

            case ClassTypeSymbol classType:
                sb.Append('C');
                AppendIdentifier(sb, Sanitize(classType.QualifiedName));
                break;

            case InterfaceTypeSymbol interfaceType:
                sb.Append('I');
                AppendIdentifier(sb, Sanitize(interfaceType.QualifiedName));
                break;

            // A com interface is not an InterfaceTypeSymbol -- the two have
            // different dispatch and different references -- so it needs a code
            // of its own. Without one it fell through to 'v', which is also
            // what "no parameters" is spelled as, so every com interface
            // parameter mangled to nothing and two overloads taking different
            // ones produced the same symbol.
            case ComInterfaceTypeSymbol comInterface:
                sb.Append('M');
                AppendIdentifier(sb, Sanitize(comInterface.QualifiedName));
                break;

            // Length first, so 'int[3]' and 'int[4]' differ. This also fell
            // through to 'v'.
            case FixedArrayTypeSymbol fixedArray:
                sb.Append('F');
                sb.Append(fixedArray.Length);
                sb.Append('_');
                AppendType(sb, fixedArray.Element);
                break;

            case StructTypeSymbol structType:
                sb.Append('S');
                AppendIdentifier(sb, Sanitize(structType.QualifiedName));
                break;

            case EnumTypeSymbol enumType:
                sb.Append('E');
                AppendIdentifier(sb, Sanitize(enumType.QualifiedName));
                break;

            case DelegateTypeSymbol delegateType:
                sb.Append('D');
                AppendIdentifier(sb, Sanitize(delegateType.QualifiedName));
                break;

            default:
                sb.Append('v');
                break;
        }
    }

    private static char PrimitiveCode(PrimitiveKind kind) => kind switch
    {
        PrimitiveKind.SByte => 'a',
        PrimitiveKind.Short => 's',
        PrimitiveKind.Int => 'i',
        PrimitiveKind.Long => 'l',
        PrimitiveKind.NInt => 'n',
        PrimitiveKind.Byte => 'h',
        PrimitiveKind.UShort => 't',
        PrimitiveKind.UInt => 'j',
        PrimitiveKind.ULong => 'm',
        PrimitiveKind.NUInt => 'y',
        PrimitiveKind.Float => 'f',
        PrimitiveKind.Double => 'd',
        PrimitiveKind.Bool => 'b',
        PrimitiveKind.Char => 'c',
        PrimitiveKind.Char16 => 'u',
        PrimitiveKind.Char32 => 'U',
        _ => 'v',
    };

    /// <summary>
    /// Reduces a name to what a linker symbol may contain. Instantiated generics
    /// arrive here as <c>App.Box&lt;int&gt;</c>, arrays as <c>int[]</c>, and both
    /// the mangler and the emitter must agree on the result.
    /// </summary>
    /// <summary>
    /// A name reduced to what a linker symbol may hold.
    ///
    /// The test is <c>IsAscii</c> rather than <c>IsLetterOrDigit</c>, and the
    /// difference is the whole of this method's history: the framework's
    /// version answers true for every letter Unicode has, so an identifier
    /// written <c>café</c> passed through unchanged and landed in generated IR,
    /// which has an ASCII grammar and rejected it -- a message about a file the
    /// author never wrote, for a name C# would have accepted. Anything past
    /// ASCII is spelled as its code point instead, so two identifiers that
    /// differ still do.
    /// </summary>
    public static string SymbolSafe(string name)
    {
        var sb = new StringBuilder(name.Length);

        foreach (char c in name)
        {
            if (char.IsAsciiLetterOrDigit(c)) sb.Append(c);
            else if (char.IsAscii(c)) sb.Append('_');
            else sb.Append("_u").Append(((int)c).ToString(
                "X4", System.Globalization.CultureInfo.InvariantCulture));
        }

        return sb.ToString();
    }

    private static string Sanitize(string qualifiedName) => SymbolSafe(qualifiedName);
}
