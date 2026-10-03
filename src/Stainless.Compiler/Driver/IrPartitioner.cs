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

using System.Text;

namespace Stainless.Driver;

/// <summary>
/// Splits one emitted module into several that compile at once and link to the
/// same program.
///
/// <para>
/// clang optimizes and lowers a module on one thread, and most of a large
/// build is that. The parts are textual: the emitter's output is a flat list of
/// definitions, so this reads it as one rather than parsing LLVM's grammar.
/// </para>
///
/// <list type="bullet">
/// <item>Functions are dealt out in runs of about equal size, in the order they
/// were emitted, so code from one module mostly stays together.</item>
/// <item>A constant without an address of its own -- a string's bytes -- is
/// copied into every part that reads it.</item>
/// <item>Anything else lives in one part. Reached from another, it is promoted
/// from <c>internal</c> to <c>hidden</c> and declared where it is used, which
/// keeps it out of a library's exports.</item>
/// <item>A small function reached from another part is also copied there as
/// <c>available_externally</c>, so it can still be inlined across the
/// split.</item>
/// </list>
///
/// The input MUST carry no debug information and no <c>asm</c> block of the
/// program's own: neither survives being divided.
/// </summary>
public static class IrPartitioner
{
    /// <summary>The longest body, in lines, copied into another part for inlining.</summary>
    private const int InlinableLines = 16;

    private enum EntityKind
    {
        /// <summary>Copied into every part: types, declarations, the target.</summary>
        Shared,

        /// <summary>Only in the first part: module-level assembly.</summary>
        Pinned,

        Function,
        Global,
    }

    private sealed class Entity
    {
        public required EntityKind Kind { get; init; }
        public required string Text { get; init; }
        public string Name { get; init; } = "";
        public List<string> References { get; init; } = [];

        /// <summary>A constant whose address nothing compares, so each part may hold a copy.</summary>
        public bool IsCopyable { get; set; }

        public bool IsInlinable { get; set; }
        public int Part { get; set; } = -1;
    }

    /// <summary>
    /// The module as up to <paramref name="mostParts"/> modules, one for each
    /// <paramref name="bytesPerPart"/> of the IR that is reachable -- exactly
    /// <paramref name="mostParts"/> when that is zero. A module too small to
    /// divide comes back as itself.
    /// </summary>
    public static IReadOnlyList<string> Split(string ir, int mostParts, long bytesPerPart)
    {
        var entities = ReadEntities(ir);

        var defined = new Dictionary<string, Entity>(StringComparer.Ordinal);
        foreach (var entity in entities)
            if (entity.Kind is EntityKind.Function or EntityKind.Global)
                defined[entity.Name] = entity;

        entities = DropUnreachable(entities, defined);
        var functions = entities.Where(e => e.Kind == EntityKind.Function).ToList();
        long live = functions.Sum(f => (long)f.Text.Length);
        int parts = bytesPerPart <= 0
            ? mostParts
            : (int)Math.Clamp(live / bytesPerPart, 1, Math.Max(1, mostParts));
        if (parts < 2 || functions.Count < parts)
            return [ir];

        DealFunctions(functions, parts);
        KeepBesideAssembly(entities);
        PlaceGlobals(entities, functions, defined);

        // What each part reaches that another part defines, and the copies it
        // takes of constants and of small functions.
        var reached = new HashSet<string>[parts];
        var copies = new List<Entity>[parts];
        var promoted = new HashSet<string>(StringComparer.Ordinal);
        for (int part = 0; part < parts; part++)
        {
            reached[part] = new HashSet<string>(StringComparer.Ordinal);
            copies[part] = [];
            CollectReached(entities, part, defined, reached[part], copies[part]);
            foreach (string name in reached[part])
                promoted.Add(name);
        }

        var result = new List<string>(parts);
        for (int part = 0; part < parts; part++)
            result.Add(WritePart(entities, part, reached[part], copies[part], promoted, defined));
        return result;
    }

    /// <summary>
    /// The module less every internal definition nothing reaches. One module
    /// loses them to LLVM in its first pass; divided, a definition one part
    /// names must be kept visible to it, and would be compiled for nothing.
    /// The roots are what the linker or the loader can see: definitions that
    /// are not internal, the appending arrays, and whatever the shared lines
    /// and the assembly name.
    /// </summary>
    private static List<Entity> DropUnreachable(List<Entity> entities, Dictionary<string, Entity> defined)
    {
        var live = new HashSet<Entity>();
        var pending = new Stack<Entity>();
        foreach (var entity in entities)
        {
            bool root = entity.Kind is EntityKind.Shared or EntityKind.Pinned ||
                        Linkage(entity.Text) is not ("internal" or "private");
            if (root && live.Add(entity))
                pending.Push(entity);
        }

        while (pending.Count > 0)
            foreach (string name in pending.Pop().References)
                if (defined.TryGetValue(name, out var target) && live.Add(target))
                    pending.Push(target);

        foreach (var entity in entities)
            if (!live.Contains(entity))
                defined.Remove(entity.Name);
        return entities.Where(live.Contains).ToList();
    }

    /// <summary>Contiguous runs of functions, each about a <paramref name="parts"/>th of the text.</summary>
    private static void DealFunctions(List<Entity> functions, int parts)
    {
        long total = functions.Sum(f => (long)f.Text.Length);
        long target = total / parts + 1;
        int part = 0;
        long filled = 0;
        foreach (var function in functions)
        {
            if (filled >= target && part < parts - 1)
            {
                part++;
                filled = 0;
            }
            function.Part = part;
            filled += function.Text.Length;
        }
    }

    /// <summary>
    /// What names a label module-level assembly defines goes in the first part,
    /// with the assembly. The label is local to the object it is assembled
    /// into, so no other part could reach it.
    /// </summary>
    private static void KeepBesideAssembly(List<Entity> entities)
    {
        var labels = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entity in entities)
        {
            if (entity.Kind != EntityKind.Pinned)
                continue;
            string line = entity.Text.TrimEnd();
            if (!line.EndsWith(":\"", StringComparison.Ordinal))
                continue;
            string label = line["module asm \"".Length..^2];
            labels.Add(label);
            labels.Add("\"\\01" + label + "\"");
        }
        if (labels.Count == 0)
            return;

        foreach (var entity in entities)
        {
            if (entity.Kind is not (EntityKind.Function or EntityKind.Global) ||
                !entity.References.Any(labels.Contains))
                continue;
            entity.Part = 0;
            entity.IsCopyable = false;
            entity.IsInlinable = false;
        }
    }

    /// <summary>
    /// Each global that cannot be copied goes with the first function to name
    /// it; one nothing names, and the appending arrays, go in the first part.
    /// </summary>
    private static void PlaceGlobals(
        List<Entity> entities, List<Entity> functions, Dictionary<string, Entity> defined)
    {
        foreach (var function in functions)
            foreach (string name in function.References)
                if (defined.TryGetValue(name, out var target) &&
                    target.Kind == EntityKind.Global && !target.IsCopyable && target.Part < 0 &&
                    !target.Text.Contains(" appending ", StringComparison.Ordinal))
                    target.Part = function.Part;

        foreach (var entity in entities)
            if (entity.Kind == EntityKind.Global && !entity.IsCopyable && entity.Part < 0)
                entity.Part = 0;
    }

    /// <summary>
    /// Walks what <paramref name="part"/> holds. A copyable constant or an
    /// inlinable function defined elsewhere is copied in and walked in turn;
    /// anything else defined elsewhere is reached.
    /// </summary>
    private static void CollectReached(
        List<Entity> entities, int part, Dictionary<string, Entity> defined,
        HashSet<string> reached, List<Entity> copies)
    {
        var copied = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Stack<(Entity Entity, bool IsCopy)>();

        foreach (var entity in entities)
            if (entity.Kind == EntityKind.Shared ||
                entity.Kind == EntityKind.Pinned && part == 0 ||
                entity.Kind is EntityKind.Function or EntityKind.Global && entity.Part == part)
                pending.Push((entity, false));

        while (pending.Count > 0)
        {
            var (from, fromCopy) = pending.Pop();
            foreach (string name in from.References)
            {
                if (!defined.TryGetValue(name, out var target))
                    continue;

                if (target.IsCopyable)
                {
                    if (copied.Add(name))
                    {
                        copies.Add(target);
                        pending.Push((target, true));
                    }
                    continue;
                }

                if (target.Part == part)
                    continue;

                reached.Add(name);

                // One level only: what a copy calls is declared, not copied too.
                if (target.IsInlinable && !fromCopy && copied.Add(name))
                {
                    copies.Add(target);
                    pending.Push((target, true));
                }
            }
        }
    }

    private static string WritePart(
        List<Entity> entities, int part, HashSet<string> reached, List<Entity> copies,
        HashSet<string> promoted, Dictionary<string, Entity> defined)
    {
        var text = new StringBuilder();

        foreach (var entity in entities)
            if (entity.Kind == EntityKind.Shared || entity.Kind == EntityKind.Pinned && part == 0)
                text.Append(entity.Text);

        var copiedNames = new HashSet<string>(copies.Select(c => c.Name), StringComparer.Ordinal);
        foreach (string name in reached)
            if (!copiedNames.Contains(name))
                text.Append(Declare(defined[name])).Append('\n');

        foreach (var copy in copies)
            text.Append(copy.IsCopyable ? copy.Text : CopyForInlining(copy.Text));

        foreach (var entity in entities)
            if (entity.Kind is EntityKind.Function or EntityKind.Global && entity.Part == part)
                text.Append(promoted.Contains(entity.Name) ? Promote(entity.Text) : entity.Text);

        return text.ToString();
    }

    // ------------------------------------------------------------- reading

    private static List<Entity> ReadEntities(string ir)
    {
        var entities = new List<Entity>();
        int at = 0;
        while (at < ir.Length)
        {
            int end = ir.IndexOf('\n', at);
            end = end < 0 ? ir.Length : end + 1;
            string line = ir[at..end];

            if (line.StartsWith("define ", StringComparison.Ordinal))
            {
                end = FunctionEnd(ir, end);
                string body = ir[at..end];
                entities.Add(new Entity
                {
                    Kind = EntityKind.Function,
                    Text = body,
                    Name = ReadDefinedName(line, line.IndexOf('@')),
                    References = ReadReferences(body, skipFirst: true),
                    IsInlinable = CountLines(body) <= InlinableLines + 3,
                });
            }
            else if (line.StartsWith('@') && !IsDeclaration(line))
            {
                bool copyable =
                    (Linkage(line) is "private" or "internal") &&
                    line.Contains(" unnamed_addr constant ", StringComparison.Ordinal);
                entities.Add(new Entity
                {
                    Kind = EntityKind.Global,
                    Text = line,
                    Name = ReadDefinedName(line, 0),
                    References = ReadReferences(line, skipFirst: true),
                    IsCopyable = copyable,
                });
            }
            else
            {
                entities.Add(new Entity
                {
                    Kind = line.StartsWith("module asm", StringComparison.Ordinal)
                        ? EntityKind.Pinned
                        : EntityKind.Shared,
                    Text = line,
                    References = ReadReferences(line, skipFirst: false),
                });
            }

            at = end;
        }
        return entities;
    }

    /// <summary>
    /// Just past the line holding only <c>}</c>, searching from the line at
    /// <paramref name="at"/>. The emitter writes CRLF on Windows and LF elsewhere.
    /// </summary>
    private static int FunctionEnd(string ir, int at)
    {
        while (at < ir.Length)
        {
            int end = ir.IndexOf('\n', at);
            end = end < 0 ? ir.Length : end + 1;
            if (ir[at] == '}' && ir.AsSpan(at + 1, end - at - 1).Trim().IsEmpty)
                return end;
            at = end;
        }
        return ir.Length;
    }

    private static int CountLines(string text)
    {
        int count = 0;
        foreach (char c in text)
            if (c == '\n')
                count++;
        return count;
    }

    /// <summary>A global with no initializer: <c>@x = external global i32</c>.</summary>
    private static bool IsDeclaration(string line) =>
        Linkage(line) is "external" or "extern_weak";

    /// <summary>The linkage keyword of a global or a function header, or "".</summary>
    private static string Linkage(string line)
    {
        int start = line.StartsWith("define ", StringComparison.Ordinal)
            ? "define ".Length
            : line.IndexOf(" = ", StringComparison.Ordinal) + 3;
        int space = line.IndexOf(' ', start);
        string word = space < 0 ? "" : line[start..space];
        return word is "private" or "internal" or "external" or "extern_weak" or "available_externally"
            or "linkonce" or "linkonce_odr" or "weak" or "weak_odr" or "common" or "appending"
            ? word
            : "";
    }

    /// <summary>The symbol at <paramref name="at"/>, quotes and all.</summary>
    private static string ReadDefinedName(string text, int at)
    {
        int start = at + 1;
        if (start < text.Length && text[start] == '"')
        {
            int close = text.IndexOf('"', start + 1);
            return text[start..(close + 1)];
        }
        int end = start;
        while (end < text.Length && IsNameCharacter(text[end]))
            end++;
        return text[start..end];
    }

    private static bool IsNameCharacter(char c) =>
        char.IsAsciiLetterOrDigit(c) || c is '-' or '$' or '.' or '_';

    /// <summary>
    /// Every <c>@name</c> in <paramref name="text"/>, skipping string literals,
    /// whose bytes may hold an <c>@</c> of their own.
    /// </summary>
    private static List<string> ReadReferences(string text, bool skipFirst)
    {
        var names = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        bool skipped = !skipFirst;
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (c == '"')
            {
                int close = text.IndexOf('"', i + 1);
                if (close < 0)
                    break;
                i = close;
            }
            else if (c == '%' && i + 1 < text.Length && text[i + 1] == '"')
            {
                int close = text.IndexOf('"', i + 2);
                if (close < 0)
                    break;
                i = close;
            }
            else if (c == '@')
            {
                string name = ReadDefinedName(text, i);
                i += name.Length;
                if (!skipped)
                {
                    skipped = true;
                    continue;
                }
                if (name.Length > 0 && seen.Add(name))
                    names.Add(name);
            }
        }
        return names;
    }

    // ------------------------------------------------------------- writing

    /// <summary>A definition reachable from the other parts, and still from no other module.</summary>
    private static string Promote(string text)
    {
        string linkage = Linkage(text);
        if (linkage is not ("internal" or "private"))
            return text;
        return ReplaceLinkage(text, linkage, "hidden");
    }

    /// <summary>
    /// A function another part defines, for this one to inline and never emit.
    /// It keeps the visibility its definition will have, or a library's export
    /// would be hidden by its own copy.
    /// </summary>
    private static string CopyForInlining(string text)
    {
        string current = Linkage(text);
        if (current is "internal" or "private")
            return ReplaceLinkage(text, current, "available_externally hidden");

        int newline = text.IndexOf('\n');
        string stripped = StripWord(text[..newline], "dllexport") + text[newline..];
        return current.Length > 0
            ? ReplaceLinkage(stripped, current, "available_externally")
            : "define available_externally " + stripped["define ".Length..];
    }

    private static string ReplaceLinkage(string text, string current, string replacement)
    {
        int start = text.StartsWith("define ", StringComparison.Ordinal)
            ? "define ".Length
            : text.IndexOf(" = ", StringComparison.Ordinal) + 3;
        return text[..start] + replacement + text[(start + current.Length)..];
    }

    /// <summary>A declaration of a definition, for a part that only reaches it.</summary>
    private static string Declare(Entity entity)
    {
        string text = entity.Text;
        string linkage = Linkage(text);
        string visibility = linkage is "internal" or "private" ? "hidden " : "";

        if (entity.Kind == EntityKind.Function)
        {
            int newline = text.IndexOf('\n');
            string header = text[..newline];
            int open = header.IndexOf('(', header.IndexOf('@'));
            int close = MatchingClose(header, open);
            string signature = header["define ".Length..(close + 1)];
            if (linkage.Length > 0)
                signature = signature[(linkage.Length + 1)..];
            signature = StripWord(signature, "dllexport");
            if (visibility.Length > 0)
                signature = StripWord(StripWord(signature, "hidden"), "protected");
            return "declare " + visibility + signature;
        }

        // `@x = <linkage> [visibility] [thread_local] [unnamed_addr] global|constant <type> <init>, align n`
        int equals = text.IndexOf(" = ", StringComparison.Ordinal);
        string rest = text[(equals + 3)..];
        var kept = new StringBuilder();
        int at = 0;
        while (true)
        {
            int space = rest.IndexOf(' ', at);
            string word = rest[at..space];
            at = space + 1;
            if (word is "global" or "constant")
            {
                kept.Append(word).Append(' ');
                break;
            }
            if (word.StartsWith("thread_local", StringComparison.Ordinal) ||
                word.StartsWith("addrspace", StringComparison.Ordinal) ||
                word == "externally_initialized")
                kept.Append(word).Append(' ');
        }

        int typeEnd = TypeEnd(rest, at);
        string type = rest[at..typeEnd];
        string trailing = "";
        int align = rest.LastIndexOf(", align ", StringComparison.Ordinal);
        if (align > typeEnd)
            trailing = rest[align..].TrimEnd('\n', '\r');

        return text[..equals] + " = external " + visibility + kept + type + trailing;
    }

    private static string StripWord(string text, string word)
    {
        string spaced = word + " ";
        return text.StartsWith(spaced, StringComparison.Ordinal)
            ? text[spaced.Length..]
            : text.Replace(" " + spaced, " ", StringComparison.Ordinal);
    }

    private static int MatchingClose(string text, int open)
    {
        int depth = 0;
        for (int i = open; i < text.Length; i++)
        {
            char c = text[i];
            if (c == '"')
            {
                i = text.IndexOf('"', i + 1);
                continue;
            }
            if (c == '(')
                depth++;
            else if (c == ')' && --depth == 0)
                return i;
        }
        return text.Length - 1;
    }

    /// <summary>Where the type starting at <paramref name="at"/> ends: a bracketed aggregate, or one word.</summary>
    private static int TypeEnd(string text, int at)
    {
        if (text[at] is '{' or '[' or '<')
        {
            int depth = 0;
            for (int i = at; i < text.Length; i++)
            {
                char c = text[i];
                if (c is '{' or '[' or '<' or '(')
                    depth++;
                else if (c is '}' or ']' or '>' or ')' && --depth == 0)
                    return i + 1;
            }
            return text.Length;
        }

        if (text[at] == '%' && at + 1 < text.Length && text[at + 1] == '"')
            return text.IndexOf('"', at + 2) + 1;

        int end = at;
        while (end < text.Length && text[end] is not (' ' or ',' or '\n'))
            end++;
        return end;
    }
}
