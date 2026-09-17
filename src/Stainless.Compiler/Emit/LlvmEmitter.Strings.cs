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
/// String constants, and the interning that gives identical literals one
/// object with an immortal reference count.
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>
    /// The compiled resource script, as bytes the program carries.
    ///
    /// **Only where the binary format has nowhere else to put them.** A PE has
    /// a resource directory and the linker fills it from the same `.res`, so a
    /// Windows build reads the real thing and this emits nothing -- carrying
    /// both would be the same bytes twice. ELF has no such section, so the
    /// bytes ride in ordinary constant data and `Standard.Resources` walks
    /// them.
    ///
    /// Emitted even when empty, so that the symbol always resolves: a program
    /// that never asks for a resource still links, and one that does gets an
    /// empty answer rather than a missing symbol.
    /// </summary>
    private void ResourceBlob()
    {
        if (resourceBlob is null) return;

        // `Standard.Resources` declares these `extern "C"`, because from the
        // program's side they are storage defined elsewhere -- and "elsewhere"
        // turns out to be here. Recording the names keeps `StaticStorage` from
        // emitting an `external global` beside the definition, which LLVM reads
        // as a redefinition.
        _definedGlobals.Add("sl_resource_blob");
        _definedGlobals.Add("sl_resource_blob_size");

        _module.AppendLine();
        // In a section of its own, named after the one a PE keeps resources in.
        //
        // The symbol is what the *program* uses -- a section has no address a
        // program can ask for without reading its own ELF headers, which is
        // more fragility than it is worth. What the section buys is everything
        // outside the program: `readelf -x .rsrc` shows what a binary carries,
        // and `llvm-objcopy --dump-section .rsrc=out.res` gets the original
        // .res back out, so a resource editor or a translator's toolchain can
        // work on a Linux binary the way it would on a Windows one.
        //
        // The name is spelled the PE way deliberately. Mach-O would need
        // `__SEGMENT,__section` instead, and is not a target yet.
        _module.AppendLine(
            $"@sl_resource_blob = constant [{resourceBlob.Length} x i8] " +
            $"c\"{RawBytes(resourceBlob)}\", section \".rsrc\"");
        _module.AppendLine(
            $"@sl_resource_blob_size = constant i64 {resourceBlob.Length}");
    }

    private void StringConstants()
    {
        if (_byteConstants.Count == 0 && _stringObjects.Count == 0) return;

        _module.AppendLine();

        foreach (var (text, name) in _byteConstants)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            _module.AppendLine(
                $"{name} = private unnamed_addr constant " +
                $"[{bytes.Length + 1} x i8] c\"{EscapeBytes(bytes)}\"");
        }

        // A string literal is a complete String object in static storage, laid
        // out exactly as sl_string_new would build one on the heap. Its strong
        // count is the immortal sentinel, so retain and release skip it and the
        // literal costs no allocation and no reference traffic at run time.
        // Windows cannot put the address of an imported datum in a static
        // initializer -- it is not known until the loader has filled in the
        // import table -- so with a shared runtime the field is left null and
        // written once at startup, and the literal has to be writable to be
        // written to. Everywhere else the loader relocates it and the literal
        // stays where a constant belongs.
        bool bindAtStartup = sharedRuntime && OperatingSystem.IsWindows();

        string storage = bindAtStartup ? "private unnamed_addr global" : "private unnamed_addr constant";
        string typeField = bindAtStartup ? "ptr null" : "ptr @sl_string_type_info";

        foreach (var (text, name) in _stringObjects)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);

            // strong, weak, type, byteLength, then the bytes. The first four are
            // an SlObject and a size_t, so all four narrow together with the
            // target -- see RuntimeLayout.
            string layout = $"{{ {Word}, {Word}, ptr, {Word}, [{bytes.Length + 1} x i8] }}";

            _module.AppendLine(
                $"{name} = {storage} {layout} " +
                $"{{ {Word} {ImmortalRefCount}, {Word} {ImmortalRefCount}, {typeField}, " +
                $"{Word} {bytes.Length}, [{bytes.Length + 1} x i8] c\"{EscapeBytes(bytes)}\" }}, " +
                $"align {TargetPlatform.Current.PointerWidth}");
        }

        if (bindAtStartup && _stringObjects.Count > 0) BindLiteralsAtStartup();
    }

    /// <summary>
    /// Emits the startup pass that gives every string literal its type.
    ///
    /// It is registered in <c>llvm.global_ctors</c>, which both PE and ELF
    /// honour, so it runs before <c>main</c> in a program and on load in a
    /// library -- and before any static initializer, which may itself hold a
    /// literal. There is one table for every literal in the module and it runs
    /// once, so the cost is a store per literal at startup and nothing at all
    /// afterwards.
    /// </summary>
    private void BindLiteralsAtStartup()
    {
        const string name = "_SLbind_literals";

        _module.AppendLine();
        _module.AppendLine($"define internal void @{name}() {{");
        _module.AppendLine("entry:");

        int slot = 0;
        foreach (var (_, literal) in _stringObjects)
        {
            // The header's type field; see docs/abi.md.
            _module.AppendLine(
                $"  %{slot} = getelementptr inbounds i8, ptr {literal}, " +
                $"i64 {RuntimeLayout.TypeInfo}");
            _module.AppendLine($"  store ptr @sl_string_type_info, ptr %{slot}, align {TargetPlatform.Current.PointerWidth}");
            slot++;
        }

        _module.AppendLine("  ret void");
        _module.AppendLine("}");
        _module.AppendLine();

        // Priority 0: ahead of anything else that asked to run at startup.
        // The table itself is emitted once, at the end, because a module may
        // define `llvm.global_ctors` only once however many things want in.
        _startup.Add((0, name));
    }

    /// <summary>Matches SL_IMMORTAL in the runtime: a count that is never touched.</summary>
    private const string ImmortalRefCount = "-1";

    /// <summary>
    /// LLVM takes printable ASCII literally and everything else as \XX, with
    /// the quote and backslash always escaped. A trailing NUL is always added.
    /// </summary>
    private static string EscapeBytes(byte[] bytes) => RawBytes(bytes) + "\\00";

    /// <summary>
    /// The bytes as LLVM spells them, with nothing added.
    ///
    /// <see cref="EscapeBytes"/> terminates what it writes, because most callers
    /// are emitting a C string. The exceptions are a GUID and a compiled
    /// resource script: neither is text, and a resource blob is handed back out
    /// by `llvm-objcopy --dump-section`, so a byte nobody put there would make
    /// what comes out differ from what went in.
    /// </summary>
    private static string RawBytes(byte[] bytes)
    {
        var escaped = new StringBuilder();
        foreach (byte b in bytes)
        {
            if (b is >= 0x20 and < 0x7F && b != (byte)'"' && b != (byte)'\\')
                escaped.Append((char)b);
            else
                escaped.Append('\\').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return escaped.ToString();
    }

    /// <summary>A bare NUL-terminated byte array, for C strings and TypeInfo names.</summary>
    private string InternBytes(string text)
    {
        if (_byteConstants.TryGetValue(text, out var existing)) return existing;
        string name = $"@.bytes.{_byteConstants.Count}";
        _byteConstants[text] = name;
        return name;
    }

    /// <summary>
    /// <c>$"a {b} c"</c>: every piece into a stack array, then one call.
    ///
    /// One allocation for the result and none for anything in between, which
    /// is the whole point of the node existing -- the chain of <c>+</c> this
    /// replaces allocated a String per operator and discarded all but the
    /// last. The array is an <c>alloca</c>, so the parts themselves cost
    /// nothing either.
    /// </summary>
    private Val EmitInterpolatedString(BoundInterpolatedString expression)
    {
        int count = expression.Parts.Count;

        // Nothing to join. The binder folds an all-literal interpolation to a
        // literal, so this is only the empty `$""`.
        if (count == 0)
            return new Val(InternStringObject(""), "ptr", expression.Type);

        string slots = Emit("ptr", $"alloca [{count} x ptr], align {TargetPlatform.Current.PointerWidth}");

        for (int i = 0; i < count; i++)
        {
            var part = EmitExpression(expression.Parts[i]);
            string at = Emit("ptr",
                $"getelementptr inbounds [{count} x ptr], ptr {slots}, i64 0, i64 {i}");
            Line($"store ptr {part.Ref}, ptr {at}");
        }

        string joined = Emit("ptr", $"call ptr @sl_string_join(ptr {slots}, {Word} {count})");
        TrackTemporary(joined, expression.Type);
        return new Val(joined, "ptr", expression.Type);
    }

    /// <summary>A static String object that a String-typed expression can refer to.</summary>
    private string InternStringObject(string text)
    {
        if (_stringObjects.TryGetValue(text, out var existing)) return existing;
        string name = $"@.strobj.{_stringObjects.Count}";
        _stringObjects[text] = name;
        return name;
    }
}
