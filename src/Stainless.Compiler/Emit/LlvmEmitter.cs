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
public sealed class LlvmEmitter(bool forSharedLibrary = false)
{
    private readonly StringBuilder _module = new();
    private readonly StringBuilder _body = new();
    private readonly Dictionary<string, string> _byteConstants = new(StringComparer.Ordinal);
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

        InterfaceTables(program);

        if (program.EntryPoint is not null && !forSharedLibrary)
            EmitEntryPoint(program.EntryPoint);

        StringConstants();

        if (_metadata.Length > 0)
        {
            _module.AppendLine();
            _module.Append(_metadata);
        }

        return _module.ToString();
    }

    // ============================================================ module scaffolding

    private void Header()
    {
        _module.AppendLine("; Generated by the Stainless compiler.");
        _module.AppendLine("; The target triple and data layout are left to clang so that this");
        _module.AppendLine("; file stays valid for whichever host toolchain compiles it.");
        _module.AppendLine();
    }

    private void StructTypes(BoundProgram program)
    {
        // Declared structs and instantiated generic ones both, which is why this
        // reads the program's list rather than walking the module type tables:
        // `Pair<int>` is in no module's table.
        var structs = program.Structs.Distinct().ToList();

        foreach (var structType in structs)
        {
            string fields = string.Join(", ", structType.Fields.Select(f => LlvmTypeOf(f.Type)));
            _module.AppendLine($"{StructName(structType)} = type {{ {(fields.Length == 0 ? "i8" : fields)} }}");
        }

        // The header every reference type is prefixed with: strong, weak, TypeInfo*.
        _module.AppendLine("%SlObjectHeader = type { i64, i64, ptr }");
        _module.AppendLine("%SlTypeInfo = type { i64, ptr, ptr, ptr, i64, ptr, i64, ptr }");
        _module.AppendLine("%SlFieldInfo = type { ptr, i64, i32, ptr, i64, ptr }");
        _module.AppendLine("%SlAttribute = type { ptr, i64, ptr }");
        _module.AppendLine("%SlAttributeValue = type { i32, i64, ptr }");
        _module.AppendLine();
    }

    /// <summary>
    /// Symbols this module has already declared. The standard library declares
    /// some runtime entry points itself with <c>extern "C"</c>, and LLVM rejects
    /// a second declaration of the same name.
    /// </summary>
    private readonly HashSet<string> _declared = new(StringComparer.Ordinal);

    private void Declare(string name, string signature)
    {
        if (!_declared.Add(name)) return;
        _module.AppendLine(signature);
    }

    private void RuntimeDeclarations()
    {
        Declare("sl_alloc", "declare ptr @sl_alloc(ptr)");
        Declare("sl_retain", "declare void @sl_retain(ptr)");
        Declare("sl_release", "declare void @sl_release(ptr)");
        Declare("sl_make_immortal", "declare void @sl_make_immortal(ptr)");
        Declare("sl_weak_retain", "declare void @sl_weak_retain(ptr)");
        Declare("sl_weak_release", "declare void @sl_weak_release(ptr)");
        Declare("sl_weak_load", "declare ptr @sl_weak_load(ptr)");
        Declare("sl_string_type_info", "@sl_string_type_info = external constant %SlTypeInfo");
        Declare("sl_utf16_string_type_info", "@sl_utf16_string_type_info = external constant %SlTypeInfo");
        Declare("sl_string_builder_type_info", "@sl_string_builder_type_info = external constant %SlTypeInfo");
        Declare("sl_array_alloc", "declare ptr @sl_array_alloc(ptr, i64, i64)");
        Declare("sl_array_bounds_fail", "declare void @sl_array_bounds_fail(i64, i64)");
        Declare("sl_divide_by_zero", "declare void @sl_divide_by_zero()");
        Declare("sl_divide_overflow", "declare void @sl_divide_overflow()");
        Declare("llvm.memcpy.p0.p0.i64", "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)");
        ConcurrencyDeclarations();
        _module.AppendLine();
    }

    private void FactoryDeclarations(BoundProgram program)
    {
        foreach (string factory in program.RuntimeFactories)
            Declare(factory, $"declare ptr @{factory}()");

        if (program.RuntimeFactories.Count > 0) _module.AppendLine();
    }

    private void ExternalDeclarations(BoundProgram program)
    {
        foreach (var function in program.ExternalFunctions)
        {
            var returnInfo = Win64Abi.ClassifyReturn(function.ReturnType, LlvmTypeOf);
            var parts = new List<string>();

            if (returnInfo.Style == PassStyle.Indirect)
                parts.Add($"ptr sret({StructName((StructTypeSymbol)function.ReturnType)})");

            foreach (var parameter in function.Parameters)
            {
                var info = Win64Abi.ClassifyArgument(parameter.Type, LlvmTypeOf);
                parts.Add(info.Style == PassStyle.Indirect
                    ? $"ptr byval({StructName((StructTypeSymbol)parameter.Type)})"
                    : info.LlvmType);
            }

            if (function.IsVariadic) parts.Add("...");

            string returnType = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
            Declare(function.MangledName,
                $"declare {returnType} @{function.MangledName}({string.Join(", ", parts)})");
        }

        if (program.ExternalFunctions.Count > 0) _module.AppendLine();
    }

    private void TypeInfos(BoundProgram program)
    {
        _interfaceCount = program.Interfaces.Count;

        foreach (var classType in program.Classes)
        {
            string nameConstant = InternBytes(classType.QualifiedName);
            string tables = classType.Interfaces.Count > 0
                ? "@" + InterfaceTableName(classType)
                : "null";

            _module.AppendLine(
                $"@{Mangler.TypeInfoSymbol(classType)} = internal constant %SlTypeInfo " +
                $"{{ i64 {classType.InstanceSize}, ptr @{DestroyName(classType)}, " +
                $"ptr {nameConstant}, ptr {tables}, {Metadata(classType, ClassTypeSymbol.HeaderSize)} }}");
        }

        // One TypeInfo per array type. The element type is not recorded at run
        // time; instead each destroy hook already knows how to walk its elements,
        // which keeps the array header the same 32 bytes whatever it holds.
        foreach (var arrayType in program.Arrays)
        {
            string nameConstant = InternBytes(arrayType.Name);
            _module.AppendLine(
                $"@{ArrayTypeInfoName(arrayType)} = internal constant %SlTypeInfo " +
                $"{{ i64 {ArrayTypeSymbol.HeaderSize}, ptr @{ArrayDestroyName(arrayType)}, " +
                $"ptr {nameConstant}, ptr null, i64 0, ptr null, i64 0, ptr null }}");
        }

        foreach (var structType in program.Modules
                     .SelectMany(m => m.Types.Values)
                     .OfType<StructTypeSymbol>()
                     .Where(t => t.IsReflected))
        {
            // A struct has no object header, so its metadata is reached only
            // through typeof rather than through an instance.
            string nameConstant = InternBytes(structType.QualifiedName);
            _module.AppendLine(
                $"@{StructTypeInfoName(structType)} = internal constant %SlTypeInfo " +
                $"{{ i64 {structType.Size}, ptr null, ptr {nameConstant}, ptr null, " +
                $"{Metadata(structType, 0)} }}");
        }

        if (program.Classes.Count > 0 || program.Arrays.Count > 0) _module.AppendLine();
    }

    private static string StructTypeInfoName(StructTypeSymbol type) =>
        "_SLti_struct_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>The TypeInfo constant holding a reflected type's metadata.</summary>
    public static string TypeInfoOf(NamedTypeSymbol type) => type switch
    {
        ClassTypeSymbol classType => "@" + Mangler.TypeInfoSymbol(classType),
        StructTypeSymbol structType => "@" + StructTypeInfoName(structType),
        _ => "null",
    };

    /// <summary>
    /// The trailing half of a TypeInfo: field and attribute tables, or four
    /// zeroes when the type was not marked [Reflect]. The tables are constants,
    /// so they cost binary size and nothing else.
    /// </summary>
    private string Metadata(NamedTypeSymbol type, int fieldBase)
    {
        if (!type.IsReflected) return "i64 0, ptr null, i64 0, ptr null";

        string fields = "null";
        if (type.Fields.Count > 0)
        {
            // Materialised before the name is taken and before anything is
            // appended: building a row emits its own attribute tables, and
            // StringBuilder's interpolation handler appends as it goes, so a
            // lazy sequence here would nest one constant inside another.
            var rows = type.Fields.Select(field =>
            {
                string attributes = AttributeTable(field.Attributes);

                return $"%SlFieldInfo {{ ptr {InternBytes(field.Name)}, " +
                       $"i64 {fieldBase + field.Offset}, i32 {(int)KindOf(field.Type)}, " +
                       $"ptr {NestedTypeInfo(field.Type)}, {attributes} }}";
            }).ToList();

            string body = string.Join(", ", rows);
            fields = "@" + NextMetadataName("fields");
            _metadata.AppendLine(
                $"{fields} = internal constant [{type.Fields.Count} x %SlFieldInfo] [{body}]");
        }

        string typeAttributes = AttributeTable(type.Attributes);

        return $"i64 {type.Fields.Count}, ptr {fields}, {typeAttributes}";
    }

    /// <summary>Emits an attribute table and returns its count-and-pointer pair.</summary>
    private string AttributeTable(IReadOnlyList<AppliedAttribute> attributes)
    {
        if (attributes.Count == 0) return "i64 0, ptr null";

        var rows = new List<string>();
        foreach (var attribute in attributes)
        {
            string values = "null";
            if (attribute.Values.Count > 0)
            {
                var cells = attribute.Values.Select(value => value switch
                {
                    string text =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.String}, i64 0, " +
                        $"ptr {InternBytes(text)} }}",
                    bool flag =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Bool}, " +
                        $"i64 {(flag ? 1 : 0)}, ptr null }}",
                    double number =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Double}, " +
                        $"i64 {BitConverter.DoubleToInt64Bits(number)}, ptr null }}",
                    ulong number =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Long}, " +
                        $"i64 {unchecked((long)number)}, ptr null }}",
                    _ => $"%SlAttributeValue {{ i32 0, i64 0, ptr null }}",
                });

                string cellBody = string.Join(", ", cells.ToList());
                values = "@" + NextMetadataName("values");
                _metadata.AppendLine(
                    $"{values} = internal constant " +
                    $"[{attribute.Values.Count} x %SlAttributeValue] [{cellBody}]");
            }

            rows.Add($"%SlAttribute {{ ptr {InternBytes(attribute.Type.SimpleName)}, " +
                     $"i64 {attribute.Values.Count}, ptr {values} }}");
        }

        string rowBody = string.Join(", ", rows);
        string table = "@" + NextMetadataName("attributes");
        _metadata.AppendLine(
            $"{table} = internal constant [{attributes.Count} x %SlAttribute] [{rowBody}]");

        return $"i64 {attributes.Count}, ptr {table}";
    }

    private readonly StringBuilder _metadata = new();
    private int _nextMetadata;

    private string NextMetadataName(string hint) => $".meta.{hint}.{_nextMetadata++}";

    /// <summary>The TypeInfo a field's own type points at, when it has one.</summary>
    private static string NestedTypeInfo(TypeSymbol type) => type switch
    {
        StructTypeSymbol { IsReflected: true } structType => TypeInfoOf(structType),
        ClassTypeSymbol { IsIntrinsic: false } classType => TypeInfoOf(classType),
        _ => "null",
    };

    /// <summary>Kept in step with enum SlKind in the runtime.</summary>
    private enum FieldKind
    {
        None = 0,
        Bool, Char, SByte, Short, Int, Long, NInt,
        Byte, UShort, UInt, ULong, NUInt,
        Float, Double,
        Pointer, String, Class, Interface, Struct, Array,
    }

    private static FieldKind KindOf(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Kind switch
        {
            PrimitiveKind.Bool => FieldKind.Bool,
            PrimitiveKind.Char => FieldKind.Char,
            PrimitiveKind.SByte => FieldKind.SByte,
            PrimitiveKind.Short => FieldKind.Short,
            PrimitiveKind.Int => FieldKind.Int,
            PrimitiveKind.Long => FieldKind.Long,
            PrimitiveKind.NInt => FieldKind.NInt,
            PrimitiveKind.Byte => FieldKind.Byte,
            PrimitiveKind.UShort => FieldKind.UShort,
            PrimitiveKind.UInt => FieldKind.UInt,
            PrimitiveKind.ULong => FieldKind.ULong,
            PrimitiveKind.NUInt => FieldKind.NUInt,
            PrimitiveKind.Float => FieldKind.Float,
            PrimitiveKind.Double => FieldKind.Double,
            _ => FieldKind.None,
        },
        ClassTypeSymbol { SimpleName: "String", IsIntrinsic: true } => FieldKind.String,
        ClassTypeSymbol => FieldKind.Class,
        InterfaceTypeSymbol => FieldKind.Interface,
        StructTypeSymbol => FieldKind.Struct,
        ArrayTypeSymbol => FieldKind.Array,
        PointerTypeSymbol => FieldKind.Pointer,
        OptionalTypeSymbol optional => KindOf(optional.Element),
        _ => FieldKind.None,
    };

    private static string ArraySuffix(ArrayTypeSymbol type) => Mangler.SymbolSafe(type.Name);

    private static string ArrayTypeInfoName(ArrayTypeSymbol type) => "_SLti_array_" + ArraySuffix(type);
    private static string ArrayDestroyName(ArrayTypeSymbol type) => "_SLdestroy_array_" + ArraySuffix(type);

    /// <summary>Total interfaces in the program; the width of every dispatch table.</summary>
    private int _interfaceCount;

    private static string InterfaceTableName(ClassTypeSymbol type) =>
        "_SLitab_" + Mangler.SymbolSafe(type.QualifiedName);

    private static string VTableName(ClassTypeSymbol type, InterfaceTypeSymbol iface) =>
        "_SLvt_" + Mangler.SymbolSafe(type.QualifiedName) + "_" + Mangler.SymbolSafe(iface.QualifiedName);

    /// <summary>
    /// Emits, for every class that implements something, one vtable per
    /// interface plus a table indexed by interface id.
    ///
    /// Ids are assigned across the whole program, so the table is indexed
    /// directly and a dispatch never searches. The cost is one pointer per
    /// interface per implementing class, which is a few hundred bytes in a
    /// realistic program.
    /// </summary>
    private void InterfaceTables(BoundProgram program)
    {
        var implementers = program.Classes.Where(c => c.Interfaces.Count > 0).ToList();
        if (implementers.Count == 0) return;

        _module.AppendLine();
        foreach (var classType in implementers)
        {
            foreach (var interfaceType in classType.Interfaces)
            {
                // By parameter types, not by name: a class implementing both
                // IEquatable<int> and IEquatable<String> has two methods called
                // Same, and each interface's table takes the one that fits it.
                var slots = interfaceType.Methods
                    .Select(classType.FindImplementation)
                    .Select(found => found is null ? "ptr null" : $"ptr @{found.MangledName}")
                    .ToList();

                string body = slots.Count == 0 ? "ptr null" : string.Join(", ", slots);
                int width = Math.Max(1, slots.Count);

                _module.AppendLine(
                    $"@{VTableName(classType, interfaceType)} = internal constant " +
                    $"[{width} x ptr] [{body}]");
            }

            var entries = new string[Math.Max(1, _interfaceCount)];
            Array.Fill(entries, "ptr null");
            foreach (var interfaceType in classType.Interfaces)
                entries[interfaceType.Id] = $"ptr @{VTableName(classType, interfaceType)}";

            _module.AppendLine(
                $"@{InterfaceTableName(classType)} = internal constant " +
                $"[{entries.Length} x ptr] [{string.Join(", ", entries)}]");
        }
    }

    private void StringConstants()
    {
        if (_byteConstants.Count == 0 && _stringObjects.Count == 0) return;

        _module.AppendLine();

        foreach (var (text, name) in _byteConstants)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            _module.AppendLine(
                $"{name} = private unnamed_addr constant " +
                $"[{bytes.Length + 1} x i8] c\"{EscapeBytes(bytes)}\"");
        }

        // A string literal is a complete String object in static storage, laid
        // out exactly as sl_string_new would build one on the heap. Its strong
        // count is the immortal sentinel, so retain and release skip it and the
        // literal costs no allocation and no reference traffic at run time.
        foreach (var (text, name) in _stringObjects)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            string layout = $"{{ i64, i64, ptr, i64, [{bytes.Length + 1} x i8] }}";

            _module.AppendLine(
                $"{name} = private unnamed_addr constant {layout} " +
                $"{{ i64 {ImmortalRefCount}, i64 {ImmortalRefCount}, ptr @sl_string_type_info, " +
                $"i64 {bytes.Length}, [{bytes.Length + 1} x i8] c\"{EscapeBytes(bytes)}\" }}, align 8");
        }
    }

    /// <summary>Matches SL_IMMORTAL in the runtime: a count that is never touched.</summary>
    private const string ImmortalRefCount = "-1";

    /// <summary>
    /// LLVM takes printable ASCII literally and everything else as \XX, with
    /// the quote and backslash always escaped. A trailing NUL is always added.
    /// </summary>
    private static string EscapeBytes(byte[] bytes)
    {
        var escaped = new StringBuilder();
        foreach (byte b in bytes)
        {
            if (b is >= 0x20 and < 0x7F && b != (byte)'"' && b != (byte)'\\')
                escaped.Append((char)b);
            else
                escaped.Append('\\').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return escaped.Append("\\00").ToString();
    }

    /// <summary>A bare NUL-terminated byte array, for C strings and TypeInfo names.</summary>
    private string InternBytes(string text)
    {
        if (_byteConstants.TryGetValue(text, out var existing)) return existing;
        string name = $"@.bytes.{_byteConstants.Count}";
        _byteConstants[text] = name;
        return name;
    }

    /// <summary>A static String object that a String-typed expression can refer to.</summary>
    private string InternStringObject(string text)
    {
        if (_stringObjects.TryGetValue(text, out var existing)) return existing;
        string name = $"@.strobj.{_stringObjects.Count}";
        _stringObjects[text] = name;
        return name;
    }

    // ============================================================ types

    private static string LlvmTypeOf(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Kind switch
        {
            PrimitiveKind.Void => "void",
            PrimitiveKind.Bool => "i1",
            PrimitiveKind.Char or PrimitiveKind.SByte or PrimitiveKind.Byte => "i8",
            PrimitiveKind.Short or PrimitiveKind.UShort => "i16",
            PrimitiveKind.Int or PrimitiveKind.UInt => "i32",
            PrimitiveKind.Float => "float",
            PrimitiveKind.Double => "double",
            _ => "i64",
        },
        StructTypeSymbol structType => StructName(structType),

        // A delegate is a bare function pointer, which is what makes it the
        // same value a C function pointer is.
        DelegateTypeSymbol => "ptr",

        // An enum is its underlying integer, which is what makes it the same
        // bytes as the C enum it lines up with.
        EnumTypeSymbol enumType => LlvmTypeOf(enumType.UnderlyingType),

        _ => "ptr",     // pointers, class references, optionals and weak references
    };

    private static string StructName(StructTypeSymbol type) =>
        "%struct." + Mangler.SymbolSafe(type.QualifiedName);

    private static string DestroyName(ClassTypeSymbol type) =>
        "_SLdestroy_" + Mangler.SymbolSafe(type.QualifiedName);

    private static bool IsSigned(TypeSymbol type) => type switch
    {
        // An enum orders and shifts as the integer it is represented by.
        EnumTypeSymbol enumType => enumType.UnderlyingType.IsSigned,
        _ => type is PrimitiveTypeSymbol { IsSigned: true },
    };

    // ============================================================ instruction helpers

    private string NextTemp() => "%" + _nextTemp++;
    private string NextLabel(string hint) => $"{hint}.{_nextLabel++}";

    private void Line(string text)
    {
        if (_blockTerminated) return;       // unreachable code after a terminator
        _body.Append("  ").AppendLine(text);
    }

    private void Terminator(string text)
    {
        if (_blockTerminated) return;
        _body.Append("  ").AppendLine(text);
        _blockTerminated = true;
    }

    private void Label(string name)
    {
        // A block must be entered somehow; fall through if the previous one is open.
        if (!_blockTerminated) _body.AppendLine($"  br label %{name}");
        _body.AppendLine($"{name}:");
        _blockTerminated = false;
        _currentBlock = name;
    }

    private string Emit(string llvmType, string instruction)
    {
        string temp = NextTemp();
        Line($"{temp} = {instruction}");
        return llvmType == "void" ? "" : temp;
    }

    /// <summary>
    /// Every alloca is hoisted into the entry block and given a name rather than a
    /// number. Hoisting keeps a declaration inside a loop from growing the stack on
    /// each iteration; naming keeps it out of LLVM's sequential numbering, which
    /// would otherwise be violated by emitting it ahead of earlier instructions.
    /// </summary>
    private string Alloca(string llvmType, string hint)
    {
        string name = $"%{SanitizeIdentifier(hint)}.s{_nextSlot++}";
        _entryAllocas.AppendLine($"  {name} = alloca {llvmType}, align {AlignOf(llvmType)}");
        return name;
    }

    private static int AlignOf(string llvmType) => llvmType switch
    {
        "i1" or "i8" => 1,
        "i16" => 2,
        "i32" or "float" => 4,
        _ => 8,
    };

    private void MemCopy(string destination, string source, int size)
    {
        Line($"call void @llvm.memcpy.p0.p0.i64(ptr {destination}, ptr {source}, i64 {size}, i1 false)");
    }

    // ============================================================ functions

    private void EmitFunction(BoundFunction function)
    {
        var symbol = function.Symbol;
        ResetFunctionState();

        var returnInfo = Win64Abi.ClassifyReturn(symbol.ReturnType, LlvmTypeOf);
        var parameterInfos = symbol.Parameters
            .Select(p => (Parameter: p, Info: Win64Abi.ClassifyArgument(p.Type, LlvmTypeOf)))
            .ToList();

        var declaredParameters = new List<string>();
        var incomingNames = new Dictionary<ParameterSymbol, string>();

        if (returnInfo.Style == PassStyle.Indirect)
        {
            _sretSlot = "%sret.result";
            declaredParameters.Add(
                $"ptr sret({StructName((StructTypeSymbol)symbol.ReturnType)}) {_sretSlot}");
        }

        foreach (var (parameter, info) in parameterInfos)
        {
            string name = "%arg." + SanitizeIdentifier(parameter.Name);
            incomingNames[parameter] = name;
            declaredParameters.Add(info.Style == PassStyle.Indirect
                ? $"ptr byval({StructName((StructTypeSymbol)parameter.Type)}) {name}"
                : $"{info.LlvmType} {name}");
        }

        _returnInfo = returnInfo;
        _nextTemp = 0;

        string returnType = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
        string linkage = symbol.Linkage == LinkageKind.ExportC || symbol.IsPublic ? "" : "internal ";

        // Windows exports only what a binary marks, so a library's declared API
        // has to say so here. Elsewhere default visibility already exports it.
        string storage = forSharedLibrary
                         && symbol.Linkage == LinkageKind.ExportC
                         && OperatingSystem.IsWindows()
            ? "dllexport "
            : "";

        _module.AppendLine(
            $"define {linkage}{storage}{returnType} @{symbol.MangledName}" +
            $"({string.Join(", ", declaredParameters)}) {{");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        // Give every parameter a stack slot so it can be assigned like a local.
        foreach (var (parameter, info) in parameterInfos)
        {
            string incoming = incomingNames[parameter];

            if (info.Style == PassStyle.Indirect)
            {
                // byval already points at a private copy owned by this call.
                _parameterSlots[parameter] = incoming;
                AdoptWrittenParameter(parameter, incoming);
                continue;
            }

            if (info.Style == PassStyle.CoerceToInteger)
            {
                string slot = Alloca(LlvmTypeOf(parameter.Type), parameter.Name);
                Line($"store {info.LlvmType} {incoming}, ptr {slot}");
                _parameterSlots[parameter] = slot;
                AdoptWrittenParameter(parameter, slot);
                continue;
            }

            string plain = Alloca(info.LlvmType, parameter.Name);
            Line($"store {info.LlvmType} {incoming}, ptr {plain}");
            _parameterSlots[parameter] = plain;
            AdoptWrittenParameter(parameter, plain);
        }

        EmitStatement(function.Body);

        // Fall off the end: void returns implicitly, everything else was already
        // checked by the binder, so this is only reached for unreachable tails.
        if (!_blockTerminated)
        {
            ReleaseScopes(0);
            Terminator(returnInfo.Style switch
            {
                PassStyle.Indirect => "ret void",
                _ when symbol.ReturnType.IsVoid() => "ret void",
                _ => $"ret {returnInfo.LlvmType} {ZeroOf(returnInfo.LlvmType)}",
            });
        }

        PopScopeWithoutRelease();

        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }


    // ============================================================ concurrency

    /// <summary>
    /// The scope a `spawn` submits to: the innermost enclosing `parallel`.
    /// It is defined before the block it governs, so it dominates every spawn
    /// inside and needs no slot of its own.
    /// </summary>
    private string? _currentScope;

    private readonly List<PendingThunk> _thunks = [];
    private int _nextThunk;

    private abstract record PendingThunk(string Name);

    private sealed record SpawnThunk(
        string Name,
        string BlockType,
        IReadOnlyList<LocalSymbol> Fields,
        BoundCall Call,
        TypeSymbol? TargetType) : PendingThunk(Name);

    private sealed record RangeThunk(
        string Name,
        string CaptureType,
        BoundParallelFor Loop) : PendingThunk(Name);

    private void ConcurrencyDeclarations()
    {
        Declare("sl_scope_begin", "declare ptr @sl_scope_begin()");
        Declare("sl_scope_submit", "declare void @sl_scope_submit(ptr, ptr, ptr)");
        Declare("sl_scope_end", "declare void @sl_scope_end(ptr)");
        Declare("sl_parallel_range", "declare void @sl_parallel_range(ptr, i64, ptr, ptr)");
        Declare("malloc", "declare ptr @malloc(i64)");
        Declare("free", "declare void @free(ptr)");
    }

    /// <summary>The type a value takes inside a marshalling block.</summary>
    private static string FieldTypeOf(TypeSymbol type) =>
        type is StructTypeSymbol structType ? StructName(structType) : LlvmTypeOf(type);

    /// <summary>The size of an LLVM type, without hard-coding a layout.</summary>
    private string SizeOfType(string llvmType)
    {
        string past = Emit("ptr", $"getelementptr {llvmType}, ptr null, i32 1");
        return Emit("i64", $"ptrtoint ptr {past} to i64");
    }

    private void EmitParallel(BoundParallel statement)
    {
        string scope = Emit("ptr", "call ptr @sl_scope_begin()");

        string? enclosing = _currentScope;
        _currentScope = scope;
        EmitStatement(statement.Body);
        _currentScope = enclosing;

        // The join. Nothing spawned inside is still running past this point,
        // which is what lets a job borrow the frame it was spawned from.
        Line($"call void @sl_scope_end(ptr {scope})");
    }

    /// <summary>
    /// Queues one call.
    ///
    /// The arguments are evaluated here, by the parent, and copied into a heap
    /// block the worker unpacks. Heap rather than stack because a spawn in a
    /// loop needs one block per iteration, and an alloca would be a single slot
    /// every job shared.
    /// </summary>
    private void EmitSpawn(BoundSpawn statement)
    {
        if (_currentScope is null) return;      // the binder already reported it

        var call = statement.Call;

        var sources = new List<BoundExpression>();
        if (call.Receiver is not null) sources.Add(call.Receiver);
        sources.AddRange(call.Arguments);

        // One synthetic local per field, so the thunk can emit an ordinary call
        // over them and reuse every rule about argument passing.
        var fields = sources
            .Select((source, index) => new LocalSymbol($"spawn.{index}", source.Type, false))
            .ToList();

        var fieldTypes = sources.Select(s => FieldTypeOf(s.Type)).ToList();
        if (statement.Target is not null) fieldTypes.Add("ptr");

        string blockType = "{ " + string.Join(", ", fieldTypes) + " }";

        string size = SizeOfType(blockType);
        string block = Emit("ptr", $"call ptr @malloc(i64 {size})");

        for (int i = 0; i < sources.Count; i++)
        {
            var value = EmitExpression(sources[i]);
            string field = Emit("ptr",
                $"getelementptr inbounds {blockType}, ptr {block}, i32 0, i32 {i}");

            if (sources[i].Type is StructTypeSymbol structType)
                MemCopy(field, value.Ref, structType.Size);
            else
                Line($"store {value.LlvmType} {value.Ref}, ptr {field}");
        }

        // Where the result lands. The address is taken now, by the parent, so
        // `spawn totals[i] = ...` means this iteration's element.
        if (statement.Target is not null)
        {
            string destination = EmitAddress(statement.Target);
            string field = Emit("ptr",
                $"getelementptr inbounds {blockType}, ptr {block}, i32 0, i32 {sources.Count}");
            Line($"store ptr {destination}, ptr {field}");
        }

        string name = $"_SLspawn.{_nextThunk++}";
        var receiverSlot = call.Receiver is null ? null : fields[0];
        var argumentSlots = fields.Skip(call.Receiver is null ? 0 : 1).ToList();

        var thunkCall = new BoundCall(
            call.Span, call.Function,
            receiverSlot is null ? null : new BoundLocalAccess(call.Span, receiverSlot),
            [.. argumentSlots.Select(slot => (BoundExpression)new BoundLocalAccess(call.Span, slot))]);

        _thunks.Add(new SpawnThunk(name, blockType, fields, thunkCall, statement.Target?.Type));

        Line($"call void @sl_scope_submit(ptr {_currentScope}, ptr @{name}, ptr {block})");
    }

    private void EmitSpawnThunk(SpawnThunk thunk)
    {
        ResetFunctionState();
        _module.AppendLine($"define internal void @{thunk.Name}(ptr %block) {{");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        for (int i = 0; i < thunk.Fields.Count; i++)
            _slots[thunk.Fields[i]] = Emit("ptr",
                $"getelementptr inbounds {thunk.BlockType}, ptr %block, i32 0, i32 {i}");

        var result = EmitCall(thunk.Call);

        if (thunk.TargetType is not null)
        {
            string field = Emit("ptr",
                $"getelementptr inbounds {thunk.BlockType}, ptr %block, i32 0, i32 {thunk.Fields.Count}");
            string destination = Emit("ptr", $"load ptr, ptr {field}");
            StoreInto(destination, result, thunk.TargetType);
        }

        FlushTemporaries();
        Line("call void @free(ptr %block)");
        Terminator("ret void");

        PopScopeWithoutRelease();

        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// A counted loop, split across the pool.
    ///
    /// The trip count is worked out here, once, and handed to the runtime with
    /// the body as a range job. Everything the body reads from the enclosing
    /// frame is captured by address, so the chunks share the parent's storage
    /// rather than a copy -- which is what makes writing through a captured
    /// array work, and why writing to a captured variable is rejected.
    /// </summary>
    private void EmitParallelFor(BoundParallelFor statement)
    {
        string start = WidenToLong(statement.Start);
        string limit = WidenToLong(statement.Limit);
        string stride = WidenToLong(statement.Stride);

        // An inclusive bound is one more iteration; then round the span up so a
        // partial final step still runs.
        string bound = statement.Inclusive
            ? Emit("i64", $"add i64 {limit}, 1")
            : limit;

        string span = Emit("i64", $"sub i64 {bound}, {start}");
        string biased = Emit("i64", $"add i64 {span}, {stride}");
        string less = Emit("i64", $"sub i64 {biased}, 1");
        string divided = Emit("i64", $"sdiv i64 {less}, {stride}");
        string positive = Emit("i1", $"icmp sgt i64 {span}, 0");
        string count = Emit("i64", $"select i1 {positive}, i64 {divided}, i64 0");

        var captures = statement.Captures;
        var captureTypes = captures.Select(_ => "ptr").ToList();
        captureTypes.Add("i64");        // the loop variable's first value
        captureTypes.Add("i64");        // its stride

        string captureType = "{ " + string.Join(", ", captureTypes) + " }";

        // The scope is joined before this returns, so the block may live on the
        // parent's stack.
        string capture = Alloca(captureType, "capture");

        for (int i = 0; i < captures.Count; i++)
        {
            string address = captures[i] switch
            {
                LocalSymbol local => _slots[local],
                ParameterSymbol parameter => _parameterSlots[parameter],
                _ => "null",
            };

            string field = Emit("ptr",
                $"getelementptr inbounds {captureType}, ptr {capture}, i32 0, i32 {i}");
            Line($"store ptr {address}, ptr {field}");
        }

        string startField = Emit("ptr",
            $"getelementptr inbounds {captureType}, ptr {capture}, i32 0, i32 {captures.Count}");
        Line($"store i64 {start}, ptr {startField}");

        string strideField = Emit("ptr",
            $"getelementptr inbounds {captureType}, ptr {capture}, i32 0, i32 {captures.Count + 1}");
        Line($"store i64 {stride}, ptr {strideField}");

        string name = $"_SLrange.{_nextThunk++}";
        _thunks.Add(new RangeThunk(name, captureType, statement));

        string scope = Emit("ptr", "call ptr @sl_scope_begin()");
        Line($"call void @sl_parallel_range(ptr {scope}, i64 {count}, ptr @{name}, ptr {capture})");
        Line($"call void @sl_scope_end(ptr {scope})");
    }

    /// <summary>Evaluates an integer expression as an i64, signed or not as its type says.</summary>
    private string WidenToLong(BoundExpression expression)
    {
        var value = EmitExpression(expression);
        if (value.LlvmType == "i64") return value.Ref;

        string instruction = IsSigned(expression.Type) ? "sext" : "zext";
        return Emit("i64", $"{instruction} {value.LlvmType} {value.Ref} to i64");
    }

    private void EmitRangeThunk(RangeThunk thunk)
    {
        var loop = thunk.Loop;

        ResetFunctionState();
        _module.AppendLine(
            $"define internal void @{thunk.Name}(ptr %capture, i64 %start, i64 %end) {{");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        // Each captured variable is reached through the address the parent
        // stored, so the body emits exactly as it would have in place.
        for (int i = 0; i < loop.Captures.Count; i++)
        {
            string field = Emit("ptr",
                $"getelementptr inbounds {thunk.CaptureType}, ptr %capture, i32 0, i32 {i}");
            string address = Emit("ptr", $"load ptr, ptr {field}");

            switch (loop.Captures[i])
            {
                case LocalSymbol local: _slots[local] = address; break;
                case ParameterSymbol parameter: _parameterSlots[parameter] = address; break;
            }
        }

        string firstField = Emit("ptr",
            $"getelementptr inbounds {thunk.CaptureType}, ptr %capture, i32 0, i32 {loop.Captures.Count}");
        string first = Emit("i64", $"load i64, ptr {firstField}");

        string strideField = Emit("ptr",
            $"getelementptr inbounds {thunk.CaptureType}, ptr %capture, i32 0, i32 {loop.Captures.Count + 1}");
        string stride = Emit("i64", $"load i64, ptr {strideField}");

        // The loop variable belongs to this chunk, not to the parent.
        string variableType = LlvmTypeOf(loop.Variable.Type);
        string variableSlot = Alloca(variableType, loop.Variable.Name);
        _slots[loop.Variable] = variableSlot;

        string index = Alloca("i64", "chunk");
        Line($"store i64 %start, ptr {index}");

        string conditionLabel = NextLabel("chunk.cond");
        string bodyLabel = NextLabel("chunk.body");
        string endLabel = NextLabel("chunk.end");

        Terminator($"br label %{conditionLabel}");

        Label(conditionLabel);
        string current = Emit("i64", $"load i64, ptr {index}");
        string more = Emit("i1", $"icmp ult i64 {current}, %end");
        Terminator($"br i1 {more}, label %{bodyLabel}, label %{endLabel}");

        Label(bodyLabel);
        string scaled = Emit("i64", $"mul i64 {current}, {stride}");
        string value = Emit("i64", $"add i64 {first}, {scaled}");
        string narrowed = variableType == "i64"
            ? value
            : Emit(variableType, $"trunc i64 {value} to {variableType}");
        Line($"store {variableType} {narrowed}, ptr {variableSlot}");

        EmitStatement(loop.Body);

        if (!_blockTerminated)
        {
            string next = Emit("i64", $"add i64 {current}, 1");
            Line($"store i64 {next}, ptr {index}");
            Terminator($"br label %{conditionLabel}");
        }

        Label(endLabel);
        Terminator("ret void");

        PopScopeWithoutRelease();

        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// Emits every thunk the program asked for. A thunk body may spawn again, so
    /// this drains rather than iterates.
    /// </summary>
    private void EmitThunks()
    {
        for (int i = 0; i < _thunks.Count; i++)
        {
            switch (_thunks[i])
            {
                case SpawnThunk spawn: EmitSpawnThunk(spawn); break;
                case RangeThunk range: EmitRangeThunk(range); break;
            }
        }
    }

    private void ResetFunctionState()
    {
        _entryAllocas.Clear();
        _nextTemp = 0;
        _nextLabel = 0;
        _nextSlot = 0;
        _currentBlock = "entry";
        _slots.Clear();
        _parameterSlots.Clear();
        _currentScope = null;
        _scopes.Clear();
        _pendingReleases.Clear();
        _loops.Clear();
        _sretSlot = null;
        _blockTerminated = false;
    }

    private static string ZeroOf(string llvmType) => llvmType switch
    {
        "float" or "double" => "0.0",
        "ptr" => "null",
        "void" => "",

        // An aggregate has no integer zero; LLVM spells it this way.
        _ when llvmType.StartsWith('%') => "zeroinitializer",

        _ => "0",
    };

    private static string SanitizeIdentifier(string name) =>
        new(name.Select(c => char.IsLetterOrDigit(c) || c == '_' || c == '.' ? c : '_').ToArray());

    /// <summary>
    /// Emits the class's destroy hook: run the user destructor, then drop every
    /// managed field. The runtime calls this exactly once, when the strong count
    /// reaches zero.
    /// </summary>
    private void EmitDestroyThunk(ClassTypeSymbol classType)
    {
        ResetFunctionState();
        _module.AppendLine($"define internal void @{DestroyName(classType)}(ptr %obj) {{");
        _body.Clear();
        _blockTerminated = false;

        if (classType.Destructor is not null)
            Line($"call void @{classType.Destructor.MangledName}(ptr %obj)");

        foreach (var field in classType.Fields)
        {
            if (!field.Type.CarriesReferences()) continue;

            string address = ClassFieldAddress("%obj", field);

            // A struct field owns whatever is inside it, so the drop reaches in
            // rather than stopping at the field.
            if (field.Type is StructTypeSymbol structField)
            {
                ReleaseFieldsAt(address, structField);
                continue;
            }

            string value = Emit("ptr", $"load ptr, ptr {address}");
            Line(field.Type is WeakTypeSymbol
                ? $"call void @sl_weak_release(ptr {value})"
                : $"call void @sl_release(ptr {value})");
        }

        Terminator("ret void");
        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// Releases an array's elements. For an array of values this is empty and
    /// the optimiser deletes the call; for an array of references it is a loop.
    /// </summary>
    private void EmitArrayDestroyThunk(ArrayTypeSymbol arrayType)
    {
        ResetFunctionState();
        _module.AppendLine($"define internal void @{ArrayDestroyName(arrayType)}(ptr %obj) {{");
        _body.Clear();
        _blockTerminated = false;

        if (arrayType.Element.CarriesReferences())
        {
            bool weak = arrayType.Element is WeakTypeSymbol;
            string elementType = LlvmTypeOf(arrayType.Element);

            string lengthSlot = Emit("ptr", "getelementptr inbounds i8, ptr %obj, i64 24");
            string length = Emit("i64", $"load i64, ptr {lengthSlot}");
            string data = Emit("ptr",
                $"getelementptr inbounds i8, ptr %obj, i64 {ArrayTypeSymbol.HeaderSize}");

            string counter = Alloca("i64", "i");
            Line($"store i64 0, ptr {counter}");

            string conditionLabel = NextLabel("free.cond");
            string bodyLabel = NextLabel("free.body");
            string endLabel = NextLabel("free.end");

            Terminator($"br label %{conditionLabel}");
            Label(conditionLabel);
            string index = Emit("i64", $"load i64, ptr {counter}");
            string more = Emit("i1", $"icmp ult i64 {index}, {length}");
            Terminator($"br i1 {more}, label %{bodyLabel}, label %{endLabel}");

            Label(bodyLabel);
            string slot = Emit("ptr",
                $"getelementptr inbounds {elementType}, ptr {data}, i64 {index}");

            if (arrayType.Element is StructTypeSymbol elementStruct)
            {
                ReleaseFieldsAt(slot, elementStruct);
            }
            else
            {
                string element = Emit("ptr", $"load ptr, ptr {slot}");
                Line($"call void @{(weak ? "sl_weak_release" : "sl_release")}(ptr {element})");
            }
            string next = Emit("i64", $"add i64 {index}, 1");
            Line($"store i64 {next}, ptr {counter}");
            Terminator($"br label %{conditionLabel}");

            Label(endLabel);
        }

        Terminator("ret void");
        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// The real <c>main</c>. It exists so that a Stainless <c>Main</c> can be a
    /// normal mangled function while the linker still finds a C entry point.
    /// </summary>
    // ============================================================ statics

    private static string StaticName(StaticSymbol symbol) =>
        "_SLstatic_" + Mangler.SymbolSafe(symbol.QualifiedName);

    /// <summary>
    /// One zeroed global per static. They are written once, by the initializer
    /// below, before anything else runs.
    /// </summary>
    private void StaticStorage(BoundProgram program)
    {
        if (program.Statics.Count == 0) return;

        foreach (var symbol in program.Statics)
        {
            string llvmType = LlvmTypeOf(symbol.Type);
            _module.AppendLine(
                $"@{StaticName(symbol)} = internal global {llvmType} {ZeroOf(llvmType)}, " +
                $"align {AlignOf(llvmType)}");
        }

        _module.AppendLine();
    }

    private Val EmitStaticAccess(BoundStaticAccess access)
    {
        // A struct is handled by address everywhere else, so it is here too.
        if (access.Type is StructTypeSymbol)
            return new Val("@" + StaticName(access.Static), "ptr", access.Type);

        string llvmType = LlvmTypeOf(access.Type);
        return new Val(
            Emit(llvmType, $"load {llvmType}, ptr @{StaticName(access.Static)}"),
            llvmType, access.Type);
    }

    /// <summary>
    /// Runs every static initializer, in the order the binder worked out.
    ///
    /// There is no lazy guard and no once-flag: the whole program was compiled
    /// together, so the dependency graph was known and sorted at compile time.
    /// A reference is made immortal as it is stored, which is what removes the
    /// last reference traffic from a value every thread can see.
    /// </summary>
    private void EmitStaticInitializer(BoundProgram program)
    {
        if (program.Statics.Count == 0) return;

        ResetFunctionState();
        _module.AppendLine($"define internal void @{StaticInitializerName}() {{");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        foreach (var symbol in program.Statics)
        {
            if (symbol.Initializer is null) continue;

            var value = EmitExpression(symbol.Initializer);
            string slot = "@" + StaticName(symbol);

            if (symbol.Type is StructTypeSymbol structType)
            {
                // Nothing to make immortal: a static must be sendable, and a
                // struct holding a reference is not, so this is plain bytes.
                MemCopy(slot, value.Ref, structType.Size);
            }
            else
            {
                Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");

                // Immortal, so retain and release skip it for the rest of the
                // program: a value that lives to process exit has no reference
                // traffic, and therefore none to race over.
                if (symbol.Type.NeedsArc())
                    Line($"call void @sl_make_immortal(ptr {value.Ref})");
            }

            // The initializer's own temporaries go now; the static holds its
            // value outright, and an immortal one cannot be released anyway.
            FlushTemporaries();
        }

        Terminator("ret void");
        PopScopeWithoutRelease();

        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// Takes ownership of a parameter the body writes to.
    ///
    /// Borrowing is what makes a call cheap, and it holds for every parameter
    /// that is only read. One that is written to cannot be borrowed: the store
    /// releases what the slot held, and what it held is the caller's. Retaining
    /// on entry and releasing on exit turns the slot into the private copy the
    /// write already treated it as, and costs nothing anywhere else.
    /// </summary>
    private void AdoptWrittenParameter(ParameterSymbol parameter, string slot)
    {
        if (!parameter.IsAssigned || !parameter.Type.CarriesReferences()) return;

        if (parameter.Type is StructTypeSymbol structType) RetainFieldsAt(slot, structType);
        else
        {
            string held = Emit("ptr", $"load ptr, ptr {slot}");
            Line(parameter.Type is WeakTypeSymbol
                ? $"call void @sl_weak_retain(ptr {held})"
                : $"call void @sl_retain(ptr {held})");
        }

        TrackOwnedLocal(slot, parameter.Type);
    }

    private const string StaticInitializerName = "_SLstatics";

    private void EmitEntryPoint(FunctionSymbol entry)
    {
        _nextTemp = 0;
        _module.AppendLine("define i32 @main() {");
        _module.AppendLine("entry:");

        // Statics first, in dependency order, before any user code runs.
        if (_hasStatics) _module.AppendLine($"  call void @{StaticInitializerName}()");

        if (entry.ReturnType.IsVoid())
        {
            _module.AppendLine($"  call void @{entry.MangledName}()");
            _module.AppendLine("  ret i32 0");
        }
        else
        {
            _module.AppendLine($"  %0 = call i32 @{entry.MangledName}()");
            _module.AppendLine("  ret i32 %0");
        }

        _module.AppendLine("}");
        _module.AppendLine();
    }

    // ============================================================ ARC

    private void PushScope() => _scopes.Add([]);

    private void PopScopeWithoutRelease() => _scopes.RemoveAt(_scopes.Count - 1);

    private void TrackOwnedLocal(string slot, TypeSymbol type)
    {
        if (type.CarriesReferences()) _scopes[^1].Add((slot, type));
    }

    /// <summary>Releases every owned local from the innermost scope down to <paramref name="depth"/>.</summary>
    private void ReleaseScopes(int depth)
    {
        for (int i = _scopes.Count - 1; i >= depth; i--)
            foreach (var (slot, type) in Enumerable.Reverse(_scopes[i]))
                ReleaseSlot(slot, type);
    }

    private void ReleaseCurrentScope()
    {
        foreach (var (slot, type) in Enumerable.Reverse(_scopes[^1]))
            ReleaseSlot(slot, type);
    }

    /// <summary>
    /// Drops what a storage slot owns: the reference it holds, or, for a struct,
    /// every reference inside it.
    /// </summary>
    private void ReleaseSlot(string slot, TypeSymbol type)
    {
        if (type is StructTypeSymbol structType)
        {
            ReleaseFieldsAt(slot, structType);
            return;
        }

        string value = Emit("ptr", $"load ptr, ptr {slot}");
        Line(type is WeakTypeSymbol
            ? $"call void @sl_weak_release(ptr {value})"
            : $"call void @sl_release(ptr {value})");
    }

    /// <summary>
    /// Retains every reference inside the struct at <paramref name="address"/>,
    /// recursing through struct fields.
    ///
    /// This is what a struct copy costs once it holds a reference. It is the
    /// price of lifting the old rule that a struct was always raw bytes, and it
    /// is charged only to structs that actually hold one — a struct of plain
    /// data still copies with a memcpy and nothing else.
    /// </summary>
    private void RetainFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Line(type is WeakTypeSymbol
                ? $"call void @sl_weak_retain(ptr {value})"
                : $"call void @sl_retain(ptr {value})");
        });

    /// <summary>Releases every reference inside the struct at <paramref name="address"/>.</summary>
    private void ReleaseFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Line(type is WeakTypeSymbol
                ? $"call void @sl_weak_release(ptr {value})"
                : $"call void @sl_release(ptr {value})");
        });

    /// <summary>
    /// Visits the address of every counted reference inside a struct value,
    /// descending into struct fields so a nested one is not missed.
    /// </summary>
    private void WalkReferences(
        string address, StructTypeSymbol structType, Action<string, TypeSymbol> visit)
    {
        foreach (var field in structType.Fields)
        {
            if (!field.Type.CarriesReferences()) continue;

            string slot = Emit("ptr",
                $"getelementptr inbounds {StructName(structType)}, ptr {address}, " +
                $"i32 0, i32 {field.Index}");

            if (field.Type is StructTypeSymbol nested) WalkReferences(slot, nested, visit);
            else visit(slot, field.Type);
        }
    }

    /// <summary>Registers a +1 value for release once the current statement finishes.</summary>
    private void TrackTemporary(string reference, TypeSymbol type) =>
        _pendingReleases.Add((reference, type));

    private void FlushTemporaries(int from = 0)
    {
        for (int i = from; i < _pendingReleases.Count; i++)
        {
            var (reference, type) = _pendingReleases[i];

            // A struct temporary is held by address, so what is dropped is what
            // lies inside it rather than the pointer itself.
            if (type is StructTypeSymbol structType)
            {
                ReleaseFieldsAt(reference, structType);
                continue;
            }

            Line(type is WeakTypeSymbol
                ? $"call void @sl_weak_release(ptr {reference})"
                : $"call void @sl_release(ptr {reference})");
        }

        _pendingReleases.RemoveRange(from, _pendingReleases.Count - from);
    }

    /// <summary>
    /// Stores into an owning slot: retain the new value, release the old one, in
    /// that order, so <c>x = x</c> cannot destroy the object mid-assignment.
    /// </summary>
    private void StoreManaged(string slot, string value, TypeSymbol type)
    {
        bool weak = type is WeakTypeSymbol;
        Line($"call void @{(weak ? "sl_weak_retain" : "sl_retain")}(ptr {value})");
        string old = Emit("ptr", $"load ptr, ptr {slot}");
        Line($"call void @{(weak ? "sl_weak_release" : "sl_release")}(ptr {old})");
        Line($"store ptr {value}, ptr {slot}");
    }

    // ============================================================ statements

    private void EmitStatement(BoundStatement statement)
    {
        switch (statement)
        {
            case BoundBlock block: EmitBlock(block); break;
            case BoundLocalDeclaration declaration: EmitLocalDeclaration(declaration); break;
            case BoundExpressionStatement expression: EmitExpressionStatement(expression); break;
            case BoundIf ifStatement: EmitIf(ifStatement); break;
            case BoundWhile whileStatement: EmitWhile(whileStatement); break;
            case BoundFor forStatement: EmitFor(forStatement); break;
            case BoundSwitch switchStatement: EmitSwitch(switchStatement); break;
            case BoundParallel parallel: EmitParallel(parallel); break;
            case BoundParallelFor parallelFor: EmitParallelFor(parallelFor); break;
            case BoundSpawn spawn: EmitSpawn(spawn); break;
            case BoundReturn returnStatement: EmitReturn(returnStatement); break;
            case BoundBreak: EmitJump(isBreak: true); break;
            case BoundContinue: EmitJump(isBreak: false); break;
        }
    }

    private void EmitBlock(BoundBlock block)
    {
        PushScope();
        foreach (var statement in block.Statements) EmitStatement(statement);
        if (!_blockTerminated) ReleaseCurrentScope();
        PopScopeWithoutRelease();
    }

    private void EmitLocalDeclaration(BoundLocalDeclaration declaration)
    {
        var local = declaration.Local;
        string llvmType = LlvmTypeOf(local.Type);
        string slot = Alloca(llvmType, local.Name);
        _slots[local] = slot;

        if (local.Type.IsManagedSlot())
        {
            // Owned slots start null so the first assignment's release is a no-op.
            Line($"store ptr null, ptr {slot}");
            TrackOwnedLocal(slot, local.Type);
        }
        else if (local.Type is StructTypeSymbol { } owning && owning.CarriesReferences())
        {
            // The same reason, one level down: the references inside start null
            // so the first assignment releases nothing.
            Line($"store {StructName(owning)} zeroinitializer, ptr {slot}");
            TrackOwnedLocal(slot, local.Type);
        }

        if (declaration.Initializer is not null)
        {
            var value = EmitExpression(declaration.Initializer);
            StoreInto(slot, value, local.Type);
        }
        else if (local.Type is StructTypeSymbol structType && !structType.CarriesReferences())
        {
            Line($"store {StructName(structType)} zeroinitializer, ptr {slot}");
        }

        FlushTemporaries();
    }

    private void EmitExpressionStatement(BoundExpressionStatement statement)
    {
        EmitExpression(statement.Expression);
        FlushTemporaries();
    }

    private void EmitIf(BoundIf statement)
    {
        var condition = EmitExpression(statement.Condition);
        FlushTemporaries();

        string thenLabel = NextLabel("if.then");
        string elseLabel = NextLabel("if.else");
        string endLabel = NextLabel("if.end");

        Terminator($"br i1 {condition.Ref}, label %{thenLabel}, label %{(statement.Else is null ? endLabel : elseLabel)}");

        Label(thenLabel);
        EmitStatement(statement.Then);
        if (!_blockTerminated) Terminator($"br label %{endLabel}");

        if (statement.Else is not null)
        {
            Label(elseLabel);
            EmitStatement(statement.Else);
            if (!_blockTerminated) Terminator($"br label %{endLabel}");
        }

        Label(endLabel);
    }

    private void EmitWhile(BoundWhile statement)
    {
        string conditionLabel = NextLabel("while.cond");
        string bodyLabel = NextLabel("while.body");
        string endLabel = NextLabel("while.end");

        Terminator($"br label %{conditionLabel}");
        Label(conditionLabel);

        var condition = EmitExpression(statement.Condition);
        FlushTemporaries();
        Terminator($"br i1 {condition.Ref}, label %{bodyLabel}, label %{endLabel}");

        Label(bodyLabel);
        _loops.Add((endLabel, _scopes.Count, conditionLabel, _scopes.Count));
        EmitStatement(statement.Body);
        _loops.RemoveAt(_loops.Count - 1);
        if (!_blockTerminated) Terminator($"br label %{conditionLabel}");

        Label(endLabel);
    }

    private void EmitFor(BoundFor statement)
    {
        PushScope();
        if (statement.Initializer is not null) EmitStatement(statement.Initializer);

        string conditionLabel = NextLabel("for.cond");
        string bodyLabel = NextLabel("for.body");
        string stepLabel = NextLabel("for.step");
        string endLabel = NextLabel("for.end");

        Terminator($"br label %{conditionLabel}");
        Label(conditionLabel);

        if (statement.Condition is not null)
        {
            var condition = EmitExpression(statement.Condition);
            FlushTemporaries();
            Terminator($"br i1 {condition.Ref}, label %{bodyLabel}, label %{endLabel}");
        }
        else
        {
            Terminator($"br label %{bodyLabel}");
        }

        Label(bodyLabel);
        // `continue` jumps to the step, not the condition, so the loop still advances.
        _loops.Add((endLabel, _scopes.Count, stepLabel, _scopes.Count));
        EmitStatement(statement.Body);
        _loops.RemoveAt(_loops.Count - 1);
        if (!_blockTerminated) Terminator($"br label %{stepLabel}");

        Label(stepLabel);
        if (statement.Step is not null)
        {
            EmitExpression(statement.Step);
            FlushTemporaries();
        }
        Terminator($"br label %{conditionLabel}");

        Label(endLabel);
        if (!_blockTerminated) ReleaseCurrentScope();
        PopScopeWithoutRelease();
    }

    /// <summary>
    /// Emits a switch: one dispatch, then the sections.
    ///
    /// An ordinal switch becomes a single LLVM <c>switch</c>, which is what
    /// makes a jump table possible — LLVM decides between one and a chain of
    /// comparisons from the density of the labels, which is a better judge than
    /// this compiler would be. A String switch has no such instruction and
    /// becomes a chain of calls to the runtime's comparison.
    /// </summary>
    private void EmitSwitch(BoundSwitch statement)
    {
        var value = EmitExpression(statement.Value);
        FlushTemporaries();

        string endLabel = NextLabel("switch.end");
        var bodies = statement.Sections.Select(_ => NextLabel("switch.section")).ToList();

        int defaultIndex = statement.Sections.ToList().FindIndex(s => s.IsDefault);
        string defaultLabel = defaultIndex < 0 ? endLabel : bodies[defaultIndex];

        // A reference governor was spilled into a local by the binder, so it is
        // alive across every one of these blocks.
        if (statement.Value.Type.NeedsArc())
        {
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var label in statement.Sections[i].Labels)
                {
                    var text = EmitExpression(label);
                    string same = Emit("i1",
                        $"call i1 @sl_string_equals(ptr {value.Ref}, ptr {text.Ref})");
                    string next = NextLabel("switch.test");
                    Terminator($"br i1 {same}, label %{bodies[i]}, label %{next}");
                    Label(next);
                }

            Terminator($"br label %{defaultLabel}");
        }
        else
        {
            var arms = new List<string>();
            for (int i = 0; i < statement.Sections.Count; i++)
                foreach (var label in statement.Sections[i].Labels)
                {
                    var constant = EmitExpression(label);
                    arms.Add($"{constant.LlvmType} {constant.Ref}, label %{bodies[i]}");
                }

            Terminator($"switch {value.LlvmType} {value.Ref}, label %{defaultLabel} " +
                       $"[ {string.Join(" ", arms)} ]");
        }

        // `break` lands after the switch; `continue` still belongs to whatever
        // loop encloses it, and unwinds to that loop's depth.
        string continueLabel = _loops.Count > 0 ? _loops[^1].ContinueLabel : endLabel;
        int continueDepth = _loops.Count > 0 ? _loops[^1].ContinueDepth : _scopes.Count;
        _loops.Add((endLabel, _scopes.Count, continueLabel, continueDepth));

        foreach (var (section, label) in statement.Sections.Zip(bodies))
        {
            Label(label);
            EmitStatement(section.Body);
            if (!_blockTerminated) Terminator($"br label %{endLabel}");
        }

        _loops.RemoveAt(_loops.Count - 1);

        Label(endLabel);
    }

    private void EmitReturn(BoundReturn statement)
    {
        var returnInfo = _returnInfo;

        if (statement.Value is null)
        {
            FlushTemporaries();
            ReleaseScopes(0);
            Terminator("ret void");
            return;
        }

        var value = EmitExpression(statement.Value);

        // A returned reference is handed to the caller at +1.
        if (value.Type.NeedsArc())
            Line($"call void @sl_retain(ptr {value.Ref})");

        if (value.Type is StructTypeSymbol structType)
        {
            // The same +1, field by field: the caller receives a copy that owns
            // what it holds, and this frame is about to release its own.
            if (structType.CarriesReferences()) RetainFieldsAt(value.Ref, structType);

            if (_sretSlot is not null)
            {
                MemCopy(_sretSlot, value.Ref, structType.Size);
                FlushTemporaries();
                ReleaseScopes(0);
                Terminator("ret void");
            }
            else
            {
                // Register-sized struct: reinterpret the bytes as an integer.
                string coerced = Emit(returnInfo.LlvmType, $"load {returnInfo.LlvmType}, ptr {value.Ref}");
                FlushTemporaries();
                ReleaseScopes(0);
                Terminator($"ret {returnInfo.LlvmType} {coerced}");
            }
            return;
        }

        // Materialise the value before releasing anything that might own it.
        string slot = Alloca(value.LlvmType, "ret");
        Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");
        FlushTemporaries();
        ReleaseScopes(0);
        string result = Emit(value.LlvmType, $"load {value.LlvmType}, ptr {slot}");
        Terminator($"ret {value.LlvmType} {result}");
    }

    private void EmitJump(bool isBreak)
    {
        if (_loops.Count == 0) return;
        var frame = _loops[^1];
        FlushTemporaries();
        ReleaseScopes(isBreak ? frame.BreakDepth : frame.ContinueDepth);
        Terminator($"br label %{(isBreak ? frame.BreakLabel : frame.ContinueLabel)}");
    }

    // ============================================================ expressions

    private Val EmitExpression(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundLiteral literal: return EmitLiteral(literal);
            case BoundStringLiteral text:
                return new Val(InternStringObject(text.Value), "ptr", text.Type);
            case BoundNullLiteral nullLiteral: return new Val("null", "ptr", nullLiteral.Type);
            case BoundConstantAccess constant: return EmitConstant(constant);
            case BoundStaticAccess shared: return EmitStaticAccess(shared);
            case BoundSizeof sizeofExpression:
                return new Val(sizeofExpression.MeasuredType.Size.ToString(), "i64", sizeofExpression.Type);

            case BoundLocalAccess or BoundParameterAccess or BoundThis
                 or BoundFieldAccess or BoundDereference or BoundIndex:
                return LoadFrom(expression);

            case BoundAddressOf addressOf:
                return new Val(EmitAddress(addressOf.Operand), "ptr", addressOf.Type);

            case BoundConversion conversion: return EmitConversion(conversion);
            case BoundUnary unary: return EmitUnary(unary);
            case BoundBinary binary: return EmitBinary(binary);
            case BoundConditional conditional: return EmitConditional(conditional);
            case BoundFunctionReference reference:
                return new Val("@" + reference.Function.MangledName, "ptr", reference.Type);
            case BoundIndirectCall indirect: return EmitIndirectCall(indirect);
            case BoundAssignment assignment: return EmitAssignment(assignment);
            case BoundPropertyAssignment written: return EmitPropertyAssignment(written);
            case BoundCall call: return EmitCall(call);
            case BoundNew newExpression: return EmitNew(newExpression);
            case BoundClosure closure: return EmitClosure(closure);
            case BoundNewArray newArray: return EmitNewArray(newArray);
            case BoundArrayLength length: return EmitArrayLength(length);
            case BoundTypeof typeofExpression: return EmitTypeof(typeofExpression);
            case BoundResultConstruction result: return EmitResultConstruction(result);

            default:
                return new Val("0", "i32", PrimitiveTypeSymbol.Int);
        }
    }

    private Val EmitLiteral(BoundLiteral literal)
    {
        string llvmType = LlvmTypeOf(literal.Type);
        string text = literal.Value switch
        {
            bool flag => flag ? "true" : "false",
            char character => ((int)character).ToString(CultureInfo.InvariantCulture),
            double number => FormatDouble(number),
            ulong number => FormatInteger(number, literal.Type),
            _ => "0",
        };
        return new Val(text, llvmType, literal.Type);
    }

    private static string FormatInteger(ulong value, TypeSymbol type)
    {
        // An enum is its underlying integer, and is spelled as one.
        if (type is EnumTypeSymbol enumType) type = enumType.UnderlyingType;

        // LLVM wants the signed two's-complement spelling for signed types.
        if (type is PrimitiveTypeSymbol { IsSigned: true, Size: var size })
        {
            long signed = size switch
            {
                1 => (sbyte)value,
                2 => (short)value,
                4 => (int)value,
                _ => (long)value,
            };
            return signed.ToString(CultureInfo.InvariantCulture);
        }
        return value.ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>LLVM accepts a double as a 16-digit hex bit pattern, which never loses precision.</summary>
    private static string FormatDouble(double value) =>
        "0x" + BitConverter.DoubleToUInt64Bits(value).ToString("X16", CultureInfo.InvariantCulture);

    private Val EmitConstant(BoundConstantAccess access)
    {
        var constant = access.Constant;
        string llvmType = LlvmTypeOf(constant.Type);
        string text = constant.Value switch
        {
            bool flag => flag ? "true" : "false",
            char character => ((int)character).ToString(CultureInfo.InvariantCulture),
            double number => FormatDouble(number),
            ulong number => FormatInteger(number, constant.Type),
            string s => InternBytes(s),
            _ => "0",
        };
        return new Val(text, llvmType, constant.Type);
    }

    /// <summary>Computes the address of an lvalue expression.</summary>
    private string EmitAddress(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundStaticAccess shared:
                return "@" + StaticName(shared.Static);

            case BoundLocalAccess local:
                return _slots[local.Local];

            case BoundParameterAccess parameter:
                return _parameterSlots[parameter.Parameter];

            case BoundThis thisExpression:
                return _parameterSlots[thisExpression.Parameter];

            case BoundFieldAccess field:
                return EmitFieldAddress(field);

            case BoundDereference dereference:
            {
                var pointer = EmitExpression(dereference.Operand);
                return pointer.Ref;
            }

            case BoundIndex index:
            {
                if (index.Target.Type is ArrayTypeSymbol) return EmitArrayElementAddress(index);

                var target = EmitExpression(index.Target);
                var offset = EmitExpression(index.Index);
                string elementType = LlvmTypeOf(index.Type);
                string widened = WidenIndex(offset);
                return Emit("ptr",
                    $"getelementptr inbounds {elementType}, ptr {target.Ref}, i64 {widened}");
            }

            default:
            {
                // A temporary that needs an address: materialise it.
                var value = EmitExpression(expression);
                if (value.IsStructAddress) return value.Ref;
                string slot = Alloca(value.LlvmType, "temp");
                Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");
                return slot;
            }
        }
    }

    private string WidenIndex(Val index)
    {
        if (index.LlvmType == "i64") return index.Ref;
        return Emit("i64", $"{(IsSigned(index.Type) ? "sext" : "zext")} {index.LlvmType} {index.Ref} to i64");
    }

    private string EmitFieldAddress(BoundFieldAccess access)
    {
        var field = access.Field;

        if (field.ContainingType is ClassTypeSymbol)
        {
            // The receiver is already a reference; fields live past the header.
            var receiver = EmitExpression(access.Receiver!);
            return ClassFieldAddress(receiver.Ref, field);
        }

        // Struct receiver: address of the value, then a structural GEP.
        string baseAddress = access.Receiver is null
            ? throw new InvalidOperationException("struct field access needs a receiver")
            : EmitAddress(access.Receiver);

        var structType = (StructTypeSymbol)field.ContainingType;
        return Emit("ptr",
            $"getelementptr inbounds {StructName(structType)}, ptr {baseAddress}, i32 0, i32 {field.Index}");
    }

    private string ClassFieldAddress(string objectRef, FieldSymbol field) =>
        Emit("ptr",
            $"getelementptr inbounds i8, ptr {objectRef}, i64 {ClassTypeSymbol.HeaderSize + field.Offset}");

    private Val LoadFrom(BoundExpression expression)
    {
        // A struct is represented by its address, so there is nothing to load.
        if (expression.Type is StructTypeSymbol)
            return new Val(EmitAddress(expression), "ptr", expression.Type);

        string address = EmitAddress(expression);
        string llvmType = LlvmTypeOf(expression.Type);
        return new Val(Emit(llvmType, $"load {llvmType}, ptr {address}"), llvmType, expression.Type);
    }

    private void StoreInto(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is StructTypeSymbol structType)
        {
            // Retain before release, for the reason StoreManaged does it: a
            // struct assigned to itself must not destroy what it is copying.
            if (structType.CarriesReferences())
            {
                RetainFieldsAt(value.Ref, structType);
                ReleaseFieldsAt(slot, structType);
            }

            MemCopy(slot, value.Ref, structType.Size);
            return;
        }

        if (targetType.IsManagedSlot())
        {
            StoreManaged(slot, value.Ref, targetType);
            return;
        }

        Line($"store {LlvmTypeOf(targetType)} {value.Ref}, ptr {slot}");
    }

    private Val EmitAssignment(BoundAssignment assignment)
    {
        var value = EmitExpression(assignment.Value);
        string address = EmitAddress(assignment.Target);
        StoreInto(address, value, assignment.Target.Type);
        return value;
    }

    /// <summary>
    /// Calls a setter, then hands back the value it was given.
    ///
    /// A setter returns nothing, but an assignment is an expression whose value
    /// is what was stored — so the value is emitted here rather than inside a
    /// call that would swallow it. Dispatch is resolved before the value for the
    /// reason <see cref="EmitCall"/> resolves it before the arguments: the
    /// value's own code must not be able to change which object is written.
    /// </summary>
    private Val EmitPropertyAssignment(BoundPropertyAssignment assignment)
    {
        var setter = assignment.Property.Setter!;

        var receiver = EmitExpression(assignment.Receiver);
        string? virtualTarget = setter.ContainingType is InterfaceTypeSymbol
            ? LoadInterfaceMethod(receiver.Ref, setter)
            : null;

        var value = EmitExpression(assignment.Value);

        var arguments = new List<string> { $"ptr {receiver.Ref}" };
        AppendArgument(value, assignment.Value.Type, arguments);

        Line($"call void {virtualTarget ?? "@" + setter.MangledName}" +
             $"({string.Join(", ", arguments)})");

        return value;
    }

    private Val EmitConversion(BoundConversion conversion)
    {
        var operand = EmitExpression(conversion.Operand);
        string to = LlvmTypeOf(conversion.Type);
        string from = operand.LlvmType;

        switch (conversion.Kind)
        {
            case ConversionKind.Identity:
            case ConversionKind.PointerCast:
            case ConversionKind.NullToReference:
            case ConversionKind.ClassToInterface:

            // Storing is what makes a reference weak: the slot's type sends the
            // store through sl_weak_retain instead of sl_retain. The value
            // itself is the same pointer either way.
            case ConversionKind.ReferenceToWeak:
                // An interface reference is the very same pointer; the vtable is
                // reached through the object's TypeInfo, not carried alongside it.
                return new Val(operand.Ref, to, conversion.Type);

            case ConversionKind.StringLiteralToPointer:
                // Point at a plain byte array rather than into the object, so no
                // offset arithmetic is needed and the constant stays shareable.
                return new Val(
                    InternBytes(((BoundStringLiteral)conversion.Operand).Value), "ptr", conversion.Type);

            case ConversionKind.ReferenceToOptional:
                // A weak reference must be proven live before it can be used strongly.
                if (conversion.Operand.Type is WeakTypeSymbol)
                {
                    string loaded = Emit("ptr", $"call ptr @sl_weak_load(ptr {operand.Ref})");
                    TrackTemporary(loaded, conversion.Type);
                    return new Val(loaded, "ptr", conversion.Type);
                }
                return new Val(operand.Ref, to, conversion.Type);

            case ConversionKind.IntegerWiden:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted(IsSigned(conversion.Operand.Type) ? "sext" : "zext");

            case ConversionKind.IntegerNarrow:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted("trunc");

            case ConversionKind.IntToFloat:
                return Converted(IsSigned(conversion.Operand.Type) ? "sitofp" : "uitofp");

            case ConversionKind.FloatToInt:
                return Converted(IsSigned(conversion.Type) ? "fptosi" : "fptoui");

            case ConversionKind.FloatResize:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted(to == "double" ? "fpext" : "fptrunc");

            case ConversionKind.PointerToInteger:
                return Converted("ptrtoint");

            case ConversionKind.IntegerToPointer:
                return Converted("inttoptr");

            case ConversionKind.BoolToInteger:
                return Converted("zext");

            default:
                return new Val(operand.Ref, to, conversion.Type);
        }

        Val Converted(string instruction) =>
            new(Emit(to, $"{instruction} {from} {operand.Ref} to {to}"), to, conversion.Type);
    }

    private Val EmitUnary(BoundUnary unary)
    {
        var operand = EmitExpression(unary.Operand);
        string llvmType = operand.LlvmType;

        string instruction = unary.Operator switch
        {
            BoundUnaryOp.Negate when unary.Type is PrimitiveTypeSymbol { IsFloat: true } =>
                $"fneg {llvmType} {operand.Ref}",
            BoundUnaryOp.Negate => $"sub {llvmType} 0, {operand.Ref}",
            BoundUnaryOp.LogicalNot => $"xor i1 {operand.Ref}, true",
            _ => $"xor {llvmType} {operand.Ref}, -1",
        };

        return new Val(Emit(llvmType, instruction), llvmType, unary.Type);
    }

    private Val EmitBinary(BoundBinary binary)
    {
        if (binary.Operator is BoundBinaryOp.LogicalAnd or BoundBinaryOp.LogicalOr)
            return EmitShortCircuit(binary);

        // Pointer arithmetic is a GEP, not an add.
        if (binary.Left.Type is PointerTypeSymbol pointer &&
            binary.Operator is BoundBinaryOp.Add or BoundBinaryOp.Subtract)
        {
            var basePointer = EmitExpression(binary.Left);
            var offset = EmitExpression(binary.Right);
            string index = WidenIndex(offset);
            if (binary.Operator == BoundBinaryOp.Subtract)
                index = Emit("i64", $"sub i64 0, {index}");

            string element = LlvmTypeOf(pointer.Element);
            return new Val(
                Emit("ptr", $"getelementptr inbounds {element}, ptr {basePointer.Ref}, i64 {index}"),
                "ptr", binary.Type);
        }

        var left = EmitExpression(binary.Left);
        var right = EmitExpression(binary.Right);

        var operandType = binary.Left.Type;
        bool isFloat = operandType is PrimitiveTypeSymbol { IsFloat: true };
        bool signed = IsSigned(operandType);
        string type = left.LlvmType;

        string? comparison = binary.Operator switch
        {
            BoundBinaryOp.Equal => isFloat ? "fcmp oeq" : "icmp eq",

            // 'une', not 'one': IEEE says a NaN is unequal to everything
            // including itself, and an ordered compare would answer false to
            // exactly that. `x != x` is how NaN is detected.
            BoundBinaryOp.NotEqual => isFloat ? "fcmp une" : "icmp ne",
            BoundBinaryOp.Less => isFloat ? "fcmp olt" : signed ? "icmp slt" : "icmp ult",
            BoundBinaryOp.LessEqual => isFloat ? "fcmp ole" : signed ? "icmp sle" : "icmp ule",
            BoundBinaryOp.Greater => isFloat ? "fcmp ogt" : signed ? "icmp sgt" : "icmp ugt",
            BoundBinaryOp.GreaterEqual => isFloat ? "fcmp oge" : signed ? "icmp sge" : "icmp uge",
            _ => null,
        };

        if (comparison is not null)
            return new Val(
                Emit("i1", $"{comparison} {type} {left.Ref}, {right.Ref}"), "i1", PrimitiveTypeSymbol.Bool);

        string opcode = binary.Operator switch
        {
            BoundBinaryOp.Add => isFloat ? "fadd" : "add",
            BoundBinaryOp.Subtract => isFloat ? "fsub" : "sub",
            BoundBinaryOp.Multiply => isFloat ? "fmul" : "mul",
            BoundBinaryOp.Divide => isFloat ? "fdiv" : signed ? "sdiv" : "udiv",
            BoundBinaryOp.Remainder => isFloat ? "frem" : signed ? "srem" : "urem",
            BoundBinaryOp.BitAnd => "and",
            BoundBinaryOp.BitOr => "or",
            BoundBinaryOp.BitXor => "xor",
            BoundBinaryOp.ShiftLeft => "shl",
            _ => signed ? "ashr" : "lshr",
        };

        // Floating point division by zero is defined and produces an infinity;
        // integer division by zero is not, and neither is the one signed case
        // that overflows.
        if (!isFloat && binary.Operator is BoundBinaryOp.Divide or BoundBinaryOp.Remainder &&
            !IsSafeDivisor(binary.Right))
            GuardDivision(type, left.Ref, right.Ref, signed);

        string operand = binary.Operator is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight
            ? MaskShiftCount(type, right.Ref)
            : right.Ref;

        return new Val(
            Emit(type, $"{opcode} {type} {left.Ref}, {operand}"), type, binary.Type);
    }

    /// <summary>
    /// True for a divisor that cannot be zero and cannot make a division
    /// overflow, so the guard would be branches the optimiser only deletes again.
    ///
    /// A constant divisor is the overwhelmingly common case — <c>n / 2</c>,
    /// <c>i % 16</c> — and skipping it keeps the emitted IR the size it was.
    /// </summary>
    private static bool IsSafeDivisor(BoundExpression divisor) =>
        divisor is BoundLiteral { Value: ulong value } && value != 0
        && value != unchecked((ulong)-1);

    /// <summary>
    /// Traps on the integer divisions LLVM leaves undefined.
    ///
    /// Undefined is not "whatever the hardware does": the optimiser may fold an
    /// expression containing one to any value it likes, which is how <c>10 /
    /// Zero()</c> came to print a number and exit successfully. A language that
    /// bounds-checks every index should not quietly return nonsense here, so
    /// this is the same shape as the bounds check — compare, branch, abort.
    /// </summary>
    private void GuardDivision(string type, string dividend, string divisor, bool signed)
    {
        string zeroLabel = NextLabel("div.zero");
        string liveLabel = NextLabel("div.live");

        string byZero = Emit("i1", $"icmp eq {type} {divisor}, 0");
        Terminator($"br i1 {byZero}, label %{zeroLabel}, label %{liveLabel}");

        Label(zeroLabel);
        Line("call void @sl_divide_by_zero()");
        Terminator("unreachable");

        Label(liveLabel);
        if (!signed) return;

        // The one remaining undefined case: the most negative value divided by
        // -1 has no representable result.
        string overflowLabel = NextLabel("div.overflow");
        string okLabel = NextLabel("div.ok");

        string atMinimum = Emit("i1", $"icmp eq {type} {dividend}, {SmallestOf(type)}");
        string byNegativeOne = Emit("i1", $"icmp eq {type} {divisor}, -1");
        string overflows = Emit("i1", $"and i1 {atMinimum}, {byNegativeOne}");
        Terminator($"br i1 {overflows}, label %{overflowLabel}, label %{okLabel}");

        Label(overflowLabel);
        Line("call void @sl_divide_overflow()");
        Terminator("unreachable");

        Label(okLabel);
    }

    /// <summary>
    /// Reduces a shift count modulo the operand's width, which is what C# does.
    ///
    /// LLVM leaves a count at or past the width undefined, so <c>1 &lt;&lt; 40</c>
    /// on an <c>int</c> produced garbage rather than the 256 a C# reader
    /// expects. One <c>and</c> makes it defined, and costs nothing the hardware
    /// was not doing anyway.
    /// </summary>
    private string MaskShiftCount(string type, string count) =>
        Emit(type, $"and {type} {count}, {WidthOf(type) - 1}");

    private static int WidthOf(string llvmType) => llvmType switch
    {
        "i8" => 8,
        "i16" => 16,
        "i64" => 64,
        _ => 32,
    };

    /// <summary>The most negative value of a signed integer type, as LLVM spells it.</summary>
    private static string SmallestOf(string llvmType) => llvmType switch
    {
        "i8" => "-128",
        "i16" => "-32768",
        "i64" => "-9223372036854775808",
        _ => "-2147483648",
    };

    /// <summary>
    /// <c>&amp;&amp;</c> and <c>||</c> must not evaluate the right operand unless
    /// they have to, so they become branches with a phi rather than bitwise ops.
    /// </summary>
    private Val EmitShortCircuit(BoundBinary binary)
    {
        bool isAnd = binary.Operator == BoundBinaryOp.LogicalAnd;
        string rightLabel = NextLabel(isAnd ? "and.rhs" : "or.rhs");
        string endLabel = NextLabel(isAnd ? "and.end" : "or.end");

        var left = EmitExpression(binary.Left);
        string leftBlock = CurrentBlockLabel();

        Terminator(isAnd
            ? $"br i1 {left.Ref}, label %{rightLabel}, label %{endLabel}"
            : $"br i1 {left.Ref}, label %{endLabel}, label %{rightLabel}");

        Label(rightLabel);

        // Anything the right operand allocates is released here, at the end of
        // its own block. Deferring it to the merge would emit a release the
        // defining instruction does not dominate, since the merge is also
        // reached when the right operand never ran.
        int mark = _pendingReleases.Count;
        var right = EmitExpression(binary.Right);
        FlushTemporaries(mark);

        string rightBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(endLabel);
        string result = Emit("i1",
            $"phi i1 [ {(isAnd ? "false" : "true")}, %{leftBlock} ], [ {right.Ref}, %{rightBlock} ]");

        return new Val(result, "i1", PrimitiveTypeSymbol.Bool);
    }

    /// <summary>
    /// <c>a ? b : c</c>. Like the short-circuit operators this is branches and a
    /// phi, because only the chosen arm may run.
    /// </summary>
    private Val EmitConditional(BoundConditional expression)
    {
        string trueLabel = NextLabel("cond.true");
        string falseLabel = NextLabel("cond.false");
        string endLabel = NextLabel("cond.end");

        var condition = EmitExpression(expression.Condition);
        Terminator($"br i1 {condition.Ref}, label %{trueLabel}, label %{falseLabel}");

        Label(trueLabel);
        var whenTrue = EmitArm(expression.WhenTrue);
        string trueBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(falseLabel);
        var whenFalse = EmitArm(expression.WhenFalse);
        string falseBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(endLabel);
        string llvmType = whenTrue.LlvmType;
        string result = Emit(llvmType,
            $"phi {llvmType} [ {whenTrue.Ref}, %{trueBlock} ], [ {whenFalse.Ref}, %{falseBlock} ]");

        // The arms each left a +1 reference; the merged one is now the temporary.
        if (expression.Type.NeedsArc() || expression.Type.CarriesReferences())
            TrackTemporary(result, expression.Type);

        return new Val(result, llvmType, expression.Type);
    }

    /// <summary>
    /// Emits one arm of a conditional so that it leaves exactly one owned
    /// reference behind and no temporaries of its own.
    ///
    /// Anything the arm allocated has to be released inside the arm's own block,
    /// since the merge is also reached when the arm never ran and a release
    /// there would not be dominated by its definition. Retaining first means the
    /// surviving value is independent of whatever the flush destroys.
    /// </summary>
    private Val EmitArm(BoundExpression arm)
    {
        int mark = _pendingReleases.Count;
        var value = EmitExpression(arm);

        if (arm.Type.NeedsArc()) Line($"call void @sl_retain(ptr {value.Ref})");
        else if (arm.Type is StructTypeSymbol structArm && structArm.CarriesReferences())
            RetainFieldsAt(value.Ref, structArm);

        FlushTemporaries(mark);

        return value;
    }

    private string CurrentBlockLabel() => _currentBlock;

    private Val EmitNew(BoundNew expression)
    {
        var classType = expression.ClassType;

        // A runtime-provided class builds itself; sl_alloc knows nothing of its
        // variable-sized or externally managed storage.
        if (classType.RuntimeFactory is not null)
        {
            string built = Emit("ptr", $"call ptr @{classType.RuntimeFactory}()");
            TrackTemporary(built, classType);
            return new Val(built, "ptr", classType);
        }

        string instance = Emit("ptr",
            $"call ptr @sl_alloc(ptr @{Mangler.TypeInfoSymbol(classType)})");

        if (expression.Constructor is not null)
        {
            var arguments = new List<string> { $"ptr {instance}" };
            AppendArguments(expression.Arguments, arguments);
            Line($"call void @{expression.Constructor.MangledName}({string.Join(", ", arguments)})");
        }

        // sl_alloc already returns +1; the statement scope releases it.
        TrackTemporary(instance, classType);
        return new Val(instance, "ptr", classType);
    }

    /// <summary>
    /// Loads the implementation of an interface method for whatever object the
    /// receiver actually is:
    ///
    ///   object -> TypeInfo -> interface table -> vtable -> slot
    ///
    /// Four loads and an indirect call, all constant-offset, with no search and
    /// no branch. It is one load more than a C++ virtual call, which is the
    /// price of leaving the object header alone.
    /// </summary>
    private string LoadInterfaceMethod(string receiver, FunctionSymbol method)
    {
        var interfaceType = (InterfaceTypeSymbol)method.ContainingType!;
        int slot = interfaceType.SlotOf(method);

        string typeSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {receiver}, i64 16");
        string typeInfo = Emit("ptr", $"load ptr, ptr {typeSlot}");

        string tablesSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {typeInfo}, i64 24");
        string tables = Emit("ptr", $"load ptr, ptr {tablesSlot}");

        string vtableSlot = Emit("ptr",
            $"getelementptr inbounds ptr, ptr {tables}, i64 {interfaceType.Id}");
        string vtable = Emit("ptr", $"load ptr, ptr {vtableSlot}");

        string methodSlot = Emit("ptr", $"getelementptr inbounds ptr, ptr {vtable}, i64 {slot}");
        return Emit("ptr", $"load ptr, ptr {methodSlot}");
    }

    /// <summary>
    /// Builds a closure: allocate the generated class, then copy each captured
    /// value into its field.
    ///
    /// Capture is by value, so a captured reference is retained here and
    /// released by the class's destroy hook -- which the emitter already writes
    /// for every class. The closure therefore owns what it captured and may
    /// outlive the scope that made it.
    /// </summary>
    private Val EmitClosure(BoundClosure closure)
    {
        var type = closure.ClosureType;

        string instance = Emit("ptr",
            $"call ptr @sl_alloc(ptr @{Mangler.TypeInfoSymbol(type)})");

        foreach (var (field, value) in closure.Captures)
        {
            var captured = EmitExpression(value);
            string address = Emit("ptr",
                $"getelementptr inbounds i8, ptr {instance}, i64 " +
                $"{ClassTypeSymbol.HeaderSize + field.Offset}");

            StoreInto(address, captured, field.Type);
        }

        TrackTemporary(instance, type);
        return new Val(instance, "ptr", closure.Type);
    }

    private Val EmitNewArray(BoundNewArray expression)
    {
        var arrayType = expression.ArrayType;
        var length = EmitExpression(expression.Length);

        string array = Emit("ptr",
            $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
            $"i64 {length.Ref}, i64 {arrayType.Element.Size})");

        TrackTemporary(array, arrayType);
        return new Val(array, "ptr", arrayType);
    }

    /// <summary>
    /// A type handle is a one-pointer struct, so this is a constant stored into
    /// a slot: no lookup, no allocation, nothing at run time.
    /// </summary>
    private Val EmitTypeof(BoundTypeof expression)
    {
        var handleType = (StructTypeSymbol)expression.Type;
        string slot = Alloca(StructName(handleType), "typeof");
        Line($"store ptr {TypeInfoOf(expression.MeasuredType)}, ptr {slot}");
        return new Val(slot, "ptr", handleType);
    }

    private Val EmitArrayLength(BoundArrayLength expression)
    {
        var array = EmitExpression(expression.Array);
        string slot = Emit("ptr", $"getelementptr inbounds i8, ptr {array.Ref}, i64 24");
        return new Val(Emit("i64", $"load i64, ptr {slot}"), "i64", expression.Type);
    }

    /// <summary>
    /// Computes the address of <c>array[index]</c>, trapping first if the index
    /// is out of range. The index is unsigned, so one compare covers both ends.
    /// </summary>
    private string EmitArrayElementAddress(BoundIndex index)
    {
        var arrayType = (ArrayTypeSymbol)index.Target.Type;
        var array = EmitExpression(index.Target);
        var offset = EmitExpression(index.Index);

        string widened = WidenIndex(offset);
        string lengthSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {array.Ref}, i64 24");
        string length = Emit("i64", $"load i64, ptr {lengthSlot}");
        string inRange = Emit("i1", $"icmp ult i64 {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail(i64 {widened}, i64 {length})");
        Terminator("unreachable");

        Label(okLabel);
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array.Ref}, i64 {ArrayTypeSymbol.HeaderSize}");
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(arrayType.Element)}, ptr {data}, i64 {widened}");
    }

    /// <summary>
    /// A call through a delegate. The only difference from a direct call is that
    /// the target is a loaded pointer rather than a symbol, so the signature has
    /// to be written out for LLVM to know how to call it.
    /// </summary>
    private Val EmitIndirectCall(BoundIndirectCall call)
    {
        var delegateType = call.DelegateType;
        var returnInfo = Win64Abi.ClassifyReturn(delegateType.ReturnType, LlvmTypeOf);

        // Resolved before the arguments, so an argument that is itself a call
        // cannot disturb the target this one loaded.
        var target = EmitExpression(call.Target);

        var arguments = new List<string>();
        string? sretSlot = null;

        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)delegateType.ReturnType;
            sretSlot = Alloca(StructName(structType), "call.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        AppendArguments(call.Arguments, arguments);

        string signature = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
        string invocation = $"call {signature} {target.Ref}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            return new Val(sretSlot!, "ptr", delegateType.ReturnType);
        }

        if (delegateType.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        var result = new Val(Emit(signature, invocation), signature, delegateType.ReturnType);
        if (delegateType.ReturnType.NeedsArc()) TrackTemporary(result.Ref, delegateType.ReturnType);
        return result;
    }

    private Val EmitCall(BoundCall call)
    {
        var function = call.Function;
        var returnInfo = Win64Abi.ClassifyReturn(function.ReturnType, LlvmTypeOf);

        var arguments = new List<string>();
        string? sretSlot = null;

        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)function.ReturnType;
            sretSlot = Alloca(StructName(structType), "call.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        // Held locally, not in a field: an argument may itself be an interface
        // call, and a field would let the inner call overwrite this one's target.
        string? virtualTarget = null;

        if (call.Receiver is not null)
        {
            var receiver = EmitExpression(call.Receiver);
            arguments.Add($"ptr {receiver.Ref}");

            // Resolved before the arguments so the load reads the receiver as it
            // was, whatever the arguments go on to do.
            if (function.ContainingType is InterfaceTypeSymbol)
                virtualTarget = LoadInterfaceMethod(receiver.Ref, function);
        }

        AppendArguments(call.Arguments, arguments);

        string signature = function.IsVariadic
            ? $"{(returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType)} " +
              $"({VariadicSignature(function)})"
            : returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;

        // An interface method is reached through the object; everything else is
        // a direct call to a known symbol.
        string target = virtualTarget ?? "@" + function.MangledName;

        string invocation =
            $"call {signature} {target}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            if (function.ReturnType.CarriesReferences())
                TrackTemporary(sretSlot!, function.ReturnType);
            return new Val(sretSlot!, "ptr", function.ReturnType);
        }

        if (function.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        string result = Emit(returnInfo.LlvmType, invocation);

        if (returnInfo.Style == PassStyle.CoerceToInteger)
        {
            // Land the register-sized struct back in memory so it has an address.
            var structType = (StructTypeSymbol)function.ReturnType;
            string slot = Alloca(StructName(structType), "call.result");
            Line($"store {returnInfo.LlvmType} {result}, ptr {slot}");
            if (structType.CarriesReferences()) TrackTemporary(slot, structType);
            return new Val(slot, "ptr", function.ReturnType);
        }

        // A returned reference arrives at +1 and is dropped when the statement ends.
        if (function.ReturnType.NeedsArc())
            TrackTemporary(result, function.ReturnType);

        return new Val(result, returnInfo.LlvmType, function.ReturnType);
    }

    /// <summary>
    /// Builds an <c>Ok(x)</c> or <c>Fail(e)</c>: a zeroed Result with its flag
    /// set and the payload stored in whichever half it belongs to.
    ///
    /// Zeroing first is what lets the payload go in through the ordinary owning
    /// store: the half being written starts null, so its release is a no-op, and
    /// the half not being written stays null for the drop that eventually comes.
    /// The finished struct is a +1 temporary, exactly like one returned by a call.
    /// </summary>
    private Val EmitResultConstruction(BoundResultConstruction expression)
    {
        var result = (StructTypeSymbol)expression.Type;
        string slot = Alloca(StructName(result), expression.Succeeded ? "ok" : "fail");
        Line($"store {StructName(result)} zeroinitializer, ptr {slot}");

        var flag = result.FindStorage("ok")!;
        Line($"store i1 {(expression.Succeeded ? "true" : "false")}, ptr " +
             $"{Emit("ptr", $"getelementptr inbounds {StructName(result)}, ptr {slot}, " +
                            $"i32 0, i32 {flag.Index}")}");

        var field = result.FindStorage(expression.Succeeded ? "value" : "error")!;
        string address = Emit("ptr",
            $"getelementptr inbounds {StructName(result)}, ptr {slot}, i32 0, i32 {field.Index}");

        StoreInto(address, EmitExpression(expression.Payload), field.Type);

        if (result.CarriesReferences()) TrackTemporary(slot, result);
        return new Val(slot, "ptr", result);
    }

    private static string VariadicSignature(FunctionSymbol function)
    {
        var parts = function.Parameters
            .Select(p => Win64Abi.ClassifyArgument(p.Type, LlvmTypeOf).LlvmType)
            .ToList();
        parts.Add("...");
        return string.Join(", ", parts);
    }

    /// <summary>
    /// Lowers each argument to its ABI form. The callee is not needed: every
    /// argument was already converted to the parameter's type during binding, so
    /// the expression's own type is the one the ABI classifies.
    /// </summary>
    private void AppendArguments(
        IReadOnlyList<BoundExpression> expressions, List<string> arguments)
    {
        for (int i = 0; i < expressions.Count; i++)
            AppendArgument(EmitExpression(expressions[i]), expressions[i].Type, arguments);
    }

    /// <summary>Lowers one already-emitted value to its ABI form.</summary>
    private void AppendArgument(Val value, TypeSymbol type, List<string> arguments)
    {
        if (type is StructTypeSymbol structType)
        {
            var info = Win64Abi.ClassifyArgument(structType, LlvmTypeOf);
            if (info.Style == PassStyle.Indirect)
            {
                // Win64 passes a pointer to a copy the caller owns.
                string copy = Alloca(StructName(structType), "arg.copy");
                MemCopy(copy, value.Ref, structType.Size);
                arguments.Add($"ptr byval({StructName(structType)}) {copy}");
            }
            else
            {
                string coerced = Emit(info.LlvmType, $"load {info.LlvmType}, ptr {value.Ref}");
                arguments.Add($"{info.LlvmType} {coerced}");
            }
            return;
        }

        arguments.Add($"{value.LlvmType} {value.Ref}");
    }
}
