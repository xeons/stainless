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
                            module.GenericFunctions.Add(
                                new GenericFunctionTemplate(function.Name, scope, function));
                        else
                            DeclareFunction(scope, containingType: null, function);
                        break;

                    case TypeDeclSyntax typeDecl:
                        // Templates wait; their members depend on type arguments.
                        if (typeDecl.TypeParameters.Count == 0)
                            DeclareTypeMembers(scope, typeDecl, module.Types[typeDecl.Name]);
                        break;

                    case StaticDeclSyntax staticDecl:
                        DeclareStatic(scope, staticDecl);
                        break;

                    case DelegateDeclSyntax delegateDecl:
                        DeclareDelegateSignature(
                            (DelegateTypeSymbol)module.Types[delegateDecl.Name], delegateDecl, scope);
                        break;

                    case EnumDeclSyntax enumDecl:
                        DeclareEnumMembers(
                            (EnumTypeSymbol)module.Types[enumDecl.Name], enumDecl, scope);
                        break;

                    case GlobalConstDeclSyntax constant:
                        DeclareGlobalConstant(scope, constant);
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
    }

    /// <summary>
    /// Resolves a delegate's return and parameter types. The names are kept for
    /// diagnostics and for the generated C header; nothing else reads them.
    /// </summary>
    private void DeclareDelegateSignature(
        DelegateTypeSymbol type, DelegateDeclSyntax declaration, FileScope scope)
    {
        type.ReturnType = ResolveType(declaration.ReturnType, scope);

        for (int i = 0; i < declaration.Parameters.Count; i++)
        {
            var parameter = declaration.Parameters[i];
            var parameterType = ResolveType(parameter.Type, scope);

            if (parameterType.IsVoid())
            {
                diagnostics.Error("SL0359", parameter.Span,
                    $"parameter '{parameter.Name}' of delegate '{type.Name}' cannot be 'void'");
                parameterType = ErrorTypeSymbol.Instance;
            }

            type.Signature.Add(new ParameterSymbol(parameter.Name, parameterType, i)
            {
                Mode = parameter.Mode,
            });
        }
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

            type.Members.Add(new EnumMemberSymbol(member.Name, type, value));
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

        if (type is VariantTypeSymbol variant) DeclareVariantCases(scope, declaration, variant);

        foreach (var member in declaration.Members)
        {
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
                    if (field.Initializer is not null)
                        diagnostics.Error("SL0206", field.Span,
                            "field initializers are not supported yet; assign the field in a constructor");

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
        if (type.FindStorage(declaration.Name) is not null ||
            type.FindProperty(declaration.Name) is not null)
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

        FieldSymbol? backing = null;
        if (wantsStorage)
        {
            // Named after the property, because that is what the storage is. It
            // is hidden from lookup, so nothing can reach past the accessors.
            backing = new FieldSymbol(declaration.Name, propertyType, type, type.Fields.Count)
            {
                IsBackingField = true,
            };
            type.Fields.Add(backing);
        }

        var property = new PropertySymbol
        {
            Name = declaration.Name,
            Type = propertyType,
            ContainingType = type,
            Span = declaration.Span,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public) || isInterface,
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            BackingField = backing,
        };

        // A property's dispatch is its accessors' -- they are the methods, and a
        // vtable has no notion of a property at all.
        var accessorModifiers = declaration.Modifiers;

        property.Getter = DeclareAccessor(scope, type, property, getter, false, accessorModifiers);
        if (setter is not null)
            property.Setter = DeclareAccessor(scope, type, property, setter, true, accessorModifiers);

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
        AccessorSyntax accessor, bool isSetter, Modifiers modifiers)
    {
        string role = isSetter ? "setter" : "getter";
        string name = (isSetter ? "set_" : "get_") + property.Name;

        if (type.FindMethod(name) is not null)
        {
            diagnostics.Error("SL0393", accessor.Span,
                $"'{type.Name}' already declares a method named '{name}', which is the name " +
                $"the {role} of property '{property.Name}' has to use");
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
            Accessor = property,
            IsAutoAccessor = accessor.Body is null
                             && !type.IsContract
                             && !modifiers.HasFlag(Modifiers.Abstract),
        };

        TypeSymbol thisType = type is ClassTypeSymbol reference
            ? reference
            : new PointerTypeSymbol(type);
        symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });

        if (isSetter)
            symbol.Parameters.Add(new ParameterSymbol("value", property.Type, 1));

        type.Methods.Add(symbol);
        scope.Module.Functions.Add(symbol);
        return symbol;
    }
}
