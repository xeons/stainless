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
    CppAbi abi = CppAbi.Microsoft)
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
    /// </summary>
    private ArgInfo ClassifyValue(TypeSymbol type) =>
        abi == CppAbi.Itanium
            ? SysVAbi.ClassifyArgument(type, LlvmTypeOf)
            : Win64Abi.ClassifyArgument(type, LlvmTypeOf);

    private ArgInfo ClassifyResult(TypeSymbol type) =>
        abi == CppAbi.Itanium
            ? SysVAbi.ClassifyReturn(type, LlvmTypeOf)
            : Win64Abi.ClassifyReturn(type, LlvmTypeOf);

    private readonly StringBuilder _module = new();
    private readonly StringBuilder _body = new();
    private readonly Dictionary<string, string> _byteConstants = new(StringComparer.Ordinal);

    /// <summary>
    /// What each named struct type must be aligned to. LLVM struct types carry
    /// no alignment of their own, so an alloca or a global has to say it, and
    /// those know only the type's name.
    /// </summary>
    private readonly Dictionary<string, int> _structAlignment = new(StringComparer.Ordinal);
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
    private ArgInfo _returnInfo = new(PassStyle.Direct, "void", PrimitiveTypeSymbol.Void);

    /// <summary>
    /// The function being described, and the point in it the next instruction
    /// belongs to. Both are null while emitting something the programmer did not
    /// write — a thunk, a destructor hook, the static initializer — which is
    /// exactly the right answer for those: they have no source to step to.
    /// </summary>
    private int? _debugScope;
    private int? _debugLocation;

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

    public string Emit(BoundProgram program)
    {
        Header();
        StructTypes(program);
        RuntimeDeclarations();
        FactoryDeclarations(program);
        ExternalDeclarations(program);
        TypeInfos(program);
        VirtualTables(program);

        _hasStatics = program.Statics.Count > 0;
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

        if (program.EntryPoint is not null && !forSharedLibrary)
            EmitEntryPoint(program.EntryPoint);

        StringConstants();

        if (_metadata.Length > 0)
        {
            _module.AppendLine();
            _module.Append(_metadata);
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

}
