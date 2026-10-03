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

public enum FunctionKind { Function, Method, Constructor, Destructor, StaticConstructor }

public sealed class ParameterSymbol(string name, TypeSymbol type, int index)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public int Index { get; } = index;

    /// <summary>
    /// Whether the caller's storage is passed rather than a copy of it. A
    /// <c>ref</c> or <c>in</c> parameter is one pointer at the ABI, and inside
    /// the callee it is the caller's variable: reading it reads that, and
    /// writing through a <c>ref</c> writes that.
    /// </summary>
    public Syntax.ParameterMode Mode { get; init; } = Syntax.ParameterMode.Value;

    /// <summary>True when this is passed by address rather than by value.</summary>
    public bool IsByReference => Mode != Syntax.ParameterMode.Value;

    /// <summary>True for the implicit receiver of a method, constructor or destructor.</summary>
    public bool IsThis { get; init; }

    /// <summary>
    /// For a parameter no source wrote -- the value of a variable a local
    /// function reads from around it -- that variable: a local, or the
    /// parameter it came from. Null for every other parameter.
    /// </summary>
    public object? CaptureOrigin { get; init; }

    /// <summary>Where it was written, for a diagnostic about the parameter itself.</summary>
    public Source.SourceSpan? DeclaredSpan { get; init; }

    /// <summary>
    /// The <c>= value</c> a caller may leave out, as written.
    ///
    /// It is kept as syntax because a signature is resolved in pass 4, before
    /// any constant has been folded: a default naming a <c>const</c> from
    /// another module would have nothing to read yet. What it is worth is
    /// settled in a pass of its own, and lands in <see cref="Default"/>.
    /// </summary>
    public Syntax.ExpressionSyntax? DefaultSyntax { get; init; }

    /// <summary>
    /// What a call that leaves this parameter out passes instead, or null when
    /// there is no default.
    ///
    /// Always a constant, so the one expression can stand at every call site
    /// that omitted it: a call site is where it is emitted, exactly as if it
    /// had been written there. That is also the rule that makes the default a
    /// property of the declaration the caller can see rather than of the one
    /// that runs -- an <c>override</c> may not restate it.
    /// </summary>
    public BoundExpression? Default { get; set; }

    /// <summary>Whether a call may leave this parameter out.</summary>
    public bool IsOptional => DefaultSyntax is not null || Default is not null;

    /// <summary>
    /// Declared <c>params</c>: a call may give the elements one by one. Only
    /// the last parameter may be, and only a <c>T[]</c> or a <c>Span&lt;T&gt;</c>.
    /// </summary>
    public bool IsParams { get; init; }

    /// <summary>What one element of a <c>params</c> parameter is, or null.</summary>
    public TypeSymbol? ParamsElement => !IsParams ? null : Type switch
    {
        ArrayTypeSymbol array => array.Element,
        SliceTypeSymbol slice => slice.Element,
        _ => null,
    };

    /// <summary>
    /// True when the body writes to this parameter, or to something inside it.
    ///
    /// A parameter is borrowed, so ordinarily it owns nothing and costs no
    /// reference traffic. Writing to one breaks that: the release of what was
    /// there would fall on a reference the caller still owns. So a parameter
    /// that is written to is retained on entry and released on exit, becoming
    /// the private copy the write already assumed it was.
    /// </summary>
    public bool IsAssigned { get; set; }

    public override string ToString() =>
        (Mode == Syntax.ParameterMode.Ref ? "ref " :
         Mode == Syntax.ParameterMode.Out ? "out " :
         Mode == Syntax.ParameterMode.In ? "in " : "") + $"{Type.Name} {Name}";
}

public sealed class LocalSymbol(string name, TypeSymbol type, bool isConst)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public bool IsConst { get; } = isConst;
    public override string ToString() => $"{Type.Name} {Name}";
}

/// <summary>
/// A <c>goto</c> target. One per label per function, made by whichever of the
/// two the binder meets first: a jump forwards names a label that has not been
/// bound yet, and a jump backwards names one that has. A switch section that a
/// <c>goto case</c> names has one too, with no name a jump could write.
/// </summary>
public sealed class LabelSymbol(string name)
{
    public string Name { get; } = name;

    /// <summary>Where the label itself is, once it has been seen.</summary>
    public SourceSpan? Declared { get; set; }

    /// <summary>
    /// The block the label is in, as the binder's scope for it. A jump reaches
    /// the label only from inside this block.
    /// </summary>
    public object? Block { get; set; }

    /// <summary>Where the first jump to it is, for the error when it is never declared.</summary>
    public SourceSpan? FirstUse { get; set; }

    public bool IsUsed { get; set; }

    /// <summary>
    /// True for a label lowering made, which every jump to it reaches from
    /// before it. Nothing can run a declaration twice by jumping there.
    /// </summary>
    public bool IsForwardOnly { get; init; }

    public override string ToString() => Name + ":";
}

public sealed class FunctionSymbol
{
    public required string Name { get; init; }
    public required string ModuleName { get; init; }
    public required TypeSymbol ReturnType { get; init; }
    public required LinkageKind Linkage { get; init; }

    /// <summary>
    /// The convention written on the declaration, or
    /// <see cref="Syntax.CallingConvention.Default"/>.
    ///
    /// It decides two things and only on x86: which LLVM calling convention the
    /// declaration and every call to it carry, and how the linker name is
    /// decorated. On a 64-bit target only <c>__vectorcall</c> is anything but a
    /// note to the reader.
    ///
    /// Settable because a com interface's slots get one that nobody wrote: on
    /// x86 every method of a COM vtable is <c>__stdcall</c>, and that is
    /// stamped on when the table is numbered rather than repeated at each of
    /// the four places a slot's symbol can be built.
    /// </summary>
    public Syntax.CallingConvention CallingConvention { get; set; }

    /// <summary>
    /// The <c>///</c> block written above the declaration, or null. Carried so
    /// that a documentation writer has the prose beside the resolved signature
    /// rather than having to go back to the source for it.
    /// </summary>
    public string? Documentation { get; init; }

    public FunctionKind Kind { get; init; } = FunctionKind.Function;
    public NamedTypeSymbol? ContainingType { get; init; }
    public bool IsPublic { get; init; }
    public bool IsVariadic { get; init; }

    /// <summary>
    /// Visible to this type and anything deriving from it, wherever that is.
    /// Never true at the same time as <see cref="IsPublic"/>.
    /// </summary>
    public bool IsProtected { get; init; }

    /// <summary>Declared <c>virtual</c>, <c>override</c> or <c>abstract</c>.</summary>
    public bool IsVirtual { get; init; }

    /// <summary>Declared <c>override</c>: it replaces something inherited.</summary>
    public bool IsOverride { get; init; }

    /// <summary>Declared <c>abstract</c>: no body, and a derived class must supply one.</summary>
    public bool IsAbstract { get; init; }

    /// <summary>Declared <c>sealed</c>: an override nothing may override further.</summary>
    public bool IsSealed { get; init; }

    /// <summary>
    /// True for a conversion operator: it converts its one parameter to its
    /// return type. <see cref="IsImplicitConversion"/> says whether a cast has
    /// to be written for it to run.
    /// </summary>
    public bool IsConversion { get; init; }

    /// <summary>True when the conversion was written <c>implicit</c>.</summary>
    public bool IsImplicitConversion { get; init; }

    /// <summary>
    /// Declared <c>static</c>: it belongs to the type, not to an instance.
    ///
    /// The whole of it is the missing receiver. There is no <c>this</c>
    /// parameter, so the body cannot reach a field, and a call names the type
    /// rather than a value. That is what lets a type own the function that
    /// makes one -- <c>FileStream.Open</c> can report why it failed, where a
    /// constructor can only leave the object holding nothing.
    /// </summary>
    public bool IsStatic { get; init; }

    /// <summary>
    /// Position in the class's vtable, or -1 for a method reached by name.
    ///
    /// Assigned once per class, root downwards, so an override lands in the slot
    /// it replaces and a new virtual is appended after everything inherited.
    /// That is what makes a call through a base reference reach the derived
    /// body: the slot number is a property of the declaration, not of the
    /// receiver's static type.
    /// </summary>
    public int VirtualSlot { get; set; } = -1;

    /// <summary>The inherited method this one replaces, or null.</summary>
    public FunctionSymbol? Overridden { get; set; }

    /// <summary>
    /// The interface named in front of this member -- <c>IShape</c> in
    /// <c>void IShape.Draw()</c> -- or null. Such a member is reached only
    /// through that interface.
    /// </summary>
    public InterfaceTypeSymbol? ExplicitInterface { get; set; }

    /// <summary>
    /// For a member written under an interface's name, the member of that
    /// interface whose slot it fills. Settled in pass 5.
    /// </summary>
    public FunctionSymbol? ImplementedMember { get; set; }

    /// <summary>True when a call to this goes through the vtable.</summary>
    public bool IsDispatched => VirtualSlot >= 0;

    public List<ParameterSymbol> Parameters { get; } = [];

    /// <summary>
    /// A local function's hidden parameters while its body is bound: one per
    /// variable it reads from around it. They join <see cref="Parameters"/>
    /// once every body is bound, which is what the emitter sees.
    /// </summary>
    public List<ParameterSymbol> Captures { get; } = [];

    /// <summary>
    /// For a function declared in a block, where it was declared --
    /// <c>Main.Square</c> -- which is the name it is linked under. Null for
    /// every other function.
    /// </summary>
    public string? LocalPath { get; init; }

    /// <summary>
    /// The declared parameter types, without the implicit receiver. This is
    /// what distinguishes one overload from another, and what an interface
    /// requirement is matched against.
    /// </summary>
    public IEnumerable<TypeSymbol> ParameterTypes =>
        Parameters.Where(p => !p.IsThis).Select(p => p.Type);

    /// <summary>True when this takes exactly these parameter types.</summary>
    public bool Accepts(IReadOnlyList<TypeSymbol> parameters) =>
        ParameterTypes.SequenceEqual(parameters);

    /// <summary>The body to bind, or null for an <c>extern "C"</c> declaration.</summary>
    public BlockSyntax? Body { get; init; }

    /// <summary>
    /// A member's own <c>where</c>, constraining its generic type's
    /// parameters: <c>void Clear() where T : zeroable</c>. Empty for most.
    /// </summary>
    public IReadOnlyList<WhereClauseSyntax> MemberConstraints { get; init; } = [];

    /// <summary>
    /// Why this member of an instantiation does not exist, or null when it
    /// does: its type's arguments fail its own <c>where</c>. Its body is never
    /// bound, and a call to it is SL0816.
    /// </summary>
    public string? Unavailable { get; set; }

    /// <summary>
    /// <c>[DoesNotReturn]</c>: a call to this never comes back, so nothing
    /// after it is reached.
    /// </summary>
    public bool DoesNotReturn { get; set; }

    /// <summary>Where the declaration came from, for diagnostics.</summary>
    public required Source.SourceSpan Span { get; init; }

    /// <summary>
    /// For built-ins: the exact symbol implemented in the runtime. Set, it
    /// bypasses mangling entirely, so <c>String.ByteLength</c> lowers straight
    /// to <c>sl_string_byte_length</c>.
    /// </summary>
    public string? RuntimeSymbol { get; init; }

    /// <summary>
    /// The type arguments this function was instantiated with. They take part in
    /// mangling, so <c>Max&lt;int&gt;</c> and <c>Max&lt;double&gt;</c> stay
    /// distinct symbols even when the parameters alone would not tell them apart.
    /// </summary>
    public IReadOnlyList<TypeSymbol> TypeArguments { get; init; } = [];

    /// <summary>The template this was instantiated from, or null.</summary>
    public GenericFunctionTemplate? Template { get; init; }

    /// <summary>
    /// For an instantiation, the call that first asked for it, and the function
    /// that call was in. A diagnostic about a type argument follows these out of
    /// the standard library to the program's own call.
    /// </summary>
    public SourceSpan? InstantiatedAt { get; init; }

    public FunctionSymbol? InstantiatedBy { get; init; }

    /// <summary>
    /// The file this was declared in. A module may span files with different
    /// imports, so a body must be bound against its own file's view.
    /// </summary>
    public FileScope? Scope { get; init; }

    /// <summary>The property this is the getter or setter of, or null.</summary>
    public PropertySymbol? Accessor { get; set; }

    /// <summary>The event this subscribes to or unsubscribes from, or null.</summary>
    public EventSymbol? Event { get; set; }

    /// <summary>Which of the two it is. Meaningless unless <see cref="Event"/> is set.</summary>
    public bool IsEventAdd { get; init; }

    /// <summary>
    /// True when the body is the compiler's rather than the programmer's: the
    /// <c>get;</c> and <c>set;</c> of an automatic property, which read and
    /// write the hidden field and do nothing else.
    /// </summary>
    public bool IsAutoAccessor { get; init; }

    /// <summary>
    /// True for an <c>init</c> accessor: a setter only an object initializer,
    /// a <c>with</c>, a constructor or another <c>init</c> accessor of the
    /// object being made may call.
    /// </summary>
    public bool IsInitAccessor { get; init; }

    /// <summary>
    /// A constructor marked <c>[SetsRequiredMembers]</c>: a <c>new</c> that
    /// runs it need not name the type's <c>required</c> members.
    /// </summary>
    public bool SetsRequiredMembers { get; init; }

    /// <summary>The constructor a primary parameter list stands for.</summary>
    public bool IsPrimaryConstructor { get; init; }

    private string? _mangledName;

    /// <summary>The symbol name the linker sees. See docs/abi.md.</summary>
    /// <summary>
    /// The enclosing C++ namespace, for a declaration with C++ linkage.
    /// </summary>
    public IReadOnlyList<string> CppNamespace { get; set; } = [];

    /// <summary>
    /// The linker name, when something other than this compiler decides it.
    ///
    /// A C++ name is mangled by a scheme that depends on the target, so it is
    /// computed once the ABI is known and stamped here rather than derived on
    /// demand the way a Stainless name is.
    /// </summary>
    public string? ForeignName { get; set; }

    /// <summary>
    /// True for a function this program calls but does not contain: it came
    /// from a referenced library's metadata, so it is declared to the emitter
    /// and never defined by it.
    /// </summary>
    public bool IsExternal { get; init; }

    /// <summary>
    /// The enum whose members' names this writes, or null. Such a function has
    /// no body and no declaration: the emitter writes one for each enum a
    /// program formats, as a switch over the enum's values.
    /// </summary>
    public EnumTypeSymbol? TextOfEnum { get; init; }

    /// <summary>
    /// The property this accessor belongs to, as the metadata named it. The
    /// property symbol itself is rebuilt from the accessor pair afterwards.
    /// </summary>
    public string? MetadataAccessor { get; init; }

    public string MangledName =>
        _mangledName ??= ForeignName ?? RuntimeSymbol ?? Mangler.Mangle(this);

    // An event's accessors are generated rather than written, so they
    // have a body without having syntax -- but only where they were
    // generated. The same two methods arriving from a referenced library
    // are external declarations, and the library has the code.
    public bool HasBody =>
        Body is not null || IsAutoAccessor || IsRecordClone || (Event is not null && !IsExternal);

    /// <summary>A record's <c>$Clone</c>, whose body is generated as bound nodes.</summary>
    public bool IsRecordClone { get; init; }

    // ------------------------------------------------------------- Objective-C

    /// <summary>
    /// The selector a call to this sends, for a member of an objc type that
    /// names one; null for everything else, which is called directly.
    /// </summary>
    public string? Selector { get; set; }

    /// <summary>True for a member reached by sending its selector.</summary>
    public bool IsMessage => Selector is not null;

    /// <summary>
    /// Declared to return <c>Self</c>, Objective-C's <c>instancetype</c>: at a
    /// call the result has the receiver's static type.
    /// </summary>
    public bool ReturnsSelf { get; set; }

    /// <summary><c>[Optional]</c> on a protocol member: an object may not answer it.</summary>
    public bool IsObjCOptional { get; set; }

    /// <summary>
    /// An object result arrives retained: the selector is in the <c>alloc</c>,
    /// <c>new</c>, <c>copy</c>, <c>mutableCopy</c> or <c>init</c> family, or
    /// <c>[ReturnsRetained]</c> says so. Otherwise it arrives +0 and the caller
    /// claims it.
    /// </summary>
    public bool ReturnsRetained { get; set; }

    /// <summary>An <c>init</c> method: a call consumes its receiver.</summary>
    public bool ConsumesSelf { get; set; }

    /// <summary>
    /// For a constructor of a class defined here, the init message
    /// Objective-C makes the object with: its <c>[Selector]</c>, or
    /// <c>init</c> for one that takes nothing. Null for one that only
    /// <c>new</c> reaches.
    ///
    /// Kept apart from <see cref="Selector"/>: a constructor is called
    /// directly from Stainless, and only its IMP answers the message.
    /// </summary>
    public string? InitSelector { get; set; }

    /// <summary>
    /// The method a class defined here runs its field initializers in, which
    /// the runtime calls through <c>.cxx_construct</c> as it allocates.
    /// </summary>
    public bool IsObjCFieldInitializer { get; init; }

    public override string ToString() =>
        $"{ReturnType.Name} {(ContainingType is null ? "" : ContainingType.Name + ".")}{Name}" +
        $"({string.Join(", ", Parameters.Where(p => !p.IsThis))})";
}

/// <summary>
/// A property: field-shaped syntax over a pair of methods.
///
/// The getter and setter are ordinary <see cref="FunctionSymbol"/>s, which is
/// the whole trick. A property therefore costs nothing new in the ABI, occupies
/// vtable slots like any other method when an interface declares it, and needs
/// no support at all in the emitter. Only an automatic property owns storage,
/// and that storage is an ordinary field the source cannot name.
/// </summary>
public sealed class PropertySymbol
{
    public required string Name { get; init; }
    public required TypeSymbol Type { get; init; }
    public required NamedTypeSymbol ContainingType { get; init; }
    public required Source.SourceSpan Span { get; init; }

    /// <summary>
    /// The <c>///</c> block written above the declaration, or null. Carried so
    /// that a documentation writer has the prose beside the resolved signature
    /// rather than having to go back to the source for it.
    /// </summary>
    public string? Documentation { get; init; }
    public bool IsPublic { get; init; }
    public bool IsProtected { get; init; }

    public FunctionSymbol? Getter { get; set; }
    public FunctionSymbol? Setter { get; set; }

    /// <summary>
    /// True for <c>this[...]</c>: a property whose accessors take arguments,
    /// reached by writing <c>a[i]</c> rather than by name.
    /// </summary>
    public bool IsIndexer { get; init; }

    /// <summary>The generated storage of an automatic property; null otherwise.</summary>
    public FieldSymbol? BackingField { get; set; }

    /// <summary>
    /// The generated storage of a static property that owns one: a static
    /// named so that no source can reach it. Null otherwise.
    /// </summary>
    public StaticSymbol? StaticBacking { get; set; }

    /// <summary>Attributes written on the property, shared with its backing field.</summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    /// <summary>Declared <c>required</c>: every <c>new</c> must give it a value.</summary>
    public bool IsRequired { get; init; }

    /// <summary>True when the setter is <c>init</c>.</summary>
    public bool IsInit => Setter?.IsInitAccessor == true;

    /// <summary>The interface named in front of it, as on a method; or null.</summary>
    public InterfaceTypeSymbol? ExplicitInterface { get; init; }

    /// <summary>True when the compiler supplies both the storage and the accessors.</summary>
    public bool IsAuto => BackingField is not null || StaticBacking is not null;

    public override string ToString() => $"{ContainingType.Name}.{Name}";
}

/// <summary>
/// An event: a list of subscribers that reads like a closure.
///
/// It is a near-twin of an automatic property — hidden storage plus two
/// generated methods — and differs in the one way that matters: a property's
/// accessors *are* its meaning, where an event's exist to keep everything else
/// away from the storage. Outside the declaring type, <c>+=</c> and <c>-=</c>
/// are the only things that can be written.
///
/// The storage is an array rather than a list, and <see cref="Add"/> and
/// <see cref="Remove"/> replace it rather than mutate it. That is what makes
/// raising safe against a handler that unsubscribes while it runs: the raise
/// took the array once, and what it is walking is no longer what the event
/// holds.
/// </summary>
public sealed class EventSymbol
{
    public required string Name { get; init; }

    /// <summary>The closure type a subscriber must be.</summary>
    public required ClosureTypeSymbol Type { get; init; }

    public required NamedTypeSymbol ContainingType { get; init; }
    public required Source.SourceSpan Span { get; init; }

    public bool IsPublic { get; init; }
    public bool IsProtected { get; init; }
    public bool IsStatic { get; init; }

    /// <summary>The generated <c>T[]</c> holding the subscribers, in order.</summary>
    public FieldSymbol? BackingField { get; set; }

    public FunctionSymbol? Add { get; set; }
    public FunctionSymbol? Remove { get; set; }

    /// <summary>
    /// <c>addweak_Name</c>: what <c>+=</c> calls when the subscriber is the
    /// object doing the subscribing. It holds that object weakly, so a form
    /// subscribed to its own button does not keep itself alive through it.
    /// Null for an event loaded from a library that predates it, where
    /// <c>+=</c> falls back to <see cref="Add"/>.
    /// </summary>
    public FunctionSymbol? AddWeak { get; set; }

    /// <summary>
    /// <c>weakcall_Name</c>: the function a weak subscription's closure holds.
    /// It loads the subscriber through the runtime's cell and calls it only if
    /// it is alive. Private and static; it never crosses a library boundary,
    /// because the accessors that compare against its address are declared
    /// alongside it.
    /// </summary>
    public FunctionSymbol? WeakCall { get; set; }

    /// <summary>
    /// The method a raise lowers to, holding the loop over the subscribers.
    ///
    /// A method rather than a loop inlined at each site, so that "what raising
    /// means" is written once -- including the part that matters, which is that
    /// it reads the array before it starts and walks what it read.
    /// </summary>
    public FunctionSymbol? Raise { get; set; }

    public List<AppliedAttribute> Attributes { get; } = [];

    public override string ToString() => $"{ContainingType.Name}.{Name}";
}

/// <summary>
/// Module-level storage, initialized once before <c>Main</c> runs.
///
/// Unlike a <see cref="ConstantSymbol"/> this has an address and a real
/// initializer, so the order the initializers run in matters. Because Stainless
/// compiles the whole program at once, that order is computed rather than
/// guessed: see the topological sort in the binder.
/// </summary>
public sealed class StaticSymbol(string name, TypeSymbol type, string moduleName)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public string ModuleName { get; } = moduleName;
    public bool IsPublic { get; init; }

    /// <summary>
    /// True for the storage of a static automatic property. Its name ends in
    /// <c>$</c>, which no identifier may, so only the accessors reach it.
    /// </summary>
    public bool IsPropertyStorage { get; init; }

    /// <summary>
    /// A property's storage its accessors read only to fill with
    /// <c>field ??= ...</c>, so it may start empty whatever its type says.
    /// </summary>
    public bool IsFilledOnFirstUse { get; init; }

    /// <summary>What a diagnostic calls it: the property, for a property's storage.</summary>
    public string DisplayName => IsPropertyStorage ? Name[..^1] : Name;

    /// <summary>
    /// What was written in brackets in front of it. Nothing reflects over a
    /// static — there is no instance to read one from — so these are here to be
    /// bound rather than dropped, and for the compiler's own <c>[Embed]</c>,
    /// which is taken out before this list is filled.
    /// </summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    /// <summary>
    /// The type this belongs to, or null for module-level storage.
    ///
    /// The two are the same thing in different scopes -- one global, named by
    /// what encloses it -- so they share a symbol, a mangled name and a place
    /// in the initialization order.
    /// </summary>
    public NamedTypeSymbol? ContainingType { get; init; }

    /// <summary>
    /// Declared <c>readonly</c>: written once by its initializer and never
    /// again.
    ///
    /// What it buys is more than the refusal to assign. A reference stored in
    /// one is made immortal, so retain and release skip it for the rest of the
    /// program -- which a mutable one cannot be, because the value it holds may
    /// be replaced and the old one has to be released.
    /// </summary>
    public bool IsReadonly { get; init; }

    /// <summary>
    /// Whether this static's value can be written on the global itself, with
    /// no code to run.
    ///
    /// <c>= false</c> and <c>= null</c> are a zero and a null pointer, and a
    /// global can be born holding them.
    ///
    /// Four shapes and no more: <c>null</c>, <c>default(T)</c>, a literal of a
    /// type that is not counted, and <c>[Embed]</c>, whose object is made by the
    /// linker rather than by code. A string literal is excluded because it
    /// is an object something has to make, where <c>null</c> is a pointer that
    /// already exists; a struct literal is excluded because a struct is stored
    /// field by field and a field may be counted. Everything past that line is
    /// code, which is what the entry point was for.
    ///
    /// The driver reads this to decide what to refuse and the emitter reads it
    /// to decide what to write, which is why it lives here rather than in
    /// either of them.
    /// </summary>
    public bool HasConstantInitializer
    {
        get
        {
            if (IsImported) return false;

            // Both are the type's zero, which a global holds by being born.
            if (Initializer is BoundNullLiteral or BoundDefault) return true;

            // An embedded file is an object the linker already placed, so the
            // global is born holding its address — the relocation is in
            // writable data, where every loader will apply one.
            if (Initializer is BoundEmbed) return true;

            return Initializer is BoundLiteral literal &&
                   Type is not StructTypeSymbol &&
                   (!Type.NeedsArc() || literal.Value is null);
        }
    }

    /// <summary>
    /// The name the linker knows this by, for storage that crosses to C, or
    /// null for ordinary Stainless storage with a mangled name.
    ///
    /// <c>extern "C" int errno;</c> and <c>export "C" int slDepth = 0;</c> are
    /// the two that set it: one names storage defined elsewhere, the other
    /// defines storage under a name C can reach. Both are the same global to
    /// everything that reads or writes it, which is why they share a symbol.
    /// </summary>
    public string? LinkName { get; init; }

    /// <summary>
    /// Declared here and defined somewhere else: <c>extern "C" int errno;</c>.
    ///
    /// It has no initializer and no storage of its own -- the emitter writes an
    /// <c>external global</c>, which is a promise to the linker rather than a
    /// definition, and the linker fails if nothing keeps it. That is the same
    /// contract an <c>extern "C"</c> function already has.
    /// </summary>
    public bool IsImported { get; init; }

    public required Source.SourceSpan Span { get; init; }

    /// <summary>The initializer, bound in pass 8 like any other body.</summary>
    public BoundExpression? Initializer { get; set; }

    /// <summary>The statics this one's initializer reads, for ordering.</summary>
    public List<StaticSymbol> DependsOn { get; } = [];

    public string QualifiedName =>
        ContainingType is not null ? ContainingType.QualifiedName + "." + Name
        : string.IsNullOrEmpty(ModuleName) ? Name
        : ModuleName + "." + Name;

    public override string ToString() => $"{Type.Name} {QualifiedName}";
}

/// <summary>
/// <c>using Handle = void*;</c>: a name that resolves to a type.
///
/// It is deliberately not a <see cref="TypeSymbol"/>. An alias *is* the type it
/// names -- the same type, not a wrapper around one -- so it lives in name
/// lookup and nowhere else, and nothing downstream has to know it existed.
/// Making it a type would mean unwrapping it at every comparison, conversion,
/// layout and mangling site, for no gain: what a binding actually wants
/// distinguished is distinguished by pointing at different opaque types.
///
/// The target is resolved on first use rather than in a pass of its own,
/// because an alias may name a type declared later or an alias declared later.
/// </summary>
public sealed class AliasSymbol(string name, string moduleName)
{
    public string Name { get; } = name;
    public string ModuleName { get; } = moduleName;
    public bool IsPublic { get; init; }
    public required Source.SourceSpan Span { get; init; }

    /// <summary>The type it stands for, once something has asked.</summary>
    public TypeSymbol? Target { get; set; }

    public string QualifiedName =>
        string.IsNullOrEmpty(ModuleName) ? Name : ModuleName + "." + Name;

    public override string ToString() => $"using {Name} = {Target?.Name ?? "?"}";
}

/// <summary>A module-level <c>const</c>, folded to a value at bind time.</summary>
public sealed class ConstantSymbol(string name, TypeSymbol type, object? value)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public object? Value { get; } = value;
    public bool IsPublic { get; init; }
}

/// <summary>
/// One source file. Modules are the unit of visibility and the reason Stainless
/// needs no headers: a module's public surface is computed from its own source,
/// then consumed directly by importers.
/// </summary>
/// <summary>
/// A generic declaration, kept as syntax rather than symbols.
///
/// Stainless monomorphizes: nothing about a template is checked until it is
/// instantiated, at which point it becomes an ordinary type or function with
/// the type arguments substituted in. That is why the template holds a syntax
/// node and a list of parameter names, and no resolved members at all.
/// </summary>
public sealed class GenericTypeTemplate(
    string name, FileScope scope, TypeDeclSyntax declaration)
{
    public string Name { get; } = name;
    public FileScope Scope { get; } = scope;
    public ModuleSymbol Module => Scope.Module;
    public TypeDeclSyntax Declaration { get; } = declaration;
    public IReadOnlyList<string> Parameters => Declaration.TypeParameters;
    public bool IsPublic => Declaration.Modifiers.HasFlag(Modifiers.Public);

    public override string ToString() => $"{Name}<{string.Join(", ", Parameters)}>";
}

/// <summary>
/// A <c>delegate</c> or <c>closure</c> with type parameters of its own.
///
/// It is not a <see cref="GenericTypeTemplate"/> because there is no type
/// declaration behind it: a delegate has a signature and nothing else, so an
/// instantiation resolves that signature under a substitution rather than
/// re-running the passes that declare members.
/// </summary>
public sealed class GenericDelegateTemplate(
    string name, FileScope scope, DelegateDeclSyntax declaration)
{
    public string Name { get; } = name;
    public FileScope Scope { get; } = scope;
    public ModuleSymbol Module => Scope.Module;
    public DelegateDeclSyntax Declaration { get; } = declaration;
    public IReadOnlyList<string> Parameters => Declaration.TypeParameters;
    public bool IsPublic => Declaration.Modifiers.HasFlag(Modifiers.Public);
    public bool CarriesReceiver => Declaration.CarriesReceiver;

    public override string ToString() => $"{Name}<{string.Join(", ", Parameters)}>";
}

public sealed class GenericFunctionTemplate(
    string name, FileScope scope, FunctionDeclSyntax declaration)
{
    public string Name { get; } = name;
    public FileScope Scope { get; } = scope;
    public ModuleSymbol Module => Scope.Module;
    public FunctionDeclSyntax Declaration { get; } = declaration;
    public IReadOnlyList<string> Parameters => Declaration.TypeParameters;
    public bool IsPublic => Declaration.Modifiers.HasFlag(Modifiers.Public);

    /// <summary>The type this is a method of, or null for a free function.</summary>
    public NamedTypeSymbol? ContainingType { get; init; }

    /// <summary>
    /// The type arguments already in force where this template was declared.
    ///
    /// A generic method inside a generic class sees two sets of parameters: the
    /// class's, fixed when the class was instantiated, and its own, inferred at
    /// each call. This holds the first so the second can be merged onto it.
    /// </summary>
    public IReadOnlyDictionary<string, TypeSymbol> OuterSubstitution { get; init; } =
        new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

    /// <summary>The binder's record of a local function, for one declared in a block.</summary>
    public object? Local { get; init; }

    /// <summary>
    /// True when a call to an instantiation goes through a table: an instance
    /// method of an interface, or one of a class written <c>virtual</c>,
    /// <c>abstract</c> or <c>override</c>. Each instantiation is a slot of its
    /// own, numbered once the whole program has said which it uses.
    /// </summary>
    public bool IsDispatched =>
        !Declaration.Modifiers.HasFlag(Modifiers.Static) &&
        (ContainingType is InterfaceTypeSymbol ||
         (ContainingType is ClassTypeSymbol &&
          (Declaration.Modifiers & (Modifiers.Virtual | Modifiers.Abstract | Modifiers.Override))
              != Modifiers.None));

    /// <summary>For an <c>override</c> template, the one it replaces. Settled in pass 5.</summary>
    public GenericFunctionTemplate? Overridden { get; set; }

    /// <summary>The template that introduced the slot this one fills.</summary>
    public GenericFunctionTemplate Root
    {
        get
        {
            var root = this;
            while (root.Overridden is { } above) root = above;
            return root;
        }
    }

    /// <summary>
    /// Whether another template could stand for this one: the same name, and
    /// as many type parameters and parameters. Which types those are is only
    /// known per instantiation, and is compared there.
    /// </summary>
    public bool HasShapeOf(GenericFunctionTemplate other) =>
        Name == other.Name &&
        Parameters.Count == other.Parameters.Count &&
        Declaration.Parameters.Count == other.Declaration.Parameters.Count;

    public override string ToString() => $"{Name}<{string.Join(", ", Parameters)}>";
}

public sealed class ModuleSymbol(string name)
{
    public string Name { get; } = name;

    public Dictionary<string, NamedTypeSymbol> Types { get; } = new(StringComparer.Ordinal);

    /// <summary>
    /// Generic delegates and closures, kept apart from
    /// <see cref="GenericTypes"/> because they instantiate differently: there
    /// is a signature to resolve rather than members to declare. Filed under
    /// <see cref="GenericKey"/>.
    /// </summary>
    public Dictionary<string, GenericDelegateTemplate> GenericDelegates { get; } =
        new(StringComparer.Ordinal);

    /// <summary>Generic declarations, awaiting instantiation. Filed under <see cref="GenericKey"/>.</summary>
    public Dictionary<string, GenericTypeTemplate> GenericTypes { get; } = new(StringComparer.Ordinal);

    /// <summary>
    /// What a generic declaration is filed under: its name and how many type
    /// parameters it takes. C# lets <c>Func&lt;T, R&gt;</c> and
    /// <c>Func&lt;A, B, R&gt;</c> share a name, and so does this.
    /// </summary>
    public static string GenericKey(string name, int arity) => $"{name}`{arity}";

    /// <summary>The generic type of that name taking <paramref name="arity"/> parameters, or the first of any arity.</summary>
    public GenericTypeTemplate? FindGenericType(string name, int? arity) =>
        arity is { } count
            ? GenericTypes.GetValueOrDefault(GenericKey(name, count))
            : GenericTypes.Values.FirstOrDefault(t => t.Name == name);

    /// <summary>The generic delegate of that name taking <paramref name="arity"/> parameters, or the first of any arity.</summary>
    public GenericDelegateTemplate? FindGenericDelegate(string name, int? arity) =>
        arity is { } count
            ? GenericDelegates.GetValueOrDefault(GenericKey(name, count))
            : GenericDelegates.Values.FirstOrDefault(t => t.Name == name);

    /// <summary>Whether a generic type or delegate of any arity has this name.</summary>
    public bool DeclaresGeneric(string name) =>
        FindGenericType(name, null) is not null || FindGenericDelegate(name, null) is not null;
    public List<GenericFunctionTemplate> GenericFunctions { get; } = [];
    public List<FunctionSymbol> Functions { get; } = [];

    /// <summary>
    /// The module-level functions in <see cref="Functions"/>, by name, as far
    /// as it has been read.
    /// </summary>
    private readonly Dictionary<string, FunctionSymbol[]> _functionsByName =
        new(StringComparer.Ordinal);
    private int _functionsIndexed;

    public Dictionary<string, AliasSymbol> Aliases { get; } = new(StringComparer.Ordinal);
    public Dictionary<string, ConstantSymbol> Constants { get; } = new(StringComparer.Ordinal);
    public Dictionary<string, StaticSymbol> Statics { get; } = new(StringComparer.Ordinal);

    /// <summary>
    /// Every module-level function of that name. <see cref="Functions"/> is
    /// only ever added to, so the index is brought up to date by reading what
    /// was added since it was last asked.
    /// </summary>
    public IReadOnlyList<FunctionSymbol> FindFunctions(string name)
    {
        for (; _functionsIndexed < Functions.Count; _functionsIndexed++)
        {
            var function = Functions[_functionsIndexed];
            if (function.ContainingType is not null) continue;

            _functionsByName[function.Name] =
                _functionsByName.TryGetValue(function.Name, out var known)
                    ? [.. known, function]
                    : [function];
        }

        return _functionsByName.TryGetValue(name, out var found) ? found : [];
    }

    public override string ToString() => Name;
}

/// <summary>
/// One source file's view of the program: the module its declarations join,
/// plus the imports written in that file.
///
/// Imports are per-file rather than per-module, as in C#. A module may be split
/// across several files, and adding an import to one of them must not quietly
/// change how a sibling resolves names.
/// </summary>
public sealed class FileScope(ModuleSymbol module)
{
    public ModuleSymbol Module { get; } = module;

    private readonly Dictionary<string, ModuleSymbol> _imports = new(StringComparer.Ordinal);
    private List<ModuleSymbol>? _importedModules;
    private List<ModuleSymbol>? _visibleModules;

    /// <summary>Modules reachable from this file, keyed by the name used to reach them.</summary>
    public IReadOnlyDictionary<string, ModuleSymbol> Imports => _imports;

    /// <summary>
    /// Makes <paramref name="imported"/> reachable from this file as
    /// <paramref name="name"/>.
    /// </summary>
    public void Import(string name, ModuleSymbol imported)
    {
        _imports[name] = imported;
        _importedModules = null;
        _visibleModules = null;
    }

    /// <summary>Each module an import reaches, once, however many names reach it.</summary>
    public IReadOnlyList<ModuleSymbol> ImportedModules =>
        _importedModules ??= _imports.Values.Distinct().ToList();

    /// <summary>This file's own module, then each module an import reaches, once.</summary>
    public IReadOnlyList<ModuleSymbol> VisibleModules =>
        _visibleModules ??= _imports.Values.Prepend(Module).Distinct().ToList();

    public override string ToString() => Module.Name;
}
