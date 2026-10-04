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

using System.Text;
using Stainless.Binding;

namespace Stainless.Emit;

/// <summary>
/// Objective-C classes defined here: the metadata the runtime reads at load,
/// and the IMP each selector is answered with.
///
/// The layout is clang's: a <c>class_t</c> and a metaclass in
/// <c>__objc_data</c>, each pointing at a <c>class_ro_t</c> with its method
/// list, and the class in <c>__objc_classlist</c>, which is how the runtime
/// finds it. A protocol a defined class adopts is written as a weak hidden
/// <c>protocol_t</c>; the runtime keeps the first one of each name it sees.
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>Runtime names of the classes this module defines, which it MUST NOT also declare.</summary>
    private readonly HashSet<string> _definedObjCClasses = new(StringComparer.Ordinal);

    /// <summary>Metadata the linker MUST keep although nothing in the code names it.</summary>
    private readonly List<string> _objcCompilerUsed = [];

    /// <summary>Protocol objects and their labels, kept as clang keeps them.</summary>
    private readonly List<string> _objcUsed = [];

    /// <summary>Strings in the Objective-C sections, by section and text.</summary>
    private readonly Dictionary<(string Section, string Text), string> _objcStrings = [];

    /// <summary>
    /// The strings' definitions, written after the metadata: a string is asked
    /// for while the line naming it is still being built.
    /// </summary>
    private readonly StringBuilder _objcStringData = new();

    /// <summary>The protocols written so far, by runtime name.</summary>
    private readonly Dictionary<string, string> _objcProtocolObjects = new(StringComparer.Ordinal);

    private const string MethodNameSection = "__TEXT,__objc_methname,cstring_literals";
    private const string MethodTypeSection = "__TEXT,__objc_methtype,cstring_literals";
    private const string ClassNameSection = "__TEXT,__objc_classname,cstring_literals";
    private const string ObjCConstSection = "__DATA, __objc_const";

    /// <summary><c>class_ro_t</c>'s flag for a metaclass.</summary>
    private const int RoMeta = 0x1;

    /// <summary>The size of a <c>class_t</c>, which is a metaclass's instance size.</summary>
    private const int ClassObjectSize = 40;

    /// <summary>
    /// Every class the program defines: its IMPs, then its metadata, then the
    /// list the runtime reads them from.
    /// </summary>
    private void ObjCClassMetadata(BoundProgram program)
    {
        var defined = program.ObjCClasses.Where(c => c.ObjC == ObjCClassKind.Defined).ToList();
        if (defined.Count == 0) return;

        foreach (var classType in defined)
            _definedObjCClasses.Add(classType.ObjCRuntimeName!);

        // Declared before any thunk is begun: a declaration written while a
        // body is being built would land inside it.
        Declare("objc_autoreleaseReturnValue", "declare ptr @objc_autoreleaseReturnValue(ptr) nounwind");
        Declare("objc_release", "declare void @objc_release(ptr) nounwind");
        Declare("__objc_personality_v0", "declare i32 @__objc_personality_v0(...)");
        Declare("_objc_empty_cache", "@_objc_empty_cache = external global ptr");
        foreach (var classType in defined)
        foreach (var external in classType.SelfAndBases().Skip(1).Where(c => c.ObjC == ObjCClassKind.Imported))
        {
            string name = external.ObjCRuntimeName!;
            ReachedModules.Add(external.ModuleName);
            Declare($"OBJC_CLASS_$_{name}", $"@\"OBJC_CLASS_$_{name}\" = external global ptr");
            Declare($"OBJC_METACLASS_$_{name}", $"@\"OBJC_METACLASS_$_{name}\" = external global ptr");
        }

        _module.AppendLine();
        foreach (var classType in defined)
        {
            foreach (var method in ObjCMethodsOf(classType))
                EmitImp(classType, method);
            EmitLifetimeImps(classType);
        }

        foreach (var classType in defined)
            EmitClassObjects(classType);

        _module.AppendLine(
            $"@\"OBJC_LABEL_CLASS_$\" = private global [{defined.Count} x ptr] " +
            $"[{string.Join(", ", defined.Select(c => $"ptr {ClassObject(c)}"))}], " +
            "section \"__DATA,__objc_classlist,regular,no_dead_strip\", align 8");
        _objcCompilerUsed.Add("@\"OBJC_LABEL_CLASS_$\"");
        _module.Append(_objcStringData);
        _objcStringData.Clear();
        _module.AppendLine();
    }

    /// <summary>
    /// The members of a class defined here that answer a selector, in
    /// declaration order: its methods, then its constructors that are inits.
    /// </summary>
    private static IEnumerable<FunctionSymbol> ObjCMethodsOf(ClassTypeSymbol classType) =>
        classType.Methods.Where(m => m.IsMessage && m.HasBody)
            .Concat(classType.Constructors.Where(c => c.InitSelector is not null));

    /// <summary>The selector a member answers: its own, or a constructor's init.</summary>
    private static string SelectorOf(FunctionSymbol method) => method.Selector ?? method.InitSelector!;

    private static string ClassObject(ClassTypeSymbol classType) =>
        $"@\"OBJC_CLASS_$_{classType.ObjCRuntimeName}\"";

    private static string MetaclassObject(ClassTypeSymbol classType) =>
        $"@\"OBJC_METACLASS_$_{classType.ObjCRuntimeName}\"";

    /// <summary>The IMP's symbol, named as clang names one: <c>-[Example.Canvas drawRect:]</c>.</summary>
    private static string ImpSymbol(ClassTypeSymbol classType, FunctionSymbol method) =>
        ImpSymbol(classType, SelectorOf(method), method.IsStatic);

    private static string ImpSymbol(ClassTypeSymbol classType, string selector, bool isStatic = false) =>
        $"@\"\\01{(isStatic ? '+' : '-')}[{classType.ObjCRuntimeName} {selector}]\"";

    // ------------------------------------------------------------- IMPs

    /// <summary>
    /// The function the runtime calls for one selector: <c>(self, _cmd,
    /// arguments)</c> under the C convention, calling the Stainless body.
    ///
    /// Arguments arrive at +0 and the body borrows them, so they pass straight
    /// through; what changes is a <c>BOOL</c> on Intel, an object handed back
    /// outside the owning families, which goes back autoreleased, and the
    /// receiver of an <c>init</c>, which the IMP was given and lets go of. An
    /// object parameter declared non-optional is checked for nil, and an
    /// Objective-C exception that reaches here stops the program.
    /// </summary>
    private void EmitImp(ClassTypeSymbol classType, FunctionSymbol method)
    {
        ResetFunctionState();
        _body.Clear();
        _blockTerminated = false;

        // A constructor's IMP is an init: it hands back the object it made.
        bool constructs = method.Kind == FunctionKind.Constructor;
        var returnInfo = ClassifyResult(method.ReturnType);
        bool boolResult = BoolIsByte && IsBool(method.ReturnType);
        var declared = new List<string>();
        var forwarded = new List<string>();

        if (returnInfo.Style == PassStyle.Indirect)
        {
            string sret = $"ptr sret({StructName((StructTypeSymbol)method.ReturnType)})";
            declared.Add($"{sret} %sret");
            forwarded.Add($"{sret} %sret");
        }

        declared.Add("ptr %self");
        declared.Add("ptr %_cmd");
        if (!method.IsStatic) forwarded.Add("ptr %self");

        string description = $"{(method.IsStatic ? "+" : "-")}[{classType.ObjCRuntimeName} {SelectorOf(method)}]";
        var checks = new List<(string Value, ParameterSymbol Parameter)>();

        // A block Objective-C hands over may be on its stack, so the body is
        // given a heap copy, let go of once it returns.
        var copied = new List<string>();

        foreach (var parameter in method.Parameters.Where(p => !p.IsThis))
        {
            var info = ClassifyParameter(parameter);
            string name = ArgumentName(parameter);

            if (IsBlock(parameter.Type) && !parameter.IsByReference)
            {
                declared.Add($"ptr {name}");
                string copy = Emit("ptr", $"call ptr @objc_retainBlock(ptr {name})");
                copied.Add(copy);
                forwarded.Add($"ptr {copy}");
                if (IsNeverNullReference(parameter.Type)) checks.Add((name, parameter));
                continue;
            }

            if (BoolIsByte && IsBool(parameter.Type) && !parameter.IsByReference)
            {
                declared.Add($"i8 signext {name}");
                forwarded.Add($"{info.LlvmType}{Widening(info)} {name}.bool");
                continue;
            }

            var spellings = Declared(info).ToList();
            for (int piece = 0; piece < spellings.Count; piece++)
            {
                string piecename = spellings.Count == 1 ? name : $"{name}.{piece}";
                declared.Add($"{spellings[piece]} {piecename}");
                forwarded.Add($"{spellings[piece]} {piecename}");
            }

            if (!parameter.IsByReference && IsObjCReference(parameter.Type) &&
                IsNeverNullReference(parameter.Type))
                checks.Add((name, parameter));
        }

        foreach (var parameter in method.Parameters.Where(p => !p.IsThis && BoolIsByte && IsBool(p.Type) && !p.IsByReference))
        {
            string name = ArgumentName(parameter);
            Line($"{name}.bool = icmp ne i8 {name}, 0");
        }

        foreach (var (value, parameter) in checks)
            RequireArgument(value, parameter, description);

        string ok = NextLabel("imp.ok");
        string landing = NextLabel("imp.unwind");
        string callee = SymbolSpelling(method);
        Reach(method);

        string bodyResult = ResultSpelling(returnInfo);
        bool hasResult = !(returnInfo.Style is PassStyle.Indirect or PassStyle.Ignore || method.ReturnType.IsVoid());
        string invocation = $"invoke {bodyResult} {callee}({string.Join(", ", forwarded)}) to label %{ok} unwind label %{landing}";
        string? result = hasResult ? Emit(returnInfo.LlvmType, invocation) : null;
        if (!hasResult)
        {
            Line(invocation);
            _blockTerminated = true;
        }
        else
        {
            _blockTerminated = true;
        }

        Label(ok);

        foreach (string copy in copied)
            Line($"call void @objc_release(ptr {copy})");

        // The IMP of an init was handed the receiver at +1, and the body only
        // borrowed it.
        if (method.ConsumesSelf)
            Line("call void @objc_release(ptr %self)");

        string returnSpelling;
        if (constructs)
        {
            Terminator("ret ptr %self");
            returnSpelling = "ptr";
        }
        else if (boolResult)
        {
            string widened = Emit("i8", $"zext i1 {result} to i8");
            Terminator($"ret i8 {widened}");
            returnSpelling = "signext i8";
        }
        else if (result is not null && IsObjCReference(method.ReturnType) && !method.ReturnsRetained)
        {
            string autoreleased = Emit("ptr", $"tail call ptr @objc_autoreleaseReturnValue(ptr {result})");
            Terminator($"ret ptr {autoreleased}");
            returnSpelling = bodyResult;
        }
        else
        {
            Terminator(result is null ? "ret void" : $"ret {returnInfo.LlvmType} {result}");
            returnSpelling = bodyResult;
        }

        EndImp(landing, description, $"{returnSpelling} {ImpSymbol(classType, method)}({string.Join(", ", declared)})");
    }

    /// <summary>
    /// Finishes an IMP: the landing pad an Objective-C exception stops the
    /// program at, and the definition around the body built so far.
    /// </summary>
    private void EndImp(string landing, string description, string signature)
    {
        Label(landing);
        Line("%exception = landingpad { ptr, i32 } catch ptr null");
        Line($"call void @sl_objc_exception(ptr {InternBytes(description)})");
        Terminator("unreachable");

        _module.AppendLine(
            $"define internal {signature}" + FrameAttributes + " personality ptr @__objc_personality_v0 {");
        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }

    /// <summary>
    /// A call into Stainless from an IMP, which an exception unwinds out of to
    /// the IMP's landing pad.
    /// </summary>
    private void InvokeFromImp(string call, string landing)
    {
        string next = NextLabel("imp.next");
        Terminator($"invoke {call} to label %{next} unwind label %{landing}");
        Label(next);
    }

    private void BeginImp()
    {
        ResetFunctionState();
        _body.Clear();
        _blockTerminated = false;
    }

    /// <summary>
    /// <c>.cxx_construct</c>, <c>.cxx_destruct</c> and <c>dealloc</c>: the
    /// IMPs a class defined here has for its field initializers, its fields
    /// and its destructor, which no declaration names a selector for.
    /// </summary>
    private void EmitLifetimeImps(ClassTypeSymbol classType)
    {
        if (HasCxxConstruct(classType))
        {
            BeginImp();
            string landing = NextLabel("imp.unwind");
            InitializeEvents("%self", classType, inherited: false);
            if (classType.ObjCFieldInitializer is { } initializer)
            {
                Reach(initializer);
                InvokeFromImp($"void {SymbolSpelling(initializer)}(ptr %self)", landing);
            }

            Terminator("ret ptr %self");
            EndImp(landing, $"-[{classType.ObjCRuntimeName} .cxx_construct]",
                $"ptr {ImpSymbol(classType, ".cxx_construct")}(ptr %self, ptr %_cmd)");
        }

        if (HasCxxDestruct(classType))
        {
            BeginImp();
            string landing = NextLabel("imp.unwind");
            foreach (var field in classType.Fields.Where(f => f.Type.CarriesReferences()))
            {
                string address = ClassFieldAddress("%self", field);
                if (field.Type is StructTypeSymbol structField)
                    ReleaseFieldsAt(address, structField);
                else
                    Release(Emit("ptr", $"load ptr, ptr {address}"), field.Type);
            }

            Terminator("ret void");
            EndImp(landing, $"-[{classType.ObjCRuntimeName} .cxx_destruct]",
                $"void {ImpSymbol(classType, ".cxx_destruct")}(ptr %self, ptr %_cmd)");
        }

        if (classType.Destructor is { } destructor)
        {
            BeginImp();
            string landing = NextLabel("imp.unwind");
            Reach(destructor);
            InvokeFromImp($"void {SymbolSpelling(destructor)}(ptr %self)", landing);

            // The superclass's dealloc last: it is what frees the object, and
            // .cxx_destruct, which releases the fields, runs inside it.
            string frame = Alloca("{ ptr, ptr }", "dealloc.super");
            Line($"store ptr %self, ptr {frame}");
            string classSlot = Emit("ptr", $"getelementptr inbounds {{ ptr, ptr }}, ptr {frame}, i32 0, i32 1");
            Line($"store ptr {Emit("ptr", $"load ptr, ptr {ClassReference(classType.BaseClass!)}")}, ptr {classSlot}");
            string selector = Emit("ptr", $"load ptr, ptr {SelectorReference("dealloc")}");
            Line($"call void @objc_msgSendSuper(ptr {frame}, ptr {selector})");
            _sendsToSuper = true;

            Terminator("ret void");
            EndImp(landing, $"-[{classType.ObjCRuntimeName} dealloc]",
                $"void {ImpSymbol(classType, "dealloc")}(ptr %self, ptr %_cmd)");
        }
    }

    /// <summary>True when the class has field initializers or events to set as it is allocated.</summary>
    private static bool HasCxxConstruct(ClassTypeSymbol classType) =>
        classType.ObjCFieldInitializer is not null ||
        classType.Events.Any(e => e.BackingField is { Type: ArrayTypeSymbol });

    /// <summary>True when the class has fields to release as it is freed.</summary>
    private static bool HasCxxDestruct(ClassTypeSymbol classType) =>
        classType.Fields.Any(f => f.Type.CarriesReferences());

    // ------------------------------------------------------------- objects and fields

    /// <summary>True once a function has made an object of a class defined here.</summary>
    private bool _allocatesObjC;

    /// <summary>True while the function being emitted is a constructor of a class defined here.</summary>
    private bool _inObjCConstructor;

    /// <summary>
    /// <c>new C(args)</c> for a class defined here: <c>objc_alloc</c>, which
    /// also runs the field initializers, and then the constructor over the
    /// object it made -- or, for a class that declares none, the
    /// <c>init</c> message, which may answer with another object.
    /// </summary>
    private Val EmitObjCNew(BoundNew expression)
    {
        var classType = expression.ClassType;
        var constructor = expression.Constructor!;
        _allocatesObjC = true;

        var arguments = new List<string>();
        if (!constructor.IsMessage)
            AppendArguments(expression.Arguments, arguments, expression.EvaluationOrder);

        string loadedClass = Emit("ptr", $"load ptr, ptr {ClassReference(classType)}");
        string instance = Emit("ptr", $"call ptr @objc_alloc(ptr {loadedClass})");

        if (!constructor.IsMessage)
        {
            arguments.Insert(0, $"ptr {instance}");
            Line($"call void {Symbol(constructor)}({string.Join(", ", arguments)})");
            return Fresh(new Val(instance, "ptr", classType));
        }

        // init consumes what alloc made and answers with the object to keep.
        string selector = Emit("ptr", $"load ptr, ptr {SelectorReference(constructor.Selector!)}");
        string made = Emit("ptr", $"call ptr @objc_msgSend(ptr {instance}, ptr {selector})");
        RequireMessageResult(made, constructor, classType);
        return Fresh(new Val(made, "ptr", classType));
    }

    /// <summary>
    /// A field of a class defined here: past the ivar the fields share, whose
    /// offset the runtime settles at load and this reads.
    /// </summary>
    private string ObjCFieldAddress(string objectRef, ClassTypeSymbol classType, FieldSymbol field)
    {
        string offset;
        if (IvarOffsetIsWord)
        {
            offset = Emit("i64", $"load i64, ptr {IvarOffsetSymbol(classType)}, align 8");
        }
        else
        {
            string narrow = Emit("i32", $"load i32, ptr {IvarOffsetSymbol(classType)}, align 4");
            offset = Emit("i64", $"sext i32 {narrow} to i64");
        }

        string at = field.Offset == 0 ? offset : Emit("i64", $"add i64 {offset}, {field.Offset}");
        return Emit("ptr", $"getelementptr inbounds i8, ptr {objectRef}, i64 {at}");
    }

    /// <summary>An ivar's offset is a word on Intel and 32 bits on Apple silicon, as clang has it.</summary>
    private static bool IvarOffsetIsWord => TargetPlatform.Current.Architecture == TargetArch.X64;

    private static string IvarOffsetSymbol(ClassTypeSymbol classType) =>
        $"@\"OBJC_IVAR_$_{classType.ObjCRuntimeName}._sl\"";

    /// <summary>
    /// After a constructor's superclass init: it MUST have answered with the
    /// object alloc made, which the constructor goes on to use as <c>this</c>.
    /// </summary>
    private void RequireSameObject(string result, string self, FunctionSymbol function)
    {
        string same = Emit("i1", $"icmp eq ptr {result}, {self}");
        string good = NextLabel("init.same");
        string bad = NextLabel("init.replaced");
        Terminator($"br i1 {same}, label %{good}, label %{bad}");

        Label(bad);
        Line($"call void @sl_objc_init_replaced(ptr {InternBytes(DescribeMessage(function, null))}, ptr {result})");
        Terminator("unreachable");

        Label(good);
    }

    /// <summary>
    /// An object parameter the declaration promises is never nil, checked as
    /// it arrives from Objective-C, which promised nothing.
    /// </summary>
    private void RequireArgument(string value, ParameterSymbol parameter, string description)
    {
        string present = Emit("i1", $"icmp ne ptr {value}, null");
        string good = NextLabel("imp.arg.ok");
        string bad = NextLabel("imp.arg.nil");
        Terminator($"br i1 {present}, label %{good}, label %{bad}");

        Label(bad);
        string type = parameter.Type is NamedTypeSymbol named ? named.QualifiedName : parameter.Type.Name;
        Line($"call void @sl_objc_nil_argument(ptr {InternBytes(description)}, " +
             $"ptr {InternBytes(parameter.Name)}, ptr {InternBytes(type)})");
        Terminator("unreachable");

        Label(good);
    }

    // ------------------------------------------------------------- class objects

    /// <summary>
    /// The class and its metaclass. The metaclass's <c>isa</c> is the root's
    /// metaclass and its superclass is the superclass's metaclass, as the
    /// runtime requires of every class.
    /// </summary>
    private void EmitClassObjects(ClassTypeSymbol classType)
    {
        string name = classType.ObjCRuntimeName!;
        var superclass = classType.BaseClass!;
        var root = classType.SelfAndBases().First(c => c.IsObjCRoot);

        string className = ObjCString(ClassNameSection, name);
        string protocols = ProtocolList($"_OBJC_CLASS_PROTOCOLS_$_{name}", classType.ObjCProtocols);

        int pointer = TargetPlatform.Current.PointerWidth;
        string objectType = $"@{2 * pointer}@0:{pointer}";
        string voidType = $"v{2 * pointer}@0:{pointer}";

        var instance = ObjCMethodsOf(classType).Where(m => !m.IsStatic)
            .Select(m => (SelectorOf(m), MethodTypeEncoding(m), (string?)ImpSymbol(classType, m)))
            .ToList();
        bool construct = HasCxxConstruct(classType);
        bool destruct = HasCxxDestruct(classType);
        if (classType.Destructor is not null)
            instance.Add(("dealloc", voidType, ImpSymbol(classType, "dealloc")));
        if (construct)
            instance.Add((".cxx_construct", objectType, ImpSymbol(classType, ".cxx_construct")));
        if (destruct)
            instance.Add((".cxx_destruct", voidType, ImpSymbol(classType, ".cxx_destruct")));

        string instanceMethods = MethodList($"_OBJC_$_INSTANCE_METHODS_{name}", instance);
        string classMethods = MethodList(
            $"_OBJC_$_CLASS_METHODS_{name}",
            ObjCMethodsOf(classType).Where(m => m.IsStatic)
                .Select(m => (SelectorOf(m), MethodTypeEncoding(m), (string?)ImpSymbol(classType, m))));

        // RO_HAS_CXX_STRUCTORS, and RO_HAS_CXX_DTOR_ONLY beside it when there
        // is nothing to construct. RO_IS_ARC is left off: the runtime has no
        // part in what the ivar holds, which .cxx_destruct releases.
        int flags = (construct || destruct ? 0x4 : 0) | (destruct && !construct ? 0x100 : 0);

        // The fields share one ivar, placed after the isa until the runtime
        // slides it past the superclass's instance as it loads.
        int start = pointer, size = pointer;
        string ivars = "null";
        if (classType.FieldsSize > 0)
        {
            int alignment = Math.Max(1, classType.FieldsAlignment);
            start = TypeExtensions.AlignTo(pointer, alignment);
            size = start + classType.FieldsSize;

            string offsetType = IvarOffsetIsWord ? "i64" : "i32";
            _module.AppendLine(
                $"{IvarOffsetSymbol(classType)} = hidden global {offsetType} {start}, " +
                $"section \"__DATA, __objc_ivar\", align {(IvarOffsetIsWord ? 8 : 4)}");

            string symbol = $"_OBJC_$_INSTANCE_VARIABLES_{name}";
            _module.AppendLine(
                $"@\"{symbol}\" = internal global {{ i32, i32, [1 x {{ ptr, ptr, ptr, i32, i32 }}] }} " +
                $"{{ i32 32, i32 1, [1 x {{ ptr, ptr, ptr, i32, i32 }}] [{{ ptr, ptr, ptr, i32, i32 }} " +
                $"{{ ptr {IvarOffsetSymbol(classType)}, ptr {ObjCString(MethodNameSection, "_sl")}, " +
                $"ptr {ObjCString(MethodTypeSection, $"[{classType.FieldsSize}C]")}, " +
                $"i32 {System.Numerics.BitOperations.Log2((uint)alignment)}, i32 {classType.FieldsSize} }}] }}, " +
                $"section \"{ObjCConstSection}\", align 8");
            _objcCompilerUsed.Add($"@\"{symbol}\"");
            ivars = $"@\"{symbol}\"";
        }

        _module.AppendLine(
            $"@\"_OBJC_METACLASS_RO_$_{name}\" = internal global {ClassRoType} {{ i32 {RoMeta | flags}, " +
            $"i32 {ClassObjectSize}, i32 {ClassObjectSize}, ptr null, ptr {className}, ptr {classMethods}, " +
            $"ptr {protocols}, ptr null, ptr null, ptr null }}, section \"{ObjCConstSection}\", align 8");
        _module.AppendLine(
            $"{MetaclassObject(classType)} = global {ClassType} {{ ptr {MetaclassObject(root)}, " +
            $"ptr {MetaclassObject(superclass)}, ptr @_objc_empty_cache, ptr null, " +
            $"ptr @\"_OBJC_METACLASS_RO_$_{name}\" }}, section \"__DATA, __objc_data\", align 8");

        _module.AppendLine(
            $"@\"_OBJC_CLASS_RO_$_{name}\" = internal global {ClassRoType} {{ i32 {flags}, " +
            $"i32 {start}, i32 {size}, ptr null, ptr {className}, ptr {instanceMethods}, " +
            $"ptr {protocols}, ptr {ivars}, ptr null, ptr null }}, section \"{ObjCConstSection}\", align 8");
        _module.AppendLine(
            $"{ClassObject(classType)} = global {ClassType} {{ ptr {MetaclassObject(classType)}, " +
            $"ptr {ClassObject(superclass)}, ptr @_objc_empty_cache, ptr null, " +
            $"ptr @\"_OBJC_CLASS_RO_$_{name}\" }}, section \"__DATA, __objc_data\", align 8");
        _module.AppendLine();

        _objcCompilerUsed.Add($"@\"_OBJC_METACLASS_RO_$_{name}\"");
        _objcCompilerUsed.Add($"@\"_OBJC_CLASS_RO_$_{name}\"");
    }

    /// <summary><c>class_t</c>: isa, superclass, cache, vtable, data.</summary>
    private const string ClassType = "{ ptr, ptr, ptr, ptr, ptr }";

    /// <summary>
    /// <c>class_ro_t</c>: flags, instance start, instance size, ivar layout,
    /// name, methods, protocols, ivars, weak ivar layout, properties.
    /// </summary>
    private const string ClassRoType = "{ i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr, ptr }";

    /// <summary>
    /// A method list -- entry size, count, then name, types and IMP for each --
    /// or <c>null</c> when there are none. A protocol's entries have no IMP.
    /// </summary>
    private string MethodList(string symbol, IEnumerable<(string Selector, string Types, string? Imp)> methods)
    {
        var entries = methods.ToList();
        if (entries.Count == 0) return "null";

        var written = entries.Select(e =>
            $"{{ ptr, ptr, ptr }} {{ ptr {ObjCString(MethodNameSection, e.Selector)}, " +
            $"ptr {ObjCString(MethodTypeSection, e.Types)}, " +
            $"ptr {e.Imp ?? "null"} }}");

        _module.AppendLine(
            $"@\"{symbol}\" = internal global {{ i32, i32, [{entries.Count} x {{ ptr, ptr, ptr }}] }} " +
            $"{{ i32 24, i32 {entries.Count}, [{entries.Count} x {{ ptr, ptr, ptr }}] [{string.Join(", ", written)}] }}, " +
            $"section \"{ObjCConstSection}\", align 8");
        _objcCompilerUsed.Add($"@\"{symbol}\"");
        return $"@\"{symbol}\"";
    }

    /// <summary>A null-terminated list of protocol objects, or <c>null</c> when there are none.</summary>
    private string ProtocolList(string symbol, IReadOnlyList<ObjCProtocolTypeSymbol> protocols)
    {
        if (protocols.Count == 0) return "null";

        var objects = protocols.Select(ProtocolObject).ToList();
        _module.AppendLine(
            $"@\"{symbol}\" = internal global {{ i64, [{objects.Count + 1} x ptr] }} " +
            $"{{ i64 {objects.Count}, [{objects.Count + 1} x ptr] " +
            $"[{string.Join(", ", objects.Select(o => "ptr " + o))}, ptr null] }}, " +
            $"section \"{ObjCConstSection}\", align 8");
        _objcCompilerUsed.Add($"@\"{symbol}\"");
        return $"@\"{symbol}\"";
    }

    /// <summary>
    /// A protocol's <c>protocol_t</c>, written the first time it is asked for:
    /// weak and hidden, so that every image may carry one and the runtime keeps
    /// whichever it saw first, and labelled in <c>__objc_protolist</c>.
    /// </summary>
    private string ProtocolObject(ObjCProtocolTypeSymbol protocol)
    {
        string name = protocol.RuntimeName ?? protocol.SimpleName;
        if (_objcProtocolObjects.TryGetValue(name, out string? existing)) return existing;

        string symbol = $"@\"_OBJC_PROTOCOL_$_{name}\"";
        _objcProtocolObjects[name] = symbol;

        string bases = ProtocolList($"_OBJC_$_PROTOCOL_REFS_{name}", protocol.Bases);

        var messages = protocol.Methods.Where(m => m.IsMessage).ToList();
        var required = messages.Where(m => !m.IsObjCOptional && !m.IsStatic).ToList();
        var requiredClass = messages.Where(m => !m.IsObjCOptional && m.IsStatic).ToList();
        var optional = messages.Where(m => m.IsObjCOptional && !m.IsStatic).ToList();
        var optionalClass = messages.Where(m => m.IsObjCOptional && m.IsStatic).ToList();

        string Methods(string kind, List<FunctionSymbol> list) =>
            MethodList($"_OBJC_$_PROTOCOL_{kind}_{name}",
                list.Select(m => (m.Selector!, MethodTypeEncoding(m), (string?)null)));

        string instance = Methods("INSTANCE_METHODS", required);
        string classMethods = Methods("CLASS_METHODS", requiredClass);
        string optionalInstance = Methods("INSTANCE_METHODS_OPT", optional);
        string optionalClassMethods = Methods("CLASS_METHODS_OPT", optionalClass);

        // The extended types run in the same order as the four lists.
        var ordered = required.Concat(requiredClass).Concat(optional).Concat(optionalClass).ToList();
        string types = "null";
        if (ordered.Count > 0)
        {
            string typesSymbol = $"_OBJC_$_PROTOCOL_METHOD_TYPES_{name}";
            _module.AppendLine(
                $"@\"{typesSymbol}\" = internal global [{ordered.Count} x ptr] " +
                $"[{string.Join(", ", ordered.Select(m => "ptr " + ObjCString(MethodTypeSection, MethodTypeEncoding(m))))}], " +
                $"section \"{ObjCConstSection}\", align 8");
            _objcCompilerUsed.Add($"@\"{typesSymbol}\"");
            types = $"@\"{typesSymbol}\"";
        }

        _module.AppendLine(
            $"{symbol} = weak hidden global {{ ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, i32, i32, ptr, ptr, ptr }} " +
            $"{{ ptr null, ptr {ObjCString(ClassNameSection, name)}, ptr {bases}, ptr {instance}, " +
            $"ptr {classMethods}, ptr {optionalInstance}, ptr {optionalClassMethods}, ptr null, " +
            $"i32 96, i32 0, ptr {types}, ptr null, ptr null }}, align 8");
        _module.AppendLine(
            $"@\"_OBJC_LABEL_PROTOCOL_$_{name}\" = weak hidden global ptr {symbol}, " +
            "section \"__DATA,__objc_protolist,coalesced,no_dead_strip\", align 8");

        _objcUsed.Add(symbol);
        _objcUsed.Add($"@\"_OBJC_LABEL_PROTOCOL_$_{name}\"");
        return symbol;
    }

    /// <summary>A string in one of the Objective-C sections, written once per section.</summary>
    private string ObjCString(string section, string text)
    {
        if (_objcStrings.TryGetValue((section, text), out string? existing)) return existing;

        string symbol = $"@sl.objc.str.{_objcStrings.Count}";
        _objcStrings[(section, text)] = symbol;

        var bytes = Encoding.UTF8.GetBytes(text);
        var escaped = new StringBuilder();
        foreach (byte b in bytes)
        {
            if (b is >= 0x20 and < 0x7F && b != '"' && b != '\\') escaped.Append((char)b);
            else escaped.Append($"\\{b:X2}");
        }

        _objcStringData.AppendLine(
            $"{symbol} = private unnamed_addr constant [{bytes.Length + 1} x i8] c\"{escaped}\\00\", " +
            $"section \"{section}\", align 1");
        _objcCompilerUsed.Add(symbol);
        return symbol;
    }

    // ------------------------------------------------------------- type encodings

    /// <summary>
    /// A method's type as the runtime reads it: the result, the size of the
    /// arguments, then each argument with its offset, the receiver at 0 and
    /// the selector after it. <c>v24@0:8q16</c> is <c>-(void)m:(long)n</c>.
    /// </summary>
    internal static string MethodTypeEncoding(FunctionSymbol method)
    {
        int pointer = TargetPlatform.Current.PointerWidth;
        var parts = new StringBuilder();
        int offset = 2 * pointer;
        var arguments = new StringBuilder($"@0:{pointer}");

        foreach (var parameter in method.Parameters.Where(p => !p.IsThis))
        {
            var type = parameter.IsByReference ? parameter.Type.MakePointerType() : parameter.Type;
            arguments.Append(TypeEncoding(type, topLevel: true)).Append(offset);
            offset += Math.Max(EncodedSize(type), 4);
        }

        // A constructor answers as an init, which hands back the object.
        string result = method.Kind == FunctionKind.Constructor ? "@" : TypeEncoding(method.ReturnType, topLevel: true);
        parts.Append(result).Append(offset).Append(arguments);
        return parts.ToString();
    }

    private static int EncodedSize(TypeSymbol type) =>
        type.IsReferenceType || type is OptionalTypeSymbol || type is PointerTypeSymbol
            ? TargetPlatform.Current.PointerWidth
            : Math.Max(type.Size, 1);

    /// <summary>
    /// One type, as clang encodes it. A struct is spelled out with its fields,
    /// except behind a pointer that is itself inside a struct, where it is
    /// named alone.
    /// </summary>
    internal static string TypeEncoding(TypeSymbol type, bool topLevel)
    {
        if ((type.AsReference() ?? type) is ObjCBlockTypeSymbol) return "@?";
        if ((type.AsReference() ?? type) is ClassTypeSymbol { IsCoreFoundation: true }) return "^v";
        if (Binder.IsObjCReference(type)) return "@";

        var element = type.AsReference() ?? type;
        switch (element)
        {
            case PrimitiveTypeSymbol primitive:
                return primitive.Kind switch
                {
                    PrimitiveKind.Void => "v",
                    PrimitiveKind.Bool => BoolIsByte ? "c" : "B",
                    PrimitiveKind.SByte => "c",
                    PrimitiveKind.Char or PrimitiveKind.Byte => "C",
                    PrimitiveKind.Short => "s",
                    PrimitiveKind.UShort or PrimitiveKind.Char16 => "S",
                    PrimitiveKind.Int => "i",
                    PrimitiveKind.UInt or PrimitiveKind.Char32 => "I",
                    PrimitiveKind.Long or PrimitiveKind.NInt => "q",
                    PrimitiveKind.ULong or PrimitiveKind.NUInt => "Q",
                    PrimitiveKind.Float => "f",
                    PrimitiveKind.Double => "d",
                    _ => "?",
                };

            case EnumTypeSymbol enumType:
                return TypeEncoding(enumType.UnderlyingType, topLevel);

            case PointerTypeSymbol { Element: var pointee }:
                if (pointee is PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte or PrimitiveKind.SByte or PrimitiveKind.Char })
                    return "*";
                if (pointee is StructTypeSymbol pointedStruct && !topLevel)
                    return $"{(pointedStruct is UnionTypeSymbol ? '(' : '{')}{pointedStruct.SimpleName}" +
                           $"{(pointedStruct is UnionTypeSymbol ? ')' : '}')}";
                return "^" + TypeEncoding(pointee, topLevel);

            case NamedTypeSymbol { SimpleName: "Selector", ModuleName: Builtins.ObjCModuleName }:
                return ":";

            case NamedTypeSymbol { SimpleName: "Class", ModuleName: Builtins.ObjCModuleName }:
                return "#";

            case DelegateTypeSymbol:
                return "^?";

            case StructTypeSymbol structType:
            {
                bool union = structType is UnionTypeSymbol;
                var fields = new StringBuilder();
                if (!structType.IsOpaque)
                    foreach (var field in structType.Fields)
                        fields.Append(field.IsBitField
                            ? $"b{field.BitWidth}"
                            : TypeEncoding(field.Type, topLevel: false));
                return union
                    ? $"({structType.SimpleName}={fields})"
                    : $"{{{structType.SimpleName}={fields}}}";
            }

            case FixedArrayTypeSymbol fixedArray:
                return $"[{fixedArray.Length}{TypeEncoding(fixedArray.Element, topLevel: false)}]";

            default:
                return "?";
        }
    }
}
