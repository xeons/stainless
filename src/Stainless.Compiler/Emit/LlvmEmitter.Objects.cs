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
/// Bringing an object into existence and finding a method on it:
/// <c>new</c>, the tear-offs a com class presents, closures, array
/// literals, and the three ways a method address is loaded.
/// </summary>
public sealed partial class LlvmEmitter
{
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

        InitializeTearOffs(instance, classType);

        if (expression.Constructor is not null)
        {
            var arguments = new List<string> { $"ptr {instance}" };
            AppendArguments(expression.Arguments, arguments);
            Line($"call void {Symbol(expression.Constructor)}({string.Join(", ", arguments)})");
        }

        // sl_alloc already returns +1; the statement scope releases it.
        TrackTemporary(instance, classType);
        return new Val(instance, "ptr", classType);
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
                $"getelementptr inbounds i8, ptr {tearOff}, i64 8");
            Line($"store i64 {offset}, ptr {ownerSlot}");
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
        string typeSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {receiver}, i64 16");
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
                StoreInto(at, value, expression.ElementType);
            }
            return new Val(slot, "ptr", expression.Type);
        }

        var arrayType = (ArrayTypeSymbol)expression.Type;
        string array = Emit("ptr",
            $"call ptr @sl_array_alloc(ptr @{ArrayTypeInfoName(arrayType)}, " +
            $"i64 {expression.Elements.Count}, i64 {arrayType.Element.Size})");

        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize}");

        for (int i = 0; i < expression.Elements.Count; i++)
        {
            var value = EmitExpression(expression.Elements[i]);
            string at = Emit("ptr",
                $"getelementptr inbounds {elementType}, ptr {data}, i64 {i}");
            StoreInto(at, value, arrayType.Element);
        }

        TrackTemporary(array, arrayType);
        return new Val(array, "ptr", arrayType);
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
        var source = EmitExpression(expression.Array);

        // A slice carries its own length; an array's is in the header.
        if (expression.Array.Type is SliceTypeSymbol slice)
            return new Val(SliceLength(source.Ref, slice), "i64", expression.Type);

        string slot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {source.Ref}, i64 {ArrayTypeSymbol.HeaderSize - 8}");
        return new Val(Emit("i64", $"load i64, ptr {slot}"), "i64", expression.Type);
    }

    /// <summary>
    /// Computes the address of <c>array[index]</c>, trapping first if the index
    /// is out of range. The index is unsigned, so one compare covers both ends.
    /// </summary>
}
