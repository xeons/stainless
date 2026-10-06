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

/// <summary>
/// The foreign call a <c>[Throws]</c> wrapper makes: an <c>invoke</c>, whose
/// landing pad records what was thrown in the call's local and goes on.
///
/// <para>
/// <b>An Objective-C exception is told from any other by the clause that
/// caught it</b>, as clang's <c>@catch (id)</c> does, and is asked its name and
/// reason. Anything else is deleted unread: only C++ can read a C++ exception,
/// and nothing here links the C++ runtime.
/// </para>
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>Whether the function being emitted makes a call that catches.</summary>
    private bool _catchesForeign;

    /// <summary>
    /// Emits <paramref name="invocation"/>, a <c>call</c>, and answers its
    /// result, or null for none.
    ///
    /// For a call that catches, an <c>invoke</c>. <paramref name="onReturned"/>
    /// runs on the path the call returned along, before the paths join: what
    /// it does to a result -- claim it, check it -- it MUST NOT do to one that
    /// was never produced. Where the call threw, the result is its type's zero.
    /// </summary>
    private string? EmitInvocation(
        BoundCall call, string? llvmType, string invocation, Func<string?, string?>? onReturned = null)
    {
        if (call.CatchesForeign is not { } caught)
        {
            string? plain = null;
            if (llvmType is null)
                Line(invocation);
            else
                plain = Emit(llvmType, invocation);
            return onReturned is null ? plain : onReturned(plain);
        }

        _catchesForeign = true;
        string returned = NextLabel("call.returned");
        string threw = NextLabel("call.threw");
        string joined = NextLabel("call.joined");

        string? slot = null;
        if (llvmType is not null)
        {
            slot = Alloca(llvmType, "call.result");
            Line($"store {llvmType} {ZeroOf(llvmType)}, ptr {slot}");
        }

        string invoke = "invoke" + invocation["call".Length..] + $" to label %{returned} unwind label %{threw}";
        string? result = null;
        if (llvmType is null)
        {
            Terminator(invoke);
        }
        else
        {
            result = NextTemp();
            Terminator($"{result} = {invoke}");
        }

        Label(returned);
        string? kept = onReturned is null ? result : onReturned(result);
        if (slot is not null && kept is not null)
            Line($"store {llvmType} {kept}, ptr {slot}");
        Terminator($"br label %{joined}");

        Label(threw);
        EmitForeignCatch(caught);
        Terminator($"br label %{joined}");

        Label(joined);
        return slot is null ? null : Emit(llvmType!, $"load {llvmType}, ptr {slot}");
    }

    /// <summary>The landing pad's work: what was thrown, recorded in <paramref name="caught"/>.</summary>
    private void EmitForeignCatch(LocalSymbol caught)
    {
        bool darwin = TargetPlatform.Current.IsDarwin;
        string pad = Emit("{ ptr, i32 }",
            "landingpad { ptr, i32 } " + (darwin ? "catch ptr @OBJC_EHTYPE_id " : "") + "catch ptr null");
        string thrown = Emit("ptr", $"extractvalue {{ ptr, i32 }} {pad}, 0");
        string into = _slots[caught];

        if (darwin)
        {
            string clause = Emit("i32", $"extractvalue {{ ptr, i32 }} {pad}, 1");
            string objectiveC = Emit("i32", "call i32 @llvm.eh.typeid.for.p0(ptr @OBJC_EHTYPE_id)");
            string isObject = Emit("i1", $"icmp eq i32 {clause}, {objectiveC}");
            string asked = NextLabel("caught.objc");
            string other = NextLabel("caught.other");
            string done = NextLabel("caught.done");
            Terminator($"br i1 {isObject}, label %{asked}, label %{other}");

            Label(asked);
            string exception = Emit("ptr", $"call ptr @objc_begin_catch(ptr {thrown})");
            string name = AskText(exception, "name");
            string reason = AskText(exception, "reason");
            string record = Emit("ptr", $"call ptr @sl_foreign_caught(ptr {name}, ptr {reason})");
            Line("call void @objc_end_catch()");
            Line($"store ptr {record}, ptr {into}");
            Terminator($"br label %{done}");

            Label(other);
            EmitOtherCatch(thrown, into);
            Terminator($"br label %{done}");

            Label(done);
            return;
        }

        EmitOtherCatch(thrown, into);
    }

    /// <summary>An exception no language here can read: its kind recorded, and itself deleted.</summary>
    private void EmitOtherCatch(string thrown, string into)
    {
        string record = Emit("ptr", $"call ptr @sl_foreign_caught_other(ptr {thrown})");
        Line($"call void @_Unwind_DeleteException(ptr {thrown})");
        Line($"store ptr {record}, ptr {into}");
    }

    /// <summary>An object's string property as UTF-8, or null when either is nil.</summary>
    private string AskText(string target, string selector)
    {
        string ask = Emit("ptr", $"load ptr, ptr {SelectorReference(selector)}");
        string value = Emit("ptr", $"call ptr @objc_msgSend(ptr {target}, ptr {ask})");
        string askText = Emit("ptr", $"load ptr, ptr {SelectorReference("UTF8String")}");
        return Emit("ptr", $"call ptr @objc_msgSend(ptr {value}, ptr {askText})");
    }

    /// <summary>The personality a function that catches is defined with.</summary>
    private static string ForeignPersonality =>
        TargetPlatform.Current.IsDarwin ? "@__objc_personality_v0" : "@__gxx_personality_v0";
}
