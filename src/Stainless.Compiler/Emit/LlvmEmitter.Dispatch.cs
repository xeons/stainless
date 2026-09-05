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
/// Every table a call may go through: virtual tables, interface tables,
/// COM vtables and the adjustor thunks that make a tear-off's address
/// usable as a <c>this</c>.
/// </summary>
public sealed partial class LlvmEmitter
{
    private int _interfaceCount;

    /// <summary>
    /// Where the vtable sits in an SlTypeInfo. The `base` pointer is beside it
    /// at 64 and has no constant here, because nothing emitted reads it: a
    /// downcast asks `sl_is_instance`, which walks the chain in C.
    /// </summary>
    private const int VirtualTableOffset = 72;

    private static string VirtualTableName(ClassTypeSymbol type) =>
        "_SLvtable_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>
    /// Emits one dispatch table per class that has virtual methods.
    ///
    /// The binder built the list, inherited entries and all, so this only writes
    /// it down: slot n holds whatever this class supplies for slot n, whether it
    /// declared it, overrode it, or inherited it untouched. An abstract entry is
    /// null and is unreachable -- the class carrying it cannot be instantiated,
    /// and every concrete class below it has filled the slot in.
    /// </summary>
    private void VirtualTables(BoundProgram program)
    {
        var dispatching = program.Classes.Where(c => c.VirtualTable.Count > 0).ToList();
        if (dispatching.Count == 0) return;

        _module.AppendLine();
        foreach (var classType in dispatching)
        {
            var slots = classType.VirtualTable
                .Select(m => m.IsAbstract ? "ptr null" : $"ptr {Symbol(m)}");

            _module.AppendLine(
                $"@{VirtualTableName(classType)} = internal constant " +
                $"[{classType.VirtualTable.Count} x ptr] [{string.Join(", ", slots)}]");
        }
    }

    private static string InterfaceTableName(ClassTypeSymbol type) =>
        "_SLitab_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>The table of tear-offs a com class presents, keyed by IID.</summary>
    private static string ComLayoutName(ClassTypeSymbol type) =>
        "_SLcom_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>One com interface's vtable, as implemented by one class.</summary>
    private static string ComVTableName(ClassTypeSymbol type, ComInterfaceTypeSymbol iface) =>
        "_SLcomvt_" + Mangler.SymbolSafe(type.QualifiedName) + "_" +
        Mangler.SymbolSafe(iface.QualifiedName);

    /// <summary>The 16-byte constant an interface's [Guid] folded to.</summary>
    private static string IidName(ComInterfaceTypeSymbol iface) =>
        "_SLiid_" + Mangler.SymbolSafe(iface.QualifiedName);

    private static string VTableName(ClassTypeSymbol type, InterfaceTypeSymbol iface) =>
        "_SLvt_" + Mangler.SymbolSafe(type.QualifiedName) + "_" + Mangler.SymbolSafe(iface.QualifiedName);

    /// <summary>
    /// Emits, for every class that implements something, one vtable per
    /// interface plus a table indexed by interface id.
    ///
    /// Ids are assigned across the whole program, so the table is indexed
    /// directly and a dispatch never searches. The cost is one pointer per
    /// interface per implementing class, which is a few hundred bytes in a
    /// realistic program.
    /// </summary>
    private void InterfaceTables(BoundProgram program)
    {
        var implementers = program.Classes.Where(c => c.Interfaces.Count > 0).ToList();
        if (implementers.Count == 0) return;

        _module.AppendLine();
        foreach (var classType in implementers)
        {
            foreach (var interfaceType in classType.Interfaces)
            {
                // By parameter types, not by name: a class implementing both
                // IEquatable<int> and IEquatable<String> has two methods called
                // Same, and each interface's table takes the one that fits it.
                // An abstract implementation is a null slot, exactly as it is
                // in the virtual table: there is no body to point at, and no
                // instance of this class to reach it through. A derived class
                // fills the slot in its own table.
                var slots = interfaceType.Methods
                    .Select(classType.FindImplementation)
                    .Select(found => found is null || found.IsAbstract
                        ? "ptr null"
                        : $"ptr {Symbol(found)}")
                    .ToList();

                string body = slots.Count == 0 ? "ptr null" : string.Join(", ", slots);
                int width = Math.Max(1, slots.Count);

                _module.AppendLine(
                    $"@{VTableName(classType, interfaceType)} = internal constant " +
                    $"[{width} x ptr] [{body}]");
            }

            var entries = new string[Math.Max(1, _interfaceCount)];
            Array.Fill(entries, "ptr null");
            foreach (var interfaceType in classType.Interfaces)
                entries[interfaceType.Id] = $"ptr @{VTableName(classType, interfaceType)}";

            _module.AppendLine(
                $"@{InterfaceTableName(classType)} = internal constant " +
                $"[{entries.Length} x ptr] [{string.Join(", ", entries)}]");
        }
    }

    /// <summary>
    /// Everything COM needs in static storage: an IID per interface, a vtable
    /// per (class, interface) pair, and one table per class saying which
    /// tear-off answers for which IID.
    /// </summary>
    private void ComTables(BoundProgram program)
    {
        var comClasses = program.Classes.Where(c => c.IsCom && c.ComInterfaces.Count > 0).ToList();
        var used = program.ComInterfaces
            .Concat(comClasses.SelectMany(c => c.ComInterfaces))
            .Distinct()
            .ToList();

        if (used.Count == 0 && comClasses.Count == 0) return;

        _module.AppendLine();

        // --- one IID per interface ---------------------------------------
        //
        // Laid out as a GUID is laid out and not as sixteen bytes in order: the
        // first three fields are little-endian integers on the wire as well as
        // in memory, which is why 00000000-0000-0000-C000-000000000046 reads
        // the way it does in a header and the way it does here.
        foreach (var comInterface in used.Where(i => i.Iid is not null))
        {
            var (a, b, c, tail) = GuidParts(comInterface.Iid!.Value);
            _module.AppendLine(
                $"@{IidName(comInterface)} = internal constant " +
                $"{{ i32, i16, i16, [8 x i8] }} " +
                $"{{ i32 {a}, i16 {b}, i16 {c}, [8 x i8] c\"{RawBytes(tail)}\" }}");
        }

        if (comClasses.Count == 0) return;

        // --- a vtable per class, per interface ----------------------------
        foreach (var classType in comClasses)
        {
            foreach (var presented in classType.ComInterfaces)
            {
                foreach (var required in presented.VirtualTable)
                {
                    if (required.ContainingType is ComInterfaceTypeSymbol { SimpleName: "IUnknown" })
                        continue;
                    EmitComAdjustor(classType, presented, required);
                }

                var slots = presented.VirtualTable
                    .Select(required => ComSlotBody(classType, presented, required))
                    .ToList();

                _module.AppendLine(
                    $"@{ComVTableName(classType, presented)} = internal constant " +
                    $"[{slots.Count} x ptr] [{string.Join(", ", slots)}]");
            }

            var entries = classType.ComInterfaces
                .Select(presented =>
                    $"{{ ptr, i64 }} {{ ptr @{IidName(presented)}, " +
                    $"i64 {classType.TearOffOffset(presented)} }}")
                .ToList();

            _module.AppendLine(
                $"@{ComLayoutName(classType)}_entries = internal constant " +
                $"[{entries.Count} x {{ ptr, i64 }}] [{string.Join(", ", entries)}]");

            _module.AppendLine(
                $"@{ComLayoutName(classType)} = internal constant {{ i64, ptr }} " +
                $"{{ i64 {entries.Count}, ptr @{ComLayoutName(classType)}_entries }}");
        }
    }

    /// <summary>
    /// What goes in one vtable slot.
    ///
    /// IUnknown's three are the runtime's, the same three functions for every
    /// com class: they only need the tear-off's own offset, and it is stored
    /// beside them rather than compiled in.
    /// </summary>
    private string ComSlotBody(
        ClassTypeSymbol classType, ComInterfaceTypeSymbol presented, FunctionSymbol required)
    {
        if (required.ContainingType is ComInterfaceTypeSymbol { SimpleName: "IUnknown" })
            return required.VirtualSlot switch
            {
                0 => "ptr @sl_com_object_query",
                1 => "ptr @sl_com_object_add_ref",
                _ => "ptr @sl_com_object_release",
            };

        var found = classType.FindImplementation(required);
        if (found is null) return "ptr null";

        // Keyed by the table this slot is in. A derived interface inherits a
        // method's slot but has its own tear-off, so the two tables need two
        // thunks for the one method, subtracting two different distances.
        return $"ptr @{AdjustorName(classType, presented, required.VirtualSlot)}";
    }

    private static string AdjustorName(
        ClassTypeSymbol type, ComInterfaceTypeSymbol presented, int slot) =>
        "_SLadj_" + Mangler.SymbolSafe(type.QualifiedName) + "_" +
        Mangler.SymbolSafe(presented.QualifiedName) + "_" + slot;

    /// <summary>
    /// Emits the thunk one vtable slot points at.
    ///
    /// It takes what COM passes -- the tear-off's address -- steps back to the
    /// object, and tail-calls the method with everything else untouched. The
    /// distance is a constant of the layout, so the whole body is one
    /// getelementptr and one call, and the call is a tail call, so the thunk
    /// leaves no frame behind.
    ///
    /// The parameters are forwarded by name and never inspected, which is what
    /// keeps this independent of how any of them are passed: a struct going by
    /// hidden pointer arrives as a pointer here too, and is handed straight on.
    /// </summary>
    private void EmitComAdjustor(
        ClassTypeSymbol classType, ComInterfaceTypeSymbol presented, FunctionSymbol required)
    {
        var target = classType.FindImplementation(required);
        if (target is null) return;

        var returnInfo = ClassifyResult(target.ReturnType);
        string returnType = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;

        var declared = new List<string>();
        var forwarded = new List<string>();

        if (returnInfo.Style == PassStyle.Indirect)
        {
            string sret = $"ptr sret({StructName((StructTypeSymbol)target.ReturnType)}) %sret";
            declared.Add(sret);
            forwarded.Add(sret);
        }

        // The receiver, which is the one argument the thunk changes.
        declared.Add("ptr %self");

        foreach (var parameter in target.Parameters.Where(p => !p.IsThis))
        {
            // One name per register, so a struct arriving in two is forwarded
            // as the two it arrived in.
            int piece = 0;
            foreach (string spelling in Declared(ClassifyParameter(parameter)))
            {
                string named = $"{spelling} %a{parameter.Index}_{piece}";
                declared.Add(named);
                forwarded.Add(named);
                piece++;
            }
        }

        int offset = classType.TearOffOffset(presented);
        string name2 = AdjustorName(classType, presented, required.VirtualSlot);

        _module.AppendLine(
            $"define internal {returnType} @{name2}({string.Join(", ", declared)}) {{");
        _module.AppendLine(
            $"  %obj = getelementptr inbounds i8, ptr %self, i64 -{offset}");

        forwarded.Insert(returnInfo.Style == PassStyle.Indirect ? 1 : 0, "ptr %obj");
        string call = $"call {returnType} {Symbol(target)}({string.Join(", ", forwarded)})";

        if (returnType == "void")
        {
            _module.AppendLine($"  {call}");
            _module.AppendLine("  ret void");
        }
        else
        {
            _module.AppendLine($"  %r = {call}");
            _module.AppendLine($"  ret {returnType} %r");
        }

        _module.AppendLine("}");
    }

    /// <summary>A GUID split the way its first three fields are stored.</summary>
    private static (uint A, ushort B, ushort C, byte[] Tail) GuidParts(Guid value)
    {
        byte[] bytes = value.ToByteArray();          // already little-endian for a, b and c
        return (BitConverter.ToUInt32(bytes, 0),
                BitConverter.ToUInt16(bytes, 4),
                BitConverter.ToUInt16(bytes, 6),
                bytes[8..]);
    }
}
