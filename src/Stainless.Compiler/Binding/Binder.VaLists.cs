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

// VaList: C's va_list, and the two things done with one here.
public sealed partial class Binder
{
    /// <summary>
    /// <c>VaList.Start()</c>, or <c>args.Next&lt;T&gt;()</c> on a local or a
    /// parameter that is a <c>VaList</c>; null for any other call.
    /// </summary>
    private BoundExpression? TryBindVaList(CallSyntax syntax, List<BoundExpression> arguments)
    {
        if (syntax.Callee is not MemberAccessSyntax { ThroughPointer: false } access ||
            access.Target is not NameSyntax { Name.Parts: [var name] })
            return null;

        if (access is { Member: "Start", TypeArguments: null } &&
            !NamesAValue(name) && LookupLocal(name) is null &&
            TypeNamed([name]) == _builtins.VaList)
            return BindVaStart(syntax, arguments);

        if (access is { Member: "Next", TypeArguments: [var written] } &&
            (LookupLocal(name)?.Type ?? _context.Function?.Parameters.FirstOrDefault(p => p.Name == name)?.Type)
                == _builtins.VaList)
            return BindVaArg(syntax, access, written, arguments);

        return null;
    }

    private BoundExpression BindVaStart(CallSyntax syntax, List<BoundExpression> arguments)
    {
        // A lambda and a local function are never variadic, so one inside a
        // variadic function cannot start its list either.
        if (_context.Function is not { IsVariadic: true } function)
        {
            diagnostics.Error("SL0935", syntax.Span,
                "'VaList.Start()' reads the extra arguments of the function it is written in, and " +
                $"{(_context.Function is { } inside ? $"'{inside.Name}'" : "this")} takes none; " +
                "declare it with '...' after its parameters");
            return new BoundErrorExpression(syntax.Span);
        }

        if (arguments.Count != 0)
        {
            diagnostics.Error("SL0935", syntax.Span,
                $"'VaList.Start()' takes nothing; it starts at the first argument after '{function.Name}''s own");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundVaStart(syntax.Span, _builtins.VaList);
    }

    private BoundExpression BindVaArg(
        CallSyntax syntax, MemberAccessSyntax access, TypeSyntax written, List<BoundExpression> arguments)
    {
        var type = ResolveType(written, _context.File!);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (arguments.Count != 0)
        {
            diagnostics.Error("SL0935", syntax.Span, "'Next<T>()' takes nothing; the type says what to read");
            return new BoundErrorExpression(syntax.Span);
        }

        if (VaArgRefusal(type) is { } why)
        {
            diagnostics.Error("SL0935", written.Span, $"'Next<{type.Name}>' cannot be read: {why}", type);
            return new BoundErrorExpression(syntax.Span);
        }

        var list = BindExpression(access.Target);
        if (!Writable(list, access.Target.Span, "Next")) return new BoundErrorExpression(syntax.Span);
        NoteWriteTo(list);
        return new BoundVaArg(syntax.Span, type, list);
    }

    /// <summary>
    /// Why a variadic argument cannot be read as this type, or null. What C
    /// passes there is what was promoted: <c>int</c> and wider integers,
    /// <c>double</c>, and pointers.
    /// </summary>
    private static string? VaArgRefusal(TypeSymbol type)
    {
        var underlying = type is EnumTypeSymbol enumType ? enumType.UnderlyingType : type;
        return underlying switch
        {
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Float } =>
                "a 'float' is passed to '...' as a 'double', so read a 'double'",
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool or PrimitiveKind.Char or PrimitiveKind.Char16 } or
                PrimitiveTypeSymbol { IsInteger: true, Size: < 4 } =>
                $"a '{underlying.Name}' is passed to '...' as an 'int', so read an 'int' and convert it",
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Int128 or PrimitiveKind.UInt128 or PrimitiveKind.NDouble } =>
                "no convention here reads one from '...'",
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Void } => "there is no value to read",
            PrimitiveTypeSymbol or PointerTypeSymbol or DelegateTypeSymbol => null,
            _ => "only an 'int' or wider integer, a 'double', a pointer or a function pointer " +
                 "reaches '...' as itself; anything else is passed as one of those or behind one",
        };
    }
}
