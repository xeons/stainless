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

/// <summary>
/// Pass 4, second half: functions, their parameters and the constants
/// that sit beside them.
///
/// This is also where a declaration is measured against the linkage it
/// claims, because <c>extern "C"</c> can only carry what C can spell.
/// </summary>
public sealed partial class Binder
{
    private void DeclareFunction(FileScope scope, NamedTypeSymbol? containingType, FunctionDeclSyntax declaration)
    {
        var module = scope.Module;
        var returnType = ResolveType(declaration.ReturnType, scope);

        var symbol = new FunctionSymbol
        {
            Name = declaration.Name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = declaration.Linkage,
            Kind = containingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = containingType,
            // Every interface member is part of the contract, so it is public
            // whether or not the programmer wrote the word.
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public)
                       || containingType is { IsContract: true },
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            IsVirtual = declaration.Modifiers.HasFlag(Modifiers.Virtual)
                        || declaration.Modifiers.HasFlag(Modifiers.Override)
                        || declaration.Modifiers.HasFlag(Modifiers.Abstract),
            IsOverride = declaration.Modifiers.HasFlag(Modifiers.Override),
            IsAbstract = declaration.Modifiers.HasFlag(Modifiers.Abstract),
            IsSealed = declaration.Modifiers.HasFlag(Modifiers.Sealed),
            IsVariadic = declaration.IsVariadic,
            Body = declaration.Body,
            Span = declaration.Span,
            Scope = scope,
        };

        if (containingType is not null)
        {
            // A method receives its instance: classes by reference, structs by pointer.
            TypeSymbol thisType = containingType is ClassTypeSymbol c
                ? c
                : new PointerTypeSymbol(containingType);
            symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });
        }

        AddParameters(symbol, declaration.Parameters, scope);

        if (declaration.Linkage.IsCpp())
        {
            // A C++ name encodes its parameters, so it can only be built once
            // they are known. `export "C++"` with no namespace written takes the
            // module's, because a module is what Stainless calls a namespace.
            symbol.CppNamespace = declaration.Namespace.Count > 0
                ? declaration.Namespace
                : declaration.Linkage == LinkageKind.ExportCpp
                    ? module.Name.Split('.', StringSplitOptions.RemoveEmptyEntries)
                    : [];

            // A `ref T` is a `T*`, so it mangles as one. C++ has a reference
            // type of its own that mangles differently, and this is not it: what
            // crosses is an address, which is what a C++ `T*` is too.
            symbol.ForeignName = CppMangler.Mangle(
                _cppAbi, symbol.CppNamespace, symbol.Name, symbol.ReturnType,
                symbol.Parameters
                    .Where(p => !p.IsThis)
                    .Select(p => p.IsByReference
                        ? new PointerTypeSymbol(p.Type)
                        : p.Type)
                    .ToList());
        }

        if (Dispatchable(declaration.Modifiers) is { } dispatch &&
            containingType is not ClassTypeSymbol)
            diagnostics.Error("SL0519", declaration.Span,
                containingType is { IsContract: true }
                    ? $"'{declaration.Name}' is an interface method, so '{dispatch}' says nothing " +
                      "new: every interface method is dispatched already"
                    : containingType is null
                        ? $"'{declaration.Name}' is a module-level function, so it cannot be " +
                          $"'{dispatch}'; there is no receiver to dispatch on"
                        : $"'{containingType.Name}' is not a class, so '{declaration.Name}' " +
                          $"cannot be '{dispatch}'; only a class is derived from");

        if (declaration.Modifiers.HasFlag(Modifiers.Protected) &&
            containingType is not ClassTypeSymbol)
            diagnostics.Error("SL0519", declaration.Span,
                $"'{declaration.Name}' cannot be 'protected'; the word means 'and anything " +
                "deriving from this', and only a class is derived from");

        // 'override' already says it is dispatched, because what it replaces was.
        if (declaration.Modifiers.HasFlag(Modifiers.Override) &&
            declaration.Modifiers.HasFlag(Modifiers.Virtual))
            diagnostics.Error("SL0507", declaration.Span,
                $"'{declaration.Name}' is both 'virtual' and 'override'; an override is " +
                "dispatched because what it replaces was");

        if (containingType is { IsContract: true })
        {
            if (declaration.Body is not null)
                diagnostics.Error("SL0301", declaration.Span,
                    $"'{declaration.Name}' is an interface method and cannot have a body; " +
                    "interfaces declare signatures only");
        }
        else if (symbol.IsAbstract)
        {
            if (declaration.Body is not null)
                diagnostics.Error("SL0498", declaration.Span,
                    $"'{declaration.Name}' is abstract, so it cannot have a body; " +
                    "a derived class supplies one");
        }
        else if (!declaration.Linkage.IsImport() && declaration.Body is null)
        {
            diagnostics.Error("SL0210", declaration.Span,
                $"'{declaration.Name}' has no body; Stainless has no forward declarations, " +
                "because declaration order never matters");
        }

        if (containingType is null && CaseNamed(scope, declaration.Name) is { } shadowed)
            diagnostics.Error("SL0414", declaration.Span,
                $"a module-level function cannot be named '{declaration.Name}': it is a case of " +
                $"variant '{shadowed.DeclaringVariant.QualifiedName}', and a bare " +
                $"'{declaration.Name}(...)' builds one of those. A method of a type may still " +
                "be called this, because a method is reached through its receiver");

        if (containingType is not null)
        {
            var signature = symbol.ParameterTypes.ToList();

            if (containingType.Methods.Any(m => m.Name == declaration.Name && m.Accepts(signature)))
                diagnostics.Error("SL0211", declaration.Span,
                    $"'{containingType.Name}' already declares a method '{declaration.Name}' " +
                    "taking these parameter types; overloads must differ in their parameters, " +
                    "and a return type alone does not distinguish two methods");

            // An interface gives each of its methods a dispatch slot by
            // position, so two of the same name in one interface would be a
            // call the receiver could not resolve.
            else if (containingType.IsContract &&
                     containingType.Methods.Any(m => m.Name == declaration.Name))
                diagnostics.Error("SL0416", declaration.Span,
                    $"'{containingType.Name}' already declares '{declaration.Name}'; an interface " +
                    "method may not be overloaded, because dispatch gives each one a single slot. " +
                    "A class may still implement two interfaces whose methods share a name");

            containingType.Methods.Add(symbol);
        }

        module.Functions.Add(symbol);
    }

    /// <summary>
    /// Refuses a C signature that would hand a counted reference across the
    /// boundary inside a struct.
    ///
    /// A struct of plain data is still a C struct, byte for byte, and crosses
    /// freely in both directions. One that holds a reference is not: copying it
    /// retains what it holds, and C has no way to perform that copy — it would
    /// memcpy the bytes and leave the count behind. The same reasoning already
    /// keeps a bare <c>String</c> out of a C signature; this closes the gap a
    /// struct could otherwise smuggle one through.
    /// </summary>
    /// <summary>
    /// The dispatch word written on a declaration that cannot be dispatched, or
    /// null when none was. Reported where the declaration is, so that a
    /// <c>virtual</c> on a field says so rather than going quiet.
    /// </summary>
    private static string? Dispatchable(Modifiers modifiers) =>
        modifiers.HasFlag(Modifiers.Virtual) ? "virtual"
        : modifiers.HasFlag(Modifiers.Override) ? "override"
        : modifiers.HasFlag(Modifiers.Abstract) ? "abstract"
        : null;

    private void ValidateLinkageSignatures()
    {
        foreach (var symbol in _modules.Values.SelectMany(m => m.Functions))
        {
            if (!symbol.Linkage.IsForeign()) continue;

            string how = symbol.Linkage switch
            {
                LinkageKind.ExternC => "extern \"C\"",
                LinkageKind.ExportC => "export \"C\"",
                LinkageKind.ExternCpp => "extern \"C++\"",
                _ => "export \"C++\"",
            };

            if (symbol.ReturnType is StructTypeSymbol { } returned && returned.CarriesReferences())
                diagnostics.Error("SL0284", symbol.Span,
                    $"'{returned.Name}' holds a reference, so it cannot be returned across " +
                    $"{how}; C would copy its bytes and leave the count behind. Return a " +
                    "struct of plain data, or a raw pointer");

            foreach (var parameter in symbol.Parameters)
            {
                if (parameter.Type is not StructTypeSymbol { } passed ||
                    !passed.CarriesReferences())
                    continue;

                diagnostics.Error("SL0284", symbol.Span,
                    $"'{passed.Name}' holds a reference, so parameter '{parameter.Name}' " +
                    $"cannot cross {how}; C would copy its bytes and leave the count behind. " +
                    "Pass a struct of plain data, or a raw pointer");
            }
        }
    }

    private void AddParameters(FunctionSymbol symbol, IReadOnlyList<ParameterSyntax> parameters, FileScope scope)
    {
        foreach (var parameter in parameters)
        {
            if (symbol.Parameters.Any(p => p.Name == parameter.Name))
            {
                diagnostics.Error("SL0212", parameter.Span,
                    $"duplicate parameter name '{parameter.Name}'");
                continue;
            }

            var type = ResolveType(parameter.Type, scope);
            if (type.IsVoid())
                diagnostics.Error("SL0213", parameter.Span,
                    $"parameter '{parameter.Name}' cannot have type 'void'");

            // C decays an array parameter to a pointer and Stainless has no
            // decay, so passing one by value would be a silent copy of every
            // element *and* a different ABI from the C it is meant to match.
            // `ref` is the one that lines up: it is `T (*)[N]` on both sides.
            if (type is FixedArrayTypeSymbol && parameter.Mode == ParameterMode.Value)
                diagnostics.Error("SL0491", parameter.Span,
                    $"parameter '{parameter.Name}' cannot be '{type.Name}' by value; C " +
                    "passes an array as a pointer and copying every element here would " +
                    $"be neither. Write 'ref {type.Name}' or 'in {type.Name}'");

            symbol.Parameters.Add(
                new ParameterSymbol(parameter.Name, type, symbol.Parameters.Count)
                {
                    Mode = parameter.Mode,
                });
        }
    }

    private void DeclareGlobalConstant(FileScope scope, GlobalConstDeclSyntax declaration)
    {
        var module = scope.Module;
        if (module.Constants.ContainsKey(declaration.Name))
        {
            diagnostics.Error("SL0201", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        // Module constants must fold at compile time, so only literals are allowed
        // for now -- and a negated one, which the parser sees as a unary minus
        // over a literal rather than as a literal. A C header is full of them.
        object? value = null;
        TypeSymbol type = declaration.Type is null
            ? PrimitiveTypeSymbol.Int
            : ResolveType(declaration.Type, scope);

        if (ConstantLiteral(declaration.Value) is { } literal)
        {
            bool negated = Negated(declaration.Value);
            value = negated ? Negate(literal.Value) : literal.Value;

            if (negated && value is null)
                diagnostics.Error("SL0215", declaration.Value.Span,
                    "only a number can be negated");

            if (declaration.Type is null)
                type = literal.Kind switch
                {
                    TokenKind.FloatLiteral => PrimitiveTypeSymbol.Double,
                    TokenKind.TrueKeyword or TokenKind.FalseKeyword => PrimitiveTypeSymbol.Bool,
                    TokenKind.CharLiteral => PrimitiveTypeSymbol.Char,
                    _ => PrimitiveTypeSymbol.Int,
                };
            else if (!Suits(literal.Kind, type))
                diagnostics.Error("SL0479", declaration.Value.Span,
                    $"'{declaration.Name}' is declared '{type.Name}', and " +
                    $"{literal.Kind.Describe()} is not one");
        }
        else
        {
            diagnostics.Error("SL0215", declaration.Value.Span,
                "a module-level 'const' must be initialized with a literal");
        }

        // A constant is a value inlined at every use, so it has to be something
        // that fits in one. A String is a counted object, and inlining a pointer
        // to its bytes would produce something that looks like a String, passes
        // every check, and is not one -- which is worse than not compiling.
        if (type is not (PrimitiveTypeSymbol or EnumTypeSymbol) && !type.IsError())
        {
            diagnostics.Error("SL0478", declaration.Span,
                $"a 'const' holds a number, a bool, a char or an enum, and " +
                $"'{type.Name}' is none of those. Write " +
                $"'static readonly {type.Name} {declaration.Name} = ...' instead, " +
                "which has storage rather than being inlined");

            // Registered anyway, so that every use of it does not then report
            // an undefined name on top of the one real error.
        }

        module.Constants[declaration.Name] = new ConstantSymbol(declaration.Name, type, value)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
        };
    }

    /// <summary>
    /// Whether a literal of this kind can be the value of a constant of this type.
    ///
    /// Without this a mistyped constant is not an error but a zero, which is
    /// the worst of the three possible outcomes: it compiles, it runs, and the
    /// number it stands for is wrong everywhere it was used.
    /// </summary>
    private static bool Suits(TokenKind kind, TypeSymbol type)
    {
        if (type.IsError()) return true;
        var underlying = type is EnumTypeSymbol enumType ? enumType.UnderlyingType : type;

        return kind switch
        {
            // A character is a byte-wide integer, so it suits both -- which is
            // the same latitude C# gives `const int Newline = '\n';`.
            TokenKind.IntLiteral or TokenKind.CharLiteral =>
                underlying is PrimitiveTypeSymbol { IsInteger: true }
                    or PrimitiveTypeSymbol { Kind: PrimitiveKind.Char },
            TokenKind.FloatLiteral => underlying is PrimitiveTypeSymbol { IsFloat: true },
            TokenKind.TrueKeyword or TokenKind.FalseKeyword =>
                underlying is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool },
            _ => false,
        };
    }

    /// <summary>The literal a constant initializer is, looking through one minus.</summary>
    private static LiteralSyntax? ConstantLiteral(ExpressionSyntax value) => value switch
    {
        LiteralSyntax literal => literal,
        UnarySyntax { Operator: TokenKind.Minus, Operand: LiteralSyntax literal } => literal,
        _ => null,
    };

    private static bool Negated(ExpressionSyntax value) =>
        value is UnarySyntax { Operator: TokenKind.Minus };

    /// <summary>
    /// Negates a literal's value, or null when it is not a number.
    ///
    /// An integer literal is held as a <c>ulong</c> whatever it will end up
    /// being, so the negation is two's complement and stays a <c>ulong</c>. That
    /// is the same shape the emitter already narrows to the constant's declared
    /// width, so -21 as an <c>int</c> comes out as -21 and not as 2^64 - 21.
    /// </summary>
    private static object? Negate(object? value) => value switch
    {
        ulong number => unchecked(0UL - number),
        double number => -number,
        _ => null,
    };
}
