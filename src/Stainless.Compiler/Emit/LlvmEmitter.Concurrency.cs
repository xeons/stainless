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
/// Spawn, parallel-for and the thunks they need.
///
/// A spawned body becomes a function of its own with a captured
/// environment, so this is the one place the emitter writes a function
/// the binder did not.
/// </summary>
public sealed partial class LlvmEmitter
{
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
        _debugScope = null;
        _debugLocation = null;
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

    /// <summary>
    /// A function's symbol as the IR must spell it.
    ///
    /// LLVM identifiers accept only <c>[-a-zA-Z$._0-9]</c> unquoted, and a C++
    /// mangled name is mostly other characters in either scheme —
    /// <c>?add@@YAHHH@Z</c> and <c>_ZN8geometry4areaEdd</c> respectively, of
    /// which only the second happens to fit.
    /// </summary>
    private static string Symbol(FunctionSymbol function) => Symbol(function.MangledName);

    /// <summary>
    /// Quoting is enough on its own: a quoted LLVM name escapes only as
    /// <c>\xx</c> hex pairs, and neither mangling scheme can produce a quote or
    /// a backslash to need one.
    /// </summary>
    private static string Symbol(string mangled) =>
        mangled.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '$' or '.' or '_')
            ? "@" + mangled
            : "@\"" + mangled + "\"";

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
            Line($"call void {Symbol(classType.Destructor)}(ptr %obj)");

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
            Release(value, field.Type);
        }

        // The base last, so the object is taken apart from the outside in: a
        // derived destructor may read what the base still holds, and would find
        // it already released the other way round. It is the same order C++ and
        // C# use, and for the same reason.
        if (classType.BaseClass is { } inheritedFrom)
            Line($"call void @{DestroyName(inheritedFrom)}(ptr %obj)");

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
                Release(element, arrayType.Element);
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
}
