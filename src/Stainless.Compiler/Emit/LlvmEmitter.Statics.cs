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
/// Module-level storage, and the initializer that runs before
/// <c>Main</c>.
/// </summary>
public sealed partial class LlvmEmitter
{
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
            Retain(held, parameter.Type);
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
            _module.AppendLine($"  call void {Symbol(entry)}()");
            _module.AppendLine("  ret i32 0");
        }
        else
        {
            _module.AppendLine($"  %0 = call i32 {Symbol(entry)}()");
            _module.AppendLine("  ret i32 %0");
        }

        _module.AppendLine("}");
        _module.AppendLine();
    }
}
