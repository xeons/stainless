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
/// Pass 4, first half: the members of a type.
///
/// Enum members, variant cases, fields, properties and their accessors.
/// A signature is resolved here and a body is not: pass 7 needs every
/// member of every type to already exist.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 4

    private void DeclareMembers()
    {
        // Delegate and closure signatures before anything else in this pass.
        //
        // An event's raise method takes the parameters of the closure it is
        // declared with, and it copies them when the event is declared -- so a
        // class declared above the closure its event names would have copied an
        // empty list. Nothing here needs a member of anything: a signature
        // names types, and pass 2 already made every type name exist.
        foreach (var (scope, unit) in _units)
        {
            _currentScope = scope;

            foreach (var declared in unit.Declarations.OfType<DelegateDeclSyntax>())
                if (_declaredTypes.TryGetValue(declared, out var type))
                    DeclareDelegateSignature(type, declared, scope);
        }

        foreach (var (scope, unit) in _units)
        {
            _currentScope = scope;
            var module = scope.Module;

            foreach (var declaration in unit.Declarations)
            {
                switch (declaration)
                {
                    case FunctionDeclSyntax function:
                        if (function.TypeParameters.Count > 0)
                        {
                            // Here and not per instantiation, which would say
                            // it once for every type argument, or never.
                            if (function.Modifiers.HasFlag(Modifiers.Static))
                                CheckStatic(containingType: null, function);

                            module.GenericFunctions.Add(
                                new GenericFunctionTemplate(function.Name, scope, function));
                        }
                        else
                        {
                            DeclareFunction(scope, containingType: null, function);
                        }
                        break;

                    // Templates wait, since their members depend on type
                    // arguments, and a declaration that lost its name to
                    // another has no type to give members to: SL0201 or SL0550
                    // has said so, and a second complaint in the shape of a
                    // crash helps nobody. Neither is in the map.
                    case TypeDeclSyntax typeDecl:
                        if (_declaredTypes.TryGetValue(typeDecl, out var declared))
                            DeclareTypeMembers(scope, typeDecl, declared);
                        break;

                    case StaticDeclSyntax staticDecl:
                        DeclareStatic(scope, staticDecl);
                        break;

                    // A delegate's signature was resolved above, before any
                    // type's members. A generic one has no type here to give a
                    // signature to at all: each instantiation resolves its own,
                    // under the substitution that gives its parameters meaning.
                    case DelegateDeclSyntax:
                        break;

                    case EnumDeclSyntax enumDecl:
                        if (_declaredTypes.TryGetValue(enumDecl, out var enumType))
                            DeclareEnumMembers((EnumTypeSymbol)enumType, enumDecl, scope);
                        break;

                    case GlobalConstDeclSyntax constant:
                        DeclareGlobalConstant(scope, constant);
                        break;

                    // Storage that crosses to C is the one module-level
                    // variable there is a reason for: it is not this program's
                    // storage to keep in a type, it is a name the C library
                    // already owns. Everything else at module scope is refused.
                    case FieldDeclSyntax field when field.Linkage.IsForeign():
                        DeclareForeignVariable(scope, field);
                        break;

                    case FieldDeclSyntax field:
                        diagnostics.Error("SL0204", field.Span,
                            $"'{field.Name}' is a module-level variable; only 'const' values are " +
                            "allowed at module scope");
                        break;

                    case PropertyDeclSyntax property:
                        diagnostics.Error("SL0400", property.Span,
                            $"'{property.Name}' is a property, and a property belongs to a type; " +
                            "a module has no instance for its accessors to read");
                        break;
                }
            }
        }

        _currentScope = null;

        // Every type declared in source now has its members, so an instantiation
        // made during this pass can finally be laid out. Until this moment it
        // could not: laying `Result<Color, E>` out reaches `Color`, and a
        // `Color` this pass had not got to yet has no fields, so it settles at
        // one byte -- and `LayoutComputed` means nothing ever looks again. The
        // same trap the generic-to-generic case documents, reached through an
        // ordinary struct instead of a second template.
        _membersDeclared = true;
        SettleDeferredLayouts();
    }

    /// <summary>
    /// A <c>closure</c> type: two fields, and the signature its call goes
    /// through.
    ///
    /// The fields are given here rather than anywhere later because layout,
    /// the ABI classifiers and the reference walk that retains and releases a
    /// value's contents are all written against a struct's fields. Two fields
    /// is the whole of what makes a closure work with machinery none of which
    /// has heard of one.
    /// </summary>
    private ClosureTypeSymbol NewClosureType(
        DelegateDeclSyntax declaration, ModuleSymbol module,
        string? displayName = null, IReadOnlyList<TypeSymbol>? typeArguments = null) =>
        NewClosureType(
            displayName ?? declaration.Name, module.Name, declaration.Span,
            declaration.Modifiers.HasFlag(Modifiers.Public), typeArguments ?? []);

    /// <summary>
    /// The same two fields, for a closure type nobody declared: the one a
    /// lambda gets when it is not being assigned to anything that would say
    /// what it should be.
    /// </summary>
    private ClosureTypeSymbol NewClosureType(
        string simpleName, string moduleName, Source.SourceSpan span,
        bool isPublic, IReadOnlyList<TypeSymbol> typeArguments)
    {
        var type = new ClosureTypeSymbol
        {
            SimpleName = simpleName,
            ModuleName = moduleName,
            IsPublic = isPublic,
            TypeArguments = typeArguments,
            Span = span,
        };

        type.AddFields(_builtins.Bound);

        return type;
    }

    /// <summary>
    /// Resolves a delegate's or closure's return and parameter types. The names
    /// are kept for diagnostics and for the generated C header; nothing else
    /// reads them.
    /// </summary>
    private void DeclareDelegateSignature(
        NamedTypeSymbol type, DelegateDeclSyntax declaration, FileScope scope)
    {
        var returnType = ResolveType(declaration.ReturnType, scope, allowVoid: true);
        string kind = type is ClosureTypeSymbol ? "closure" : "delegate";

        var signature = new List<ParameterSymbol>();

        for (int i = 0; i < declaration.Parameters.Count; i++)
        {
            var parameter = declaration.Parameters[i];
            var parameterType = ResolveType(parameter.Type, scope);

            if (parameterType.IsVoid())
            {
                diagnostics.Error("SL0359", parameter.Span,
                    $"parameter '{parameter.Name}' of {kind} '{type.Name}' cannot be 'void'");
                parameterType = ErrorTypeSymbol.Instance;
            }

            signature.Add(new ParameterSymbol(parameter.Name, parameterType, i)
            {
                Mode = parameter.Mode,
            });
        }

        if (type is ClosureTypeSymbol closure)
        {
            closure.ReturnType = returnType;
            closure.Signature.AddRange(signature);
            return;
        }

        var asDelegate = (DelegateTypeSymbol)type;
        asDelegate.ReturnType = returnType;
        asDelegate.Signature.AddRange(signature);
        asDelegate.Convention = declaration.Convention;
    }

    /// <summary>
    /// Resolves an enum's underlying type and folds its members to constants.
    ///
    /// A member without a value continues from the previous one, starting at
    /// zero, as in C and C#. The values are checked against the underlying type
    /// here so that a too-large constant is reported at the enum, not at a use.
    /// </summary>
    private void DeclareEnumMembers(EnumTypeSymbol type, EnumDeclSyntax declaration, FileScope scope)
    {
        if (declaration.UnderlyingType is not null)
        {
            var underlying = ResolveType(declaration.UnderlyingType, scope);
            if (underlying is PrimitiveTypeSymbol { IsInteger: true } integer)
            {
                type.UnderlyingType = integer;
            }
            else if (!underlying.IsError())
            {
                diagnostics.Error("SL0350", declaration.UnderlyingType.Span,
                    $"an enum must be built on an integer type, but '{underlying.Name}' is not one");
            }
        }

        ulong next = 0;

        foreach (var member in declaration.Members)
        {
            if (type.FindMember(member.Name) is not null)
            {
                diagnostics.Error("SL0351", member.Span,
                    $"'{type.Name}' already has a member named '{member.Name}'");
                continue;
            }

            ulong value = next;

            if (member.Value is not null)
            {
                if (FoldEnumValue(member.Value, type.UnderlyingType) is { } folded)
                    value = folded;
                else
                    diagnostics.Error("SL0352", member.Value.Span,
                        $"the value of '{type.Name}.{member.Name}' must be an integer constant");
            }

            type.Members.Add(new EnumMemberSymbol(member.Name, type, value)
            {
                Documentation = member.Documentation,
            });
            next = value + 1;
        }
    }

    /// <summary>An enum member's constant: an integer literal, optionally negated.</summary>
    private ulong? FoldEnumValue(ExpressionSyntax syntax, PrimitiveTypeSymbol underlying)
    {
        bool negate = false;

        while (syntax is UnarySyntax { Operator: TokenKind.Minus or TokenKind.Plus } unary)
        {
            if (unary.Operator == TokenKind.Minus) negate = !negate;
            syntax = unary.Operand;
        }

        if (syntax is not LiteralSyntax { Kind: TokenKind.IntLiteral, Value: ulong raw }) return null;

        ulong value = negate ? unchecked((ulong)-(long)raw) : raw;

        // Keep only the bits the underlying type actually has.
        return underlying.Size >= 8 ? value : value & ((1UL << underlying.Bits) - 1);
    }

    /// <summary>
    /// Turns a variant's cases into symbols, and gives the variant the two
    /// fields that represent it.
    ///
    /// Each case's parameters become a struct of their own. That struct is an
    /// ordinary one — laid out, copied, retained and described by the machinery
    /// that already exists — and the case is a name for it plus a tag. The
    /// variant itself then has two fields: the tag, and a filler wide enough for
    /// the largest payload, whose size is not known until every case has been
    /// laid out and so is settled in pass 7.
    /// </summary>
    private void DeclareVariantCases(
        FileScope scope, TypeDeclSyntax declaration, VariantTypeSymbol variant)
    {
        if (declaration.Cases.Count > 255)
            diagnostics.Error("SL0432", declaration.Span,
                $"variant '{variant.Name}' has {declaration.Cases.Count} cases; the tag is a " +
                "byte, so 255 is the limit");

        foreach (var declared in declaration.Cases)
        {
            if (variant.FindCase(declared.Name) is not null)
            {
                diagnostics.Error("SL0433", declared.Span,
                    $"variant '{variant.Name}' already has a case named '{declared.Name}'");
                continue;
            }

            var caseSymbol = new VariantCaseSymbol
            {
                Name = declared.Name,
                DeclaringVariant = variant,
                Tag = variant.Cases.Count,
                Span = declared.Span,
            };

            if (declared.Parameters.Count > 0)
            {
                var payload = new StructTypeSymbol
                {
                    // '$' is in no identifier, so this names a type the source
                    // cannot reach. It is reached through the case instead.
                    SimpleName = variant.SimpleName + "$" + declared.Name,
                    ModuleName = variant.ModuleName,
                    IsPublic = variant.IsPublic,
                    Span = declared.Span,
                };

                foreach (var parameter in declared.Parameters)
                {
                    if (payload.FindStorage(parameter.Name) is not null)
                    {
                        diagnostics.Error("SL0434", parameter.Span,
                            $"case '{declared.Name}' already carries a field named " +
                            $"'{parameter.Name}'");
                        continue;
                    }

                    payload.Fields.Add(new FieldSymbol(
                        parameter.Name, ResolveType(parameter.Type, scope),
                        payload, payload.Fields.Count) { IsPublic = true });
                }

                _structs.Add(payload);
                caseSymbol.Payload = payload;
            }

            variant.Cases.Add(caseSymbol);
        }

        // The tag first, so a variant with no payload at all is one byte and
        // reads like an enum. Both fields are hidden storage: the case is the
        // name for what is in there, and reaching past it would be reading a
        // payload without the proof that makes it mean anything.
        variant.Fields.Add(new FieldSymbol(
            VariantTypeSymbol.TagFieldName, PrimitiveTypeSymbol.Byte, variant, 0)
        {
            IsBackingField = true,
        });

        if (!variant.Cases.Any(c => c.Payload is not null)) return;

        var storage = new StructTypeSymbol
        {
            SimpleName = variant.SimpleName + "$payload",
            ModuleName = variant.ModuleName,
            IsPublic = variant.IsPublic,
            Span = declaration.Span,
        };

        _structs.Add(storage);
        variant.PayloadStorage = storage;

        variant.Fields.Add(new FieldSymbol(
            VariantTypeSymbol.PayloadFieldName, storage, variant, 1)
        {
            IsBackingField = true,
        });
    }

    /// <summary>
    /// The width of a bit-field, checked against what may be one.
    ///
    /// A bit-field is storage measured in bits rather than bytes, so what may
    /// have one is what the target's C compiler will give one: an integer or a
    /// bool. The width has to be a constant, because the layout of everything
    /// after it depends on the number.
    /// </summary>
    private int? BindBitWidth(
        FieldDeclSyntax field, TypeSymbol fieldType, NamedTypeSymbol owner, FileScope scope)
    {
        if (owner is not StructTypeSymbol || owner is VariantTypeSymbol)
        {
            diagnostics.Error("SL0469", field.Span,
                $"'{owner.Name}.{field.Name}' is a bit-field, and only a struct or a union has " +
                "those; a class lays its fields out behind a header the compiler owns");
            return null;
        }

        bool usable = fieldType is PrimitiveTypeSymbol { IsInteger: true } or
                                   PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool };

        if (!usable)
        {
            diagnostics.Error("SL0471", field.Span,
                $"'{fieldType.Name}' cannot be a bit-field; a bit-field is some of the bits of " +
                "an integer or a bool");
            return null;
        }

        if (ConstantValue(field.BitWidth!, PrimitiveTypeSymbol.Int) is not { } value)
        {
            diagnostics.Error("SL0472", field.BitWidth!.Span,
                "a bit-field's width must be a constant; the layout of everything after it " +
                "depends on the number");
            return null;
        }

        long width = Convert.ToInt64(value, System.Globalization.CultureInfo.InvariantCulture);
        int capacity = fieldType.Size * 8;

        if (width <= 0)
        {
            diagnostics.Error("SL0473", field.BitWidth!.Span,
                $"a bit-field is at least one bit wide, and '{field.Name}' asks for {width}. " +
                "C's zero-width field, which closes a storage unit, is not written yet");
            return null;
        }

        if (width > capacity)
        {
            diagnostics.Error("SL0474", field.BitWidth!.Span,
                $"'{field.Name}' asks for {width} bits, and '{fieldType.Name}' has {capacity}");
            return null;
        }

        return (int)width;
    }

    private void DeclareTypeMembers(
        FileScope scope, TypeDeclSyntax declaration, NamedTypeSymbol type)
    {
        var module = scope.Module;
        var classType = type as ClassTypeSymbol;

        var enclosing = _declaringType;

        // The template's name where there is one: a type nested in `Cache<T>`
        // was hoisted as `Cache.Entry`, before any instantiation of it.
        _declaringType = type.Template?.Name ?? type.SimpleName;

        try
        {
            DeclareMembersOf(scope, declaration, type, module, classType);
        }
        finally
        {
            _declaringType = enclosing;
        }
    }

    private void DeclareMembersOf(
        FileScope scope, TypeDeclSyntax declaration, NamedTypeSymbol type,
        ModuleSymbol module, ClassTypeSymbol? classType)
    {
        if (type is VariantTypeSymbol variant) DeclareVariantCases(scope, declaration, variant);

        bool staticOnly = type is ClassTypeSymbol { IsStaticClass: true };

        foreach (var member in declaration.Members)
        {
            // A static class has no instances, so every member that would be
            // reached through one is a member that could never be reached.
            if (staticOnly && InstanceMember(member) is { } instanceMember)
            {
                diagnostics.Error("SL0583", member.Span,
                    $"'{type.Name}' is a static class, so it has no instance for " +
                    $"{instanceMember} to belong to. Make it 'static', or make the class " +
                    "an ordinary one");
                continue;
            }

            if (type is AttributeTypeSymbol && member is not FieldDeclSyntax)
            {
                diagnostics.Error("SL0340", member.Span,
                    $"attribute '{type.Name}' may only declare fields; " +
                    "it is compile-time data, not a type with behaviour");
                continue;
            }

            if (type.IsContract && member is not (FunctionDeclSyntax or PropertyDeclSyntax))
            {
                diagnostics.Error("SL0300", member.Span,
                    $"interface '{type.Name}' may only declare methods and properties; " +
                    "it has no state, no constructor and no destructor");
                continue;
            }

            switch (member)
            {
                case FieldDeclSyntax field:
                {
                    // A later declaration may add behaviour and not state: the
                    // layout was settled by the first one, and for an intrinsic
                    // it was settled by the runtime.
                    if (_additionalParts.Contains(declaration))
                    {
                        diagnostics.Error("SL0552", field.Span,
                            $"'{type.Name}' is already declared in this module, so this " +
                            $"declaration may add methods but not the field '{field.Name}'; " +
                            "the layout belongs to the declaration that has the fields");
                        break;
                    }

                    if (type.FindStorage(field.Name) is not null ||
                        type.FindProperty(field.Name) is not null)
                    {
                        diagnostics.Error("SL0205", field.Span,
                            $"'{type.Name}' already declares a member named '{field.Name}'");
                        break;
                    }
                    var fieldType = ResolveType(field.Type, scope);

                    // A struct holding a reference is allowed, and copying one
                    // then retains what it holds. What it costs is the C
                    // guarantee: such a struct is no longer bytes a C function
                    // could be handed, which ValidateLinkageSignature enforces.

                    if (Dispatchable(field.Modifiers) is { } wrongOnAField)
                        diagnostics.Error("SL0497", field.Span,
                            $"'{type.Name}.{field.Name}' is a field, so it cannot be " +
                            $"'{wrongOnAField}'; only a method or a property is dispatched");

                    if (field.Modifiers.HasFlag(Modifiers.Protected) &&
                        type is not ClassTypeSymbol)
                        diagnostics.Error("SL0519", field.Span,
                            $"'{type.Name}.{field.Name}' cannot be 'protected'; the word means " +
                            "'and anything deriving from this', and only a class is derived from");

                    var declared = new FieldSymbol(field.Name, fieldType, type, type.Fields.Count)
                    {
                        IsPublic = field.Modifiers.HasFlag(Modifiers.Public),
                        IsProtected = field.Modifiers.HasFlag(Modifiers.Protected),
                        IsAnonymous = field.IsAnonymous,
                        Documentation = field.Documentation,
                        InitializerSyntax = CheckedFieldInitializer(type, field),
                        InitializerScope = scope,
                    };

                    if (field.BitWidth is not null)
                        declared.BitWidth = BindBitWidth(field, fieldType, type, scope);

                    type.Fields.Add(declared);
                    break;
                }

                case FunctionDeclSyntax method:
                    if (method.TypeParameters.Count > 0)
                    {
                        if (type.IsContract)
                        {
                            // A vtable has one slot per method, and a generic
                            // method has as many bodies as it has instantiations.
                            diagnostics.Error("SL0322", method.Span,
                                $"'{method.Name}' is generic, and an interface method cannot be; " +
                                "dispatch needs one entry per method, and a generic one has " +
                                "a body per instantiation");
                            break;
                        }

                        // The substitution in force is the enclosing type's, if it
                        // is itself an instantiation; the method's own parameters
                        // are merged onto it at each call.
                        type.GenericMethods.Add(new GenericFunctionTemplate(method.Name, scope, method)
                        {
                            ContainingType = type,
                            OuterSubstitution = new Dictionary<string, TypeSymbol>(
                                _substitution, StringComparer.Ordinal),
                        });
                        break;
                    }
                    DeclareFunction(scope, type, method);
                    break;

                case PropertyDeclSyntax property:
                    DeclareProperty(scope, type, property);
                    break;

                case EventDeclSyntax declared:
                    DeclareEvent(scope, type, declared);
                    break;

                // Only pass 2 declares aliases, and it looks at the top level.
                // Taking one here and dropping it is the shape of bug this
                // language keeps finding in itself, so it is refused instead.
                case AliasDeclSyntax alias:
                    diagnostics.Error("SL0525", alias.Span,
                        $"'{alias.Name}' is a type alias inside '{type.Name}'; an alias belongs " +
                        "to a module, which is what this language has instead of a namespace. " +
                        "Move it out of the type");
                    break;

                case ConstructorDeclSyntax constructor:
                {
                    if (classType is null)
                    {
                        diagnostics.Error("SL0207", constructor.Span,
                            $"'{type.Name}' is a struct; structs are plain C values and have no constructors");
                        break;
                    }
                    var symbol = new FunctionSymbol
                    {
                        Name = "ctor",
                        ModuleName = module.Name,
                        ReturnType = PrimitiveTypeSymbol.Void,
                        Linkage = LinkageKind.Stainless,
                        Kind = FunctionKind.Constructor,
                        ContainingType = type,
                        Body = constructor.Body,
                        Span = constructor.Span,
                        Scope = scope,
                        IsPublic = constructor.Modifiers.HasFlag(Modifiers.Public),
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    AddParameters(symbol, constructor.Parameters, scope);
                    classType.Constructors.Add(symbol);
                    break;
                }

                case StaticDeclSyntax shared:
                    DeclareStatic(scope, shared, type);
                    break;

                case GlobalConstDeclSyntax constant:
                    DeclareGlobalConstant(scope, constant, type);
                    break;

                case StaticConstructorDeclSyntax initializer:
                    DeclareStaticConstructor(scope, type, initializer);
                    break;

                case DestructorDeclSyntax destructor:
                {
                    if (classType is null)
                    {
                        diagnostics.Error("SL0208", destructor.Span,
                            $"'{type.Name}' is a struct; only classes are reference counted and can have a destructor");
                        break;
                    }
                    if (classType.Destructor is not null)
                    {
                        diagnostics.Error("SL0209", destructor.Span,
                            $"'{type.Name}' already declares a destructor");
                        break;
                    }
                    var symbol = new FunctionSymbol
                    {
                        Name = "dtor",
                        ModuleName = module.Name,
                        ReturnType = PrimitiveTypeSymbol.Void,
                        Linkage = LinkageKind.Stainless,
                        Kind = FunctionKind.Destructor,
                        ContainingType = type,
                        Body = destructor.Body,
                        Span = destructor.Span,
                        Scope = scope,
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    classType.Destructor = symbol;
                    break;
                }
            }
        }

        CheckOperatorPairs(type);
    }

    /// <summary>
    /// Gives a class with field initializers and no constructor one to run them
    /// in.
    ///
    /// A field initializer is a statement at the head of a constructor, so a
    /// class that declares none has nowhere to put it. The one made here takes
    /// no arguments and has an empty body, which is exactly what
    /// <c>new Thing()</c> already meant for such a class -- the difference is
    /// that there is now something for the initializers to be the head of, and
    /// for the base chain to be inserted into.
    /// </summary>
    private void SynthesizeInitializerConstructors()
    {
        foreach (var type in _modules.Values
                     .SelectMany(m => m.Types.Values)
                     .OfType<ClassTypeSymbol>()
                     .ToList())
        {
            if (type.Constructors.Count > 0) continue;
            if (type.Fields.FirstOrDefault(f => f.InitializerSyntax is not null) is not { } first)
                continue;

            // The first initializer is where this constructor came from, and
            // where a diagnostic about it should point.
            var where = first.InitializerSyntax!.Span;

            var symbol = new FunctionSymbol
            {
                Name = "ctor",
                ModuleName = type.ModuleName,
                ReturnType = PrimitiveTypeSymbol.Void,
                Linkage = LinkageKind.Stainless,
                Kind = FunctionKind.Constructor,
                ContainingType = type,
                Body = new BlockSyntax(where, []),
                Span = where,
                Scope = first.InitializerScope,
                IsPublic = true,
            };

            symbol.Parameters.Add(new ParameterSymbol("this", type, 0) { IsThis = true });
            type.Constructors.Add(symbol);
        }
    }

    /// <summary>
    /// A field's <c>= value</c>, or null where one cannot mean anything.
    ///
    /// A field initializer is a statement at the head of every constructor, so
    /// what it needs is a constructor to be at the head of. A class has one --
    /// written, or made for it when it declares none. A value type does not:
    /// <c>Point p;</c> makes one by declaring it, and there is no moment there
    /// for an initializer to run at.
    /// </summary>
    private ExpressionSyntax? CheckedFieldInitializer(NamedTypeSymbol type, FieldDeclSyntax field)
    {
        if (field.Initializer is null) return null;

        if (type is not ClassTypeSymbol)
        {
            diagnostics.Error("SL0617", field.Initializer.Span,
                $"'{type.Name}' is not a class, so there is no moment at which this would " +
                $"run: '{type.Name} value;' makes one by declaring it rather than by " +
                "constructing it, and a field initializer runs in a constructor. Give the " +
                "field its value where the value is made");
            return null;
        }

        if (field.IsAnonymous)
        {
            diagnostics.Error("SL0617", field.Initializer.Span,
                "a nameless member has no name to assign to; give its fields their values " +
                "one at a time");
            return null;
        }

        if (field.BitWidth is not null)
        {
            diagnostics.Error("SL0617", field.Initializer.Span,
                $"'{field.Name}' is a bit-field, and bit-fields are laid out in a struct, " +
                "which has no constructor to run this in");
            return null;
        }

        return field.Initializer;
    }

    /// <summary>
    /// An automatic property's <c>= value</c>, which is its storage's: the two
    /// are the same field, so the same rule decides both.
    /// </summary>
    private ExpressionSyntax? CheckedPropertyInitializer(
        NamedTypeSymbol type, PropertyDeclSyntax declaration)
    {
        if (declaration.Initializer is null) return null;

        if (type is not ClassTypeSymbol)
        {
            diagnostics.Error("SL0617", declaration.Initializer.Span,
                $"'{type.Name}' is not a class, so there is no moment at which this would " +
                "run: a property's first value is given in a constructor, and a value type " +
                "has none");
            return null;
        }

        return declaration.Initializer;
    }

    /// <summary>
    /// An operator that comes in a pair has to be declared with its opposite.
    ///
    /// Checked here rather than at the declaration because the other half may
    /// be written below it. A type that can be asked <c>==</c> and not
    /// <c>!=</c>, or <c>&lt;</c> and not <c>&gt;</c>, is a trap: the reader
    /// has no way to know which questions it answers, and the missing one
    /// fails at a call site far from the declaration that forgot it. C#
    /// arrived at the same rule for the same reason.
    /// </summary>
    /// <summary>
    /// Declares an event: hidden storage, and the two methods that reach it.
    ///
    /// The shape is an automatic property's, and so is most of the code. What
    /// differs is what the methods are *for*: a property's accessors are its
    /// meaning, where an event's exist so that nothing else can touch the list.
    /// </summary>
    private void DeclareEvent(FileScope scope, NamedTypeSymbol type, EventDeclSyntax declaration)
    {
        var declared = ResolveType(declaration.Type, scope);

        // A closure and not a delegate, because a subscriber is nearly always a
        // method on some object -- `button.OnClick` -- and a delegate has
        // nowhere to keep the object. A plain function still subscribes, by way
        // of a lambda, which is the same answer the rest of the language gives.
        if (declared is not ClosureTypeSymbol closure)
        {
            if (!declared.IsError())
                diagnostics.Error("SL0548", declaration.Span,
                    $"'{type.Name}.{declaration.Name}' is an event of type " +
                    $"'{declared.Name}', and an event is a list of closures: its type has to be " +
                    "a 'closure', which is a method and the object it belongs to. A 'delegate' " +
                    "is one pointer and has no object, so a subscriber could not be " +
                    "'listener.OnChanged'");
            return;
        }

        // Raising calls every subscriber, so there is no one value to hand back.
        // C# keeps the last one's and discards the rest, which is a wart rather
        // than a feature.
        if (!closure.ReturnType.IsVoid())
        {
            diagnostics.Error("SL0549", declaration.Span,
                $"'{type.Name}.{declaration.Name}' is an event whose handlers return " +
                $"'{closure.ReturnType.Name}', and raising one calls every subscriber -- so " +
                "there is no single value for it to return. Declare the closure 'void', and " +
                "let a handler report through an argument it is given");
            return;
        }

        if (declaration.Modifiers.HasFlag(Modifiers.Static))
        {
            diagnostics.Error("SL0550", declaration.Span,
                $"'{type.Name}.{declaration.Name}' is a static event, which is not supported: " +
                "its subscribers would outlive every object that added one, and nothing would " +
                "ever take them off");
            return;
        }

        // An event on an interface needs no case of its own: an event is storage
        // as well as a pair of methods, and SL0300 already refuses every member
        // of a type that has no state.

        // Named after the event, and hidden from lookup exactly as a property's
        // storage is, so nothing can reach past the two methods.
        var backing = new FieldSymbol(declaration.Name, ArrayOf(closure), type, type.Fields.Count)
        {
            IsBackingField = true,
        };

        type.Fields.Add(backing);

        var symbol = new EventSymbol
        {
            Name = declaration.Name,
            Type = closure,
            ContainingType = type,
            Span = declaration.Span,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            BackingField = backing,
        };

        symbol.Add = DeclareEventAccessor(scope, type, symbol, adding: true);
        symbol.Remove = DeclareEventAccessor(scope, type, symbol, adding: false);
        symbol.Raise = DeclareEventRaiser(scope, type, symbol);
        symbol.AddWeak = DeclareEventWeakAdd(scope, type, symbol);
        symbol.WeakCall = DeclareEventWeakCall(scope, type, symbol);

        type.Events.Add(symbol);
        _eventNames.Add(symbol.Name);
    }

    /// <summary>
    /// One of an event's two methods: <c>add_Name</c> or <c>remove_Name</c>,
    /// each taking one subscriber and returning nothing.
    ///
    /// They are ordinary methods with ordinary mangled names, the way a
    /// property's accessors are, so an event crosses a library boundary as two
    /// symbols and a field rather than as anything new.
    /// </summary>
    private FunctionSymbol? DeclareEventAccessor(
        FileScope scope, NamedTypeSymbol type, EventSymbol symbol, bool adding)
    {
        string name = (adding ? "add_" : "remove_") + symbol.Name;

        if (type.Methods.Any(m => m.Name == name && m.Accepts([symbol.Type])))
        {
            diagnostics.Error("SL0552", symbol.Span,
                $"'{type.Name}' already declares a method named '{name}' taking one " +
                $"'{symbol.Type.Name}', which is what the event '{symbol.Name}' has to use");
            return null;
        }

        var accessor = new FunctionSymbol
        {
            Name = name,
            ModuleName = type.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            ContainingType = type,
            Span = symbol.Span,
            IsPublic = symbol.IsPublic,
            IsProtected = symbol.IsProtected,
            IsEventAdd = adding,
        };

        accessor.Event = symbol;
        accessor.Parameters.Add(new ParameterSymbol("this", type, 0) { IsThis = true });
        accessor.Parameters.Add(new ParameterSymbol("handler", symbol.Type, 1));

        type.Methods.Add(accessor);
        scope.Module.Functions.Add(accessor);
        return accessor;
    }

    /// <summary>
    /// <c>addweak_Name</c>: <c>add_Name</c> for a subscriber that is the object
    /// subscribing, held weakly. Public on the same terms as <c>add_</c>, so
    /// it crosses a library boundary as one more ordinary method.
    ///
    /// The prefix cannot collide with <c>add_</c> of any event: <c>add_</c>
    /// followed by a name never begins <c>addw</c>.
    /// </summary>
    private FunctionSymbol? DeclareEventWeakAdd(
        FileScope scope, NamedTypeSymbol type, EventSymbol symbol)
    {
        string name = "addweak_" + symbol.Name;
        if (type.Methods.Any(m => m.Name == name)) return null;

        var accessor = new FunctionSymbol
        {
            Name = name,
            ModuleName = type.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            ContainingType = type,
            Span = symbol.Span,
            IsPublic = symbol.IsPublic,
            IsProtected = symbol.IsProtected,
            IsEventAdd = true,
        };

        accessor.Event = symbol;
        accessor.Parameters.Add(new ParameterSymbol("this", type, 0) { IsThis = true });
        accessor.Parameters.Add(new ParameterSymbol("handler", symbol.Type, 1));

        type.Methods.Add(accessor);
        scope.Module.Functions.Add(accessor);
        return accessor;
    }

    /// <summary>
    /// <c>weakcall_Name</c>: the thunk a weak subscription calls through. It
    /// takes the runtime's cell where a method takes its receiver, then the
    /// event's own parameters, so a closure holding it calls it exactly as it
    /// would call the subscriber's method.
    /// </summary>
    private FunctionSymbol? DeclareEventWeakCall(
        FileScope scope, NamedTypeSymbol type, EventSymbol symbol)
    {
        string name = "weakcall_" + symbol.Name;
        if (type.Methods.Any(m => m.Name == name)) return null;

        var thunk = new FunctionSymbol
        {
            Name = name,
            ModuleName = type.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            ContainingType = type,
            Span = symbol.Span,
            IsPublic = false,
            IsStatic = true,
        };

        thunk.Event = symbol;
        thunk.Parameters.Add(new ParameterSymbol(
            "cell", new PointerTypeSymbol(PrimitiveTypeSymbol.Byte), 0));

        int index = 1;
        foreach (var parameter in symbol.Type.Signature)
            thunk.Parameters.Add(new ParameterSymbol(parameter.Name, parameter.Type, index++)
            {
                Mode = parameter.Mode,
            });

        type.Methods.Add(thunk);
        scope.Module.Functions.Add(thunk);
        return thunk;
    }

    /// <summary>
    /// The method a raise lowers to: the event's own parameters, and a loop
    /// over its subscribers.
    ///
    /// Never public, whatever the event is. Who may *raise* an event and who
    /// may subscribe to one are different questions, and the answer to the
    /// first is only ever the type that declared it -- a publisher whose
    /// callers could raise its events on its behalf is not publishing anything.
    /// </summary>
    private FunctionSymbol? DeclareEventRaiser(
        FileScope scope, NamedTypeSymbol type, EventSymbol symbol)
    {
        string name = "raise_" + symbol.Name;

        var parameters = symbol.Type.Signature.Select(p => p.Type).ToList();

        if (type.Methods.Any(m => m.Name == name && m.Accepts(parameters)))
        {
            diagnostics.Error("SL0552", symbol.Span,
                $"'{type.Name}' already declares a method named '{name}' taking these " +
                $"parameters, which is what raising the event '{symbol.Name}' has to use");
            return null;
        }

        var raiser = new FunctionSymbol
        {
            Name = name,
            ModuleName = type.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            ContainingType = type,
            Span = symbol.Span,
            IsPublic = false,
        };

        raiser.Event = symbol;
        raiser.Parameters.Add(new ParameterSymbol("this", type, 0) { IsThis = true });

        int index = 1;
        foreach (var parameter in symbol.Type.Signature)
            raiser.Parameters.Add(new ParameterSymbol(parameter.Name, parameter.Type, index++)
            {
                Mode = parameter.Mode,
            });

        type.Methods.Add(raiser);
        scope.Module.Functions.Add(raiser);
        return raiser;
    }

    /// <summary>
    /// Names a member that would need an instance, or null when it would not.
    /// A destructor is included because it runs when one is destroyed, and a
    /// constructor because it is what makes one.
    /// </summary>
    private static string? InstanceMember(Declaration member) => member switch
    {
        FieldDeclSyntax field => $"the field '{field.Name}'",
        ConstructorDeclSyntax => "a constructor",
        DestructorDeclSyntax => "a destructor",
        PropertyDeclSyntax property when !property.Modifiers.HasFlag(Modifiers.Static) =>
            $"the property '{property.Name}'",
        FunctionDeclSyntax function when !function.Modifiers.HasFlag(Modifiers.Static) &&
                                         !function.IsOperator =>
            $"the method '{function.Name}'",
        _ => null,
    };

    private void CheckOperatorPairs(NamedTypeSymbol type)
    {
        foreach (var (token, opposite) in OperatorNames.Pairs)
        {
            if (OperatorNames.For(token) is not { } name) continue;
            if (OperatorNames.For(opposite) is not { } otherName) continue;

            foreach (var declared in type.Operators.Where(o => o.Name == name))
            {
                var operands = declared.ParameterTypes.ToList();

                if (type.Operators.Any(o => o.Name == otherName && o.Accepts(operands))) continue;

                diagnostics.Error("SL0567", declared.Span,
                    $"'{type.Name}' declares operator '{token.FixedText()}' for these operands " +
                    $"and not '{opposite.FixedText()}'; the two come together, because a type " +
                    "that answers one and not the other is a question nobody can ask twice");
            }
        }
    }

    /// <summary>
    /// Declares a property: the pair of methods it really is, and the hidden
    /// field it keeps its value in when it asked for one.
    ///
    /// Everything downstream sees methods and a field. That is what makes a
    /// property free: it dispatches through an interface, crosses a generic
    /// instantiation and lands in a vtable without any of those knowing it is
    /// not an ordinary method.
    /// </summary>
    private void DeclareProperty(
        FileScope scope, NamedTypeSymbol type, PropertyDeclSyntax declaration)
    {
        // An indexer may be overloaded on what it takes -- `this[nuint]` and
        // `this[String]` are different questions -- so the name alone does not
        // decide whether one is already declared.
        if (!declaration.IsIndexer &&
            (type.FindStorage(declaration.Name) is not null ||
             type.FindProperty(declaration.Name) is not null))
        {
            diagnostics.Error("SL0205", declaration.Span,
                $"'{type.Name}' already declares a member named '{declaration.Name}'");
            return;
        }

        var propertyType = ResolveType(declaration.Type, scope);
        if (propertyType.IsVoid())
        {
            diagnostics.Error("SL0387", declaration.Span,
                $"property '{type.Name}.{declaration.Name}' cannot have type 'void'; " +
                "a property is a value, and 'void' is the absence of one");
            propertyType = ErrorTypeSymbol.Instance;
        }

        var getter = declaration.Accessors.FirstOrDefault(a => a.IsGetter);
        var setter = declaration.Accessors.FirstOrDefault(a => !a.IsGetter);

        if (declaration.Accessors.Count > 2 || declaration.Accessors.Count(a => a.IsGetter) > 1)
        {
            diagnostics.Error("SL0388", declaration.Span,
                $"property '{type.Name}.{declaration.Name}' declares the same accessor twice");
            return;
        }

        if (getter is null)
        {
            // A value that can only be written is a method, and reads better as
            // one. Allowing the shape would only disguise that.
            diagnostics.Error("SL0389", declaration.Span,
                setter is null
                    ? $"property '{type.Name}.{declaration.Name}' declares no accessor; write 'get;'"
                    : $"property '{type.Name}.{declaration.Name}' has a setter but no getter; " +
                      "something that can only be written is a method, not a property");
            return;
        }

        bool isInterface = type.IsContract;
        bool isAbstract = declaration.Modifiers.HasFlag(Modifiers.Abstract);
        bool wantsStorage = false;

        if (isInterface || isAbstract)
        {
            foreach (var accessor in declaration.Accessors.Where(a => a.Body is not null))
                diagnostics.Error("SL0392", accessor.Span,
                    isInterface
                        ? $"'{type.Name}.{declaration.Name}' is an interface property, so its " +
                          $"{(accessor.IsGetter ? "getter" : "setter")} cannot have a body; " +
                          "interfaces declare signatures only"
                        : $"'{type.Name}.{declaration.Name}' is abstract, so its " +
                          $"{(accessor.IsGetter ? "getter" : "setter")} cannot have a body; " +
                          "a derived class supplies one");
        }
        else
        {
            bool getterIsAuto = getter.Body is null;

            // Half a hidden field is not a thing: an automatic accessor and a
            // written one would have to agree about storage nothing can name.
            if (setter is not null && (setter.Body is null) != getterIsAuto)
            {
                diagnostics.Error("SL0391", declaration.Span,
                    $"property '{type.Name}.{declaration.Name}' mixes an automatic accessor " +
                    "with a written one; either both are automatic, or both have bodies and " +
                    "name storage the type already declares");
                return;
            }

            wantsStorage = getterIsAuto;

            // A struct has no constructor, so a get-only automatic property on
            // one has no moment at which it could ever be given a value.
            if (wantsStorage && setter is null && type is StructTypeSymbol)
                diagnostics.Error("SL0401", declaration.Span,
                    $"'{type.Name}.{declaration.Name}' could never be assigned: it is automatic " +
                    "and has no setter, and a struct has no constructor to fill it in; add " +
                    "'set;', or give it a body that computes the value");
        }

        bool isStatic = declaration.Modifiers.HasFlag(Modifiers.Static);

        if (isStatic && wantsStorage)
        {
            diagnostics.Error("SL0584", declaration.Span,
                $"'{type.Name}.{declaration.Name}' is static and automatic, so its storage " +
                "would have no moment at which to be given a first value: a static is written " +
                "by its initializer and there is no initializer here. Write the accessors over " +
                "a 'static' field, which has one");
            return;
        }

        if (declaration.Initializer is not null && !wantsStorage)
            diagnostics.Error("SL0617", declaration.Initializer.Span,
                $"'{type.Name}.{declaration.Name}' computes its value, so there is no storage " +
                "here to give one to; a value after the accessors belongs to an automatic " +
                "property, which is the one that owns a field");

        FieldSymbol? backing = null;
        if (wantsStorage)
        {
            // Named after the property, because that is what the storage is. It
            // is hidden from lookup, so nothing can reach past the accessors.
            backing = new FieldSymbol(declaration.Name, propertyType, type, type.Fields.Count)
            {
                IsBackingField = true,
                InitializerSyntax = CheckedPropertyInitializer(type, declaration),
                InitializerScope = scope,
            };
            type.Fields.Add(backing);
        }

        var property = new PropertySymbol
        {
            Name = declaration.Name,
            Type = propertyType,
            ContainingType = type,
            Span = declaration.Span,
            Documentation = declaration.Documentation,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public) || isInterface,
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            BackingField = backing,
            IsIndexer = declaration.IsIndexer,
        };

        // A property's dispatch is its accessors' -- they are the methods, and a
        // vtable has no notion of a property at all.
        var accessorModifiers = declaration.Modifiers;

        property.Getter = DeclareAccessor(
            scope, type, property, getter, false, accessorModifiers, declaration.Indices);
        if (setter is not null)
            property.Setter = DeclareAccessor(
                scope, type, property, setter, true, accessorModifiers, declaration.Indices);

        type.Properties.Add(property);
    }

    /// <summary>
    /// Declares one accessor as the method it is: <c>get_Name</c> returning the
    /// property type, or <c>set_Name</c> taking one parameter called
    /// <c>value</c> — which is why <c>value</c> resolves inside a setter with no
    /// special case anywhere in name lookup.
    /// </summary>
    private FunctionSymbol? DeclareAccessor(
        FileScope scope, NamedTypeSymbol type, PropertySymbol property,
        AccessorSyntax accessor, bool isSetter, Modifiers modifiers,
        IReadOnlyList<ParameterSyntax> indices)
    {
        string role = isSetter ? "setter" : "getter";
        string name = (isSetter ? "set_" : "get_") + property.Name;

        // What this accessor will take, which is what says whether the name is
        // really taken: an indexer may be overloaded on its index -- `this[nuint]`
        // and `this[String]` are different questions -- and both lower to
        // `get_Item`, so the name alone does not decide.
        var willTake = indices.Select(i => ResolveType(i.Type, scope)).ToList();
        if (isSetter) willTake.Add(property.Type);

        if (type.Methods.Any(m => m.Name == name && m.Accepts(willTake)))
        {
            diagnostics.Error("SL0393", accessor.Span,
                $"'{type.Name}' already declares a method named '{name}' taking these " +
                $"parameters, which is what the {role} of " +
                (property.IsIndexer ? "this indexer" : $"property '{property.Name}'") +
                " has to use");
            return null;
        }

        // A setter may be narrowed; a getter may not. The getter is what the
        // property's visibility means, so letting it differ would only make the
        // word 'public' on the property itself a lie.
        bool isPublic = property.IsPublic;
        if (accessor.Modifiers.HasFlag(Modifiers.Private))
        {
            if (isSetter) isPublic = false;
            else
                diagnostics.Error("SL0394", accessor.Span,
                    $"the getter of '{type.Name}.{property.Name}' is what makes the property " +
                    "public or not, so it cannot be narrowed on its own; write the property " +
                    "itself without 'public', or narrow the setter instead");
        }

        var symbol = new FunctionSymbol
        {
            Name = name,
            ModuleName = scope.Module.Name,
            ReturnType = isSetter ? PrimitiveTypeSymbol.Void : property.Type,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = type,
            IsPublic = isPublic,
            IsProtected = property.IsProtected,
            IsVirtual = modifiers.HasFlag(Modifiers.Virtual)
                        || modifiers.HasFlag(Modifiers.Override)
                        || modifiers.HasFlag(Modifiers.Abstract),
            IsOverride = modifiers.HasFlag(Modifiers.Override),
            IsAbstract = modifiers.HasFlag(Modifiers.Abstract),
            IsSealed = modifiers.HasFlag(Modifiers.Sealed),
            Body = accessor.Body,
            Span = accessor.Span,
            Scope = scope,
            IsStatic = modifiers.HasFlag(Modifiers.Static),
            Accessor = property,
            IsAutoAccessor = accessor.Body is null
                             && !type.IsContract
                             && !modifiers.HasFlag(Modifiers.Abstract),
        };

        if (!symbol.IsStatic)
        {
            TypeSymbol thisType = type is ClassTypeSymbol reference
                ? reference
                : new PointerTypeSymbol(type);
            symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });
        }

        // An indexer's indices come before `value`, so that a setter reads
        // `set_Item(i, v)` -- the order the call site writes them in.
        for (int i = 0; i < indices.Count; i++)
            symbol.Parameters.Add(new ParameterSymbol(
                indices[i].Name, willTake[i], symbol.Parameters.Count));

        if (isSetter)
            symbol.Parameters.Add(
                new ParameterSymbol("value", property.Type, symbol.Parameters.Count));

        type.Methods.Add(symbol);
        scope.Module.Functions.Add(symbol);
        return symbol;
    }
}
