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
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Which functions are emitted. The program's own are, every one, called or
/// not, so a mistake in one is found when it is written. A function of a
/// pruned module -- the standard library's -- is emitted only when something
/// emitted names it.
///
/// <para>
/// A function is queued the first time <see cref="Symbol(FunctionSymbol)"/>
/// spells its name, so what is reached is exactly what the IR refers to, and
/// there is no second account of the references to fall out of step with the
/// first. The roots are the program's own functions and the exports; the
/// entry point, the static initializers and the dispatch tables name the rest
/// as they are written.
/// </para>
///
/// <para>
/// A reached library module holds a great deal no program calls, which LLVM
/// deletes in its first pass and the linker strips from a debug build;
/// skipping it saves writing it, reading it back and the work in between. The
/// unit tests, the samples' tests and the fuzzer prune nothing, so the IR of a
/// library function nothing calls is still verified.
/// </para>
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>Every function with a body, by its symbol name.</summary>
    private readonly Dictionary<string, BoundFunction> _bodies = new(StringComparer.Ordinal);

    private readonly HashSet<string> _reached = new(StringComparer.Ordinal);
    private readonly Queue<BoundFunction> _toEmit = new();

    /// <summary>Queues the body of <paramref name="function"/>, once, if it has one here.</summary>
    private void Reach(FunctionSymbol function)
    {
        if (_bodies.TryGetValue(function.MangledName, out var body) && _reached.Add(function.MangledName))
            _toEmit.Enqueue(body);
    }

    /// <summary>
    /// Registers every body, and queues the roots: every function outside the
    /// pruned modules, and the exports inside them.
    /// </summary>
    private void QueueRoots(BoundProgram program)
    {
        foreach (var function in program.Functions)
            _bodies.TryAdd(function.Symbol.MangledName, function);

        foreach (var function in program.Functions)
            if (prunedModules is null || !prunedModules.Contains(function.Symbol.ModuleName) ||
                IsExported(function.Symbol))
                Reach(function.Symbol);
    }

    /// <summary>
    /// Emits what is queued, and the thunks and enum texts those ask for, until
    /// nothing new is named.
    /// </summary>
    private void EmitReached()
    {
        do
        {
            while (_toEmit.Count > 0)
                EmitFunction(_toEmit.Dequeue());
            EmitThunks();
            EmitEnumTexts();
        }
        while (_toEmit.Count > 0);
    }

    /// <summary>
    /// Whether a function is reachable from outside this binary: a C export,
    /// or the public surface of a library a Stainless consumer binds against.
    /// </summary>
    /// <remarks>
    /// <c>public</c> alone does not export: it says which modules may see a
    /// function, and a C library's surface is stated once with
    /// <c>export "C"</c>. Asking for module metadata says something different
    /// -- that another Stainless compilation will bind against this -- and that
    /// surface is exactly the public declarations the metadata describes.
    /// Protected is exported alongside public, and only from a public type: a
    /// dispatched method must be public or protected (SL0506), so a protected
    /// one can be filling a slot that a class derived in another binary has to
    /// copy into its own table or replace. A consumer that is not deriving
    /// still cannot reach it -- what keeps it protected is the binder, and the
    /// export only means the linker can find it.
    /// </remarks>
    private bool IsExported(FunctionSymbol symbol) =>
        symbol.Linkage is LinkageKind.ExportC or LinkageKind.ExportCpp
        || (DescribedToConsumers(symbol.ModuleName) && symbol.Linkage == LinkageKind.Stainless
            && !symbol.IsExternal
            && (symbol.IsPublic || symbol.IsProtected
                || symbol.Kind == FunctionKind.Constructor)
            && symbol.ContainingType is null or { IsPublic: true }
            && symbol.TypeArguments.Count == 0);
}
