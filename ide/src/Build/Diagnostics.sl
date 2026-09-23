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

// What the compiler said about a build.
//
// **A module of its own, and not part of the window.** This was a struct at the
// bottom of `Shell.sl`, which made it untestable without a widget set: a
// console harness that wanted to check how a diagnostic is read had to link
// Forms and open a display to do it. Nothing here mentions a control, so
// nothing here needs one.
module Ide.Build;

import Standard.Text;
import Standard.Json;

/// One thing the compiler said, as the compiler said it.
///
/// **Read from JSON rather than out of the message.** This used to take the
/// rendered form apart again: a line was an error because it began with
/// "error", and the place came from counting colons from the right of the
/// arrow line so that a drive letter would survive. It worked, and it was a
/// parser for a format never meant to be parsed -- the first time a message
/// wrapped differently, or a path held something the rule did not expect, it
/// would have been wrong and silent about it.
///
/// `stainless --diagnostics json` writes one object per line instead, and this
/// reads it. What that buys beyond not guessing: a code to look up, a length
/// to underline, and a severity that is a field rather than a prefix.
public struct BuildMessage
{
    public String File;
    public nuint Line;
    public nuint Column;
    public nuint Length;
    public String Code;
    public String Message;
    public bool IsError;

    /// True when this is a diagnostic at all, as against a line of linker
    /// output or something a crash left behind.
    public bool IsDiagnostic;

    public bool HasPlace => Line > 0u;

    /// One that is only text.
    ///
    /// **Not `None`**, which is `Optional`'s case constructor and in scope
    /// everywhere -- a static of that name here resolves to the variant case
    /// and the error lands nowhere near the cause.
    public static BuildMessage CreateEmpty()
    {
        BuildMessage made;
        made.File = "";
        made.Line = 0u;
        made.Column = 0u;
        made.Length = 0u;
        made.Code = "";
        made.Message = "";
        made.IsError = false;
        made.IsDiagnostic = false;
        return made;
    }

    /// Reads one line of the compiler's JSON, or answers `None` for a line
    /// that is not one.
    ///
    /// Forgiving on purpose. Everything the compiler writes to its error stream
    /// arrives here and not all of it is a diagnostic: the linker's own
    /// complaints come through unchanged, and so does whatever a crash left
    /// behind. A line that does not parse is a line to show rather than a
    /// reason to stop.
    public static BuildMessage Parse(String line)
    {
        var made = CreateEmpty();

        String trimmed = line.Trim();
        if (!trimmed.StartsWith("{"))
        {
            made.Message = line;
            return made;
        }

        var parsed = Json.Parse(trimmed);
        if (!parsed.Ok)
        {
            made.Message = line;
            return made;
        }

        var document = parsed.Value;
        if (!document.Object)
        {
            made.Message = line;
            return made;
        }

        var members = document.Members;
        if (!members.ContainsKey("severity"))
        {
            made.Message = line;
            return made;
        }

        made.IsDiagnostic = true;
        made.Message = Json.GetTextOrDefault(members.GetValueOrNull("message"), "");
        made.Code = Json.GetTextOrDefault(members.GetValueOrNull("code"), "");
        made.IsError = Json.GetTextOrDefault(members.GetValueOrNull("severity"), "") == "error";
        made.File = Json.GetTextOrDefault(members.GetValueOrNull("file"), "");
        made.Line = (nuint)Json.GetIntegerOrDefault(members.GetValueOrNull("line"), 0);
        made.Column = (nuint)Json.GetIntegerOrDefault(members.GetValueOrNull("column"), 0);
        made.Length = (nuint)Json.GetIntegerOrDefault(members.GetValueOrNull("length"), 0);
        return made;
    }

    /// The one line this puts in the output list.
    ///
    /// The place goes last. A list of diagnostics is read for what is wrong,
    /// and putting the path first buries every message behind the part they
    /// all have in common.
    public String ToDisplayText()
    {
        if (!IsDiagnostic)
            return Message;

        var built = new StringBuilder();
        built.Append(IsError ? "error" : "warning");
        if (Code != "")
        {
            built.Append("[");
            built.Append(Code);
            built.Append("]");
        }
        built.Append(": ");
        built.Append(Message);

        if (HasPlace)
        {
            built.Append("   ");
            built.Append(GetFileName(File));
            built.Append(":");
            built.Append(Standard.Text.FromInteger((long)Line));
            built.Append(":");
            built.Append(Standard.Text.FromInteger((long)Column));
        }

        return built.ToText();
    }

    /// The last component of a path, since the directory is the same on every
    /// line and the file is not.
    static String GetFileName(String path)
    {
        long cut = path.LastIndexOf("\\");
        long other = path.LastIndexOf("/");
        if (other > cut)
            cut = other;
        return cut < 0 ? path : path.Substring((nuint)cut + 1u);
    }
}
