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
/// The fully resolved program: what binding hands to lowering, and what
/// lowering hands to the emitter.
/// </summary>
public sealed record BoundProgram
{
    public required IReadOnlyList<ModuleSymbol> Modules { get; init; }
    public required IReadOnlyList<BoundFunction> Functions { get; init; }
    public required IReadOnlyList<ClassTypeSymbol> Classes { get; init; }
    public required IReadOnlyList<InterfaceTypeSymbol> Interfaces { get; init; }

    /// <summary>
    /// Every com interface the program mentions, so the emitter can write out
    /// the IID each one folded to and the vtables that point at it.
    /// </summary>
    public required IReadOnlyList<ComInterfaceTypeSymbol> ComInterfaces { get; init; }

    /// <summary>
    /// Every Objective-C class the program declares, imported or defined. None
    /// of them is in <see cref="Classes"/>: an objc object has no Stainless
    /// header, so nothing emitted for those may be emitted for these.
    /// </summary>
    public IReadOnlyList<ClassTypeSymbol> ObjCClasses { get; init; } = [];

    /// <summary>Every Objective-C protocol the program declares.</summary>
    public IReadOnlyList<ObjCProtocolTypeSymbol> ObjCProtocols { get; init; } = [];

    /// <summary>
    /// Every struct type the program uses: those declared in a module, and the
    /// instantiations of a generic one. An instantiation belongs to no module's
    /// type table, so without this the IR would name a type nothing defined.
    /// </summary>
    public required IReadOnlyList<StructTypeSymbol> Structs { get; init; }

    /// <summary>Every distinct array type used, each needing its own TypeInfo.</summary>
    public required IReadOnlyList<ArrayTypeSymbol> Arrays { get; init; }

    /// <summary>Runtime constructors for intrinsic classes, needing a declaration in the IR.</summary>
    public required IReadOnlyList<string> RuntimeFactories { get; init; }
    public required IReadOnlyList<FunctionSymbol> ExternalFunctions { get; init; }
    public FunctionSymbol? EntryPoint { get; init; }

    /// <summary>Module-level storage, in the order its initializers must run.</summary>
    public required IReadOnlyList<StaticSymbol> Statics { get; init; }

    /// <summary>The <c>static Name() { }</c> blocks.</summary>
    public required IReadOnlyList<FunctionSymbol> StaticConstructors { get; init; }

    /// <summary>
    /// Everything that runs before <c>Main</c>, in order: each static's
    /// initializer and each type's static constructor, a type's constructor
    /// after its own initializers and before anything that reads its statics.
    /// </summary>
    public required IReadOnlyList<StaticInitialization> Initialization { get; init; }

    /// <summary>
    /// Every file an <c>embed</c> carries into the binary, one per distinct
    /// object, in the order they were first bound.
    ///
    /// The emitter writes them and the driver reads them, because a file the
    /// program embeds is as much an input to the build as a source file is.
    /// </summary>
    public IReadOnlyList<EmbeddedFile> Embeds { get; init; } = [];

    /// <summary>
    /// True once <see cref="Lowering.Lowerer"/> has rewritten the bodies into
    /// the core the emitter handles. The emitter refuses a program that is not.
    /// </summary>
    public bool IsLowered { get; init; }

    /// <summary>
    /// Each static's initializer as lowered. A static's symbol keeps the one
    /// binding made, which is what the program says rather than how it runs.
    /// </summary>
    public IReadOnlyDictionary<StaticSymbol, BoundExpression> LoweredInitializers { get; init; } =
        new Dictionary<StaticSymbol, BoundExpression>();

    /// <summary>What a static is initialized with, as the emitter is to run it.</summary>
    public BoundExpression? InitializerOf(StaticSymbol shared) =>
        LoweredInitializers.TryGetValue(shared, out var lowered) ? lowered : shared.Initializer;
}

/// <summary>One step before <c>Main</c>: a static's initializer, or a type's static constructor.</summary>
public sealed record StaticInitialization(StaticSymbol? Static, FunctionSymbol? Constructor);

/// <summary>
/// Turns parsed files into a typed program.
///
/// The passes exist in this order for one reason: Stainless has no headers, so
/// nothing may depend on declaration order. Every name in the program is known
/// before any body is checked, which is exactly the guarantee a header file
/// exists to fake in C and C++.
/// </summary>
/// <param name="requireEntryPoint">
/// False when building a library, which has no <c>Main</c> and must not be
/// warned about one.
/// </param>
/// <param name="omittedModules">
/// The standard-library modules the program does not reach and so were never
/// parsed. A documentation link into one is not wrong, only out of sight.
/// </param>
public sealed partial class Binder(
    DiagnosticBag diagnostics,
    bool requireEntryPoint = true,
    CppAbi? cppAbi = null,
    IReadOnlyList<Driver.ModuleMetadata>? references = null,
    IReadOnlySet<string>? omittedModules = null)
{
    private readonly Builtins _builtins = new();

    /// <summary>The C++ ABI names are mangled and bit-fields laid out for, defaulting to the target's.</summary>
    private readonly CppAbi _cppAbi = cppAbi ?? TargetPlatform.Current.Abi;
    private readonly Dictionary<string, ModuleSymbol> _modules = new(StringComparer.Ordinal);
    private readonly List<(FileScope Scope, CompilationUnitSyntax Unit)> _units = [];
    private readonly List<BoundFunction> _functions = [];
    private readonly List<ClassTypeSymbol> _classes = [];
    private readonly List<InterfaceTypeSymbol> _interfaces = [];
    private readonly List<StructTypeSymbol> _structs = [];


    /// <summary>Every array type asked for, by element; each needs a TypeInfo.</summary>
    private readonly Dictionary<TypeSymbol, ArrayTypeSymbol> _arrays = [];
    private readonly Dictionary<(TypeSymbol Element, bool IsReadOnly), SliceTypeSymbol> _slices = [];

    /// <summary>Tuple types, by their element types.</summary>
    private readonly Dictionary<TypeList, TupleTypeSymbol> _tuples = [];

    /// <summary>Instantiated generics, keyed by template and type arguments.</summary>
    private readonly Dictionary<InstantiationKey, NamedTypeSymbol> _instantiatedTypes = [];
    private readonly Dictionary<InstantiationKey, FunctionSymbol> _instantiatedFunctions = [];

    /// <summary>
    /// Bodies already bound. An instantiated method is reachable both through its
    /// module's function list and through the pending queue, so without this it
    /// would be bound twice and emitted twice.
    /// </summary>
    private readonly HashSet<FunctionSymbol> _boundFunctions = [];

    /// <summary>
    /// Bodies to be bound, with the substitution they belong to, in the order
    /// they were asked for. Those before <see cref="_pendingBound"/> have been.
    /// </summary>
    private readonly List<(FunctionSymbol Function, Dictionary<string, TypeSymbol> Substitution)>
        _pending = [];
    private int _pendingBound;

    private int PendingCount => _pending.Count - _pendingBound;

    private readonly Dictionary<NamedTypeSymbol, (TypeDeclSyntax Declaration, FileScope Scope)> _typeSyntax = [];

    /// <summary>
    /// Declarations that add to a type already declared in the same module.
    ///
    /// Held by identity rather than by name: the point of the set is to tell
    /// one <em>declaration</em> from another of the same type, which is what
    /// decides whether a field in it is allowed.
    /// </summary>
    private readonly HashSet<TypeDeclSyntax> _additionalParts = [];

    /// <summary>
    /// The declaration a class takes its base list from, where that is not
    /// its first. At most one declaration of a type may write one.
    /// </summary>
    private readonly Dictionary<NamedTypeSymbol, (TypeDeclSyntax Declaration, FileScope Scope)> _baseListSyntax = [];

    /// <summary>
    /// The type each non-generic type, enum, delegate or closure declaration
    /// made, or added to.
    ///
    /// Every pass after the second finds a declaration's symbol here and never
    /// by its name. The name belongs to whichever declaration won it, so a
    /// lookup by name hands a declaration that lost -- SL0201, SL0550 -- a
    /// symbol of some other kind, or none at all. A declaration absent from
    /// this map is either a generic one, which is a template and has no type
    /// until something instantiates it, or one pass 2 reported and which has
    /// nothing more to say.
    /// </summary>
    private readonly Dictionary<Declaration, NamedTypeSymbol> _declaredTypes =
        new(ReferenceEqualityComparer.Instance);

    private readonly Dictionary<EnumTypeSymbol, (EnumDeclSyntax Declaration, FileScope Scope)> _enumSyntax = [];
    /// <summary>
    /// Keyed by <see cref="NamedTypeSymbol"/> rather than by delegate, because
    /// a <c>closure</c> is declared the same way and is a struct.
    /// </summary>
    private readonly Dictionary<NamedTypeSymbol, (DelegateDeclSyntax Declaration, FileScope Scope)> _delegateSyntax = [];
    /// <summary>
    /// Each static's declaration, and the substitution in force where it was
    /// declared. That last part is what lets a static of <c>Box&lt;int&gt;</c>
    /// bind an initializer that mentions <c>T</c>: it is bound long after the
    /// instantiation made it, by which time nothing else remembers what T was.
    /// </summary>
    private readonly Dictionary<StaticSymbol,
        (StaticDeclSyntax Declaration, FileScope Scope,
         Dictionary<string, TypeSymbol> Substitution)> _staticSyntax = [];

    /// <summary>
    /// Statics whose initializer has been bound. The table above is added to
    /// while it is being drained -- instantiating a generic declares its
    /// statics -- so binding is by difference rather than by one walk.
    /// </summary>
    private readonly HashSet<StaticSymbol> _boundStatics = [];
    private List<StaticSymbol> _staticOrder = [];
    private List<StaticInitialization> _initialization = [];

    /// <summary>
    /// Module-level storage that crosses to C. Kept apart because the ordering
    /// pass walks initializers, and an imported variable has none -- it would
    /// otherwise never reach the emitter that has to declare it.
    /// </summary>
    private readonly List<StaticSymbol> _foreignVariables = [];
    private readonly List<FunctionSymbol> _staticConstructors = [];

    /// <summary>
    /// Numbers the hidden locals a lowering introduces. A '$' cannot appear in a
    /// source identifier, and the counter keeps nested lowerings of the same
    /// construct from colliding with one another.
    /// </summary>
    private int _synthetic;

    private string SyntheticName(string hint) => $"${hint}.{_synthetic++}";

    /// <summary>
    /// The simple name of the type whose members are being declared, or null.
    ///
    /// It is what lets a bare `Inner` inside `Outer` find `Outer.Inner` during
    /// pass 4, when there is no function to ask.
    /// </summary>
    private string? _declaringType;

    public BoundProgram Bind(IReadOnlyList<CompilationUnitSyntax> units)
    {
        _builtins.RegisterInto(_modules);

        // A referenced library's declarations come first, so a source file can
        // name them exactly as it names anything else. This runs before pass 1
        // rather than as one of them: it declares rather than resolves, and a
        // program with no references skips it entirely.
        if (references is { Count: > 0 })
        {
            var loader = new MetadataLoader(
                diagnostics, _builtins,
                (element, readOnly) => SliceOf(element, readOnly),
                elements => TupleOf(elements));
            loader.RegisterIntrinsics(_modules.Values);
            loader.Load(references, _modules);

            // A library's events are events here too, so `+=` on one has to
            // find them. Without this the name is not in the set the
            // subscription probe asks first, and the access falls through to
            // being read -- which an event cannot be.
            foreach (var declared in _modules.Values
                         .SelectMany(m => m.Types.Values)
                         .SelectMany(t => t.Events))
            {
                _eventNames.Add(declared.Name);

                // And its storage type has to be one this compilation emits a
                // TypeInfo for. `new Publisher()` here allocates the whole
                // object, events included, so the empty array is built on this
                // side -- and an array's TypeInfo is emitted only for the
                // element types something asked for.
                ArrayOf(declared.Type);
            }
        }

        DeclareModules(units);      // pass 1: every module exists
        DeclareTypes();             // pass 2: every type name exists
        ResolveImports();           // pass 3: every module can see its imports
        DeclareMembers();           // pass 4: every signature and field type is resolved
        ResolveInterfaces();        // pass 5: every class satisfies what it claims
        _interfacesResolved = true;
        RunDeferredConstraintChecks();
        CheckConstraintDeclarations();
        CheckVarianceDeclarations();
                                    //         and every 'where' clause could be met
        ResolveAttributes();        // pass 6: attributes fold to constants
        CheckObjCClasses();         //         and every objc class is one the runtime can find
        SettleLayoutsWaitingForAttributes();
        CheckActivatableClasses();  //         and a CLSID says who can be made
        ComputeLayouts();           // pass 7: every value type has a size
        CheckUnions();              //         and a union counts nothing
        ValidateLinkageSignatures();// pass 8: no counted reference crosses a language boundary
        CheckForeignNames();        //         and one C name is one function
        CheckConversions();         //         and no declared conversion restates one
        SynthesizeInitializerConstructors();
                                    //         and a class with field initializers has somewhere
                                    //         to run them
        BindParameterDefaults();    //         and every default in a signature is a constant
        BindBodies();               // pass 9: only now is any code checked
        BindStatics();              // pass 10: static initializers
        DrainPending();             // pass 11: bodies of everything instantiated along the way,
                                    //          the statics that came with them, and their order
        NumberGenericVirtualSlots();//          and a slot for each dispatched generic instantiation
        BuildVarianceTables();      //          and a table for each interface a class stands for
        CheckConstructorDelegation();
        CheckClassesWithoutConstructors();
        CheckConstructorsAssignFields();
        ResolveRemainingAliases();
        CheckDocumentation();       //          and every '@tag' says something true

        // Last, because both halves of the question need every body bound: a
        // member may be captured in one file and written in another.
        ReportCapturedMembersThatChange();
        ReportReadOnlyReceiversWritten();

        SealLocalFunctions();

        // Interface ids are assigned last, because instantiating a generic can
        // introduce a new interface at any point up to here.
        for (int id = 0; id < _interfaces.Count; id++) _interfaces[id].Id = id;

        var external = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Linkage.IsImport() || f.IsExternal)
            .GroupBy(f => f.MangledName)
            .Select(g => g.First())
            .ToList();

        var program = new BoundProgram
        {
            Modules = _modules.Values.ToList(),
            Functions = _functions,
            Classes = _classes,
            Interfaces = _interfaces,
            ComInterfaces = _comInterfaces,
            ObjCClasses = _objcClasses,
            ObjCProtocols = _objcProtocols,
            Structs = _modules.Values
                .SelectMany(m => m.Types.Values)
                .OfType<StructTypeSymbol>()
                .Concat(_structs)
                .ToList(),
            Arrays = _arrays.Values.ToList(),
            RuntimeFactories = _modules.Values
                .SelectMany(m => m.Types.Values)
                .OfType<ClassTypeSymbol>()
                .Select(c => c.RuntimeFactory)
                .OfType<string>()
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToList(),
            ExternalFunctions = external,
            EntryPoint = requireEntryPoint ? FindEntryPoint() : null,
            Statics = _staticOrder,
            StaticConstructors = _staticConstructors,
            Initialization = _initialization,
            Embeds = _embeds.Values.OrderBy(e => e.Index).ToList(),
        };

        // A tree with an error in it is allowed to be unfinished, and is never
        // lowered or emitted.
        if (BoundTreeVerifier.IsEnabled && !diagnostics.HasErrors)
            BoundTreeVerifier.Verify(program, BoundTreeForm.Semantic);

        return program;
    }

}
