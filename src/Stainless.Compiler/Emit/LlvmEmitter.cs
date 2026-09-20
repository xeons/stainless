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

using System.Globalization;
using System.Text;
using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// An emitted value.
///
/// For every type except <c>struct</c>, <see cref="Ref"/> is the value itself.
/// Struct values are always represented by a pointer to their storage, the way
/// a C front end represents an lvalue, because aggregates in SSA registers make
/// both ABI lowering and field access far harder than they need to be.
/// </summary>
public readonly record struct Val(string Ref, string LlvmType, TypeSymbol Type)
{
    public bool IsStructAddress => Type is StructTypeSymbol;
    public static readonly Val Void = new("", "void", PrimitiveTypeSymbol.Void);
}

/// <summary>
/// Emits textual LLVM IR. Text rather than the LLVM C API deliberately: the IR
/// is then readable, diffable and testable, and the compiler has no native
/// dependency of its own.
/// </summary>
/// <param name="forSharedLibrary">
/// When true, <c>export "C"</c> functions are marked <c>dllexport</c> so they
/// reach a Windows DLL's export table, and no C <c>main</c> is emitted.
/// </param>
/// <param name="debug">
/// The debug metadata graph to describe this program into, or null to emit no
/// debug information at all. When it is present every instruction carries a
/// source location, which is what a debugger, a profiler and a stack trace all
/// read; when it is absent nothing about the output changes.
/// </param>
/// <param name="sharedRuntime">
/// When true the runtime is one shared library rather than a copy compiled into
/// this binary, and Windows needs its data symbols declared <c>dllimport</c>:
/// a function the linker can reach through a generated thunk, and a constant it
/// cannot, because the address has to come from the import address table.
/// </param>
public sealed partial class LlvmEmitter(
    bool forSharedLibrary = false, bool forStainlessConsumers = false,
    DebugInfo? debug = null, bool sharedRuntime = false,
    CppAbi abi = CppAbi.Microsoft, byte[]? resourceBlob = null)
{
    /// <summary>
    /// How a struct crosses a call, which is a property of the target and not
    /// of the language.
    ///
    /// Win64 asks only how big it is; SysV asks what is in it. Both are here
    /// because `--abi` selects one, and until this existed it selected the
    /// name mangling and the bit-field packing and left the argument passing
    /// as Win64 whatever it said -- which made `--abi itanium` produce a
    /// program that could not call a C library.
    ///
    /// The architecture is asked first, because it decides more than the name
    /// mangling does. x86 has no argument registers at all and its two systems
    /// disagree about returns; ARM64 asks what is in the struct, the way System
    /// V does, and gets different answers. Only on x86-64 is the C++ ABI what
    /// picks, and there it picks between the two that exist.
    /// </summary>
    private ArgInfo ClassifyValue(TypeSymbol type) =>
        Binding.TargetPlatform.Current.Architecture switch
        {
            Binding.TargetArch.X86 => X86Abi.ClassifyArgument(type, LlvmTypeOf),
            Binding.TargetArch.Arm64 => Aapcs64Abi.ClassifyArgument(type, LlvmTypeOf),
            _ => abi == CppAbi.Itanium
                ? SysVAbi.ClassifyArgument(type, LlvmTypeOf)
                : Win64Abi.ClassifyArgument(type, LlvmTypeOf),
        };

    private ArgInfo ClassifyResult(TypeSymbol type) =>
        Binding.TargetPlatform.Current.Architecture switch
        {
            Binding.TargetArch.X86 => X86Abi.ClassifyReturn(
                type, LlvmTypeOf, Binding.TargetPlatform.Current.IsWindows),
            Binding.TargetArch.Arm64 => Aapcs64Abi.ClassifyReturn(type, LlvmTypeOf),
            _ => abi == CppAbi.Itanium
                ? SysVAbi.ClassifyReturn(type, LlvmTypeOf)
                : Win64Abi.ClassifyReturn(type, LlvmTypeOf),
        };

    /// <summary>
    /// How a <c>size_t</c> is spelled in IR for this target: <c>i64</c> on a
    /// 64-bit one and <c>i32</c> on a 32-bit one.
    ///
    /// Every runtime declaration that takes or returns a <c>size_t</c> is
    /// written with it. Getting one wrong does not fail to build: on x86 a
    /// cdecl call would push eight bytes where the callee reads four, and
    /// everything after that argument is somebody else's.
    /// </summary>
    private static string Word => Binding.TargetPlatform.Current.NativeIntType;

    private readonly StringBuilder _module = new();
    private readonly StringBuilder _body = new();
    private readonly Dictionary<string, string> _byteConstants = new(StringComparer.Ordinal);

    /// <summary>
    /// What each named struct type must be aligned to. LLVM struct types carry
    /// no alignment of their own, so an alloca or a global has to say it, and
    /// those know only the type's name.
    /// </summary>
    private readonly Dictionary<string, int> _structAlignment = new(StringComparer.Ordinal);

    /// <summary>
    /// For a struct whose padding had to be written out, where each declared
    /// field ended up among the members. Absent for every struct whose fields
    /// are its members, which is nearly all of them.
    /// </summary>
    private readonly Dictionary<string, int[]> _fieldSlots = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _stringObjects = new(StringComparer.Ordinal);
    private readonly Dictionary<LocalSymbol, string> _slots = [];
    private readonly Dictionary<ParameterSymbol, string> _parameterSlots = [];

    private readonly StringBuilder _entryAllocas = new();
    private int _nextTemp;
    private int _nextLabel;
    private int _nextSlot;
    private bool _blockTerminated;
    private string? _sretSlot;
    private string _currentBlock = "entry";
    private bool _hasStatics;

    /// <summary>
    /// Whether this module keeps a count of the com class objects it has made.
    ///
    /// True only where something can be activated, which is what makes the
    /// module a COM server and gives <c>DllCanUnloadNow</c> a question to
    /// answer. A program that presents com interfaces but hosts nothing pays
    /// nothing: the two atomics below are not emitted at all.
    /// </summary>
    private bool _countsComObjects;

    /// <summary>
    /// Globals this emitter defines itself, which a matching `extern "C"`
    /// declaration must therefore not declare a second time.
    /// </summary>
    private readonly HashSet<string> _definedGlobals = new(StringComparer.Ordinal);
    private ArgInfo _returnInfo = new(PassStyle.Direct, "void", PrimitiveTypeSymbol.Void);

    /// <summary>
    /// The function being described, and the point in it the next instruction
    /// belongs to. Both are null while emitting something the programmer did not
    /// write — a thunk, a destructor hook, the static initializer — which is
    /// exactly the right answer for those: they have no source to step to.
    /// </summary>
    private int? _debugScope;
    private int? _debugLocation;

    /// <summary>
    /// True while the next block emitted is a function's own body, which the
    /// subprogram already scopes.
    /// </summary>
    /// <remarks>
    /// Clang scopes a body's locals to the <c>DISubprogram</c> too. A lexical
    /// block there would be one more entry per function saying what
    /// <c>DW_TAG_subprogram</c> already says, over every function in the
    /// standard library as well as the program's own.
    /// </remarks>
    private bool _atFunctionBody;

    /// <summary>Owned locals per lexical scope, released on the way out.</summary>
    private readonly List<List<(string Slot, TypeSymbol Type)>> _scopes = [];

    /// <summary>+1 values produced mid-statement, released once the statement completes.</summary>
    private readonly List<(string Ref, TypeSymbol Type)> _pendingReleases = [];

    /// <summary>
    /// Where <c>break</c> and <c>continue</c> go, and how many scopes each has
    /// to unwind on the way. They are tracked separately because a switch is a
    /// target for one and not the other: a <c>continue</c> written inside a
    /// switch belongs to the enclosing loop, and must release the switch's
    /// scopes as it leaves.
    /// </summary>
    private readonly List<(string BreakLabel, int BreakDepth,
                           string ContinueLabel, int ContinueDepth)> _loops = [];

    /// <summary>
    /// What runs before main, lowest priority first.
    ///
    /// A module may define <c>llvm.global_ctors</c> only once, so everything
    /// that wants in records itself here and <see cref="StartupTable"/> emits
    /// the one array at the end. Two things want in today: binding string
    /// literals to their type on Windows, and registering this binary's
    /// reflected types so that one can be found by name.
    /// </summary>
    private readonly List<(int Priority, string Name)> _startup = [];

    /// <summary>
    /// The <c>llvm.*.with.overflow</c> declarations <c>checked</c> arithmetic
    /// asked for. Collected rather than declared where they are used, because a
    /// <c>declare</c> written mid-function would land inside its body.
    /// </summary>
    private readonly HashSet<string> _overflowIntrinsics = new(StringComparer.Ordinal);

    public string Emit(BoundProgram program)
    {
        Header();
        StructTypes(program);
        RuntimeDeclarations();
        FactoryDeclarations(program);
        ExternalDeclarations(program);
        TypeInfos(program);
        VirtualTables(program);

        _hasStatics = program.Statics.Count > 0 || program.StaticConstructors.Count > 0;

        // Before the functions, because EmitNew and the destroy thunks are what
        // maintain the count and both are emitted below.
        _countsComObjects = program.Classes.Any(
            c => c is { IsCom: true, Clsid: not null } && c.ComInterfaces.Count > 0);

        ResourceBlob();
        StaticStorage(program);

        foreach (var function in program.Functions)
            EmitFunction(function);

        EmitStaticInitializer(program);

        // After the functions, because a thunk clobbers the per-function state
        // the one that asked for it is still using.
        EmitThunks();

        foreach (var classType in program.Classes)
            EmitDestroyThunk(classType);

        foreach (var arrayType in program.Arrays)
            EmitArrayDestroyThunk(arrayType);

        foreach (var variant in program.Structs.OfType<VariantTypeSymbol>()
                     .Where(v => v.CarriesReferences()).Distinct())
            EmitVariantArcThunks(variant);

        InterfaceTables(program);
        ComTables(program);
        ComFactoryTable(program);

        if (program.EntryPoint is not null && !forSharedLibrary)
            EmitEntryPoint(program.EntryPoint);

        StringConstants();
        EmbeddedData(program);
        TypeRegistry(program);
        StartupTable();

        // After the functions, because which of these are needed is not known
        // until the last `checked` expression has been emitted.
        if (_overflowIntrinsics.Count > 0)
        {
            _module.AppendLine();
            foreach (string declaration in _overflowIntrinsics.OrderBy(d => d, StringComparer.Ordinal))
                _module.AppendLine(declaration);
        }

        if (_metadata.Length > 0)
        {
            _module.AppendLine();
            _module.Append(_metadata);
        }

        // The one attribute group, and only under -g. See FrameAttributes.
        if (debug is not null)
        {
            _module.AppendLine();
            _module.AppendLine($"attributes #{FrameAttributeGroup} = " +
                               "{ \"frame-pointer\"=\"all\" }");
        }

        // Last, because a node is created the first time something refers to it
        // and the functions above are what refer to most of them.
        if (debug is not null)
        {
            _module.AppendLine();
            _module.Append(debug.Render());
        }

        return _module.ToString();
    }

    /// <summary>
    /// The attribute group number every definition carries under <c>-g</c>.
    /// </summary>
    private const int FrameAttributeGroup = 0;

    /// <summary>
    /// <c>" #0"</c> under <c>-g</c>, and nothing otherwise: the frame pointer,
    /// which a debugger cannot walk a stack without.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <b>LLVM omits the frame pointer at every level unless asked, including
    /// at <c>-O0</c>.</b> That is not the behaviour clang has, because clang
    /// passes this attribute itself; a front end that emits no function
    /// attributes at all — which this one did — gets no frame pointer anywhere
    /// and a <c>DW_AT_frame_base</c> of <c>DW_OP_reg7 RSP</c>. The description
    /// is correct and describes a frame nothing can unwind.
    /// </para>
    /// <para>
    /// With it, a function opens <c>push rbp; mov rbp, rsp</c>,
    /// <c>DW_AT_frame_base</c> becomes <c>DW_OP_reg6 RBP</c>, and a stack walk
    /// is a two-load loop rather than a CFI interpreter.
    /// <c>docs/dwarf.md</c> has the measurement either way.
    /// </para>
    /// <para>
    /// Only under <c>-g</c>: a frame pointer costs a register and a couple of
    /// instructions per call, which is a price a release build has no reason to
    /// pay. It also makes <c>perf</c> and WPA produce usable stacks for any
    /// Stainless binary built for debugging, which is worth having on its own.
    /// </para>
    /// </remarks>
    private string FrameAttributes => debug is not null
        ? $" #{FrameAttributeGroup}"
        : "";

    /// <summary>
    /// The one <c>llvm.global_ctors</c>, which both PE and ELF honour: what it
    /// names runs before <c>main</c> in a program and on load in a library.
    /// </summary>
    private void StartupTable()
    {
        if (_startup.Count == 0) return;

        var entries = _startup
            .OrderBy(s => s.Priority)
            .Select(s => $"{{ i32, ptr, ptr }} {{ i32 {s.Priority}, ptr @{s.Name}, ptr null }}");

        _module.AppendLine();
        _module.AppendLine(
            $"@llvm.global_ctors = appending global [{_startup.Count} x {{ i32, ptr, ptr }}] " +
            $"[{string.Join(", ", entries)}]");
    }
}
