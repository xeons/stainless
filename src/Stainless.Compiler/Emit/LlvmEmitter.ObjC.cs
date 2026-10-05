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
/// Objective-C: messages, the selector and class references they go
/// through, and the counting of the objects they return.
///
/// Every send is clang's classic form: load the selector from
/// <c>__objc_selrefs</c>, which the loader fills in, and call
/// <c>objc_msgSend</c> under the method's own signature. A class message
/// loads its class from <c>__objc_classrefs</c>, never names the class symbol
/// directly, so that the loader may move what it points at.
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>
    /// The modules the program reaches something of: a function it calls, a
    /// variable it reads, a class it names, a message a member of it
    /// declares. A framework a module names with <c>#pragma comment</c> is
    /// linked when the module is reached, so naming every binding costs a
    /// program nothing it does not use, and links nothing its macOS lacks.
    /// </summary>
    public HashSet<string> ReachedModules { get; } = new(StringComparer.Ordinal);

    /// <summary>Each selector sent, and the reference a send loads it from.</summary>
    private readonly Dictionary<string, int> _selectors = new(StringComparer.Ordinal);

    /// <summary>Each class a class message is sent to, by runtime name, and its reference.</summary>
    private readonly Dictionary<string, int> _classReferences = new(StringComparer.Ordinal);

    /// <summary>True for a reference counted by the Objective-C runtime, optional or not.</summary>
    /// <remarks>Not a weak reference to one, which is a box counted by Stainless.</remarks>
    private static bool IsObjCReference(TypeSymbol type) =>
        type is not WeakTypeSymbol && Binder.IsObjCType(type.AsReference() ?? type);

    /// <summary>A weak reference to an Objective-C object, which is a box rather than the object's pointer.</summary>
    private static bool IsObjCWeak(TypeSymbol type) =>
        type is WeakTypeSymbol { Element: var element } && Binder.IsObjCType(element.AsReference() ?? element);

    /// <summary>
    /// <c>BOOL</c> is <c>signed char</c> on Intel and <c>bool</c> on Apple
    /// silicon, and a message carries what the target's <c>BOOL</c> is.
    /// </summary>
    private static bool BoolIsByte => TargetPlatform.Current.Architecture == TargetArch.X64;

    /// <summary>True once a message has been sent to a superclass.</summary>
    private bool _sendsToSuper;

    /// <summary>True once anything has been retained or released with libobjc's counting.</summary>
    private bool _countsObjC;

    private bool UsesObjC =>
        _selectors.Count > 0 || _classReferences.Count > 0 || _definedObjCClasses.Count > 0 || _countsObjC ||
        _blockTypes.Count > 0;

    /// <summary>
    /// Sends the message a call to a member of an objc type stands for.
    /// </summary>
    private Val EmitMessage(BoundCall call)
    {
        var function = call.Function;
        var returnInfo = ClassifyResult(function.ReturnType);
        var arguments = new List<string>();

        // Intel's objc_msgSend leaves a struct returned in memory alone; the
        // stret entry point is the one that knows to skip the hidden pointer.
        // Apple silicon passes that pointer in x8 and has no stret at all.
        bool stret = returnInfo.Style == PassStyle.Indirect;
        string? sretSlot = null;
        if (stret)
        {
            var structType = (StructTypeSymbol)function.ReturnType;
            sretSlot = Alloca(StructName(structType), "send.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        string receiver;
        if (function.IsStatic)
        {
            var classType = call.ClassReceiver ?? (ClassTypeSymbol)function.ContainingType!;
            receiver = Emit("ptr", $"load ptr, ptr {ClassReference(classType)}");
        }
        else if (function.ConsumesSelf)
        {
            // An init takes the receiver's +1 and hands back its own.
            receiver = EmitOwned(call.Receiver!).Ref;
        }
        else
        {
            receiver = EmitExpression(call.Receiver!).Ref;
        }

        // `base.M()`: the search starts at the superclass, which objc_super
        // names beside the receiver.
        bool super = call.IsNonVirtual && !function.IsStatic;
        if (super)
        {
            var superclass = (ClassTypeSymbol)(call.Receiver!.Type.AsReference() ?? call.Receiver.Type);
            string frame = Alloca("{ ptr, ptr }", "send.super");
            Line($"store ptr {receiver}, ptr {frame}");
            string classSlot = Emit("ptr", $"getelementptr inbounds {{ ptr, ptr }}, ptr {frame}, i32 0, i32 1");
            Line($"store ptr {Emit("ptr", $"load ptr, ptr {ClassReference(superclass)}")}, ptr {classSlot}");
            arguments.Add($"ptr {frame}");
        }
        else
        {
            arguments.Add($"ptr {receiver}");
        }

        string selector = Emit("ptr", $"load ptr, ptr {SelectorReference(function.Selector!)}");
        arguments.Add($"ptr {selector}");

        if (function.IsObjCOptional)
            RequireAnswer(receiver, selector, function, call.ClassReceiver);

        var writebacks = AppendMessageArguments(call, arguments);

        bool boolResult = BoolIsByte && IsBool(function.ReturnType);
        string spelling = boolResult ? "signext i8" : ResultSpelling(returnInfo);
        string callee = (super, stret) switch
        {
            (true, true) => "@objc_msgSendSuper_stret",
            (true, false) => "@objc_msgSendSuper",
            (false, true) => "@objc_msgSend_stret",
            _ => "@objc_msgSend",
        };
        if (super) _sendsToSuper = true;
        // A variadic message is called as the C variadic it is: the extra
        // arguments go where the convention puts them, on the stack on Apple
        // silicon, and the call says so.
        string calleeType = function.IsVariadic ? $"{spelling} ({MessageVariadicSignature(function, stret)})" : spelling;
        string invocation = $"call {calleeType} {callee}({string.Join(", ", arguments)})";

        string? result = null;
        if (stret || returnInfo.Style == PassStyle.Ignore || function.ReturnType.IsVoid())
            Line(invocation);
        else
            result = Emit(boolResult ? "i8" : returnInfo.LlvmType, invocation);

        // A constructor's `this` is the object alloc made, so the superclass's
        // init MUST answer with it.
        if (super && function.ConsumesSelf && _inObjCConstructor && result is not null)
            RequireSameObject(result, receiver, function);

        // Straight after the send, before anything else can run: an object
        // handed back at +0 is only alive until the pool drains.
        bool returnsObject = IsObjCReference(function.ReturnType);
        if (result is not null && returnsObject && !function.ReturnsRetained)
            result = ClaimReturned(result);

        foreach (var (target, temporary, type) in writebacks)
            WriteBack(target, temporary, type);

        if (stret)
            return Fresh(new Val(sretSlot!, "ptr", function.ReturnType));
        if (returnInfo.Style == PassStyle.Ignore)
            return EmptyResult(function.ReturnType);
        if (result is null)
            return Val.Void;
        if (boolResult)
            return new Val(Emit("i1", $"icmp ne i8 {result}, 0"), "i1", function.ReturnType);

        if (returnsObject && IsNeverNullReference(function.ReturnType))
            RequireMessageResult(result, function, call.ClassReceiver);

        return Landed(result, returnInfo, function.ReturnType);
    }

    /// <summary>
    /// A message's arguments, lowered as a C call's are, except that a
    /// <c>bool</c> becomes the target's <c>BOOL</c> and an <c>out</c> or
    /// <c>ref</c> object goes through a temporary.
    /// </summary>
    /// <returns>The temporaries to write back once the message returns.</returns>
    private List<(string Target, string Temporary, TypeSymbol Type)> AppendMessageArguments(
        BoundCall call, List<string> arguments)
    {
        var parameters = call.Function.Parameters.Where(p => !p.IsThis).ToList();
        var lowered = new List<string>[call.Arguments.Count];
        var order = call.EvaluationOrder ?? Enumerable.Range(0, call.Arguments.Count).ToList();
        var writebacks = new List<(string, string, TypeSymbol)>();

        foreach (int i in order)
        {
            var expression = call.Arguments[i];
            var value = EmitExpression(expression);
            lowered[i] = [];

            // The callee stores an object it does not hand over, so it is given
            // a slot nothing owns and the caller takes what it left there.
            if (i < parameters.Count &&
                parameters[i].Mode is Syntax.ParameterMode.Out or Syntax.ParameterMode.Ref &&
                IsObjCReference(parameters[i].Type))
            {
                string temporary = Alloca("ptr", "send.writeback");
                string initial = parameters[i].Mode == Syntax.ParameterMode.Ref
                    ? Emit("ptr", $"load ptr, ptr {value.Ref}")
                    : "null";
                Line($"store ptr {initial}, ptr {temporary}");
                lowered[i].Add($"ptr {temporary}");
                writebacks.Add((value.Ref, temporary, parameters[i].Type));
                continue;
            }

            if (BoolIsByte && IsBool(expression.Type))
                lowered[i].Add($"i8 signext {Emit("i8", $"zext i1 {value.Ref} to i8")}");
            else
                AppendArgument(value, expression.Type, lowered[i], variadic: i >= parameters.Count);
        }

        foreach (var pieces in lowered) arguments.AddRange(pieces);
        return writebacks;
    }

    /// <summary>
    /// What a callee left in a writeback temporary, retained into the slot
    /// the call named, whose old value is let go of. A <c>ref</c> the callee
    /// did not change is retained and released once each, which is nothing.
    /// </summary>
    private void WriteBack(string target, string temporary, TypeSymbol type)
    {
        string left = Emit("ptr", $"load ptr, ptr {temporary}");
        Retain(left, type);
        string old = Emit("ptr", $"load ptr, ptr {target}");
        Line($"store ptr {left}, ptr {target}");
        Release(old, type);
    }

    private static bool IsBool(TypeSymbol type) => type == PrimitiveTypeSymbol.Bool;

    /// <summary>The fixed parameters of a variadic message, as the call lowers them, and then <c>...</c>.</summary>
    private string MessageVariadicSignature(FunctionSymbol function, bool stret)
    {
        var parts = new List<string>();
        if (stret) parts.Add("ptr");
        parts.Add("ptr");
        parts.Add("ptr");
        foreach (var parameter in function.Parameters.Where(p => !p.IsThis))
        {
            if (parameter.Mode is Syntax.ParameterMode.Out or Syntax.ParameterMode.Ref && IsObjCReference(parameter.Type))
                parts.Add("ptr");
            else if (BoolIsByte && IsBool(parameter.Type))
                parts.Add("i8");
            else
                parts.AddRange(DeclaredTypes(ClassifyParameter(parameter, variadic: true)));
        }

        parts.Add("...");
        return string.Join(", ", parts);
    }

    /// <summary>
    /// Takes ownership of an object a message handed back at +0. On Apple
    /// silicon clang marks the call with a no-op the runtime looks for, which
    /// lets the callee skip putting the object in the pool at all.
    /// </summary>
    private string ClaimReturned(string result)
    {
        _countsObjC = true;
        if (TargetPlatform.Current.Architecture == TargetArch.Arm64)
            Line("call void asm sideeffect \"mov\\09fp, fp\\09\\09// marker for " +
                 "objc_retainAutoreleaseReturnValue\", \"\"()");

        // Never a tail call: the runtime recognises the handshake by what
        // follows the send, and a jump in its place is not that.
        return Emit("ptr", $"notail call ptr @objc_retainAutoreleasedReturnValue(ptr {result})");
    }

    /// <summary>
    /// What a message handed back where the declaration promises an object.
    /// Objective-C promised nothing, so a nil stops the program here, naming
    /// the message.
    /// </summary>
    private void RequireMessageResult(string result, FunctionSymbol function, ClassTypeSymbol? classReceiver)
    {
        string present = Emit("i1", $"icmp ne ptr {result}, null");
        string good = NextLabel("send.ok");
        string bad = NextLabel("send.nil");
        Terminator($"br i1 {present}, label %{good}, label %{bad}");

        Label(bad);
        string message = DescribeMessage(function, classReceiver);
        string type = function.ReturnType is NamedTypeSymbol named ? named.QualifiedName : function.ReturnType.Name;
        Line($"call void @sl_objc_nil(ptr {InternBytes(message)}, ptr {InternBytes(type)})");
        Terminator("unreachable");

        Label(good);
    }

    /// <summary>How a diagnostic at run time names a message: <c>-[NSView frame]</c>.</summary>
    private static string DescribeMessage(FunctionSymbol function, ClassTypeSymbol? classReceiver)
    {
        string owner = (classReceiver ?? function.ContainingType)?.Name ?? "?";
        return $"{(function.IsStatic ? "+" : "-")}[{owner} {function.Selector}]";
    }

    /// <summary>
    /// An <c>[Optional]</c> protocol member is sent only to an object that
    /// answers it, asked with <c>respondsToSelector:</c>; one that does not
    /// stops the program, naming the message.
    /// </summary>
    private void RequireAnswer(
        string receiver, string selector, FunctionSymbol function, ClassTypeSymbol? classReceiver)
    {
        string asked = Emit("ptr", $"load ptr, ptr {SelectorReference("respondsToSelector:")}");
        string answers;
        if (BoolIsByte)
        {
            string answer = Emit("i8", $"call signext i8 @objc_msgSend(ptr {receiver}, ptr {asked}, ptr {selector})");
            answers = Emit("i1", $"icmp ne i8 {answer}, 0");
        }
        else
        {
            answers = Emit("i1", $"call zeroext i1 @objc_msgSend(ptr {receiver}, ptr {asked}, ptr {selector})");
        }

        string good = NextLabel("send.answered");
        string bad = NextLabel("send.unanswered");
        Terminator($"br i1 {answers}, label %{good}, label %{bad}");

        Label(bad);
        Line($"call void @sl_objc_unanswered(ptr {InternBytes(DescribeMessage(function, classReceiver))})");
        Terminator("unreachable");

        Label(good);
    }

    /// <summary>
    /// Whether the object at <paramref name="value"/> is a
    /// <paramref name="wanted"/>, asked of the object: <c>isKindOfClass:</c>
    /// for a class, <c>conformsToProtocol:</c> for a protocol. Nil answers no.
    /// </summary>
    private string EmitObjCTest(string value, TypeSymbol wanted)
    {
        var target = wanted.AsReference() ?? wanted;
        string argument;
        string selector;

        ReachedModules.Add(((NamedTypeSymbol)target).ModuleName);
        if (target is ClassTypeSymbol { IsCoreFoundation: true } cf)
            return EmitCFTest(value, cf);

        if (target is ClassTypeSymbol classType)
        {
            argument = Emit("ptr", $"load ptr, ptr {ClassReference(classType)}");
            selector = "isKindOfClass:";
        }
        else
        {
            string name = ((ObjCProtocolTypeSymbol)target).RuntimeName ?? target.Name;
            argument = Emit("ptr", $"call ptr @objc_getProtocol(ptr {InternBytes(name)})");
            selector = "conformsToProtocol:";
        }

        string sel = Emit("ptr", $"load ptr, ptr {SelectorReference(selector)}");
        if (!BoolIsByte)
            return Emit("i1", $"call zeroext i1 @objc_msgSend(ptr {value}, ptr {sel}, ptr {argument})");

        string answer = Emit("i8", $"call signext i8 @objc_msgSend(ptr {value}, ptr {sel}, ptr {argument})");
        return Emit("i1", $"icmp ne i8 {answer}, 0");
    }

    /// <summary>Each constant string object, by its text, and its index.</summary>
    private readonly Dictionary<string, int> _constantStrings = new(StringComparer.Ordinal);

    /// <summary>
    /// The constant object an <c>NSString</c> or <c>CFStringRef</c> constant is:
    /// what clang makes of <c>@"..."</c> and <c>CFSTR("...")</c>, an isa of
    /// <c>__CFConstantStringClassReference</c>, flags, the characters and their
    /// count. It is immortal, and costs nothing until it is read.
    /// </summary>
    private string ConstantStringObject(string text)
    {
        _countsObjC = true;
        if (!_constantStrings.TryGetValue(text, out int index))
            _constantStrings[text] = index = _constantStrings.Count;
        return $"@sl.cfstring.{index}";
    }

    /// <summary>
    /// The constant string objects, as clang lays them out: ASCII text as
    /// bytes in <c>__cstring</c> with flags 0x7C8, anything else as UTF-16 in
    /// <c>__ustring</c> with flags 0x7D0, the count in the units each holds.
    /// </summary>
    private void ConstantStringTables()
    {
        if (_constantStrings.Count == 0) return;

        _module.AppendLine("%struct.__NSConstantString_tag = type { ptr, i32, ptr, i64 }");
        Declare("__CFConstantStringClassReference", "@__CFConstantStringClassReference = external global [0 x i32]");

        foreach (var (text, index) in _constantStrings)
        {
            bool ascii = text.All(c => c < 0x80);
            string characters = $"@sl.cfstring.chars.{index}";
            if (ascii)
            {
                var bytes = Encoding.ASCII.GetBytes(text);
                string cells = string.Concat(bytes.Select(b => $"\\{b:X2}"));
                _module.AppendLine(
                    $"{characters} = private unnamed_addr constant [{bytes.Length + 1} x i8] c\"{cells}\\00\", " +
                    "section \"__TEXT,__cstring,cstring_literals\", align 1");
            }
            else
            {
                var units = text.Select(c => $"i16 {(int)c}").Append("i16 0");
                _module.AppendLine(
                    $"{characters} = private unnamed_addr constant [{text.Length + 1} x i16] " +
                    $"[{string.Join(", ", units)}], section \"__TEXT,__ustring\", align 2");
            }

            int length = ascii ? Encoding.ASCII.GetByteCount(text) : text.Length;
            _module.AppendLine(
                $"@sl.cfstring.{index} = private global %struct.__NSConstantString_tag " +
                $"{{ ptr @__CFConstantStringClassReference, i32 {(ascii ? 1992 : 2000)}, ptr {characters}, " +
                $"i64 {length} }}, section \"__DATA,__cfstring\", align 8");
        }
    }

    /// <summary>The functions answering a Core Foundation type's CFTypeID that a cast has asked.</summary>
    private readonly SortedSet<string> _cfTypeIDs = new(StringComparer.Ordinal);

    /// <summary>
    /// Whether the object at <paramref name="value"/> is a <paramref name="cf"/>:
    /// its <c>CFTypeID</c> against the type's. <c>CFGetTypeID</c> does not
    /// take nil, so nil is answered here, no.
    /// </summary>
    private string EmitCFTest(string value, ClassTypeSymbol cf)
    {
        string function = cf.CFTypeIDFunction!;
        _cfTypeIDs.Add(function);
        _countsObjC = true;

        string entry = CurrentBlockLabel();
        string ask = NextLabel("cf.ask");
        string done = NextLabel("cf.done");
        Terminator($"br i1 {Emit("i1", $"icmp eq ptr {value}, null")}, label %{done}, label %{ask}");

        Label(ask);
        string actual = Emit("i64", $"call i64 @CFGetTypeID(ptr {value})");
        string expected = Emit("i64", $"call i64 @{function}()");
        string same = Emit("i1", $"icmp eq i64 {actual}, {expected}");
        string asked = CurrentBlockLabel();
        Terminator($"br label %{done}");

        Label(done);
        return Emit("i1", $"phi i1 [ false, %{entry} ], [ {same}, %{asked} ]");
    }

    /// <summary>
    /// A cast down to <paramref name="wanted"/>: asked of the object, and a
    /// program that stops, naming the object's class, if it says no.
    /// </summary>
    private void EmitObjCCheck(string value, TypeSymbol wanted)
    {
        string held = EmitObjCTest(value, wanted);
        string good = NextLabel("objc.cast.ok");
        string bad = NextLabel("objc.cast.bad");
        Terminator($"br i1 {held}, label %{good}, label %{bad}");

        Label(bad);
        string actual = Emit("ptr", $"call ptr @object_getClassName(ptr {value})");
        string name = wanted is NamedTypeSymbol named ? named.QualifiedName : wanted.Name;
        Line($"call void @sl_objc_cast_failed(ptr {actual}, ptr {InternBytes(name)})");
        Terminator("unreachable");

        Label(good);
    }

    /// <summary>The selector reference a send of <paramref name="selector"/> loads.</summary>
    private string SelectorReference(string selector)
    {
        if (!_selectors.TryGetValue(selector, out int index))
        {
            index = _selectors.Count;
            _selectors[selector] = index;
        }

        return $"@sl.objc.selref.{index}";
    }

    /// <summary>The class reference a class message to <paramref name="classType"/> loads.</summary>
    private string ClassReference(ClassTypeSymbol classType)
    {
        ReachedModules.Add(classType.ModuleName);
        string name = classType.ObjCRuntimeName ?? classType.SimpleName;
        if (!_classReferences.TryGetValue(name, out int index))
        {
            index = _classReferences.Count;
            _classReferences[name] = index;
        }

        return $"@sl.objc.classref.{index}";
    }

    /// <summary>
    /// The selector and class references, in clang's sections, and the
    /// runtime functions the sends call. Every one is kept from the linker's
    /// dead stripping: the loader reads these sections whole.
    /// </summary>
    private void ObjCTables()
    {
        if (!UsesObjC) return;

        ConstantStringTables();

        var used = new List<string>();
        _module.AppendLine();

        foreach (var (selector, index) in _selectors)
        {
            var bytes = Encoding.UTF8.GetBytes(selector);
            _module.AppendLine(
                $"@sl.objc.methname.{index} = private unnamed_addr constant [{bytes.Length + 1} x i8] " +
                $"c\"{selector}\\00\", section \"__TEXT,__objc_methname,cstring_literals\", align 1");
            _module.AppendLine(
                $"@sl.objc.selref.{index} = internal externally_initialized global ptr " +
                $"@sl.objc.methname.{index}, section \"__DATA,__objc_selrefs,literal_pointers,no_dead_strip\", " +
                "align 8");
            used.Add($"@sl.objc.methname.{index}");
            used.Add($"@sl.objc.selref.{index}");
        }

        foreach (var (name, index) in _classReferences)
        {
            string symbol = $"@\"OBJC_CLASS_$_{name}\"";
            if (!_definedObjCClasses.Contains(name))
                Declare($"OBJC_CLASS_$_{name}", $"{symbol} = external global ptr");
            _module.AppendLine(
                $"@sl.objc.classref.{index} = internal global ptr {symbol}, " +
                "section \"__DATA,__objc_classrefs,regular,no_dead_strip\", align 8");
            used.Add($"@sl.objc.classref.{index}");
        }

        used.AddRange(_objcCompilerUsed);
        if (_objcUsed.Count > 0)
            _module.AppendLine(
                $"@llvm.used = appending global [{_objcUsed.Count} x ptr] " +
                $"[{string.Join(", ", _objcUsed.Select(u => "ptr " + u))}], section \"llvm.metadata\"");

        // Empty when the module only counts objects, which LLVM refuses.
        if (used.Count > 0)
            _module.AppendLine(
                $"@llvm.compiler.used = appending global [{used.Count} x ptr] " +
                $"[{string.Join(", ", used.Select(u => "ptr " + u))}], section \"llvm.metadata\"");

        Declare("objc_msgSend", "declare ptr @objc_msgSend(ptr, ptr, ...)");
        Declare("objc_begin_catch", "declare ptr @objc_begin_catch(ptr)");
        Declare("OBJC_EHTYPE_id", "@OBJC_EHTYPE_id = external global ptr");
        Declare("llvm.eh.typeid.for.p0", "declare i32 @llvm.eh.typeid.for.p0(ptr) nounwind memory(none)");
        if (TargetPlatform.Current.Architecture == TargetArch.X64)
            Declare("objc_msgSend_stret", "declare void @objc_msgSend_stret(ptr, ptr, ...)");
        if (_allocatesObjC)
            Declare("objc_alloc", "declare ptr @objc_alloc(ptr) nounwind");
        if (_sendsToSuper)
        {
            Declare("objc_msgSendSuper", "declare ptr @objc_msgSendSuper(ptr, ptr, ...)");
            if (TargetPlatform.Current.Architecture == TargetArch.X64)
                Declare("objc_msgSendSuper_stret", "declare void @objc_msgSendSuper_stret(ptr, ptr, ...)");
        }
        Declare("objc_retain", "declare ptr @objc_retain(ptr) nounwind");
        Declare("objc_release", "declare void @objc_release(ptr) nounwind");
        Declare("objc_retainAutoreleasedReturnValue",
            "declare ptr @objc_retainAutoreleasedReturnValue(ptr) nounwind");
        Declare("objc_getProtocol", "declare ptr @objc_getProtocol(ptr) nounwind");
        if (_blockTypes.Count > 0 || _definedObjCClasses.Count > 0)
        {
            Declare("objc_autoreleaseReturnValue", "declare ptr @objc_autoreleaseReturnValue(ptr) nounwind");
            Declare("objc_retainBlock", "declare ptr @objc_retainBlock(ptr) nounwind");
            Declare("__objc_personality_v0", "declare i32 @__objc_personality_v0(...)");
        }
        if (_blockTypes.Count > 0)
        {
            Declare("_Block_copy", "declare ptr @_Block_copy(ptr) nounwind");
            Declare("_NSConcreteStackBlock", "@_NSConcreteStackBlock = external global ptr");
        }
        Declare("objc_autoreleasePoolPush", "declare ptr @objc_autoreleasePoolPush() nounwind");
        Declare("objc_autoreleasePoolPop", "declare void @objc_autoreleasePoolPop(ptr) nounwind");
        Declare("object_getClassName", "declare ptr @object_getClassName(ptr) nounwind");

        if (_cfTypeIDs.Count > 0)
        {
            Declare("CFGetTypeID", "declare i64 @CFGetTypeID(ptr) nounwind");
            foreach (string function in _cfTypeIDs)
                Declare(function, $"declare i64 @{function}() nounwind");
        }
    }

    /// <summary>
    /// The flags that make the linker write the image info the Objective-C
    /// runtime reads, as clang writes them. Empty for a program that sends
    /// nothing.
    /// </summary>
    private IReadOnlyList<string> ObjCModuleFlags() => !UsesObjC
        ? []
        :
        [
            "!{i32 1, !\"Objective-C Version\", i32 2}",
            "!{i32 1, !\"Objective-C Image Info Version\", i32 0}",
            "!{i32 1, !\"Objective-C Image Info Section\", !\"__DATA,__objc_imageinfo,regular,no_dead_strip\"}",
            "!{i32 1, !\"Objective-C Garbage Collection\", i8 0}",
            "!{i32 1, !\"Objective-C Class Properties\", i32 64}",
        ];
}
