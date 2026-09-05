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
/// Pass 5: what each type derives from, and the dispatch tables that
/// follow from it.
///
/// Base classes, interfaces, virtual tables, interface tables and COM
/// slots. A derived type resolves base-first by recursion, since it
/// cannot inherit a table that does not exist yet.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 5

    /// <summary>
    /// Resolves what each type derives from -- a base class, interfaces, or both
    /// -- checks that it really supplies what it claims, and lays out its
    /// dispatch table.
    ///
    /// Interfaces go first so that an interface's own <c>extends</c> list is
    /// settled before any class is measured against it. Classes then resolve
    /// base-first, by recursion rather than by sorting: a derived class cannot
    /// inherit a vtable that does not exist yet.
    ///
    /// Interface ids are assigned across the whole program, which is what lets a
    /// class's dispatch table be indexed directly instead of searched.
    /// </summary>
    private void ResolveInterfaces()
    {
        foreach (var (type, entry) in _typeSyntax.Where(e => e.Key.IsContract))
            ResolveImplements(type, entry.Declaration, entry.Scope);

        foreach (var (type, entry) in _typeSyntax.Where(e => !e.Key.IsContract))
            ResolveImplements(type, entry.Declaration, entry.Scope);
    }

    /// <summary>
    /// Every com interface in the program, so the emitter can write out the
    /// IID constants and the vtables that mention them.
    /// </summary>
    private readonly List<ComInterfaceTypeSymbol> _comInterfaces = [];

    /// <summary>Types whose bases and interfaces are settled.</summary>
    private readonly HashSet<NamedTypeSymbol> _inheritanceDone = [];

    /// <summary>Types being settled right now; a second visit is a cycle.</summary>
    private readonly HashSet<NamedTypeSymbol> _inheritanceInProgress = [];

    private void ResolveImplements(
        NamedTypeSymbol type, TypeDeclSyntax declaration, FileScope scope)
    {
        if (_inheritanceDone.Contains(type)) return;
        if (!_inheritanceInProgress.Add(type)) return;      // a cycle; the caller reports it

        var classType = type as ClassTypeSymbol;

        if (type is StructTypeSymbol && declaration.Implements.Count > 0)
        {
            string kind = type switch
            {
                VariantTypeSymbol => "variant",
                UnionTypeSymbol => "union",
                _ => "struct",
            };
            diagnostics.Error("SL0302", declaration.Span,
                $"{kind} '{type.Name}' cannot implement an interface; an interface " +
                "reference is a counted pointer, and a " + kind + " is a plain C value");
        }
        else
        {
            for (int i = 0; i < declaration.Implements.Count; i++)
            {
                var written = declaration.Implements[i];
                var resolved = ResolveType(written, scope);
                if (resolved.IsError()) continue;

                // A class in the list is the base class, and only the first name
                // may be one -- which is what makes `: Base, IShape` read the way
                // it does in C# without any lookahead at all.
                if (resolved is ClassTypeSymbol baseClass)
                {
                    BindBaseClass(type, classType, baseClass, written.Span, isFirst: i == 0);
                    continue;
                }

                // A com interface in the list. For a com interface it is the
                // one base; for a com class it is one more tear-off.
                if (resolved is ComInterfaceTypeSymbol comInterface)
                {
                    BindComInterface(type, classType, comInterface, written.Span);
                    continue;
                }

                if (resolved is not InterfaceTypeSymbol interfaceType)
                {
                    diagnostics.Error("SL0303", written.Span,
                        $"'{resolved.Name}' is not an interface, so '{type.Name}' cannot " +
                        (type.IsContract ? "extend" : "implement") + " it");
                    continue;
                }

                // A com interface extends com interfaces only. Its vtable is one
                // flat array with IUnknown at the front, and a Stainless
                // interface is not reached through a vtable pointer at all.
                if (type is ComInterfaceTypeSymbol)
                {
                    diagnostics.Error("SL0529", written.Span,
                        $"'{type.Name}' is a com interface and '{interfaceType.Name}' is not; " +
                        "a COM vtable is one array with IUnknown at the front, and a Stainless " +
                        "interface is reached through the object header instead");
                    continue;
                }

                if (type.Interfaces.Contains(interfaceType))
                {
                    diagnostics.Warning("SL0304", written.Span,
                        $"'{type.Name}' already lists '{interfaceType.Name}'");
                    continue;
                }

                if (interfaceType == type || interfaceType.AllInterfaces().Contains(type))
                {
                    diagnostics.Error("SL0333", written.Span,
                        $"'{type.Name}' and '{interfaceType.Name}' extend each other");
                    continue;
                }

                type.Interfaces.Add(interfaceType);

                // Only a class has to supply implementations. An interface
                // extending another merely widens its own contract.
                if (classType is not null)
                    VerifyImplements(classType, interfaceType, written.Span);
            }
        }

        // Every class gets a table, base or no base: a class may declare the
        // first `virtual` in its own family.
        if (classType is not null) ResolveVirtuals(classType, declaration);

        if (type is ComInterfaceTypeSymbol comType) ResolveComSlots(comType, declaration);
        if (classType is { IsCom: true }) ResolveComClass(classType, declaration);

        _inheritanceInProgress.Remove(type);
        _inheritanceDone.Add(type);
    }

    /// <summary>
    /// A com interface named in a <c>:</c> list.
    ///
    /// For a com interface it is the single base, whose slots come first. For a
    /// com class it is one more interface to present, and therefore one more
    /// tear-off in the object.
    /// </summary>
    private void BindComInterface(
        NamedTypeSymbol type, ClassTypeSymbol? classType,
        ComInterfaceTypeSymbol comInterface, SourceSpan span)
    {
        if (type is ComInterfaceTypeSymbol derived)
        {
            if (derived.BaseInterface is not null)
            {
                diagnostics.Error("SL0530", span,
                    $"'{derived.Name}' already extends '{derived.BaseInterface.Name}', so it " +
                    $"cannot also extend '{comInterface.Name}'. A COM vtable is one array and a " +
                    "reference is one pointer to it, so there is room for one chain and not two");
                return;
            }

            if (comInterface == derived || comInterface.DerivesFrom(derived))
            {
                diagnostics.Error("SL0531", span,
                    comInterface == derived
                        ? $"'{derived.Name}' cannot extend itself"
                        : $"'{derived.Name}' and '{comInterface.Name}' extend each other, so " +
                          "neither has a vtable");
                return;
            }

            // The base's slots have to be numbered before this one's can follow
            // them, and a com interface declared later in the file is resolved
            // no differently from one declared earlier.
            if (_typeSyntax.TryGetValue(comInterface, out var entry))
                ResolveImplements(comInterface, entry.Declaration, entry.Scope);

            derived.BaseInterface = comInterface;
            return;
        }

        if (classType is null)
        {
            diagnostics.Error("SL0532", span,
                $"'{type.Name}' cannot present '{comInterface.Name}': a com interface is laid " +
                "out inside the object that presents it, and only a class has an object");
            return;
        }

        if (!classType.IsCom)
        {
            diagnostics.Error("SL0533", span,
                $"'{classType.Name}' implements the com interface '{comInterface.Name}', so it " +
                $"must be declared 'com class {classType.Name}'. A COM reference points at a " +
                "vtable pointer, and an ordinary class has no room for one");
            return;
        }

        if (classType.ComInterfaces.Contains(comInterface))
        {
            diagnostics.Warning("SL0304", span,
                $"'{classType.Name}' already lists '{comInterface.Name}'");
            return;
        }

        classType.ComInterfaces.Add(comInterface);
    }

    /// <summary>
    /// Numbers a com interface's vtable: IUnknown's three, then everything
    /// inherited, then its own declarations in the order they were written.
    ///
    /// Root-down, exactly as a class's table is numbered, and for the same
    /// reason: a slot number belongs to the declaration rather than to the
    /// reference it is reached through, which is what lets a derived reference
    /// be used as a base one with no conversion at all.
    /// </summary>
    private void ResolveComSlots(ComInterfaceTypeSymbol type, TypeDeclSyntax declaration)
    {
        // Nothing extends nothing: a root com interface still starts with
        // IUnknown, because every COM vtable does and ARC calls two of its
        // slots.
        type.BaseInterface ??= _builtins.Unknown == type ? null : _builtins.Unknown;

        if (type.BaseInterface is { } baseInterface)
            type.VirtualTable.AddRange(baseInterface.VirtualTable);

        // A slot number is all that makes a call dispatch; `IsVirtual` records
        // that the word was written, and on a com interface method it never is.
        foreach (var method in type.Methods)
        {
            method.VirtualSlot = type.VirtualTable.Count;
            type.VirtualTable.Add(method);
        }

        if (type.VirtualTable.Count > ComInterfaceTypeSymbol.UnknownSlots) return;
        if (type == _builtins.Unknown) return;

        diagnostics.Warning("SL0534", declaration.Span,
            $"'{type.Name}' declares no methods, so it is IUnknown under another name; " +
            "give it members or use 'IUnknown' directly");
    }

    /// <summary>
    /// Checks a com class against the interfaces it presents, and reserves the
    /// tear-offs it needs.
    /// </summary>
    private void ResolveComClass(ClassTypeSymbol classType, TypeDeclSyntax declaration)
    {
        if (classType.ComInterfaces.Count == 0)
        {
            diagnostics.Error("SL0535", classType.Span ?? declaration.Span,
                $"'{classType.Name}' is a com class and presents no com interface, so nothing " +
                "outside could ever hold one. List at least one after ':'");
            return;
        }

        if (classType.BaseClass is not null)
            diagnostics.Error("SL0536", classType.Span ?? declaration.Span,
                $"'{classType.Name}' is a com class and derives from " +
                $"'{classType.BaseClass.Name}'; the two cannot be combined yet, because the " +
                "tear-offs sit after the fields and a derived class adds fields after those");

        // Every interface a presented one extends is also presented: a caller
        // holding IFileDialog may hand it on as the IUnknown it extends, and
        // QueryInterface has to answer for both.
        foreach (var presented in classType.ComInterfaces.ToList())
        foreach (var inherited in presented.SelfAndBases().Skip(1))
        {
            if (inherited == _builtins.Unknown) continue;
            if (classType.ComInterfaces.Contains(inherited)) continue;
            classType.ComInterfaces.Add(inherited);
        }

        foreach (var presented in classType.ComInterfaces)
            VerifyPresents(classType, presented, declaration.Span);
    }

    /// <summary>
    /// Every method of a presented com interface has a public method on the
    /// class with exactly that signature.
    ///
    /// IUnknown's three are the compiler's, not the programmer's: they are the
    /// same three functions for every com class, they have to agree with the
    /// tear-off layout, and a hand-written AddRef would put the object's count
    /// and ARC's out of step.
    /// </summary>
    private void VerifyPresents(
        ClassTypeSymbol classType, ComInterfaceTypeSymbol comInterface, SourceSpan span)
    {
        foreach (var required in comInterface.Methods)
        {
            if (required.ContainingType == _builtins.Unknown) continue;

            var found = classType.FindImplementation(required);
            if (found is null)
            {
                diagnostics.Error("SL0305", span,
                    $"'{classType.Name}' does not implement '{comInterface.Name}.{required.Name}'; " +
                    $"add 'public {required.ReturnType.Name} {required.Name}(" +
                    string.Join(", ", required.Parameters.Where(p => !p.IsThis)
                        .Select(p => p.Type.Name + " " + p.Name)) + ")'");
                continue;
            }

            if (!found.IsPublic)
                diagnostics.Error("SL0306", found.Span,
                    $"'{classType.Name}.{found.Name}' implements " +
                    $"'{comInterface.Name}.{required.Name}' and must therefore be public");
        }
    }

    /// <summary>
    /// Adopts <paramref name="baseClass"/> as the base of <paramref name="classType"/>,
    /// having first settled the base's own inheritance -- a derived class cannot
    /// inherit a dispatch table that has not been built.
    /// </summary>
    private void BindBaseClass(
        NamedTypeSymbol type, ClassTypeSymbol? classType,
        ClassTypeSymbol baseClass, SourceSpan span, bool isFirst)
    {
        if (classType is null)
        {
            diagnostics.Error("SL0512", span,
                $"'{type.Name}' is an interface and '{baseClass.Name}' is a class; an interface " +
                "extends interfaces only, because it has no state to inherit");
            return;
        }

        if (classType.BaseClass is not null)
        {
            diagnostics.Error("SL0510", span,
                $"'{classType.Name}' already derives from '{classType.BaseClass.Name}', so it " +
                $"cannot also derive from '{baseClass.Name}'. With two bases a reference to one " +
                "of them is a different address from the object itself, and reference identity, " +
                "free upcasts and 'sl_retain' all rest on those being the same. Interfaces give " +
                "several types without several states");
            return;
        }

        if (!isFirst)
        {
            diagnostics.Error("SL0508", span,
                $"the base class must be written first: '{classType.Name} : {baseClass.Name}, ...'. " +
                "A class has one base and any number of interfaces, and putting the base at the " +
                "front is what tells them apart without a keyword");
            return;
        }

        if (_inheritanceInProgress.Contains(baseClass))
        {
            diagnostics.Error("SL0511", span,
                baseClass == classType
                    ? $"'{classType.Name}' cannot derive from itself"
                    : $"'{classType.Name}' and '{baseClass.Name}' derive from each other, so " +
                      "neither has a size");
            return;
        }

        if (baseClass.IsSealed)
        {
            diagnostics.Error("SL0509", span,
                $"'{baseClass.Name}' is sealed, so nothing may derive from it");
            return;
        }

        if (baseClass.IsIntrinsic || baseClass.RuntimeFactory is not null)
        {
            diagnostics.Error("SL0513", span,
                $"'{baseClass.Name}' is provided by the runtime rather than compiled here, so " +
                "its layout and its destructor are not this compilation's to extend");
            return;
        }

        if (baseClass.ExternalTypeInfo is not null)
        {
            diagnostics.Error("SL0513", span,
                $"'{baseClass.Name}' comes from a referenced library, and deriving across a " +
                "library boundary is not supported: the derived object would carry a dispatch " +
                "table built here for a layout compiled there");
            return;
        }

        // Settle the base before taking anything from it. This is what puts the
        // whole hierarchy in order without a separate sorting pass.
        if (_typeSyntax.TryGetValue(baseClass, out var entry))
            ResolveImplements(baseClass, entry.Declaration, entry.Scope);

        classType.BaseClass = baseClass;

        // Implementing an interface is inherited along with everything else, and
        // the object needs its dispatch table either way.
        foreach (var inherited in baseClass.Interfaces)
            if (!classType.Interfaces.Contains(inherited))
                classType.Interfaces.Add(inherited);
    }

    /// <summary>
    /// Builds a class's dispatch table and checks every word written about
    /// overriding.
    ///
    /// The table starts as a copy of the base's, so an inherited method keeps its
    /// slot and a call through a base reference reaches whatever the object
    /// really is. An <c>override</c> replaces the entry in place; a new
    /// <c>virtual</c> is appended after everything inherited.
    /// </summary>
    private void ResolveVirtuals(ClassTypeSymbol classType, TypeDeclSyntax declaration)
    {
        if (classType.BaseClass is { } inheritedFrom)
            classType.VirtualTable.AddRange(inheritedFrom.VirtualTable);

        foreach (var method in classType.Methods)
        {
            if (method.IsVirtual && !method.IsPublic && !method.IsProtected)
                diagnostics.Error("SL0506", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is dispatched, so it must be " +
                    "'public' or 'protected': a derived class has to be able to name what it " +
                    "is replacing");

            if (method.IsSealed && !method.IsOverride)
                diagnostics.Error("SL0507", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is 'sealed' and overrides nothing; " +
                    "the word closes an inherited chain, so it goes with 'override'");

            if (method.IsAbstract && !classType.IsAbstract)
                diagnostics.Error("SL0505", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is abstract, so '{classType.Name}' " +
                    "must be abstract too; a class with a method that has no body cannot be made");

            var signature = method.ParameterTypes.ToList();
            var inherited = classType.BaseClass?
                .FindMethods(method.Name)
                .FirstOrDefault(m => m.Accepts(signature));

            if (method.IsOverride)
            {
                if (inherited is null)
                {
                    diagnostics.Error("SL0499", method.Span,
                        classType.BaseClass is null
                            ? $"'{classType.Name}.{Describe(method)}' is marked 'override' and " +
                              $"'{classType.Name}' derives from nothing"
                            : $"'{classType.Name}.{Describe(method)}' is marked 'override' and " +
                              $"'{classType.BaseClass.Name}' declares nothing of that name and " +
                              "those parameters");
                    continue;
                }

                if (!inherited.IsVirtual)
                {
                    diagnostics.Error("SL0500", method.Span,
                        $"'{inherited.ContainingType!.Name}.{Describe(inherited)}' is not " +
                        "virtual, so it cannot be overridden; mark it 'virtual' or 'abstract'");
                    continue;
                }

                if (inherited.IsSealed)
                {
                    diagnostics.Error("SL0501", method.Span,
                        $"'{inherited.ContainingType!.Name}.{Describe(inherited)}' is a sealed " +
                        "override, so nothing may override it further");
                    continue;
                }

                if (!SignaturesAgree(method, inherited))
                {
                    diagnostics.Error("SL0502", method.Span,
                        $"'{classType.Name}.{Describe(method)}' does not match what it overrides; " +
                        $"expected '{inherited.ReturnType.Name} {inherited.Name}(" +
                        string.Join(", ", inherited.Parameters.Where(p => !p.IsThis).Select(Spelled)) +
                        ")'");
                    continue;
                }

                method.Overridden = inherited;
                method.VirtualSlot = inherited.VirtualSlot;
                classType.VirtualTable[method.VirtualSlot] = method;
                continue;
            }

            if (inherited is not null)
            {
                // Silent hiding is the one shape C# allows here and this does
                // not: `new` exists to say "I know", and a language with no way
                // to reach the hidden member has nothing to say it about.
                diagnostics.Error("SL0503", method.Span,
                    $"'{classType.Name}.{Describe(method)}' has the same name and parameters as " +
                    $"'{inherited.ContainingType!.Name}.{Describe(inherited)}'" +
                    (inherited.IsVirtual
                        ? "; write 'override' to replace it"
                        : ", which is not virtual; rename one of them, or mark the inherited " +
                          "one 'virtual' and this one 'override'"));
                continue;
            }

            if (method.IsVirtual)
            {
                method.VirtualSlot = classType.VirtualTable.Count;
                classType.VirtualTable.Add(method);
            }
        }

        if (classType.IsAbstract) return;

        // A class that declares no constructor is built by its base's, and one
        // with no base constructor it could call is a class nothing can make.
        // Said here rather than at each `new`, because the declaration is where
        // the missing constructor goes.
        if (classType.Constructors.Count == 0 &&
            !TryImplicitBaseConstructor(classType, out _))
            diagnostics.Error("SL0517", classType.Span ?? declaration.Span,
                $"'{classType.Name}' declares no constructor and every constructor of " +
                $"'{NearestConstructing(classType)!.Name}' takes arguments, so nothing could " +
                $"ever build one; give '{classType.Name}' a constructor whose first statement " +
                "is 'base(...)'");

        // A concrete class is one every abstract method of which has a body
        // somewhere in the chain -- which is exactly the table having no
        // abstract entry left in it.
        // One its own declaration left abstract has already been reported
        // against that declaration, which is where the mistake is.
        foreach (var missing in classType.VirtualTable
                     .Where(m => m.IsAbstract && m.ContainingType != classType))
            diagnostics.Error("SL0504", classType.Span ?? declaration.Span,
                $"'{classType.Name}' does not implement abstract " +
                $"'{missing.ContainingType!.Name}.{Describe(missing)}'; add 'public override " +
                $"{missing.ReturnType.Name} {missing.Name}(" +
                string.Join(", ", missing.Parameters.Where(p => !p.IsThis)
                    .Select(p => p.Type.Name + " " + p.Name)) + ")'");
    }

    /// <summary>
    /// True when two methods agree on everything a caller can observe: the
    /// return type, and each parameter's type and mode. The mode is part of it
    /// because a <c>ref int</c> and an <c>int</c> are passed differently, and the
    /// slot would then hold a function the caller is about to hand a pointer to.
    /// </summary>
    private static bool SignaturesAgree(FunctionSymbol method, FunctionSymbol other)
    {
        var mine = method.Parameters.Where(p => !p.IsThis).ToList();
        var theirs = other.Parameters.Where(p => !p.IsThis).ToList();

        return method.ReturnType.Equals(other.ReturnType) &&
               mine.Count == theirs.Count &&
               mine.Zip(theirs).All(pair =>
                   pair.First.Type.Equals(pair.Second.Type) &&
                   pair.First.Mode == pair.Second.Mode);
    }

    /// <summary>
    /// A method as a diagnostic should name it. An accessor is named by its
    /// property, because that is the thing the source wrote.
    /// </summary>
    private static string Describe(FunctionSymbol method) =>
        method.Accessor is { } property ? property.Name : method.Name;

    /// <summary>The <c>[Reflect]</c> marker, found in Standard.Reflection.</summary>
    private AttributeTypeSymbol? ReflectAttribute =>
        _modules.TryGetValue("Standard.Reflection", out var module) &&
        module.Types.TryGetValue("Reflect", out var found)
            ? found as AttributeTypeSymbol
            : null;

    /// <summary>The struct <c>typeof</c> produces, also from Standard.Reflection.</summary>
    private StructTypeSymbol? TypeHandle =>
        _modules.TryGetValue("Standard.Reflection", out var module) &&
        module.Types.TryGetValue("Type", out var found)
            ? found as StructTypeSymbol
            : null;

    /// <summary>
    /// Binds every applied attribute once all types are known. Arguments must be
    /// constants, since the values are written into the binary rather than
    /// evaluated.
    /// </summary>
    private void ResolveAttributes()
    {
        var reflect = ReflectAttribute;

        // Enums live in their own table, and until [Flags] there was nothing an
        // attribute on one could mean -- so they were silently dropped.
        foreach (var (type, entry) in _enumSyntax)
            BindAttributes(entry.Declaration.Attributes, type.Attributes, entry.Scope, type.Name);

        foreach (var (type, entry) in _typeSyntax)
            if (entry.Declaration.Attributes.Count > 0 &&
                entry.Declaration.Attributes.Any(a => a.Name.Last == "Flags"))
                diagnostics.Error("SL0411", entry.Declaration.Span,
                    $"'[Flags]' says an enum's members combine as bits; '{type.Name}' is not an enum");

        foreach (var (type, entry) in _typeSyntax)
        {
            var written = BindGuid(type, entry.Declaration);
            BindAttributes(written, type.Attributes, entry.Scope, type.Name);

            if (reflect is not null && type.Attributes.Any(a => a.Type == reflect))
            {
                // A variant is a struct, so it would pass the test below and emit
                // its two hidden fields as if they were the programmer's. They
                // are not, and a variant's shape is its cases, which the field
                // tables have no way to say.
                if (type is VariantTypeSymbol)
                    diagnostics.Error("SL0442", entry.Declaration.Span,
                        $"'[Reflect]' emits a type's fields, and the fields of variant " +
                        $"'{type.Name}' are a tag and a payload the source cannot name. What " +
                        "a reader would want is its cases, and those are not described yet");
                else if (type.Fields.Any(f => f.IsBitField))
                    diagnostics.Error("SL0475", entry.Declaration.Span,
                        $"'[Reflect]' describes a field by its byte offset, and '{type.Name}' " +
                        "has bit-fields, which have not got one. Reflecting them means saying " +
                        "where in a byte they start, and the tables do not");
                else if (type is ClassTypeSymbol or StructTypeSymbol) type.IsReflected = true;
                else
                    diagnostics.Error("SL0341", entry.Declaration.Span,
                        $"'[Reflect]' applies to a class or a struct; '{type.Name}' is neither");
            }

            ReadLayoutAttributes(type, entry.Declaration.Span);

            foreach (var member in entry.Declaration.Members.OfType<FieldDeclSyntax>())
            {
                if (member.Attributes.Count == 0) continue;
                if (type.FindField(member.Name) is not { } field) continue;

                BindAttributes(member.Attributes, field.Attributes, entry.Scope,
                    type.Name + "." + field.Name);
            }

            // An attribute on an automatic property lands on its backing field
            // too, so a reflected type reports the storage the way it was
            // annotated rather than losing the annotation to the lowering.
            foreach (var member in entry.Declaration.Members.OfType<PropertyDeclSyntax>())
            {
                if (member.Attributes.Count == 0) continue;
                if (type.FindProperty(member.Name) is not { } property) continue;

                BindAttributes(member.Attributes, property.Attributes, entry.Scope,
                    type.Name + "." + property.Name);
                property.BackingField?.Attributes.AddRange(property.Attributes);
            }
        }
    }

    /// <summary>
    /// Reads <c>[Guid("...")]</c> off a com interface and returns the
    /// attributes that are left for the ordinary machinery.
    ///
    /// The string is parsed here rather than at run time, so a malformed one is
    /// a compile error and the binary carries sixteen bytes.
    /// </summary>
    private IReadOnlyList<AttributeSyntax> BindGuid(
        NamedTypeSymbol type, TypeDeclSyntax declaration)
    {
        var guids = declaration.Attributes.Where(a => a.Name.Last == "Guid").ToList();
        if (guids.Count == 0)
        {
            // Without one the interface has no identity, so nothing can ask an
            // object for it and a cast to it could never be answered.
            if (type is ComInterfaceTypeSymbol needsOne && needsOne != _builtins.Unknown)
                diagnostics.Error("SL0537", declaration.Span,
                    $"'{type.Name}' is a com interface and has no '[Guid(\"...\")]'. An IID is " +
                    "how QueryInterface names an interface, so without one nothing could ever " +
                    "ask an object for this one");
            return declaration.Attributes;
        }

        if (type is not ComInterfaceTypeSymbol comInterface)
        {
            diagnostics.Error("SL0538", guids[0].Span,
                $"'[Guid]' names a COM interface, and '{type.Name}' is not one; write it on a " +
                "'com interface' declaration");
            return declaration.Attributes.Except(guids).ToList();
        }

        if (guids.Count > 1)
            diagnostics.Error("SL0539", guids[1].Span,
                $"'{type.Name}' has more than one '[Guid]', and an interface has one identity");

        var only = guids[0];
        if (only.Arguments.Count != 1 ||
            ConstantValue(only.Arguments[0], _builtins.String) is not string text)
        {
            diagnostics.Error("SL0540", only.Span,
                "'[Guid]' takes one string literal, as in " +
                "'[Guid(\"42f85136-db7e-439c-85f1-e4075d135fc8\")]'");
            return declaration.Attributes.Except(guids).ToList();
        }

        if (!Guid.TryParseExact(text, "D", out var parsed))
            diagnostics.Error("SL0541", only.Arguments[0].Span,
                $"'{text}' is not a GUID; the form is eight hex digits, three groups of four, " +
                "then twelve, separated by hyphens");
        else
            comInterface.Iid = parsed;

        return declaration.Attributes.Except(guids).ToList();
    }

    private void BindAttributes(
        IReadOnlyList<AttributeSyntax> syntax,
        List<AppliedAttribute> applied,
        FileScope scope,
        string owner)
    {
        foreach (var attribute in syntax)
        {
            var resolved = ResolveNamedType(
                new NamedTypeSyntax(attribute.Span, attribute.Name), scope);
            if (resolved.IsError()) continue;

            if (resolved is not AttributeTypeSymbol attributeType)
            {
                diagnostics.Error("SL0342", attribute.Span,
                    $"'{resolved.Name}' is not an attribute, so it cannot be written on {owner}");
                continue;
            }

            if (attribute.Arguments.Count != attributeType.Fields.Count)
            {
                diagnostics.Error("SL0343", attribute.Span,
                    $"'{attributeType.Name}' takes {attributeType.Fields.Count} " +
                    $"argument{(attributeType.Fields.Count == 1 ? "" : "s")}, " +
                    $"but {Given(attribute.Arguments.Count)}");
                continue;
            }

            var values = new List<object?>();
            bool ok = true;

            for (int i = 0; i < attribute.Arguments.Count; i++)
            {
                var expected = attributeType.Fields[i].Type;
                var value = ConstantValue(attribute.Arguments[i], expected);

                if (value is null)
                {
                    diagnostics.Error("SL0344", attribute.Arguments[i].Span,
                        $"argument {i + 1} of '{attributeType.Name}' must be a constant " +
                        $"'{expected.Name}'; attribute values are written into the binary");
                    ok = false;
                    break;
                }

                values.Add(value);
            }

            if (ok) applied.Add(new AppliedAttribute(attributeType, values));
        }
    }

    /// <summary>Folds a literal to the value an attribute field will hold, or null.</summary>
    private object? ConstantValue(ExpressionSyntax syntax, TypeSymbol expected)
    {
        if (syntax is not LiteralSyntax literal) return null;

        if (literal.Kind == TokenKind.StringLiteral)
            return _builtins.IsString(expected) ? literal.Value : null;

        return (literal.Kind, expected) switch
        {
            (TokenKind.IntLiteral, PrimitiveTypeSymbol { IsInteger: true }) => literal.Value,
            (TokenKind.FloatLiteral, PrimitiveTypeSymbol { IsFloat: true }) => literal.Value,
            (TokenKind.TrueKeyword or TokenKind.FalseKeyword,
                PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool }) => literal.Value,
            _ => null,
        };
    }

    private void VerifyImplements(
        ClassTypeSymbol classType, InterfaceTypeSymbol interfaceType, SourceSpan span)
    {
        // Implementing IList also means implementing IReadOnlyList, and the
        // object needs a dispatch table for each.
        foreach (var inherited in interfaceType.AllInterfaces())
        {
            if (classType.Interfaces.Contains(inherited)) continue;
            classType.Interfaces.Add(inherited);
            VerifyImplements(classType, inherited, span);
        }

        foreach (var required in interfaceType.Methods)
        {
            var found = classType.FindImplementation(required);

            // A missing property is one mistake, not two: the getter reports it
            // and the setter stays quiet.
            if (found is null && required.Accessor is { Getter: not null } missing &&
                required != missing.Getter && classType.FindProperty(missing.Name) is null)
                continue;

            if (found is null)
            {
                // A missing accessor is a missing property as far as the source
                // is concerned, so say so in the shape it was written in.
                diagnostics.Error("SL0305", span,
                    required.Accessor is { } declared
                        ? $"'{classType.Name}' does not implement property " +
                          $"'{interfaceType.Name}.{declared.Name}'; add 'public {declared.Type.Name} " +
                          $"{declared.Name} {{ get;{(declared.Setter is null ? "" : " set;")} }}'"
                        : $"'{classType.Name}' does not implement '{interfaceType.Name}.{required.Name}'; " +
                          $"add 'public {required.ReturnType.Name} {required.Name}(" +
                          string.Join(", ", required.Parameters.Where(p => !p.IsThis)
                              .Select(p => p.Type.Name + " " + p.Name)) + ")'");
                continue;
            }

            if (!found.IsPublic)
            {
                diagnostics.Error("SL0306", found.Span,
                    $"'{classType.Name}.{found.Name}' implements " +
                    $"'{interfaceType.Name}.{required.Name}' and must therefore be public");
            }

            var wanted = required.Parameters.Where(p => !p.IsThis).ToList();
            var actual = found.Parameters.Where(p => !p.IsThis).ToList();

            // The mode is part of the match, not decoration on it. A method
            // taking an int cannot stand in for one taking a ref int: the two
            // are passed differently, and the vtable slot would hold a function
            // the caller is about to hand a pointer to.
            if (!found.ReturnType.Equals(required.ReturnType) ||
                wanted.Count != actual.Count ||
                !wanted.Zip(actual).All(pair =>
                    pair.First.Type.Equals(pair.Second.Type) &&
                    pair.First.Mode == pair.Second.Mode))
            {
                diagnostics.Error("SL0307", found.Span,
                    $"'{classType.Name}.{found.Name}' does not match " +
                    $"'{interfaceType.Name}.{required.Name}'; expected " +
                    $"'{required.ReturnType.Name} {required.Name}(" +
                    string.Join(", ", wanted.Select(Spelled)) + ")'");
            }
        }
    }

    /// <summary>A parameter as the source writes it, mode included.</summary>
    private static string Spelled(ParameterSymbol parameter) =>
        (parameter.Mode == ParameterMode.Ref ? "ref " :
         parameter.Mode == ParameterMode.In ? "in " : "") + parameter.Type.Name;

    /// <summary>
    /// Reads <c>[Packed]</c> and <c>[Align(N)]</c> onto a type, before pass 7
    /// lays it out.
    ///
    /// The cap is what the allocator can promise. <c>malloc</c> guarantees
    /// <c>max_align_t</c>, which is 16 on every target here, and a class holding
    /// an over-aligned field would be handed memory that does not honour it. A
    /// local could be aligned further, and a heap object could too once the
    /// runtime allocates by a type's alignment rather than by its size -- but
    /// half a rule is worse than a stated limit.
    /// </summary>
    private void ReadLayoutAttributes(NamedTypeSymbol type, SourceSpan span)
    {
        const int MaxAlignment = 16;

        if (type.Attributes.Any(a => a.Type == _builtins.Packed))
        {
            if (type is StructTypeSymbol and not VariantTypeSymbol) type.IsPacked = true;
            else
                diagnostics.Error("SL0463", span,
                    $"'[Packed]' lays out a struct with no padding, and '{type.Name}' is " +
                    (type is VariantTypeSymbol
                        ? "a variant, whose payload area is not a field the source arranged"
                        : "not a struct"));
        }

        if (type.Attributes.FirstOrDefault(a => a.Type == _builtins.Align) is not { } align) return;

        if (type is not StructTypeSymbol || type is VariantTypeSymbol)
        {
            diagnostics.Error("SL0464", span,
                $"'[Align]' applies to a struct; '{type.Name}' is not one");
            return;
        }

        int requested = align.Values.Count > 0 && align.Values[0] is { } value
            ? Convert.ToInt32(value, System.Globalization.CultureInfo.InvariantCulture)
            : 0;

        if (requested <= 0 || (requested & (requested - 1)) != 0)
        {
            diagnostics.Error("SL0465", span,
                $"'[Align({requested})]' is not an alignment; it must be a power of two");
            return;
        }

        if (requested > MaxAlignment)
        {
            diagnostics.Error("SL0466", span,
                $"'[Align({requested})]' is more than the {MaxAlignment} bytes the allocator " +
                "guarantees, so an object holding one of these would not honour it. " +
                $"{MaxAlignment} is the most that can be promised until the runtime allocates " +
                "by alignment as well as by size");
            return;
        }

        type.RequestedAlignment = requested;
    }

    /// <summary>
    /// Checks that nothing in a union is counted.
    ///
    /// A union does not record which member is live, so a copy would not know
    /// what to retain and a drop would not know what to release. Every other
    /// value type in the language answers both questions from its type alone;
    /// this is the one that cannot, which is why the reference is refused rather
    /// than the counting made conditional.
    /// </summary>
    private void CheckUnions()
    {
        foreach (var union in _modules.Values.SelectMany(m => m.Types.Values).OfType<UnionTypeSymbol>())
        {
            if (union.Fields.Count == 0)
                diagnostics.Error("SL0467", union.Span ?? default,
                    $"union '{union.Name}' has no members; a union is the choice between its " +
                    "members, so one with none has no values at all");

            foreach (var member in union.Fields.Where(f => f.Type.CarriesReferences()))
                diagnostics.Error("SL0468", union.Span ?? default,
                    $"'{union.Name}.{member.Name}' is '{member.Type.Name}', which holds a " +
                    "counted reference, and a union does not record which member is the live " +
                    "one -- so a copy could not know what to retain. Hold the reference beside " +
                    "the union, or use a 'variant', which does record it");
        }
    }
}
