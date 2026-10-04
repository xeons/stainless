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

using Stainless.Binding;

namespace Stainless.Emit;

// VaList: started with LLVM's va_start, and read here rather than with its
// va_arg, which is wrong on Win64 (a four-byte step through eight-byte slots)
// and on AArch64 Linux (the stack, never the registers). clang reads it
// itself everywhere but Apple's ARM64 for the same reason.
public sealed partial class LlvmEmitter
{
    /// <summary>
    /// The list in a slot of its own, started. <c>va_end</c> does nothing on
    /// any target here, so nothing ends it.
    /// </summary>
    private Val EmitVaStart(BoundVaStart started)
    {
        string list = Alloca(LlvmTypeOf(started.Type), "va.list");
        _overflowIntrinsics.Add("declare void @llvm.va_start.p0(ptr) nounwind");
        Line($"call void @llvm.va_start.p0(ptr {list})");
        return new Val(list, "ptr", started.Type);
    }

    private Val EmitVaArg(BoundVaArg read)
    {
        string list = EmitAddress(read.List);
        string type = LlvmTypeOf(read.Type);
        var target = TargetPlatform.Current;
        bool real = read.Type is PrimitiveTypeSymbol { IsFloat: true };

        string address = target switch
        {
            { Architecture: TargetArch.X64, IsWindows: false } => real
                ? FromSaveArea(list, offsetAt: 4, areaAt: 16, step: 16, limit: 176, overflowAt: 8)
                : FromSaveArea(list, offsetAt: 0, areaAt: 16, step: 8, limit: 48, overflowAt: 8),
            { Architecture: TargetArch.Arm64, IsLinux: true } => real
                ? FromTopOfArea(list, offsetAt: 28, topAt: 16, step: 16)
                : FromTopOfArea(list, offsetAt: 24, topAt: 8, step: 8),
            _ => FromSlot(list, Math.Max(target.PointerWidth, read.Type.Size)),
        };

        return new Val(Emit(type, $"load {type}, ptr {address}"), type, read.Type);
    }

    /// <summary>
    /// A list that is a pointer to the next slot: read it there, and step past
    /// a slot of <paramref name="slot"/> bytes.
    /// </summary>
    private string FromSlot(string list, int slot)
    {
        string at = Emit("ptr", $"load ptr, ptr {list}");
        string next = Emit("ptr", $"getelementptr inbounds i8, ptr {at}, i64 {slot}");
        Line($"store ptr {next}, ptr {list}");
        return at;
    }

    /// <summary>
    /// System V x86-64: an offset into the register save area while it is
    /// below <paramref name="limit"/>, then the overflow area eight bytes at a time.
    /// </summary>
    private string FromSaveArea(string list, int offsetAt, int areaAt, int step, int limit, int overflowAt)
    {
        string offsetSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {list}, i64 {offsetAt}");
        string offset = Emit("i32", $"load i32, ptr {offsetSlot}");
        string inRegisters = Emit("i1", $"icmp ule i32 {offset}, {limit - step}");

        string registers = NextLabel("va.registers");
        string memory = NextLabel("va.memory");
        string joined = NextLabel("va.read");
        Terminator($"br i1 {inRegisters}, label %{registers}, label %{memory}");

        Label(registers);
        string areaSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {list}, i64 {areaAt}");
        string area = Emit("ptr", $"load ptr, ptr {areaSlot}");
        string wide = Emit("i64", $"zext i32 {offset} to i64");
        string inArea = Emit("ptr", $"getelementptr inbounds i8, ptr {area}, i64 {wide}");
        string stepped = Emit("i32", $"add i32 {offset}, {step}");
        Line($"store i32 {stepped}, ptr {offsetSlot}");
        Terminator($"br label %{joined}");

        Label(memory);
        string fromMemory = FromSlot(Emit("ptr", $"getelementptr inbounds i8, ptr {list}, i64 {overflowAt}"), 8);
        Terminator($"br label %{joined}");

        Label(joined);
        return Emit("ptr", $"phi ptr [ {inArea}, %{registers} ], [ {fromMemory}, %{memory} ]");
    }

    /// <summary>
    /// AAPCS64: a negative offset back from the top of a register save area,
    /// stepped towards zero; at zero or past it, the stack eight bytes at a time.
    /// </summary>
    private string FromTopOfArea(string list, int offsetAt, int topAt, int step)
    {
        string offsetSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {list}, i64 {offsetAt}");
        string offset = Emit("i32", $"load i32, ptr {offsetSlot}");

        string maybe = NextLabel("va.maybe");
        string registers = NextLabel("va.registers");
        string stack = NextLabel("va.stack");
        string joined = NextLabel("va.read");

        string spent = Emit("i1", $"icmp sge i32 {offset}, 0");
        Terminator($"br i1 {spent}, label %{stack}, label %{maybe}");

        // The offset is stepped before it is known to fit, as clang does: a
        // value that straddles the end of the area is on the stack.
        Label(maybe);
        string stepped = Emit("i32", $"add i32 {offset}, {step}");
        Line($"store i32 {stepped}, ptr {offsetSlot}");
        string beyond = Emit("i1", $"icmp sgt i32 {stepped}, 0");
        Terminator($"br i1 {beyond}, label %{stack}, label %{registers}");

        Label(registers);
        string topSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {list}, i64 {topAt}");
        string top = Emit("ptr", $"load ptr, ptr {topSlot}");
        string back = Emit("i64", $"sext i32 {offset} to i64");
        string inArea = Emit("ptr", $"getelementptr inbounds i8, ptr {top}, i64 {back}");
        Terminator($"br label %{joined}");

        Label(stack);
        string fromStack = FromSlot(list, 8);
        Terminator($"br label %{joined}");

        Label(joined);
        return Emit("ptr", $"phi ptr [ {inArea}, %{registers} ], [ {fromStack}, %{stack} ]");
    }
}
