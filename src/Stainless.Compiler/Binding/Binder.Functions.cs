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
        var returnType = ResolveType(declaration.ReturnType, scope, allowVoid: true);

        // Static is a statement about a member. On a module-level function the
        // word is refused below (SL0573) and the function is an ordinary one:
        // everything that reads IsStatic goes on to ask which type the method
        // is a member of, and this one is a member of nothing.
        bool isStatic = declaration.Modifiers.HasFlag(Modifiers.Static);

        var symbol = new FunctionSymbol
        {
            Name = declaration.Name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = declaration.Linkage,
            CallingConvention = declaration.CallingConvention,
            Documentation = declaration.Documentation,
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
            IsConversion = declaration.IsConversion,
            IsImplicitConversion = declaration.IsImplicitConversion,
            IsStatic = isStatic && containingType is not null,
            IsVariadic = declaration.IsVariadic,
            Body = declaration.Body,
            Span = declaration.Span,
            Scope = scope,
        };

        // An operator has no receiver: it is static, and every operand is
        // written out. That is what makes `2 * money` expressible, since an
        // operator whose left operand is not the declaring type would have
        // nothing to hang a `this` off. A static method has none for the same
        // reason it is called by naming the type: there is no instance.
        if (containingType is not null && !declaration.IsOperator && !isStatic)
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

        if (isStatic) CheckStatic(containingType, declaration);

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

        if (declaration.IsConversion)
        {
            CheckConversion(containingType, symbol, declaration);
            module.Functions.Add(symbol);
            return;
        }

        if (declaration.IsOperator)
        {
            CheckOperator(containingType, symbol, declaration);
            module.Functions.Add(symbol);
            return;
        }

        // Two functions in one module collide exactly when they mangle alike,
        // and the mangled name is the parameter types. Left unchecked, both
        // would be emitted under one symbol and LLVM would be the one to say so,
        // in a message about generated IR naming a symbol that is in no source
        // file. An `extern` redeclared is caught here too: one C symbol with two
        // prototypes is a mistake, and with one prototype twice is a forward
        // declaration, which the language has no need of.
        if (containingType is null &&
            module.FindFunctions(declaration.Name).Any(f => f.Accepts(symbol.ParameterTypes.ToList())))
            diagnostics.Error("SL0211", declaration.Span,
                $"'{module.Name}' already declares a function '{declaration.Name}' taking " +
                "these parameter types; overloads must differ in their parameters, and a " +
                "return type alone does not distinguish two functions");

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
    /// What <c>static</c> may be written on.
    ///
    /// It belongs to a type and means "no receiver", so every word that is
    /// about a receiver contradicts it, and at module scope it says nothing
    /// that was not already true.
    /// </summary>
    private void CheckStatic(NamedTypeSymbol? containingType, FunctionDeclSyntax declaration)
    {
        if (containingType is null)
        {
            diagnostics.Error("SL0573", declaration.Span,
                $"'{declaration.Name}' is already at module scope, so 'static' says nothing " +
                "new: a module has no instance for a function to belong to. Write the " +
                "function without the word, or move it into the type it is about");
            return;
        }

        if (containingType.IsContract)
        {
            diagnostics.Error("SL0574", declaration.Span,
                $"'{containingType.Name}' is an interface, so '{declaration.Name}' cannot be " +
                "'static': an interface promises what an object can do, and a static method " +
                "has no object. Declare it on a type that implements this");
            return;
        }

        // Only for a class: on anything else the word was already refused for
        // the better reason that there is nothing to derive from.
        if (containingType is ClassTypeSymbol && Dispatchable(declaration.Modifiers) is { } dispatch)
            diagnostics.Error("SL0575", declaration.Span,
                $"'{declaration.Name}' cannot be both 'static' and '{dispatch}'; dispatch " +
                "chooses a body from the object a call arrives on, and a static method has " +
                "no object");

        if (containingType is ClassTypeSymbol && declaration.Modifiers.HasFlag(Modifiers.Protected))
            diagnostics.Error("SL0575", declaration.Span,
                $"'{declaration.Name}' cannot be both 'static' and 'protected'; 'protected' " +
                "is about what a derived object may reach through itself, and a static " +
                "method is not reached through an object");
    }

    /// <summary>
    /// What an operator declaration has to be, beyond parsing.
    ///
    /// Every rule here is C#'s, and each is C#'s for a reason that holds:
    ///
    /// <list type="bullet">
    /// <item>It belongs to a type. A module-level one would let a program add
    /// an operator to somebody else's type from a distance, which is the thing
    /// that makes an expression unreadable.</item>
    /// <item>One operand must be that type, so that reading <c>a + b</c> tells
    /// you where to look for what it means.</item>
    /// <item>It must be public. An operator nobody outside can use is a method
    /// with a strange spelling.</item>
    /// <item>A comparison returns <c>bool</c>, and the pairs come together:
    /// a type that can be asked <c>==</c> and not <c>!=</c> is a trap.</item>
    /// </list>
    /// </summary>
    private void CheckOperator(
        NamedTypeSymbol? containingType, FunctionSymbol symbol, FunctionDeclSyntax declaration)
    {
        var token = declaration.OperatorToken;
        string written = token.FixedText() ?? "?";

        if (containingType is null)
        {
            diagnostics.Error("SL0560", declaration.Span,
                $"operator '{written}' has to be declared inside the type it is for; a " +
                "module-level one would let a program give somebody else's type a meaning " +
                "from a distance");
            return;
        }

        if (containingType.IsContract)
        {
            diagnostics.Error("SL0560", declaration.Span,
                $"'{containingType.Name}' is an interface, and an operator is not dispatched: " +
                "it is chosen from the operand types where it is written, so an interface has " +
                "nothing to promise here");
            return;
        }

        if (!declaration.Modifiers.HasFlag(Modifiers.Public))
            diagnostics.Error("SL0561", declaration.Span,
                $"operator '{written}' has to be 'public'; an operator only this module could " +
                "write is a method with an unusual spelling");

        int count = symbol.Parameters.Count;
        bool unary = OperatorNames.IsUnary(token);
        bool either = OperatorNames.IsEither(token);

        int wanted = unary ? 1 : 2;
        if ((unary || !either) && count != wanted)
            diagnostics.Error("SL0562", declaration.Span,
                $"operator '{written}' takes {wanted} operand{(wanted == 1 ? "" : "s")}, " +
                $"and this declares {count}");
        else if (either && count is not (1 or 2))
            diagnostics.Error("SL0562", declaration.Span,
                $"operator '{written}' takes one operand or two, and this declares {count}");

        // One operand has to be the type, so that reading `a + b` says where
        // to look. Without it, a type could give meaning to `int + int`.
        if (count > 0 && !symbol.Parameters.Any(p => Mentions(p.Type, containingType)))
            diagnostics.Error("SL0563", declaration.Span,
                $"operator '{written}' is declared in '{containingType.Name}', so one of its " +
                "operands has to be one; an operator over other people's types belongs to " +
                "neither of them");

        if (OperatorNames.IsComparison(token) && !symbol.ReturnType.IsBool() &&
            !symbol.ReturnType.IsError())
            diagnostics.Error("SL0564", declaration.Span,
                $"operator '{written}' answers a question, so it returns 'bool', not " +
                $"'{symbol.ReturnType.Name}'");

        var signature = symbol.ParameterTypes.ToList();
        if (containingType.Operators.Any(o => o.Name == symbol.Name && o.Accepts(signature)))
            diagnostics.Error("SL0211", declaration.Span,
                $"'{containingType.Name}' already declares operator '{written}' for these " +
                "operand types");

        containingType.Operators.Add(symbol);
    }

    /// <summary>
    /// The rules a conversion operator keeps, and where it is registered.
    ///
    /// They are C#'s, and each is about the same thing: a conversion is chosen
    /// by the types at the point of use rather than by anything written there,
    /// so the reader has to be able to find it from the two types alone, and
    /// there has to be exactly one of it.
    /// </summary>
    private void CheckConversion(
        NamedTypeSymbol? containingType, FunctionSymbol symbol, FunctionDeclSyntax declaration)
    {
        if (containingType is null)
        {
            diagnostics.Error("SL0615", declaration.Span,
                "a conversion belongs to one of the two types it converts between; a " +
                "module-level one would give somebody else's types a meaning from a distance");
            return;
        }

        if (!symbol.IsPublic)
            diagnostics.Error("SL0615", declaration.Span,
                "a conversion must be 'public'; one only its own module could use is a " +
                "function with an unusual spelling");

        if (symbol.Parameters.Count != 1)
        {
            diagnostics.Error("SL0615", declaration.Span,
                "a conversion takes exactly the value it converts, and this declares " +
                $"{symbol.Parameters.Count}");
            return;
        }

        // Registered now and judged later. What is left to check is about how
        // two types are related -- whether one derives from the other, whether
        // the language already converts between them -- and none of that is
        // settled while signatures are still being resolved.
        containingType.Conversions.Add(symbol);
    }

    /// <summary>
    /// The rules a conversion operator keeps.
    ///
    /// They are C#'s, and each is about the same thing: a conversion is chosen
    /// by the types at the point of use rather than by anything written there,
    /// so a reader has to be able to find it from the two types alone, and
    /// there has to be exactly one of it.
    ///
    /// This runs after inheritance and layout, because <i>every</i> rule left
    /// is a question about a pair of types: whether they are the same, whether
    /// one is an interface, and above all whether the language already carries
    /// one to the other -- which needs the base chain that pass 5 built.
    /// </summary>
    private void CheckConversions()
    {
        foreach (var type in _modules.Values.SelectMany(m => m.Types.Values).ToList())
        {
            var kept = new List<FunctionSymbol>();

            foreach (var conversion in type.Conversions)
            {
                var from = conversion.Parameters[0].Type;
                var to = conversion.ReturnType;

                if (from.IsError() || to.IsError()) continue;

                if (from.Equals(to))
                {
                    diagnostics.Error("SL0615", conversion.Span,
                        $"this converts '{from.Name}' to itself, which is what it already is");
                    continue;
                }

                // One side has to be the declaring type, for the reason an
                // operator's operand does: reading `(Money)x` says where to
                // look for what it means.
                if (!Mentions(from, type) && !Mentions(to, type))
                {
                    diagnostics.Error("SL0615", conversion.Span,
                        $"this converts '{from.Name}' to '{to.Name}', and neither is " +
                        $"'{type.Name}'; a conversion belongs to one of the two types it is " +
                        "between, so that the two types are where a reader looks for it");
                    continue;
                }

                // An interface is reached by what an object *is*, and a
                // conversion makes something else. Both would mean a cast to an
                // interface sometimes asked the object and sometimes ran code.
                if (from is InterfaceTypeSymbol or ComInterfaceTypeSymbol ||
                    to is InterfaceTypeSymbol or ComInterfaceTypeSymbol)
                {
                    diagnostics.Error("SL0615", conversion.Span,
                        "a conversion may not be to or from an interface: a cast to one asks " +
                        "the object what it is, and a conversion would make a different " +
                        "object instead");
                    continue;
                }

                // And nothing may restate a conversion the language already
                // has -- a base class, an optional, an array to a slice, a
                // widening. A second answer to a question that is already
                // answered is one a reader would have to know about to predict
                // what a cast does.
                if (ClassifyConversion(
                        from, to, explicitCast: !conversion.IsImplicitConversion) is not null)
                {
                    diagnostics.Error("SL0615", conversion.Span,
                        $"'{from.Name}' already converts to '{to.Name}'" +
                        (conversion.IsImplicitConversion ? "" : " with a cast") +
                        "; a second answer to the same question is one the reader would have " +
                        "to know about to predict what a cast does");
                    continue;
                }

                if (kept.Any(c => c.ReturnType.Equals(to) && c.Parameters[0].Type.Equals(from)))
                {
                    diagnostics.Error("SL0211", conversion.Span,
                        $"'{type.Name}' already declares a conversion from '{from.Name}' " +
                        $"to '{to.Name}'");
                    continue;
                }

                kept.Add(conversion);
            }

            type.Conversions.Clear();
            type.Conversions.AddRange(kept);
        }
    }

    /// <summary>Whether an operand type is the declaring type, or a pointer to it.</summary>
    private static bool Mentions(TypeSymbol operand, NamedTypeSymbol type) =>
        ReferenceEquals(operand, type) ||
        (operand is PointerTypeSymbol pointer && ReferenceEquals(pointer.Element, type)) ||
        (operand is OptionalTypeSymbol optional && ReferenceEquals(optional.Element, type));

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
                    DeclaredSpan = parameter.Span,
                    DefaultSyntax = CheckedDefault(symbol, parameter),
                });
        }

        // A default that is not on the end could only be reached by a name, and
        // a reader counting arguments would have to know which of them were
        // filled in. Checked here rather than per call, because it is a fact
        // about the declaration.
        var written = symbol.Parameters.Where(p => !p.IsThis).ToList();

        for (int i = 1; i < written.Count; i++)
            if (!written[i].IsOptional && written[i - 1].IsOptional)
            {
                diagnostics.Error("SL0614", written[i].DeclaredSpan ?? symbol.Span,
                    $"'{written[i].Name}' has no default and '{written[i - 1].Name}' before it " +
                    "has one; the ones that may be left out go at the end, so that what a call " +
                    "leaves off is the tail of the list and not a hole in the middle");
                break;
            }
    }

    /// <summary>
    /// The default as written, or null where a default cannot mean anything.
    ///
    /// Each refusal is about the same thing: a default is a value the *caller*
    /// passes, filled in at the call site from the declaration it can see. So
    /// it needs a call site that has a declaration to read, and it needs to be
    /// a value.
    /// </summary>
    private ExpressionSyntax? CheckedDefault(FunctionSymbol symbol, ParameterSyntax parameter)
    {
        if (parameter.Default is null) return null;

        if (parameter.Mode != ParameterMode.Value)
        {
            diagnostics.Error("SL0613", parameter.Default.Span,
                $"'{parameter.Name}' is '{Spelled(parameter.Mode)}', which passes the caller's " +
                "storage rather than a value, and a default has no storage to be; make it an " +
                "ordinary parameter, or write an overload that supplies one");
            return null;
        }

        if (symbol.IsVariadic)
        {
            diagnostics.Error("SL0613", parameter.Default.Span,
                $"'{symbol.Name}' is variadic, so what a call leaves off is already open-ended; " +
                "a default here would make two rules for the same tail");
            return null;
        }

        return parameter.Default;
    }

    private static string Spelled(ParameterMode mode) => mode switch
    {
        ParameterMode.Ref => "ref",
        ParameterMode.In => "in",
        ParameterMode.Out => "out",
        _ => "",
    };

    /// <summary>
    /// Works out what every declared default is worth, and where one may be
    /// declared at all.
    ///
    /// A pass of its own, between the signatures and the bodies, because a
    /// default is an expression in a signature: <c>int width = Layout.Wide</c>
    /// names a constant that pass 4 had not folded yet, and no body may be
    /// bound until every signature is settled. Doing it here also means a
    /// default nothing ever leaves out is still checked.
    /// </summary>
    private void BindParameterDefaults()
    {
        // A method is in its module's function list and in its type's, so the
        // set is what stops one being reported against twice.
        var seen = new HashSet<FunctionSymbol>();

        void BindDefaultsOnce(FunctionSymbol function)
        {
            if (seen.Add(function)) BindDefaultsOf(function);
        }

        foreach (var module in _modules.Values.ToList())
        {
            foreach (var function in module.Functions.ToList())
                BindDefaultsOnce(function);

            foreach (var type in module.Types.Values.ToList())
            {
                foreach (var method in type.Methods.ToList()) BindDefaultsOnce(method);
                foreach (var declared in type.Operators.ToList()) BindDefaultsOnce(declared);

                foreach (var constructor in type.Constructors.ToList())
                    BindDefaultsOnce(constructor);

                if (type is ClassTypeSymbol classType) CheckImplementedDefaults(classType);
            }
        }
    }

    /// <summary>
    /// Settles one function's defaults, and refuses the one shape that would
    /// make the same written call mean two things.
    ///
    /// <b>An override may not restate a default.</b> A call fills one in from
    /// the declaration it can see, which is the one the static type gives it,
    /// so a restated default would be a value that depended on which reference
    /// the call was made through -- the reader's worst case, because both
    /// spellings are the same line. C# allows it, and it is a documented trap
    /// there.
    /// </summary>
    private void BindDefaultsOf(FunctionSymbol function)
    {
        foreach (var parameter in function.Parameters)
        {
            if (parameter.DefaultSyntax is not { } written) continue;

            if (function.IsOverride)
            {
                diagnostics.Error("SL0614", written.Span,
                    $"'{function.Name}' is an override, so it cannot give '{parameter.Name}' a " +
                    "default: a call fills one in from the declaration it can see, which is the " +
                    "one the static type gives it, and a second value here would mean the same " +
                    "line meant different things through a base reference and a derived one");
                parameter.Default = null;
                continue;
            }

            EnsureDefault(function, parameter);
        }
    }

    /// <summary>
    /// The same rule as an override's, across an interface: both declarations
    /// are visible, and a call through each would read a different value.
    /// </summary>
    private void CheckImplementedDefaults(ClassTypeSymbol classType)
    {
        foreach (var contract in classType.AllInterfaces())
            foreach (var required in contract.Methods)
            {
                if (!required.Parameters.Any(p => p.IsOptional)) continue;
                if (classType.FindImplementation(required) is not { } implementation) continue;

                foreach (var parameter in implementation.Parameters)
                {
                    if (parameter.DefaultSyntax is not { } written) continue;
                    if (!required.Parameters.Any(p => p.Name == parameter.Name && p.IsOptional))
                        continue;

                    diagnostics.Error("SL0614", written.Span,
                        $"'{contract.Name}.{required.Name}' already gives '{parameter.Name}' a " +
                        "default, and a call fills one in from the declaration it can see; two " +
                        "of them would mean a call through the interface and a call through " +
                        $"'{classType.Name}' passed different values. Leave this one off");
                    parameter.Default = null;
                }
            }
    }

    /// <summary>
    /// Binds a default if it has not been bound yet, and returns it.
    ///
    /// Lazy as well as eager because a generic's parameters are built when it
    /// is instantiated, which happens while bodies are being bound -- after the
    /// pass above has run. There the first call site to leave the parameter out
    /// is what settles it, and the result is cached, so the expression is bound
    /// once however many calls omit it.
    /// </summary>
    private BoundExpression? EnsureDefault(FunctionSymbol function, ParameterSymbol parameter)
    {
        if (parameter.Default is not null) return parameter.Default;
        if (parameter.DefaultSyntax is not { } written) return null;

        // Bound where it was written, against that file's imports, and with no
        // function around it: a default is a constant, so there is nothing for
        // a local, a parameter or a `this` to be.
        var savedScope = _currentScope;
        var savedFunction = _currentFunction;
        var savedPatterns = _patterns;

        if (function.Scope is not null) _currentScope = function.Scope;
        _currentFunction = null;
        _patterns = null;

        PushScope();
        var bound = BindConversion(BindExpression(written), parameter.Type, written.Span);
        PopScope();

        _currentScope = savedScope;
        _currentFunction = savedFunction;
        _patterns = savedPatterns;

        if (bound.Type.IsError()) return null;

        if (!IsConstantDefault(bound))
        {
            diagnostics.Error("SL0613", written.Span,
                $"the default for '{parameter.Name}' is not a constant, and a default is " +
                "written into every call that leaves it out -- so a call would be running this " +
                "rather than passing it. A literal, 'null', a 'const', an enum member or " +
                "'default(T)' is what it may be; anything else belongs in the body");
            return null;
        }

        parameter.Default = bound;
        return bound;
    }

    /// <summary>
    /// Whether an expression is the same value every time it is written out.
    ///
    /// The test is on the bound tree rather than on the syntax, so a conversion
    /// the compiler inserted on the way -- an <c>int</c> literal becoming a
    /// <c>long</c>, an enum member reaching its own type -- does not make a
    /// constant stop being one.
    /// </summary>
    private static bool IsConstantDefault(BoundExpression expression) => expression switch
    {
        BoundLiteral or BoundStringLiteral or BoundNullLiteral or BoundDefault => true,
        BoundConstantAccess => true,
        BoundConversion conversion => IsConstantDefault(conversion.Operand),
        BoundUnary { Operator: BoundUnaryOp.Negate } negated => IsConstantDefault(negated.Operand),
        _ => false,
    };

    /// <summary>
    /// <c>const int Limit = 64;</c>, at module scope or inside a type.
    ///
    /// The two differ only in where the symbol is filed. A constant is inlined
    /// at every use and has no storage, so unlike a <c>static</c> it needs no
    /// moment at which to be initialized -- which is what lets a type in a
    /// <c>--shared</c> library carry one (SL0380 refuses the static).
    /// </summary>
    private void DeclareGlobalConstant(
        FileScope scope, GlobalConstDeclSyntax declaration,
        NamedTypeSymbol? containingType = null)
    {
        var module = scope.Module;

        if (containingType is null && module.Constants.ContainsKey(declaration.Name))
        {
            diagnostics.Error("SL0201", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        if (containingType is not null &&
            (containingType.Constants.Any(c => c.Name == declaration.Name) ||
             containingType.FindStatic(declaration.Name) is not null ||
             containingType.FindStorage(declaration.Name) is not null ||
             containingType.FindProperty(declaration.Name) is not null))
        {
            diagnostics.Error("SL0205", declaration.Span,
                $"'{containingType.Name}' already declares a member named '{declaration.Name}'");
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
                    TokenKind.FloatLiteral => literal.Value is float
                        ? PrimitiveTypeSymbol.Float
                        : PrimitiveTypeSymbol.Double,
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
                "a 'const' must be initialized with a literal");
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

        var symbol = new ConstantSymbol(declaration.Name, type, value)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
        };

        if (containingType is not null) containingType.Constants.Add(symbol);
        else module.Constants[declaration.Name] = symbol;
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
        float number => -number,
        _ => null,
    };
}
