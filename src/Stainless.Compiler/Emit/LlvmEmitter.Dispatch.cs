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
/// Every table a call may go through: virtual tables, interface tables,
/// COM vtables and the adjustor thunks that make a tear-off's address
/// usable as a <c>this</c>.
/// </summary>
public sealed partial class LlvmEmitter
{
    private int _interfaceCount;

    /// <summary>
    /// Where the vtable sits in an SlTypeInfo: the tenth word, whatever a word
    /// is on this target. See <see cref="RuntimeLayout"/>.
    /// </summary>
    private static int VirtualTableOffset => RuntimeLayout.TypeInfoVTable;

    /// <summary>
    /// Where the base TypeInfo pointer sits, for the one case that has to write
    /// it after the fact. See <see cref="PatchBasesAtStartup"/>.
    /// </summary>
    private const int BaseTypeInfoOffset = 64;

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

            // SlComEntry is { const SlGuid *iid; size_t offset; } and SlComLayout
            // is { size_t count; const SlComEntry *entries; }, so the offsets
            // and the count are a word wide and not eight bytes. Written as
            // eight, a 32-bit build put the entry array's stride at sixteen
            // where the runtime read it at eight, and QueryInterface answered
            // with whatever was next.
            var entries = classType.ComInterfaces
                .Select(presented =>
                    $"{{ ptr, {Word} }} {{ ptr @{IidName(presented)}, " +
                    $"{Word} {classType.TearOffOffset(presented)} }}")
                .ToList();

            _module.AppendLine(
                $"@{ComLayoutName(classType)}_entries = internal constant " +
                $"[{entries.Count} x {{ ptr, {Word} }}] [{string.Join(", ", entries)}]");

            _module.AppendLine(
                $"@{ComLayoutName(classType)} = internal constant {{ {Word}, ptr }} " +
                $"{{ {Word} {entries.Count}, ptr @{ComLayoutName(classType)}_entries }}");
        }
    }

    /// <summary>The CLSID a com class's <c>[Guid]</c> folded to.</summary>
    private static string ClsidName(ClassTypeSymbol type) =>
        "_SLclsid_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>The function that makes one, for the runtime's class factory.</summary>
    private static string ComCreateName(ClassTypeSymbol type) =>
        "_SLcomcreate_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>
    /// The table <c>DllGetClassObject</c> is answered from: every com class
    /// carrying a CLSID, paired with a function that makes one.
    ///
    /// It is emitted into the program rather than kept in the runtime, and its
    /// address is passed to <c>sl_com_get_class_object</c> rather than looked
    /// up by name. The runtime is a separate library and may be a shared one,
    /// so a symbol it referenced and the program defined would have to be weak
    /// -- which COFF does not do the way ELF does. Passing the address costs an
    /// argument and works the same everywhere.
    ///
    /// Always emitted, empty table and all, so the symbol exists whether or not
    /// this program has anything to activate.
    /// </summary>
    private void ComFactoryTable(BoundProgram program)
    {
        var activatable = program.Classes
            .Where(c => c is { IsCom: true, Clsid: not null } && c.ComInterfaces.Count > 0)
            .OrderBy(c => c.QualifiedName, StringComparer.Ordinal)
            .ToList();

        _module.AppendLine();

        foreach (var classType in activatable)
        {
            var (a, b, c, tail) = GuidParts(classType.Clsid!.Value);
            _module.AppendLine(
                $"@{ClsidName(classType)} = internal constant " +
                $"{{ i32, i16, i16, [8 x i8] }} " +
                $"{{ i32 {a}, i16 {b}, i16 {c}, [8 x i8] c\"{RawBytes(tail)}\" }}");

            EmitComCreate(classType);
        }

        // { const SlGuid *clsid; void *(*create)(void); }
        var entries = activatable
            .Select(c => $"{{ ptr, ptr }} {{ ptr @{ClsidName(c)}, ptr @{ComCreateName(c)} }}")
            .ToList();

        _module.AppendLine(
            $"@sl_com_factory_entries = internal constant " +
            $"[{entries.Count} x {{ ptr, ptr }}] " +
            (entries.Count == 0 ? "zeroinitializer" : $"[{string.Join(", ", entries)}]"));

        // What DllCanUnloadNow reads: every com class object this module has
        // made and not yet destroyed, plus every class factory still held.
        //
        // A module-wide total rather than a walk over objects, because there is
        // nothing to walk -- ARC gives each object its own count and keeps no
        // list of them. This is the one number those counts do not add up to on
        // their own, so it is kept as they move.
        if (_countsComObjects)
            _module.AppendLine("@sl_com_live = internal global i32 0");

        _module.AppendLine(
            $"@sl_com_factory_table = internal constant {{ {Word}, ptr, ptr }} " +
            $"{{ {Word} {entries.Count}, ptr @sl_com_factory_entries, " +
            (_countsComObjects ? "ptr @sl_com_live" : "ptr null") + " }");

        // What `Com.GetClassObject` binds to: the runtime function with this
        // module's table already supplied. A shim rather than a special case in
        // the expression emitter, so the call site is an ordinary call.
        //
        // Not `internal`, because the builtin is declared like any other
        // runtime entry point and LLVM refuses a `declare` that a later
        // `define internal` contradicts. Nothing exports it, so it stays inside
        // whichever binary emitted it either way.
        _module.AppendLine(
            "define i32 @sl_com_class_object_here(" +
            "ptr %clsid, ptr %iid, ptr %result) {");
        _module.AppendLine("entry:");
        _module.AppendLine(
            "  %answer = call i32 @sl_com_get_class_object(" +
            "ptr @sl_com_factory_table, ptr %clsid, ptr %iid, ptr %result)");
        _module.AppendLine("  ret i32 %answer");
        _module.AppendLine("}");

        // And the same for `Com.CanUnloadNow`, which reads the live count the
        // table points at.
        _module.AppendLine("define i32 @sl_com_can_unload_here() {");
        _module.AppendLine("entry:");
        _module.AppendLine(
            "  %answer = call i32 @sl_com_can_unload_now(ptr @sl_com_factory_table)");
        _module.AppendLine("  ret i32 %answer");
        _module.AppendLine("}");
    }

    /// <summary>
    /// A parameterless maker for one activatable class: allocate, wire the
    /// tear-offs, run the constructor, hand back the first tear-off.
    ///
    /// The first tear-off and not the object, because what a class factory
    /// returns is a COM pointer -- and it is the same address
    /// <c>QueryInterface</c> answers for IUnknown, which is what lets two
    /// references to this object be compared for identity. The +1 that
    /// <c>sl_alloc</c> produced is the one the caller receives.
    /// </summary>
    private void EmitComCreate(ClassTypeSymbol classType)
    {
        // Parameterless as the source writes it: `this` is a parameter here.
        var constructor = classType.Constructors
            .FirstOrDefault(c => !c.Parameters.Any(p => !p.IsThis));

        _module.AppendLine($"define internal ptr @{ComCreateName(classType)}() {{");
        _module.AppendLine("entry:");
        _module.AppendLine(
            $"  %object = call ptr @sl_alloc(ptr @{Mangler.TypeInfoSymbol(classType)})");

        // The same count EmitNew keeps; this path does not go through it. Named
        // because atomicrmw yields a value, and every other value in this
        // function is named too.
        if (_countsComObjects)
            _module.AppendLine(
                "  %live = atomicrmw add ptr @sl_com_live, i32 1 monotonic");

        foreach (var presented in classType.ComInterfaces)
        {
            int offset = classType.TearOffOffset(presented);
            string slot = $"%tearoff{offset}";
            _module.AppendLine(
                $"  {slot} = getelementptr inbounds i8, ptr %object, i64 {offset}");
            _module.AppendLine(
                $"  store ptr @{ComVTableName(classType, presented)}, ptr {slot}");
            _module.AppendLine(
                $"  %owner{offset} = getelementptr inbounds i8, ptr {slot}, " +
                $"i64 {RuntimeLayout.TearOffOwner}");
            _module.AppendLine($"  store {Word} {offset}, ptr %owner{offset}");
        }

        // Events, for the reason InitializeEvents gives: an array is never
        // null, and an event is read by the first `+=` as much as by a raise.
        int slotIndex = 0;
        for (var current = classType; current is not null; current = current.BaseClass)
            foreach (var declared in current.Events)
            {
                if (declared.BackingField is not { } field) continue;
                if (field.Type is not ArrayTypeSymbol arrayType) continue;

                string empty = $"%event{slotIndex}";
                string address = $"%eventat{slotIndex}";
                slotIndex++;

                _module.AppendLine(
                    $"  {empty} = call ptr @sl_array_alloc(" +
                    $"ptr @{ArrayTypeInfoName(arrayType)}, {Word} 0, " +
                    $"{Word} {arrayType.Element.Size})");
                _module.AppendLine(
                    $"  {address} = getelementptr inbounds i8, ptr %object, " +
                    $"i64 {ClassTypeSymbol.HeaderSize + field.Offset}");
                _module.AppendLine($"  store ptr {empty}, ptr {address}");
            }

        if (constructor is not null)
            _module.AppendLine($"  call void {Symbol(constructor)}(ptr %object)");

        int first = classType.TearOffOffset(classType.ComInterfaces[0]);
        _module.AppendLine(
            $"  %result = getelementptr inbounds i8, ptr %object, i64 {first}");
        _module.AppendLine("  ret ptr %result");
        _module.AppendLine("}");
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
            return "ptr " + (required.VirtualSlot switch
            {
                0 => ComRuntimeSymbol("sl_com_object_query", 3),
                1 => ComRuntimeSymbol("sl_com_object_add_ref", 1),
                _ => ComRuntimeSymbol("sl_com_object_release", 1),
            });

        var found = classType.FindImplementation(required);
        if (found is null) return "ptr null";

        // Keyed by the table this slot is in. A derived interface inherits a
        // method's slot but has its own tear-off, so the two tables need two
        // thunks for the one method, subtracting two different distances.
        return $"ptr @{AdjustorName(classType, presented, required.VirtualSlot)}";
    }

    /// <summary>
    /// The runtime's IUnknown, as the linker will have it.
    ///
    /// These three sit in a COM vtable, so on x86 they are <c>__stdcall</c> like
    /// every other slot -- and Microsoft's decoration then makes the argument
    /// bytes part of the symbol, so <c>sl_com_object_add_ref</c> is linked as
    /// <c>_sl_com_object_add_ref@4</c>. The <c>\01</c> tells LLVM that is the
    /// whole name and not to add the target's underscore to one that has it.
    ///
    /// ELF decorates nothing, whatever the convention, so an x86 Linux build
    /// gets the convention and the plain name. This is the answer to whether a
    /// vtable's slot names carry byte counts: these three do, because they are
    /// C names, and no Stainless-linkage slot does -- a mangled name already
    /// states the parameters, and a slot is reached by address in any case.
    /// </summary>
    /// <param name="words">
    /// How many stack slots the arguments occupy, the receiver included. Every
    /// parameter of these three is one pointer.
    /// </param>
    private static string ComRuntimeSymbol(string name, int words)
    {
        var target = Binding.TargetPlatform.Current;

        if (target.Architecture != Binding.TargetArch.X86) return "@" + name;
        if (!target.IsWindows) return "@" + name;

        return $"@\"\\01_{name}@{words * target.PointerWidth}\"";
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

        // The thunk is what COM calls, so it carries the slot's convention --
        // read off the interface's own method rather than decided here, so a
        // thunk and the vtable it goes in cannot drift apart. The call below
        // keeps the target's, which on x86 is the default: a com class's
        // methods are reached from Stainless directly and from COM through
        // this.
        _module.AppendLine(
            $"define internal {Convention(required)}{returnType} " +
            $"@{name2}({string.Join(", ", declared)}) {{");
        _module.AppendLine(
            $"  %obj = getelementptr inbounds i8, ptr %self, i64 -{offset}");

        forwarded.Insert(returnInfo.Style == PassStyle.Indirect ? 1 : 0, "ptr %obj");
        string call =
            $"call {Convention(target)}{returnType} {Symbol(target)}" +
            $"({string.Join(", ", forwarded)})";

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
