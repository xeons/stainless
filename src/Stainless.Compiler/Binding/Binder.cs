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

/// <summary>The fully resolved program handed to the emitter.</summary>
public sealed class BoundProgram
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

    /// <summary>
    /// The <c>static Name() { }</c> blocks, in declaration order, to run after
    /// every static field has its value.
    /// </summary>
    public required IReadOnlyList<FunctionSymbol> StaticConstructors { get; init; }
}

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
public sealed partial class Binder(
    DiagnosticBag diagnostics,
    bool requireEntryPoint = true,
    CppAbi? cppAbi = null,
    IReadOnlyList<Driver.ModuleMetadata>? references = null)
{
    private readonly Builtins _builtins = new();

    /// <summary>The C++ ABI names are mangled for, defaulting to the host's.</summary>
    private readonly CppAbi _cppAbi = cppAbi ?? CppMangler.HostAbi;
    private readonly Dictionary<string, ModuleSymbol> _modules = new(StringComparer.Ordinal);
    private readonly List<(FileScope Scope, CompilationUnitSyntax Unit)> _units = [];
    private readonly List<BoundFunction> _functions = [];
    private readonly List<ClassTypeSymbol> _classes = [];
    private readonly List<InterfaceTypeSymbol> _interfaces = [];
    private readonly List<StructTypeSymbol> _structs = [];

    /// <summary>
    /// Which case each variant in scope is known to be holding. A fact is put
    /// here by a condition that tested one, and taken away by anything that
    /// could have changed it.
    /// </summary>
    private Dictionary<object, Fact> _variantFacts = [];
    private readonly Dictionary<TypeSymbol, ArrayTypeSymbol> _arrays = [];
    private readonly Dictionary<TypeSymbol, SliceTypeSymbol> _slices = [];

    /// <summary>
    /// Tuple types, by their element types written out. Keyed by name rather
    /// than by the list, because two lists of the same types are two objects
    /// and one type.
    /// </summary>
    private readonly Dictionary<string, TupleTypeSymbol> _tuples = new(StringComparer.Ordinal);

    /// <summary>Instantiated generics, keyed by template and type arguments.</summary>
    private readonly Dictionary<string, NamedTypeSymbol> _instantiatedTypes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, FunctionSymbol> _instantiatedFunctions = new(StringComparer.Ordinal);

    /// <summary>
    /// Bodies already bound. An instantiated method is reachable both through its
    /// module's function list and through the pending queue, so without this it
    /// would be bound twice and emitted twice.
    /// </summary>
    private readonly HashSet<FunctionSymbol> _boundFunctions = [];

    /// <summary>Bodies awaiting binding, with the substitution they belong to.</summary>
    private readonly Queue<(FunctionSymbol Function, Dictionary<string, TypeSymbol> Substitution)> _pending = new();

    /// <summary>The type arguments in force while binding inside an instantiation.</summary>
    private Dictionary<string, TypeSymbol> _substitution = new(StringComparer.Ordinal);
    private readonly Dictionary<NamedTypeSymbol, (TypeDeclSyntax Declaration, FileScope Scope)> _typeSyntax = [];

    /// <summary>
    /// Declarations that add to a type already declared in the same module.
    ///
    /// Held by identity rather than by name: the point of the set is to tell
    /// one <em>declaration</em> from another of the same type, which is what
    /// decides whether a field in it is allowed.
    /// </summary>
    private readonly HashSet<TypeDeclSyntax> _additionalParts = [];
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

    /// <summary>How many 'parallel' scopes enclose what is being bound.</summary>
    private int _parallelDepth;

    private string SyntheticName(string hint) => $"${hint}.{_synthetic++}";

    // Per-function binding state.
    private FunctionSymbol? _currentFunction;

    /// <summary>The file being bound. Imports are per-file, so this is the unit of lookup.</summary>
    private FileScope? _currentScope;
    private ModuleSymbol? _currentModule => _currentScope?.Module;
    private readonly List<Dictionary<string, LocalSymbol>> _scopes = [];
    private int _loopDepth;

    /// <summary>
    /// How many <c>switch</c> statements enclose what is being bound. Separate
    /// from the loop depth because a switch is a target for <c>break</c> but not
    /// for <c>continue</c>, which passes straight through it to the loop.
    /// </summary>
    private int _switchDepth;

    /// <summary>
    /// Every <c>goto</c> target in the function being bound, by name.
    ///
    /// Labels are per function, not per block, so this is cleared with the rest
    /// of the per-function state. A name lands here from whichever comes first,
    /// the label or a jump to it, because a jump forwards names one that does
    /// not exist yet.
    /// </summary>
    private readonly Dictionary<string, LabelSymbol> _labels = new(StringComparer.Ordinal);

    /// <summary>
    /// The scope depth of the function body's own block, which is the one depth
    /// a label may be written at. See <c>BindLabel</c> for why.
    /// </summary>
    private int _bodyDepth;

    /// <summary>
    /// The simple name of the type whose members are being declared, or null.
    ///
    /// It is what lets a bare `Inner` inside `Outer` find `Outer.Inner` during
    /// pass 4, when there is no function to ask.
    /// </summary>
    private string? _declaringType;

    /// <summary>
    /// Whether <c>+</c>, <c>-</c> and <c>*</c> on integers are being asked to
    /// notice that they overflowed. False everywhere but inside
    /// <c>checked</c>: wrapping is the language's defined default (§9).
    /// </summary>
    private bool _checkedArithmetic;

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
                element => SliceOf(element),
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
        ResolveAttributes();        // pass 6: attributes fold to constants
        ComputeLayouts();           // pass 7: every value type has a size
        CheckUnions();              //         and a union counts nothing
        ValidateLinkageSignatures();// pass 8: no counted reference crosses a language boundary
        BindBodies();               // pass 9: only now is any code checked
        BindStatics();              // pass 10: static initializers
        DrainPending();             // pass 11: bodies of everything instantiated along the way,
                                    //          the statics that came with them, and their order
        CheckConstructorDelegation();
        ResolveRemainingAliases();

        // Last, because both halves of the question need every body bound: a
        // member may be captured in one file and written in another.
        ReportCapturedMembersThatChange();

        // Interface ids are assigned last, because instantiating a generic can
        // introduce a new interface at any point up to here.
        for (int id = 0; id < _interfaces.Count; id++) _interfaces[id].Id = id;

        var external = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Linkage.IsImport() || f.IsExternal)
            .GroupBy(f => f.MangledName)
            .Select(g => g.First())
            .ToList();

        return new BoundProgram
        {
            Modules = _modules.Values.ToList(),
            Functions = _functions,
            Classes = _classes,
            Interfaces = _interfaces,
            ComInterfaces = _comInterfaces,
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
        };
    }

}
