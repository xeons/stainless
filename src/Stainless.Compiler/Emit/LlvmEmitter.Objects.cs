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
/// Bringing an object into existence and finding a method on it:
/// <c>new</c>, the tear-offs a com class presents, closures, array
/// literals, and the three ways a method address is loaded.
/// </summary>
public sealed partial class LlvmEmitter
{
    private Val EmitNew(BoundNew expression)
    {
        var classType = expression.ClassType;

        if (classType.ObjC == ObjCClassKind.Defined) return EmitObjCNew(expression);

        // A runtime-provided class builds itself; sl_alloc knows nothing of its
        // variable-sized or externally managed storage.
        if (classType.RuntimeFactory is not null)
        {
            string built = Emit("ptr", $"call ptr @{classType.RuntimeFactory}()");
            return Fresh(new Val(built, "ptr", classType));
        }

        // The arguments come first, as C#'s do, so that a `try` among them
        // that returns has no half-made object to let go of.
        var arguments = new List<string>();
        if (expression.Constructor is not null)
            AppendArguments(expression.Arguments, arguments, expression.EvaluationOrder);

        string instance = Emit("ptr",
            $"call ptr @sl_alloc(ptr @{Mangler.TypeInfoSymbol(classType)})");

        CountComObject(up: true, classType);
        InitializeTearOffs(instance, classType);
        InitializeEvents(instance, classType);

        if (expression.Constructor is not null)
        {
            arguments.Insert(0, $"ptr {instance}");
            Line($"call void {Symbol(expression.Constructor)}({string.Join(", ", arguments)})");
        }

        // sl_alloc already returns +1.
        return Fresh(new Val(instance, "ptr", classType));
    }

    /// <summary>
    /// <c>new Point(3, 4)</c>: a slot, zeroed, with the constructor run over
    /// it.
    ///
    /// The slot is the value, as every struct expression's is, so there is no
    /// allocation and no reference count. Zeroing first is what makes a field
    /// the constructor did not write agree with what <c>Point value;</c> would
    /// have left there.
    /// </summary>
    private Val EmitStructNew(BoundStructNew expression)
    {
        var structType = expression.StructType;

        string slot = Alloca(StructName(structType), "struct.new");
        Line($"store {StructName(structType)} zeroinitializer, ptr {slot}");

        var arguments = new List<string> { $"ptr {slot}" };
        AppendArguments(expression.Arguments, arguments, expression.EvaluationOrder);
        Line($"call void {Symbol(expression.Constructor)}({string.Join(", ", arguments)})");

        // What the constructor stored is owned by the slot.
        return Fresh(new Val(slot, "ptr", structType));
    }

    /// <summary>
    /// Moves this module's live-com-object count, where it keeps one.
    ///
    /// Every com class instance is counted, not only an activated one: a class
    /// factory is not the only way an object leaves: a `com class` made inside
    /// the library and handed out through some other export is just as much
    /// something the host holds. Counting all of them makes the answer
    /// conservative, which is the safe direction -- it can only ever refuse an
    /// unload that would have been fine.
    /// </summary>
    private void CountComObject(bool up, ClassTypeSymbol classType)
    {
        if (!_countsComObjects || !classType.IsCom) return;

        // Through Emit and not Line: atomicrmw yields the previous value, so it
        // takes an SSA name whether or not anything wants it, and emitting it
        // unnamed leaves the emitter's numbering one behind LLVM's.
        Emit("i32", $"atomicrmw {(up ? "add" : "sub")} ptr @sl_com_live, i32 1 " +
                    (up ? "monotonic" : "acq_rel"));
    }

    /// <summary>
    /// Gives every event in a freshly allocated object an empty subscriber list.
    ///
    /// An array is a value and never null (SL0271), so the zeroed storage
    /// <c>sl_alloc</c> hands back is not yet one -- and an event is read before
    /// anything has subscribed, by the first <c>+=</c> as much as by a raise.
    /// The empty array is what makes "no subscribers" an ordinary case with no
    /// test anywhere rather than a state every use has to know about.
    ///
    /// Here rather than in a constructor because a class need not declare one:
    /// <c>new Publisher()</c> on a class with no constructor runs nothing, and
    /// this has to happen on every path that makes an object. Base classes
    /// included, for the same reason -- the base's constructor may not exist
    /// either, and the fields are in this object.
    /// </summary>
    private void InitializeEvents(string instance, ClassTypeSymbol classType, bool inherited = true)
    {
        for (var current = classType; current is not null; current = inherited ? current.BaseClass : null)
            foreach (var declared in current.Events)
            {
                if (declared.BackingField is not { } field) continue;
                if (field.Type is not ArrayTypeSymbol arrayType) continue;

                string empty = Emit("ptr",
                    $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
                    $"{Word} 0, {Word} {arrayType.Element.Size})");

                Line($"store ptr {empty}, ptr {ClassFieldAddress(instance, field)}");
            }
    }

    /// <summary>
    /// Writes a com class's tear-offs into a freshly allocated object.
    ///
    /// One per interface it presents, each a vtable pointer followed by its own
    /// distance back to the start of the object. The distance is what lets a
    /// Release arriving through any of them find the header: the pointer COM
    /// holds is the tear-off's address, not the object's, and subtracting is
    /// cheaper than the adjustor thunks C++ generates for the same problem.
    ///
    /// sl_alloc has already zeroed the memory, so nothing else needs writing.
    /// </summary>
    private void InitializeTearOffs(string instance, ClassTypeSymbol classType)
    {
        if (!classType.IsCom || classType.ComInterfaces.Count == 0) return;

        foreach (var presented in classType.ComInterfaces)
        {
            int offset = classType.TearOffOffset(presented);

            string tearOff = Emit("ptr",
                $"getelementptr inbounds i8, ptr {instance}, i64 {offset}");
            Line($"store ptr @{ComVTableName(classType, presented)}, ptr {tearOff}");

            string ownerSlot = Emit("ptr",
                $"getelementptr inbounds i8, ptr {tearOff}, i64 {RuntimeLayout.TearOffOwner}");
            Line($"store {Word} {offset}, ptr {ownerSlot}");
        }
    }

    /// <summary>
    /// Loads the implementation of a virtual method for whatever object the
    /// receiver actually is:
    ///
    ///   object -> TypeInfo -> vtable -> slot
    ///
    /// Three loads and an indirect call, all at constant offsets. It is one load
    /// fewer than an interface call, which has an interface id to look up on the
    /// way, and one more than C++, which is the price of leaving the object
    /// header at three words whether or not a class has any virtual methods.
    /// </summary>
    private string LoadVirtualMethod(string receiver, FunctionSymbol method)
    {
        string typeSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {receiver}, i64 {RuntimeLayout.TypeInfo}");
        string typeInfo = Emit("ptr", $"load ptr, ptr {typeSlot}");

        string tableSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {typeInfo}, i64 {VirtualTableOffset}");
        string table = Emit("ptr", $"load ptr, ptr {tableSlot}");

        string methodSlot = Emit("ptr",
            $"getelementptr inbounds ptr, ptr {table}, i64 {method.VirtualSlot}");
        return Emit("ptr", $"load ptr, ptr {methodSlot}");
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
    /// <summary>
    /// Loads a COM method: the reference points at the vtable pointer, so the
    /// whole of it is a load and an index.
    ///
    ///   this -> [0] = vtable -> [slot]
    ///
    /// Two loads, against four for a Stainless interface, which has to reach
    /// the object's TypeInfo and then its table of tables. That is not a COM
    /// virtue so much as the consequence of giving up the object header: a COM
    /// pointer knows how to call and nothing else, and cannot be retained,
    /// compared or reflected on without asking the object first.
    /// </summary>
    private string LoadComMethod(string receiver, FunctionSymbol method)
    {
        int slot = method.VirtualSlot;

        string vtable = Emit("ptr", $"load ptr, ptr {receiver}");
        string methodSlot = Emit("ptr",
            $"getelementptr inbounds ptr, ptr {vtable}, i64 {slot}");
        return Emit("ptr", $"load ptr, ptr {methodSlot}");
    }

    private string LoadInterfaceMethod(string receiver, FunctionSymbol method)
    {
        var interfaceType = (InterfaceTypeSymbol)method.ContainingType!;
        int slot = interfaceType.SlotOf(method);

        string typeSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {receiver}, i64 {RuntimeLayout.TypeInfo}");
        string typeInfo = Emit("ptr", $"load ptr, ptr {typeSlot}");

        string tablesSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {typeInfo}, i64 {RuntimeLayout.TypeInfoInterfaces}");
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
    /// Capture is by value, so a captured reference is kept here and
    /// released by the class's destroy hook -- which the emitter already writes
    /// for every class. The closure therefore owns what it captured and may
    /// outlive the scope that made it.
    /// </summary>
    private Val EmitClosure(BoundClosure closure)
    {
        var type = closure.ClosureType;

        string instance = Emit("ptr",
            $"call ptr @sl_alloc(ptr @{Mangler.TypeInfoSymbol(type)})");
        var made = Building(new Val(instance, "ptr", closure.Type));

        foreach (var (field, value) in closure.Captures)
        {
            var captured = EmitOwned(value);
            string address = Emit("ptr",
                $"getelementptr inbounds i8, ptr {instance}, i64 " +
                $"{ClassTypeSymbol.HeaderSize + field.Offset}");

            InitializeWith(address, captured, field.Type);
        }

        return Built(made);
    }

    /// <summary>
    /// An array written out.
    ///
    /// The same allocation <c>new T[n]</c> makes, followed by a store per
    /// element -- at a constant index, so no bounds check is emitted and none
    /// is needed. Each store owns what it holds, exactly as an assignment into
    /// an element would, so an array of references retains every one of them.
    ///
    /// An inline <c>T[N]</c> allocates nothing: it is a slot, and the elements
    /// are stored into it where it sits.
    /// </summary>
    private Val EmitArrayLiteral(BoundArrayLiteral expression)
    {
        string elementType = LlvmTypeOf(expression.ElementType);

        if (expression.Type is FixedArrayTypeSymbol inline)
        {
            string slot = Alloca(
                $"[{inline.Length} x {elementType}]", "array.inline");

            for (int i = 0; i < expression.Elements.Count; i++)
            {
                var value = EmitExpression(expression.Elements[i]);
                string at = Emit("ptr",
                    $"getelementptr inbounds {elementType}, ptr {slot}, i64 {i}");
                StoreUncounted(at, value, expression.ElementType);
            }
            return new Val(slot, "ptr", expression.Type);
        }

        var arrayType = (ArrayTypeSymbol)expression.Type;
        string array = expression.OnStack
            ? StackArray(arrayType, expression.Elements.Count)
            : Emit("ptr",
                $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
                $"{Word} {expression.Elements.Count}, {Word} {arrayType.Element.Size})");

        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize}");

        var made = new Val(array, "ptr", arrayType);
        if (!expression.OnStack) Building(made);

        for (int i = 0; i < expression.Elements.Count; i++)
        {
            var value = EmitOwned(expression.Elements[i]);
            string at = Emit("ptr",
                $"getelementptr inbounds {elementType}, ptr {data}, i64 {i}");
            InitializeWith(at, value, arrayType.Element);
        }

        if (!expression.OnStack) return Built(made);

        // One in the frame ends when its statement does, whatever holds it, so
        // it is only ever borrowed. It is registered after its elements, which
        // may be slices of arrays in the frame too, so that it ends first.
        _stackArrays.Add(array);
        TrackTemporary(array, arrayType);
        return made;
    }

    /// <summary>
    /// An array in this frame rather than on the heap: the header the runtime
    /// would have written, and zeroed elements, in a slot of its own.
    ///
    /// It is counted like any array, so a slice of it retains and releases as
    /// usual. What a heap array does at zero this one does when the statement
    /// ends, in <see cref="EndStackArray"/>.
    /// </summary>
    private string StackArray(ArrayTypeSymbol arrayType, int length)
    {
        int bytes = ArrayTypeSymbol.HeaderSize + length * arrayType.Element.Size;
        string slot = $"%params.s{_nextSlot++}";

        // Sixteen, as calloc gives a heap array, whatever the element asks for.
        _entryAllocas.AppendLine($"  {slot} = alloca [{bytes} x i8], align 16");

        Line($"store [{bytes} x i8] zeroinitializer, ptr {slot}");
        Line($"call void @sl_object_init(ptr {slot}, ptr @{ArrayTypeInfoName(arrayType)})");

        string lengthSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {slot}, i64 {RuntimeLayout.ArrayLength}");
        Line($"store {Word} {length}, ptr {lengthSlot}");
        return slot;
    }

    /// <summary>
    /// Ends an array made by <see cref="StackArray"/>. The runtime refuses one
    /// still referenced from anywhere but here, which is the only way it could
    /// outlive the frame, and releases the elements.
    /// </summary>
    private void EndStackArray(string array) =>
        Line($"call void @sl_array_end_on_stack(ptr {array})");

    private Val EmitNewArray(BoundNewArray expression)
    {
        var arrayType = expression.ArrayType;
        var length = EmitExpression(expression.Length);

        string array = Emit("ptr",
            $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
            $"{Word} {length.Ref}, {Word} {arrayType.Element.Size})");

        return Fresh(new Val(array, "ptr", arrayType));
    }

    /// <summary>
    /// <c>Array.Create</c>: the array allocated, then every element stored in
    /// order from zero by an owning store, so none is read before it is set.
    /// </summary>
    private Val EmitArrayFill(BoundArrayFill fill)
    {
        var makeLocal = fill.MakeLocal;
        var atLocal = fill.AtLocal;
        var element = fill.Element;

        var arrayType = fill.ArrayType;
        var count = EmitExpression(fill.Count);

        // The function is held for the whole statement, as a `try` holds its operand.
        string makeType = LlvmTypeOf(makeLocal.Type);
        string make = Alloca(makeType, "fill.make");
        Line($"store {makeType} zeroinitializer, ptr {make}");
        InitializeWith(make, EmitOwned(fill.Make), makeLocal.Type);
        if (makeLocal.Type.CarriesReferences()) TrackTemporary(make, makeLocal.Type);
        _slots[makeLocal] = make;

        string at = Alloca(Word, "fill.at");
        Line($"store {Word} 0, ptr {at}");
        _slots[atLocal] = at;

        string array = Emit("ptr",
            $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
            $"{Word} {count.Ref}, {Word} {arrayType.Element.Size})");
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize}");

        string head = NextLabel("fill.head");
        string body = NextLabel("fill.body");
        string done = NextLabel("fill.done");
        Terminator($"br label %{head}");

        Label(head);
        string index = Emit(Word, $"load {Word}, ptr {at}");
        string more = Emit("i1", $"icmp ult {Word} {index}, {count.Ref}");
        Terminator($"br i1 {more}, label %{body}, label %{done}");

        Label(body);
        int pending = _pendingReleases.Count;
        var made = EmitOwned(element);
        string slot = Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(arrayType.Element)}, ptr {data}, {Word} {index}");
        InitializeWith(slot, made, arrayType.Element);

        // A temporary made here would be released once, after the loop.
        if (_pendingReleases.Count != pending)
            throw new Source.InternalCompilerError("an array fill's element left a temporary", fill.Span);

        Line($"store {Word} {Emit(Word, $"add {Word} {index}, 1")}, ptr {at}");
        Terminator($"br label %{head}");

        Label(done);
        return Fresh(new Val(array, "ptr", arrayType));
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
        var source = EmitExpression(expression.Array);

        // A slice carries its own length; an array's is in the header. Either
        // way it is a `nuint`, so it is a word wide.
        if (expression.Array.Type is SliceTypeSymbol slice)
            return new Val(SliceLength(source.Ref, slice), Word, expression.Type);

        string slot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {source.Ref}, i64 {RuntimeLayout.ArrayLength}");
        return new Val(Emit(Word, $"load {Word}, ptr {slot}"), Word, expression.Type);
    }

    /// <summary>
    /// Computes the address of <c>array[index]</c>, trapping first if the index
    /// is out of range. The index is unsigned, so one compare covers both ends.
    /// </summary>
}
