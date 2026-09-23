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

namespace Stainless.Syntax;

/// <summary>
/// What a <c>///</c> block says, once its <c>@tags</c> are separated from its
/// prose.
///
/// <para>
/// <b>The prose is Markdown and stays Markdown.</b> A block is read, rendered
/// and written as Markdown, so there is no third syntax in the middle: a
/// backtick is code, <c>**bold**</c> is bold, an indented or fenced block is a
/// sample, and a list is a list. The tags exist for what Markdown has no way
/// to say -- which parameter a sentence is about, what a call answers, which
/// failures it can report.
/// </para>
///
/// <para>
/// <b>Everything before the first tag is the summary</b>, so a block that uses
/// no tags is a summary and nothing else. That is what every block in this
/// tree already is, and they keep working untouched.
/// </para>
/// </summary>
public sealed record DocComment(string Summary, IReadOnlyList<DocTag> Tags)
{
    /// <summary>A block with no prose and no tags.</summary>
    public static readonly DocComment Empty = new("", []);

    /// <summary>The tags of one kind, in the order they were written.</summary>
    public IEnumerable<DocTag> OfKind(DocTagKind kind) => Tags.Where(t => t.Kind == kind);

    /// <summary>The first tag of this kind, or null.</summary>
    public DocTag? FirstOfKind(DocTagKind kind) => Tags.FirstOrDefault(t => t.Kind == kind);

    /// <summary>True when nothing was written at all.</summary>
    public bool IsEmpty => Summary.Length == 0 && Tags.Count == 0;

    /// <summary>
    /// Reads a block. <paramref name="text"/> is what the lexer captured: the
    /// <c>///</c> markers and one following space removed, the lines joined
    /// with newlines.
    ///
    /// <para>
    /// <paramref name="block"/> is where that text was written, which gives
    /// each tag a span of its own. Null where there is no source to point at.
    /// </para>
    /// </summary>
    public static DocComment Parse(string text, SourceSpan? block = null)
    {
        if (text.Length == 0) return Empty;

        var lines = text.Split('\n');
        int[]? starts = LineStarts(lines, block);

        var summary = new List<string>();
        var tags = new List<DocTag>();

        // The tag being collected, and its lines so far. A tag runs until the
        // next one or the end of the block, so a description may be as long as
        // it needs and wraps like any other prose.
        var open = DocTagKind.None;
        string word = "";
        string? name = null;
        var body = new List<string>();
        int at = 0;

        void Close()
        {
            if (open == DocTagKind.None) return;

            // An example is kept exactly as written. Its indentation is what
            // makes it a Markdown code block, so taking the alignment off it
            // would turn the sample into prose.
            string text = open == DocTagKind.Example
                ? string.Join("\n", body).Trim('\n').TrimEnd()
                : Dedent(body);

            tags.Add(new DocTag(open, word, name, text, Line(block, starts, at, lines)));
            body.Clear();
        }

        for (int i = 0; i < lines.Length; i++)
        {
            var (opened, spelling, rest) = TagOn(lines[i]);

            if (opened == DocTagKind.None)
            {
                if (open == DocTagKind.None) summary.Add(lines[i]);
                else body.Add(lines[i]);
                continue;
            }

            Close();

            open = opened;
            word = spelling;
            at = i;
            name = TakesAName(opened) ? FirstWord(ref rest) : null;
            if (rest.Length > 0 || opened != DocTagKind.Example) body.Add(rest);
        }

        Close();

        return new DocComment(string.Join("\n", summary).Trim('\n').TrimEnd(), tags);
    }

    /// <summary>
    /// The tag a line opens, or <see cref="DocTagKind.None"/> for prose.
    ///
    /// <para>
    /// <b>A tag starts at the very start of a line.</b> An indented <c>@</c> is
    /// text, which is what keeps the four-space code samples this tree already
    /// has from being read as markup -- and an address or a decorated symbol
    /// such as <c>_LoadLibraryA@4</c> is never at a line's start.
    /// </para>
    /// </summary>
    private static (DocTagKind Kind, string Word, string Text) TagOn(string line)
    {
        if (line.Length < 2 || line[0] != '@') return (DocTagKind.None, "", line);

        int end = 1;
        while (end < line.Length && char.IsAsciiLetter(line[end])) end++;

        string spelling = line[1..end];
        if (spelling.Length == 0) return (DocTagKind.None, "", line);

        return (KindOf(spelling), spelling, line[end..].TrimStart());
    }

    /// <summary>
    /// The tag vocabulary. Each is .NET's element under the name a Markdown
    /// document would use for it, and there is one spelling of each: a word
    /// that is nearly one -- <c>@summary</c>, <c>@return</c> -- is an unknown
    /// tag, and the diagnostic says what to write instead.
    ///
    /// <c>@failure</c> is what this language has in place of
    /// <c>&lt;exception&gt;</c>: nothing is thrown here, and a call that can
    /// fail says so in its return type.
    /// </summary>
    private static DocTagKind KindOf(string word) => word switch
    {
        "param" => DocTagKind.Param,
        "typeparam" => DocTagKind.TypeParam,
        "returns" => DocTagKind.Returns,
        "value" => DocTagKind.Value,
        "remarks" => DocTagKind.Remarks,
        "example" => DocTagKind.Example,
        "failure" => DocTagKind.Failure,
        "see" => DocTagKind.See,
        "seealso" => DocTagKind.SeeAlso,
        "inheritdoc" => DocTagKind.InheritDoc,
        _ => DocTagKind.Unknown,
    };

    /// <summary>Whether the first word after the tag names what it is about.</summary>
    private static bool TakesAName(DocTagKind kind) => kind is
        DocTagKind.Param or DocTagKind.TypeParam or DocTagKind.Failure or
        DocTagKind.See or DocTagKind.SeeAlso or DocTagKind.InheritDoc;

    /// <summary>Takes the first word off a line, leaving the rest.</summary>
    private static string? FirstWord(ref string rest)
    {
        int end = 0;
        while (end < rest.Length && !char.IsWhiteSpace(rest[end])) end++;
        if (end == 0) return null;

        string first = rest[..end];
        rest = rest[end..].TrimStart();
        return first;
    }

    /// <summary>
    /// A tag's text, with the indent its continuation lines were aligned with
    /// removed.
    ///
    /// A description wrapped under <c>@param path</c> is usually indented to
    /// line up with the first line, and that indent is alignment rather than
    /// content -- four spaces of it would otherwise be a Markdown code block.
    /// </summary>
    private static string Dedent(List<string> body)
    {
        int common = int.MaxValue;

        for (int i = 1; i < body.Count; i++)
        {
            string line = body[i];
            if (line.Trim().Length == 0) continue;

            int indent = 0;
            while (indent < line.Length && line[indent] == ' ') indent++;
            common = Math.Min(common, indent);
        }

        var lines = new List<string>(body.Count);
        for (int i = 0; i < body.Count; i++)
            lines.Add(i == 0 || common == int.MaxValue || body[i].Length < common
                ? body[i]
                : body[i][common..]);

        return string.Join("\n", lines).Trim('\n').TrimEnd();
    }

    /// <summary>
    /// Where each line of the block starts in the source, so that a tag can be
    /// reported where it was written.
    ///
    /// The lexer strips the marker and one space, so the text it captured is
    /// not laid out like the file. The source is walked instead, one line per
    /// captured line, which is exact and costs one scan of the block.
    /// </summary>
    private static int[]? LineStarts(string[] lines, SourceSpan? block)
    {
        if (block is not { } span) return null;

        var starts = new int[lines.Length];
        string source = span.File.Text;
        int at = span.Start;

        for (int i = 0; i < lines.Length; i++)
        {
            // Past the indentation and the marker, which is where the captured
            // text begins. One space after the marker is the marker's own.
            int from = at;
            while (from < source.Length && (source[from] == ' ' || source[from] == '\t')) from++;
            if (source.AsSpan(from).StartsWith("///")) from += 3;
            if (from < source.Length && source[from] == ' ') from++;

            starts[i] = Math.Min(from, source.Length);

            while (at < source.Length && source[at] != '\n') at++;
            at++;
        }

        return starts;
    }

    /// <summary>The span of one line of the block, or null where there is no source.</summary>
    private static SourceSpan? Line(SourceSpan? block, int[]? starts, int index, string[] lines)
    {
        if (block is not { } span || starts is null || index >= starts.Length) return null;

        int start = starts[index];
        return new SourceSpan(span.File, start, start + lines[index].Length);
    }
}

/// <summary>What a tag is. <see cref="DocTagKind.None"/> means a line of prose.</summary>
public enum DocTagKind
{
    None,
    Remarks,
    Param,
    TypeParam,
    Returns,
    Value,
    Example,
    Failure,
    See,
    SeeAlso,
    InheritDoc,
    Unknown,
}

/// <summary>
/// One <c>@tag</c>: what it is, the word that spelled it, what it names, the
/// Markdown under it, and where it was written.
/// </summary>
public sealed record DocTag(
    DocTagKind Kind, string Word, string? Name, string Text, SourceSpan? Span);
