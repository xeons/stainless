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
/// Retain and release, and everything that decides where they go.
///
/// Every reference-counting decision in the compiler is made here.
/// Which function a retain calls depends on what is being retained --
/// an object, a weak reference or a COM interface -- and open-coding
/// that anywhere else is how the three drift apart.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ ARC

    private void PushScope() => _scopes.Add([]);

    private void PopScopeWithoutRelease() => _scopes.RemoveAt(_scopes.Count - 1);

    private void TrackOwnedLocal(string slot, TypeSymbol type)
    {
        if (type.CarriesReferences()) _scopes[^1].Add((slot, type));
    }

    /// <summary>Releases every owned local from the innermost scope down to <paramref name="depth"/>.</summary>
    private void ReleaseScopes(int depth)
    {
        for (int i = _scopes.Count - 1; i >= depth; i--)
            foreach (var (slot, type) in Enumerable.Reverse(_scopes[i]))
                ReleaseSlot(slot, type);
    }

    private void ReleaseCurrentScope()
    {
        foreach (var (slot, type) in Enumerable.Reverse(_scopes[^1]))
            ReleaseSlot(slot, type);
    }

    /// <summary>
    /// Drops what a storage slot owns: the reference it holds, or, for a struct,
    /// every reference inside it.
    /// </summary>
    private void ReleaseSlot(string slot, TypeSymbol type)
    {
        if (type is StructTypeSymbol structType)
        {
            ReleaseFieldsAt(slot, structType);
            return;
        }

        string value = Emit("ptr", $"load ptr, ptr {slot}");
        Release(value, type);
    }

    /// <summary>
    /// Retains every reference inside the struct at <paramref name="address"/>,
    /// recursing through struct fields.
    ///
    /// This is what a struct copy costs once it holds a reference. It is the
    /// price of lifting the old rule that a struct was always raw bytes, and it
    /// is charged only to structs that actually hold one — a struct of plain
    /// data still copies with a memcpy and nothing else.
    /// </summary>
    private void RetainFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            if (type is VariantTypeSymbol variant)
            {
                Line($"call void @{VariantArcName(variant, retaining: true)}(ptr {slot})");
                return;
            }

            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Retain(value, type);
        });

    /// <summary>Releases every reference inside the struct at <paramref name="address"/>.</summary>
    private void ReleaseFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            if (type is VariantTypeSymbol variant)
            {
                Line($"call void @{VariantArcName(variant, retaining: false)}(ptr {slot})");
                return;
            }

            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Release(value, type);
        });

    /// <summary>
    /// Visits the address of every counted reference inside a struct value,
    /// descending into struct fields so a nested one is not missed.
    ///
    /// A variant is handed to the visitor whole rather than walked. Which of
    /// its references are really there is a question about the tag, and the
    /// answer is a branch at run time rather than a list at compile time — so
    /// it goes to a function of its own that the visitor calls.
    /// </summary>
    private void WalkReferences(
        string address, StructTypeSymbol structType, Action<string, TypeSymbol> visit)
    {
        if (structType is VariantTypeSymbol self)
        {
            visit(address, self);
            return;
        }

        foreach (var field in structType.Fields)
        {
            if (!field.Type.CarriesReferences()) continue;

            string slot = StructFieldAddress(address, structType, field);

            if (field.Type is VariantTypeSymbol nestedVariant) visit(slot, nestedVariant);
            else if (field.Type is StructTypeSymbol nested) WalkReferences(slot, nested, visit);
            else visit(slot, field.Type);
        }
    }

    private static string VariantArcName(VariantTypeSymbol variant, bool retaining) =>
        (retaining ? "_SLvretain_" : "_SLvrelease_") + Mangler.SymbolSafe(variant.QualifiedName);

    /// <summary>
    /// The two functions that copy and drop a variant's references.
    ///
    /// A struct's references are a list the compiler can write out; a variant's
    /// are whichever case is in the tag, so this is a switch. Only the case
    /// actually present is touched, which is the whole reason the payloads may
    /// overlap: nothing ever retains or releases through the bytes of a case
    /// that is not there.
    ///
    /// A variant no case of which holds a reference gets no function at all,
    /// because nothing asks for one — <c>CarriesReferences</c> is false for it,
    /// and it copies as plain bytes like any other struct.
    /// </summary>
    private void EmitVariantArcThunks(VariantTypeSymbol variant)
    {
        foreach (bool retaining in (bool[])[true, false])
        {
            ResetFunctionState();
            _module.AppendLine(
                $"define internal void @{VariantArcName(variant, retaining)}(ptr %value) {{");
            _body.Clear();
            _blockTerminated = false;

            string tag = Emit("i8",
                $"load i8, ptr {Emit("ptr", $"getelementptr inbounds {StructName(variant)}, " +
                                           "ptr %value, i32 0, i32 0")}");

            string endLabel = NextLabel("variant.done");
            var arms = new List<(VariantCaseSymbol Case, string Label)>();

            foreach (var variantCase in variant.Cases)
            {
                if (variantCase.Payload is not { } payload) continue;
                if (!payload.Fields.Any(f => f.Type.CarriesReferences())) continue;

                arms.Add((variantCase, NextLabel("variant.case")));
            }

            Terminator($"switch i8 {tag}, label %{endLabel} [ " +
                       string.Join(" ", arms.Select(a => $"i8 {a.Case.Tag}, label %{a.Label}")) +
                       " ]");

            foreach (var (variantCase, label) in arms)
            {
                Label(label);

                string address = Emit("ptr",
                    $"getelementptr inbounds {StructName(variant)}, ptr %value, i32 0, i32 1");

                if (retaining) RetainFieldsAt(address, variantCase.Payload!);
                else ReleaseFieldsAt(address, variantCase.Payload!);

                Terminator($"br label %{endLabel}");
            }

            Label(endLabel);
            Terminator("ret void");

            _module.AppendLine("entry:");
            _module.Append(_entryAllocas);
            _module.Append(_body);
            _module.AppendLine("}");
            _module.AppendLine();
        }
    }

    /// <summary>Registers a +1 value for release once the current statement finishes.</summary>
    private void TrackTemporary(string reference, TypeSymbol type) =>
        _pendingReleases.Add((reference, type));

    private void FlushTemporaries(int from = 0)
    {
        for (int i = from; i < _pendingReleases.Count; i++)
        {
            var (reference, type) = _pendingReleases[i];

            // A struct temporary is held by address, so what is dropped is what
            // lies inside it rather than the pointer itself.
            if (type is StructTypeSymbol structType)
            {
                ReleaseFieldsAt(reference, structType);
                continue;
            }

            Release(reference, type);
        }

        _pendingReleases.RemoveRange(from, _pendingReleases.Count - from);
    }

    /// <summary>
    /// True when a slot of this type is counted by COM rather than by the
    /// runtime's own header. An optional one still is: <c>IFoo?</c> is the same
    /// pointer, allowed to be null.
    /// </summary>
    private static bool IsComReference(TypeSymbol type) =>
        type is ComInterfaceTypeSymbol or OptionalTypeSymbol { Element: ComInterfaceTypeSymbol };

    /// <summary>
    /// The runtime function that adds a reference to a value of this type.
    ///
    /// Three kinds of counting, one decision. A COM reference goes through the
    /// object's own AddRef -- sl_com_retain is a null test and an indirect call,
    /// in one place rather than emitted at every site.
    /// </summary>
    private static string RetainOf(TypeSymbol type) =>
        type is WeakTypeSymbol ? "sl_weak_retain"
        : IsComReference(type) ? "sl_com_retain"
        : "sl_retain";

    private static string ReleaseOf(TypeSymbol type) =>
        type is WeakTypeSymbol ? "sl_weak_release"
        : IsComReference(type) ? "sl_com_release"
        : "sl_release";

    private void Retain(string value, TypeSymbol type) =>
        Line($"call void @{RetainOf(type)}(ptr {value})");

    private void Release(string value, TypeSymbol type) =>
        Line($"call void @{ReleaseOf(type)}(ptr {value})");

    /// <summary>
    /// Stores into an owning slot: retain the new value, release the old one, in
    /// that order, so <c>x = x</c> cannot destroy the object mid-assignment.
    /// </summary>
    private void StoreManaged(string slot, string value, TypeSymbol type)
    {
        Retain(value, type);
        string old = Emit("ptr", $"load ptr, ptr {slot}");
        Release(old, type);
        Line($"store ptr {value}, ptr {slot}");
    }
}
