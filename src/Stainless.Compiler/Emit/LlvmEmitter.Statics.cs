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
/// Module-level storage, and the initializer that runs before
/// <c>Main</c>.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ statics

    /// <summary>
    /// The global's name. Storage that crosses to C keeps the name C knows it
    /// by; everything else is mangled, because an ordinary static is this
    /// program's business and two modules may each have one called `count`.
    /// </summary>
    private static string StaticName(StaticSymbol symbol) =>
        symbol.LinkName ?? "_SLstatic_" + Mangler.SymbolSafe(symbol.QualifiedName);

    /// <summary>
    /// The LLVM constant a static can carry on the global itself, or null for
    /// one that needs code to run.
    ///
    /// <b>This is what lets a <c>--shared</c> library have statics at all.</b>
    /// Initializers run from the entry point and a library has none (SL0380) --
    /// but <c>static bool tried = false</c> and <c>static Backend? loaded =
    /// null</c> have nothing to run: they are a zero and a null pointer, and a
    /// global can be born holding them. Without this, no module compiled into
    /// every program could remember anything, which is what `Standard.Drawing`
    /// found when it tried to cache the imaging library it had loaded.
    ///
    /// Literals only, and never a managed reference with a value. A string
    /// literal is an object that has to be made; <c>null</c> is a pointer that
    /// does not. That line is where the rule stops, because everything past it
    /// is code.
    /// </summary>
    private string? ConstantStaticText(StaticSymbol symbol)
    {
        if (!symbol.HasConstantInitializer) return null;

        string llvmType = LlvmTypeOf(symbol.Type);

        // `null` and `default(T)` are the type's zero, which is what the global
        // would have been given anyway. `EmitLiteral` spells an absent value as
        // "0", which is right for an integer and is not a pointer, so the same
        // answer serves a literal holding nothing.
        if (symbol.Initializer is BoundNullLiteral or BoundDefault) return ZeroOf(llvmType);

        // An address the linker fills in, in writable data where every loader
        // applies a relocation. See `EmbeddedData`.
        if (symbol.Initializer is BoundEmbed embedded) return EmbedSymbol(embedded.File);

        var literal = (BoundLiteral)symbol.Initializer!;
        return literal.Value is null ? ZeroOf(llvmType) : EmitLiteral(literal).Ref;
    }

    /// <summary>
    /// One global per static: holding its constant if it has one, and zeroed
    /// for the initializer below to write if it does not.
    /// </summary>
    private void StaticStorage(BoundProgram program)
    {
        if (program.Statics.Count == 0) return;


        foreach (var symbol in program.Statics)
        {
            // Declared `extern "C"` and defined by this emitter: the definition
            // is already written and a declaration beside it is a redefinition.
            if (symbol.LinkName is not null && _definedGlobals.Contains(symbol.LinkName))
                continue;

            string llvmType = LlvmTypeOf(symbol.Type);

            // An imported one is a promise rather than storage: no initializer,
            // and the linker supplies the definition or fails. An exported one
            // is storage under a name C can reach, so it is not `internal`.
            string linkage = symbol.IsImported ? "external " :
                             symbol.LinkName is not null ? "" : "internal ";

            // A constant goes on the global itself; everything else starts
            // zeroed and is written by the initializer below. See
            // `ConstantStaticText`.
            string body = symbol.IsImported ? ""
                        : " " + (ConstantStaticText(symbol) ?? ZeroOf(llvmType));

            _module.AppendLine(
                $"@{StaticName(symbol)} = {linkage}global {llvmType}{body}, " +
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
    /// Runs every static initializer, in the order the binder worked out, then
    /// every <c>static Name() { }</c> block in declaration order.
    ///
    /// There is no lazy guard and no once-flag: the whole program was compiled
    /// together, so the dependency graph was known and sorted at compile time.
    /// A <c>readonly</c> reference is made immortal as it is stored, which is
    /// what removes the last reference traffic from a value every thread can
    /// see. A mutable one cannot be: the value it holds may be replaced, and
    /// the old one has to be released.
    /// </summary>
    private void EmitStaticInitializer(BoundProgram program)
    {
        if (program.Statics.Count == 0 && program.StaticConstructors.Count == 0) return;

        ResetFunctionState();
        _module.AppendLine($"define internal void @{StaticInitializerName}()"
                           + FrameAttributes + " {");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        foreach (var symbol in program.Statics)
        {
            if (symbol.Initializer is null) continue;

            // Already on the global, written by `StaticStorage`. Storing it
            // again would be the same value twice and would put a `--shared`
            // library's statics back in the hands of an entry point it has not
            // got.
            if (ConstantStaticText(symbol) is not null) continue;

            var value = EmitExpression(symbol.Initializer);
            string slot = "@" + StaticName(symbol);

            if (symbol.Type is StructTypeSymbol structType)
            {
                // A struct that holds references is retained field by field,
                // exactly as an assignment to one anywhere else is. The slot
                // starts zeroed, so there is nothing for the store to release.
                if (structType.CarriesReferences()) StoreInto(slot, value, symbol.Type);
                else MemCopy(slot, value.Ref, structType.Size);
            }
            else
            {
                Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");

                // A readonly one is immortal, so retain and release skip it for
                // the rest of the program: a value that lives to process exit
                // has no reference traffic, and therefore none to race over.
                if (symbol.Type.NeedsArc() && symbol.IsReadonly)
                    Line($"call void @sl_make_immortal(ptr {value.Ref})");

                // A mutable one is counted like any other slot. It cannot be
                // immortal, because a later assignment has to release what it
                // is replacing, and an immortal object is never released.
                else if (symbol.Type.NeedsArc())
                    Retain(value.Ref, symbol.Type);
            }

            // The initializer's own temporaries go now; the static holds its
            // value outright, and an immortal one cannot be released anyway.
            FlushTemporaries();
        }

        // Then the `static Name() { }` blocks, after every field has its
        // value -- which is C#'s order, and the only one that makes a block
        // able to read the fields it is there to arrange.
        foreach (var initializer in program.StaticConstructors)
            Line($"call void {Symbol(initializer)}()");

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
            Retain(held, parameter.Type);
        }

        TrackOwnedLocal(slot, parameter.Type);
    }

    private const string StaticInitializerName = "_SLstatics";

    /// <summary>
    /// The C entry point, which calls the program's.
    ///
    /// It always takes argc and argv, whether or not <c>Main</c> asked for
    /// them: the arguments are handed to the runtime either way, so that
    /// <c>Env.Program()</c> can name the executable in a program that declared
    /// <c>Main()</c>. An unused parameter costs a register that the call
    /// already had to leave alone.
    /// </summary>
    private void EmitEntryPoint(FunctionSymbol entry)
    {
        _nextTemp = 0;

        // **The shim is described too**, though nobody wrote it and nothing
        // steps through it. A call with no debug location, inlined into a
        // function with no subprogram, takes the callee's locations with it --
        // so at -O2, where `Main` is inlined into this, the program's own code
        // would be described by nothing at all.
        int? scope = debug?.EntryPoint(entry.Span);
        string at = scope is { } where && debug is not null
            ? $", !dbg !{debug.Location(entry.Span, where)}"
            : "";

        _module.AppendLine("define i32 @main(i32 %argc, ptr %argv)"
                           + FrameAttributes
                           + (scope is { } attached ? $" !dbg !{attached}" : "")
                           + " {");
        _module.AppendLine("entry:");
        _module.AppendLine($"  call void @sl_args_set(i32 %argc, ptr %argv){at}");

        // Statics first, in dependency order, before any user code runs. After
        // the arguments, so that a static initializer may read them.
        if (_hasStatics)
            _module.AppendLine($"  call void @{StaticInitializerName}(){at}");

        // `Main(String[] args)`. The runtime builds the array, because the
        // TypeInfo that says how to destroy it belongs to this module and a
        // loop in the entry point is the last place to want one.
        //
        // Written out rather than through Emit(), which appends to whichever
        // function body is open and there is none here.
        string arguments = "";
        if (entry.Parameters.Count == 1 && entry.Parameters[0].Type is ArrayTypeSymbol array)
        {
            _module.AppendLine(
                $"  %args = call ptr @sl_args_array(ptr @{ArrayTypeInfoName(array)}){at}");
            arguments = "ptr %args";
        }

        if (entry.ReturnType.IsVoid())
        {
            _module.AppendLine($"  call void {Symbol(entry)}({arguments}){at}");
            if (arguments.Length > 0)
                _module.AppendLine($"  call void @sl_release(ptr %args){at}");
            _module.AppendLine($"  ret i32 0{at}");
        }
        else
        {
            _module.AppendLine($"  %code = call i32 {Symbol(entry)}({arguments}){at}");
            if (arguments.Length > 0)
                _module.AppendLine($"  call void @sl_release(ptr %args){at}");
            _module.AppendLine($"  ret i32 %code{at}");
        }

        _module.AppendLine("}");
        _module.AppendLine();
    }
}
