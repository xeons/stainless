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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// The types and functions the compiler provides itself, arranged as ordinary
/// modules so that name resolution, visibility and overloading need no special
/// cases.
///
/// Most of their bodies are C, in runtime/, declared with C linkage and a fixed
/// runtime symbol: a call to <c>text.ByteLength()</c> lowers to exactly
/// <c>call @sl_string_byte_length(ptr)</c> and nothing more.
///
/// <para>
/// The rest are Stainless, in stdlib/, and this class only finds them — see
/// <see cref="Found"/>. A built-in moves that way when nothing about it needs
/// the compiler: what is left behind is the name, not the code.
/// </para>
/// </summary>
public sealed class Builtins
{
    public const string TextModuleName = "Standard.Text";

    /// <summary>
    /// Where <c>Guid</c> and <c>IUnknown</c> live.
    ///
    /// Not auto-imported: a program that never says <c>com</c> should not have
    /// two more names in scope, and one that does is already writing an import
    /// for the bindings it is calling.
    /// </summary>
    public const string ComModuleName = "Standard.Com";

    /// <summary>
    /// Markers the language itself understands, rather than a library feature
    /// to opt into. It is auto-imported, because needing an import to say
    /// <c>[Flags]</c> would make a rule about enums look like a dependency.
    /// </summary>
    public const string StandardModuleName = "Standard";

    public ModuleSymbol Text { get; }
    public ModuleSymbol Standard { get; }
    public ModuleSymbol Com { get; }

    /// <summary>
    /// <c>Guid</c>: 16 bytes, laid out as every existing COM header lays one
    /// out, so a <c>Guid*</c> passed to a C function is the <c>GUID*</c> it
    /// expects.
    /// </summary>
    public StructTypeSymbol Guid { get; }

    /// <summary>
    /// <c>IUnknown</c>: the root of every com interface, and the reason ARC can
    /// drive COM at all.
    ///
    /// Its three methods occupy slots 0, 1 and 2 of every COM vtable there has
    /// ever been. A com interface that names no base extends this one, so those
    /// slots are always where they are and <c>sl_com_retain</c> can call the
    /// second without knowing anything else about the object.
    /// </summary>
    public ComInterfaceTypeSymbol Unknown { get; }

    /// <summary>
    /// <c>[Flags]</c>: the enum is a set of bits rather than a choice among
    /// alternatives, which is what makes <c>|</c>, <c>&amp;</c>, <c>^</c> and
    /// <c>~</c> meaningful on it.
    /// </summary>
    public AttributeTypeSymbol Flags { get; }

    /// <summary>
    /// <c>[Packed]</c>: lay this type out with no padding at all, and give it an
    /// alignment of one. It is a rule about layout rather than a library
    /// feature, so it needs no import, exactly as <c>[Flags]</c> does not.
    /// </summary>
    public AttributeTypeSymbol Packed { get; }

    /// <summary>
    /// <c>[Align(N)]</c>: give this type an alignment of at least N. It raises
    /// and never lowers, the way C's <c>alignas</c> does.
    /// </summary>
    public AttributeTypeSymbol Align { get; }

    /// <summary>
    /// <c>[Embed("logo.png", Section = ".logo", Access = "r")]</c>: the static
    /// this is written on holds that file's bytes, placed by the linker.
    ///
    /// A marker the compiler acts on rather than a library type, so it needs no
    /// import — and being one of the compiler's own is what keeps a program's
    /// own <c>attribute Embed</c> from being mistaken for it, since the check is
    /// against this symbol and not against the name.
    /// </summary>
    public AttributeTypeSymbol Embed { get; }

    /// <summary>The static type of a closure's receiver; see where it is made.</summary>
    public ClassTypeSymbol Bound { get; }

    public ClassTypeSymbol String { get; }
    public ClassTypeSymbol Utf16String { get; }
    public ClassTypeSymbol StringBuilder { get; }

    public FunctionSymbol StringConcat { get; }

    /// <summary>
    /// The conversions an interpolated string reaches for. Named rather than
    /// looked up, because overload resolution would have to pick between the
    /// signed and unsigned versions of FromInteger and the binder already
    /// knows which it means.
    /// </summary>
    public FunctionSymbol TextFromLong { get; }
    public FunctionSymbol TextFromULong { get; }
    public FunctionSymbol TextFromBool { get; }
    public FunctionSymbol TextFromChar { get; }
    public FunctionSymbol TextFromDouble { get; }
    public FunctionSymbol StringEquals { get; }

    /// <summary>
    /// Ordering and hashing for the types that cannot implement an interface.
    ///
    /// A primitive is not a class, so <c>int</c> cannot be declared to
    /// implement <c>IComparable&lt;int&gt;</c>. The binder recognises
    /// <c>CompareTo</c> and <c>HashCode</c> on one anyway and lowers each to
    /// one of these, which is what lets <c>Sort(numbers)</c> work on a
    /// <c>List&lt;int&gt;</c> without the language growing operator constraints.
    ///
    /// <para>
    /// <b>These seven are found rather than declared.</b> Their bodies are
    /// Stainless, in <c>stdlib/Standard.sl</c>, and what is here is a lookup by
    /// name and signature run the first time the binder needs one -- which is
    /// during body binding, long after the standard library's own names were
    /// declared. Nothing else is required to move a built-in into the language:
    /// the call the binder builds is an ordinary call to an ordinary function.
    /// </para>
    /// </summary>
    public FunctionSymbol CompareLong => Found(ref _compareLong, "CompareLong",
        PrimitiveTypeSymbol.Int, PrimitiveTypeSymbol.Long, PrimitiveTypeSymbol.Long);

    public FunctionSymbol CompareULong => Found(ref _compareULong, "CompareULong",
        PrimitiveTypeSymbol.Int, PrimitiveTypeSymbol.ULong, PrimitiveTypeSymbol.ULong);

    public FunctionSymbol CompareDouble => Found(ref _compareDouble, "CompareDouble",
        PrimitiveTypeSymbol.Int, PrimitiveTypeSymbol.Double, PrimitiveTypeSymbol.Double);

    public FunctionSymbol CompareText => Found(ref _compareText, "CompareText",
        PrimitiveTypeSymbol.Int, String, String);

    public FunctionSymbol HashInteger => Found(ref _hashInteger, "HashInteger",
        PrimitiveTypeSymbol.NUInt, PrimitiveTypeSymbol.ULong);

    public FunctionSymbol HashDouble => Found(ref _hashDouble, "HashDouble",
        PrimitiveTypeSymbol.NUInt, PrimitiveTypeSymbol.Double);

    public FunctionSymbol HashText => Found(ref _hashText, "HashText",
        PrimitiveTypeSymbol.NUInt, String);

    private FunctionSymbol? _compareLong;
    private FunctionSymbol? _compareULong;
    private FunctionSymbol? _compareDouble;
    private FunctionSymbol? _compareText;
    private FunctionSymbol? _hashInteger;
    private FunctionSymbol? _hashDouble;
    private FunctionSymbol? _hashText;

    private static readonly SourceText BuiltinSource = new("<builtin>", "");
    private static readonly SourceSpan BuiltinSpan = new(BuiltinSource, 0, 0);

    private static readonly PointerTypeSymbol BytePointer = new(PrimitiveTypeSymbol.Byte);
    /// <summary>
    /// <c>char16*</c>: what a wide platform API takes and writes into.
    ///
    /// It was <c>ushort*</c> until char16 existed, which said the width and not
    /// what the units were, and so accepted any 16-bit pointer that happened to
    /// be in reach.
    /// </summary>
    private static readonly PointerTypeSymbol Char16Pointer = new(PrimitiveTypeSymbol.Char16);

    public Builtins()
    {
        Text = new ModuleSymbol(TextModuleName);
        Standard = new ModuleSymbol(StandardModuleName);
        Com = new ModuleSymbol(ComModuleName);

        Flags = new AttributeTypeSymbol
        {
            SimpleName = "Flags",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Flags.SetLayout(0, 1);
        Standard.Types[Flags.SimpleName] = Flags;

        Packed = new AttributeTypeSymbol
        {
            SimpleName = "Packed",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Packed.SetLayout(0, 1);
        Standard.Types[Packed.SimpleName] = Packed;

        Align = new AttributeTypeSymbol
        {
            SimpleName = "Align",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Align.Fields.Add(new FieldSymbol("Bytes", PrimitiveTypeSymbol.Int, Align, 0)
        {
            IsPublic = true,
        });
        Align.SetLayout(4, 4);
        Standard.Types[Align.SimpleName] = Align;

        // The static type of a closure's receiver, and nothing else.
        //
        // A closure holds whatever object its method belongs to, and reference
        // counting does not care which class that is: sl_release finds the type
        // in the object's own header. So the field needs *a* strong reference
        // type rather than the right one, and this is it -- never instantiated,
        // never given a TypeInfo, and not public, so no program can name it.
        Bound = new ClassTypeSymbol
        {
            SimpleName = "$bound",
            ModuleName = StandardModuleName,
            IsPublic = false,
            IsIntrinsic = true,
        };
        Bound.SetLayout(0, TargetPlatform.Current.PointerWidth);

        String = new ClassTypeSymbol
        {
            SimpleName = "String",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
        };
        String.SetLayout(0, TargetPlatform.Current.PointerWidth);

        Utf16String = new ClassTypeSymbol
        {
            SimpleName = "Utf16String",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
        };
        Utf16String.SetLayout(0, TargetPlatform.Current.PointerWidth);

        // Mutable text. Its bytes are a separate growable allocation, so `new`
        // goes through a runtime factory rather than the usual sl_alloc.
        StringBuilder = new ClassTypeSymbol
        {
            SimpleName = "StringBuilder",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
            RuntimeFactory = "sl_string_builder_new",
        };
        StringBuilder.SetLayout(0, TargetPlatform.Current.PointerWidth);

        Text.Types[String.SimpleName] = String;
        Text.Types[Utf16String.SimpleName] = Utf16String;
        Text.Types[StringBuilder.SimpleName] = StringBuilder;

        // Declared after String, because its three fields are Strings. It is
        // never laid out -- nothing makes one -- but a size is what every other
        // attribute type has, and one pointer per field is what this would be.
        Embed = new AttributeTypeSymbol
        {
            SimpleName = "Embed",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };

        int word = TargetPlatform.Current.PointerWidth;
        foreach (string field in new[] { "Path", "Section", "Access" })
            Embed.Fields.Add(
                new FieldSymbol(field, String, Embed, Embed.Fields.Count * word)
                {
                    IsPublic = true,
                });

        Embed.SetLayout(3 * word, word);
        Standard.Types[Embed.SimpleName] = Embed;

        // --- String methods ------------------------------------------------
        Method(String, "ByteLength", PrimitiveTypeSymbol.NUInt, "sl_string_byte_length");
        Method(String, "CodePointCount", PrimitiveTypeSymbol.NUInt, "sl_string_code_point_count");
        Property(String, "IsEmpty", PrimitiveTypeSymbol.Bool, "sl_string_is_empty");
        Method(String, "ToPointer", BytePointer, "sl_string_pointer");
        Method(String, "ToUtf16", Utf16String, "sl_string_to_utf16");
        Method(String, "Substring", String, "sl_string_substring",
            ("start", PrimitiveTypeSymbol.NUInt), ("length", PrimitiveTypeSymbol.NUInt));

        // --- Utf16String methods -------------------------------------------
        Method(Utf16String, "UnitCount", PrimitiveTypeSymbol.NUInt, "sl_utf16_unit_count");
        Method(Utf16String, "ToPointer", Char16Pointer, "sl_utf16_pointer");
        Method(Utf16String, "ToText", String, "sl_utf16_to_string");

        // --- StringBuilder methods ------------------------------------------
        Method(StringBuilder, "Append", PrimitiveTypeSymbol.Void, "sl_string_builder_append",
            ("text", String));
        Method(StringBuilder, "AppendLine", PrimitiveTypeSymbol.Void, "sl_string_builder_append_line",
            ("text", String));
        Method(StringBuilder, "AppendInteger", PrimitiveTypeSymbol.Void,
            "sl_string_builder_append_integer", ("value", PrimitiveTypeSymbol.Long));
        Method(StringBuilder, "AppendDouble", PrimitiveTypeSymbol.Void,
            "sl_string_builder_append_double", ("value", PrimitiveTypeSymbol.Double));

        // One byte. A scanner appending what it just looked at had to build a
        // one-element array to call AppendBytes with. A whole code point was
        // already `AppendCodePoint`, in Text.sl.
        Method(StringBuilder, "AppendByte", PrimitiveTypeSymbol.Void,
            "sl_string_builder_append_byte", ("value", PrimitiveTypeSymbol.Byte));
        Method(StringBuilder, "ByteLength", PrimitiveTypeSymbol.NUInt,
            "sl_string_builder_byte_length");
        Property(StringBuilder, "IsEmpty", PrimitiveTypeSymbol.Bool, "sl_string_builder_is_empty");
        Method(StringBuilder, "Clear", PrimitiveTypeSymbol.Void, "sl_string_builder_clear");

        // Reading and editing what is already there. A builder's bytes move as
        // it grows, so there is no pointer to hand out the way String has one:
        // these go through the runtime one byte at a time, and the rest of the
        // API is built on them in stdlib/Text.sl.
        Method(StringBuilder, "ByteAt", PrimitiveTypeSymbol.Byte, "sl_string_builder_byte_at",
            ("index", PrimitiveTypeSymbol.NUInt));
        Method(StringBuilder, "SetByteAt", PrimitiveTypeSymbol.Void,
            "sl_string_builder_set_byte_at",
            ("index", PrimitiveTypeSymbol.NUInt), ("value", PrimitiveTypeSymbol.Byte));
        Method(StringBuilder, "Insert", PrimitiveTypeSymbol.Void, "sl_string_builder_insert",
            ("at", PrimitiveTypeSymbol.NUInt), ("text", String));
        Method(StringBuilder, "Remove", PrimitiveTypeSymbol.Void, "sl_string_builder_remove",
            ("at", PrimitiveTypeSymbol.NUInt), ("count", PrimitiveTypeSymbol.NUInt));

        Method(StringBuilder, "ToText", String, "sl_string_builder_to_string");

        // --- Standard.Com ----------------------------------------------------
        //
        // Guid is a plain struct with C's layout: a 32-bit field, two 16-bit
        // ones and eight bytes, which is what every COM header and every
        // registry entry agrees a GUID is.
        Guid = new StructTypeSymbol
        {
            SimpleName = "Guid",
            ModuleName = ComModuleName,
            IsPublic = true,
        };
        // The last argument is the field's *index*, and the offset is set after
        // it: this type is built by hand rather than bound from source, so
        // nothing else fills either in. The two are not the same number past the
        // first field, and a `Guid` laid out as though they were reaches one
        // member off.
        Guid.Fields.Add(new FieldSymbol("Data1", PrimitiveTypeSymbol.UInt, Guid, 0)
            { IsPublic = true, Offset = 0 });
        Guid.Fields.Add(new FieldSymbol("Data2", PrimitiveTypeSymbol.UShort, Guid, 1)
            { IsPublic = true, Offset = 4 });
        Guid.Fields.Add(new FieldSymbol("Data3", PrimitiveTypeSymbol.UShort, Guid, 2)
            { IsPublic = true, Offset = 6 });
        Guid.Fields.Add(new FieldSymbol(
            "Data4", new FixedArrayTypeSymbol(PrimitiveTypeSymbol.Byte, 8), Guid, 3)
            { IsPublic = true, Offset = 8 });
        Guid.SetLayout(16, 4);
        Com.Types[Guid.SimpleName] = Guid;

        // IUnknown, whose three methods are slots 0, 1 and 2 of every COM
        // vtable. They are declared here rather than in source because the
        // compiler emits calls to the last two itself, at every place ARC
        // touches a COM reference.
        Unknown = new ComInterfaceTypeSymbol
        {
            SimpleName = "IUnknown",
            ModuleName = ComModuleName,
            IsPublic = true,
        };
        Com.Types[Unknown.SimpleName] = Unknown;

        // The IID is fixed, and has been since 1993.
        Unknown.Iid = new System.Guid("00000000-0000-0000-C000-000000000046");

        var guidPointer = new PointerTypeSymbol(Guid);
        var bytePointerPointer = new PointerTypeSymbol(BytePointer);

        ComMethod(Unknown, 0, "QueryInterface", PrimitiveTypeSymbol.Int,
            ("iid", guidPointer), ("result", bytePointerPointer));

        // AddRef and Release are declared so the slots exist and are not
        // public, because ARC owns the count. Calling one by hand would put
        // the compiler's bookkeeping and the object's out of step, and there
        // is nothing a program can do with the result that ARC has not done.
        ComMethod(Unknown, 1, "AddRef", PrimitiveTypeSymbol.UInt, isPublic: false);
        ComMethod(Unknown, 2, "Release", PrimitiveTypeSymbol.UInt, isPublic: false);

        // --- Standard.Com results ---------------------------------------------
        //
        // The HRESULTs a com method actually returns, named rather than spelled
        // as hex at every site. Negative is failure, which is the whole of the
        // convention; these are the handful the language's own machinery uses
        // or hands back, not a transcription of winerror.h.
        Constant(Com, "Ok", PrimitiveTypeSymbol.Int, 0);
        Constant(Com, "False", PrimitiveTypeSymbol.Int, 1);
        Constant(Com, "NoInterface", PrimitiveTypeSymbol.Int, unchecked((int)0x80004002));
        Constant(Com, "PointerError", PrimitiveTypeSymbol.Int, unchecked((int)0x80004003));
        Constant(Com, "OutOfMemory", PrimitiveTypeSymbol.Int, unchecked((int)0x8007000E));
        Constant(Com, "InvalidArgument", PrimitiveTypeSymbol.Int, unchecked((int)0x80070057));
        Constant(Com, "NoAggregation", PrimitiveTypeSymbol.Int, unchecked((int)0x80040110));
        Constant(Com, "ClassNotAvailable", PrimitiveTypeSymbol.Int, unchecked((int)0x80040111));

        // --- Standard.Com activation -----------------------------------------
        //
        // What an in-process COM server exports DllGetClassObject to answer.
        // The runtime function takes the compiler's factory table first; this
        // binds to a shim the emitter writes into the module, which supplies
        // it. So the source writes three arguments and the table stays a thing
        // the program has rather than a symbol it has to name.
        Function(Com, "GetClassObject", PrimitiveTypeSymbol.Int,
            "sl_com_class_object_here",
            ("clsid", guidPointer), ("iid", guidPointer), ("result", bytePointerPointer));

        // S_OK when nothing this module made is still held. Like GetClassObject
        // it goes through a shim that supplies the table, which is what carries
        // the count.
        Function(Com, "CanUnloadNow", PrimitiveTypeSymbol.Int, "sl_com_can_unload_here");

        // --- Standard.Text free functions -----------------------------------
        TextFromLong = Function(Text, "FromInteger", String, "sl_string_from_integer",
            ("value", PrimitiveTypeSymbol.Long));
        // A separate runtime entry point rather than the signed one: a `ulong`
        // past 2^63 formatted through "%lld" prints as a negative number.
        TextFromULong = Function(Text, "FromInteger", String, "sl_string_from_unsigned",
            ("value", PrimitiveTypeSymbol.ULong));

        // And one for `nuint`, which is a `size_t` in C and so cannot share the
        // `unsigned long long` entry point: this was once the only unsigned
        // overload, declared as taking a `nuint` and bound to the 64-bit
        // function, and on a 32-bit target the runtime read four bytes of
        // argument and four of whatever was next on the stack. `$"{n}"` printed
        // 8612659968337772549 for 5. It stays an overload of its own rather than
        // leaving a `nuint` to widen, so that the call a `nuint` makes is to an
        // entry point declared with its own width on every target.
        Function(Text, "FromInteger", String, "sl_string_from_size",
            ("value", PrimitiveTypeSymbol.NUInt));
        TextFromBool = Function(Text, "FromBool", String, "sl_string_from_bool",
            ("value", PrimitiveTypeSymbol.Bool));

        // A code point as the character it names, not as its number. `Text.
        // FromInteger((long)c)` is how to ask for the number.
        TextFromChar = Function(Text, "FromChar", String, "sl_string_from_char",
            ("value", PrimitiveTypeSymbol.Char32));
        TextFromDouble = Function(Text, "FromDouble", String, "sl_string_from_double",
            ("value", PrimitiveTypeSymbol.Double));
        Function(Text, "FromBytes", String, "sl_string_from_bytes",
            ("data", BytePointer), ("byteLength", PrimitiveTypeSymbol.NUInt));
        Function(Text, "FromNullTerminated", String, "sl_string_from_null_terminated",
            ("text", BytePointer));

        // The way back from a platform that speaks UTF-16. A wide API writes into
        // a buffer the caller owns, so what comes back is a pointer and a length
        // rather than a Utf16String, and the pair is what these two take.
        Function(Text, "FromUtf16", String, "sl_string_from_utf16",
            ("units", Char16Pointer), ("unitCount", PrimitiveTypeSymbol.NUInt));
        Function(Text, "FromNullTerminatedUtf16", String,
            "sl_string_from_null_terminated_utf16", ("units", Char16Pointer));

        // Operators. These are resolved by the binder, not written by hand.
        StringConcat = Function(Text, "Concat", String, "sl_string_concat",
            ("left", String), ("right", String));
        StringEquals = Function(Text, "Equals", PrimitiveTypeSymbol.Bool, "sl_string_equals",
            ("left", String), ("right", String));

    }

    public bool IsString(TypeSymbol type) => ReferenceEquals(type, String);

    /// <summary>Registers the built-in modules so imports and lookups can find them.</summary>
    public void RegisterInto(Dictionary<string, ModuleSymbol> modules)
    {
        modules[Text.Name] = Text;
        modules[Standard.Name] = Standard;
        modules[Com.Name] = Com;
    }

    /// <summary>
    /// Standard.Text is visible in every file without an import, because string
    /// literals produce a <c>String</c> whether the program asked for one or not.
    /// </summary>
    public void AutoImportInto(FileScope scope)
    {
        if (scope.Module == Text) return;
        scope.Imports[TextModuleName] = Text;
        scope.Imports["Text"] = Text;
        scope.Imports[StandardModuleName] = Standard;
    }

    private FunctionSymbol Method(
        ClassTypeSymbol owner,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        params (string Name, TypeSymbol Type)[] parameters)
    {
        var symbol = Declare(Text, name, returnType, runtimeSymbol, owner, parameters);
        owner.Methods.Add(symbol);
        return symbol;
    }

    /// <summary>
    /// A built-in member that reads as a property rather than a call:
    /// <c>text.IsEmpty</c>, not <c>text.IsEmpty()</c>.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The getter is an ordinary runtime function and the <see cref="PropertySymbol"/>
    /// is what member lookup finds, so nothing in the binder or the emitter
    /// needed a special case -- <c>FindProperty</c> already searches any named
    /// type's <c>Properties</c>, and a built-in class is one.
    /// </para>
    /// <para>
    /// <b>The getter is deliberately not added to <c>owner.Methods</c>.</b>
    /// Leaving it there would make both spellings work, and two spellings of one
    /// member is exactly how a codebase ends up using the wrong one everywhere.
    /// </para>
    /// <para>
    /// This is what <c>docs/style.md</c> §2.1 was waiting for: <c>IsEmpty</c>
    /// was the one question in that section still answered by a method, and only
    /// because <c>String</c> and <c>StringBuilder</c> get theirs from here.
    /// </para>
    /// </remarks>
    private PropertySymbol Property(
        ClassTypeSymbol owner, string name, TypeSymbol type, string runtimeSymbol)
    {
        var getter = Declare(Text, "get_" + name, type, runtimeSymbol, owner, []);

        var property = new PropertySymbol
        {
            Name = name,
            Type = type,
            ContainingType = owner,
            Span = BuiltinSpan,
            IsPublic = true,
            Getter = getter,
        };

        owner.Properties.Add(property);
        return property;
    }

    /// <summary>
    /// The standard library's declaration of a function the compiler calls for
    /// itself, resolved by name and signature on first use and then kept.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The signature is matched rather than assumed, so that an overload added
    /// beside one of these later cannot silently take its place.
    /// </para>
    /// <para>
    /// The throw is an assertion about the compiler and not a diagnostic about
    /// the program. <c>stdlib/</c> is an embedded resource inside this binary,
    /// so a declaration that is missing or reshaped means the compiler itself
    /// was built wrong, and every compilation it goes on to perform is wrong
    /// too. There is nothing a program could write to reach it.
    /// </para>
    /// </remarks>
    private FunctionSymbol Found(
        ref FunctionSymbol? kept,
        string name,
        TypeSymbol returnType,
        params TypeSymbol[] parameters)
    {
        if (kept is not null) return kept;

        foreach (var candidate in Standard.FindFunctions(name))
        {
            if (!candidate.ReturnType.Equals(returnType)) continue;
            if (candidate.Parameters.Count != parameters.Length) continue;

            bool matched = true;
            for (int i = 0; i < parameters.Length && matched; i++)
                matched = candidate.Parameters[i].Type.Equals(parameters[i]);

            if (matched) return kept = candidate;
        }

        throw new InvalidOperationException(
            $"the embedded standard library does not declare {StandardModuleName}.{name}(" +
            string.Join(", ", parameters.Select(p => p.Name)) + ")");
    }

    /// <summary>
    /// One method of a built-in com interface, at a fixed vtable slot.
    ///
    /// It has no runtime symbol: the call goes through the object's vtable, and
    /// which body it reaches is the object's business rather than ours.
    /// </summary>
    private static FunctionSymbol ComMethod(
        ComInterfaceTypeSymbol owner,
        int slot,
        string name,
        TypeSymbol returnType,
        params (string Name, TypeSymbol Type)[] parameters) =>
        ComMethod(owner, slot, name, returnType, true, parameters);

    private static FunctionSymbol ComMethod(
        ComInterfaceTypeSymbol owner,
        int slot,
        string name,
        TypeSymbol returnType,
        bool isPublic,
        params (string Name, TypeSymbol Type)[] parameters)
    {
        var symbol = new FunctionSymbol
        {
            Name = name,
            ModuleName = owner.ModuleName,
            ReturnType = returnType,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = owner,
            IsPublic = isPublic,
            IsVirtual = true,
            Span = BuiltinSpan,
            VirtualSlot = slot,

            // IUnknown's three are com interface methods like any others, and
            // on x86 that means __stdcall. They are built here rather than
            // bound from source, so the rule has to be repeated once.
            CallingConvention = TargetPlatform.Current.HasCallingConventions
                ? Syntax.CallingConvention.Stdcall
                : Syntax.CallingConvention.Default,
        };

        symbol.Parameters.Add(new ParameterSymbol("this", owner, 0) { IsThis = true });
        foreach (var (parameterName, parameterType) in parameters)
            symbol.Parameters.Add(
                new ParameterSymbol(parameterName, parameterType, symbol.Parameters.Count));

        owner.Methods.Add(symbol);
        owner.VirtualTable.Add(symbol);
        return symbol;
    }

    private FunctionSymbol Function(
        ModuleSymbol module,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        params (string Name, TypeSymbol Type)[] parameters) =>
        Declare(module, name, returnType, runtimeSymbol, containingType: null, parameters);

    /// <summary>A public constant of a built-in module.</summary>
    private static void Constant(ModuleSymbol module, string name, TypeSymbol type, object value) =>
        module.Constants[name] = new ConstantSymbol(name, type, value) { IsPublic = true };

    private static FunctionSymbol Declare(
        ModuleSymbol module,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        NamedTypeSymbol? containingType,
        (string Name, TypeSymbol Type)[] parameters,
        bool isPublic = true)
    {
        var symbol = new FunctionSymbol
        {
            Name = name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = LinkageKind.ExternC,
            RuntimeSymbol = runtimeSymbol,
            Kind = containingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = containingType,
            IsPublic = isPublic,
            Span = BuiltinSpan,
        };

        if (containingType is not null)
            symbol.Parameters.Add(new ParameterSymbol("this", containingType, 0) { IsThis = true });

        foreach (var (parameterName, parameterType) in parameters)
            symbol.Parameters.Add(
                new ParameterSymbol(parameterName, parameterType, symbol.Parameters.Count));

        module.Functions.Add(symbol);
        return symbol;
    }
}
