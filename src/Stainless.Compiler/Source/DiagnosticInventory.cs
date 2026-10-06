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

namespace Stainless.Source;

/// <summary>
/// The registry as a reader sees it: one diagnostic as a line, and all of them
/// as `docs/diagnostics.md`, which a unit test holds to this.
/// </summary>
public static class DiagnosticInventory
{
    public static string Describe(DiagnosticDescriptor descriptor) =>
        $"{descriptor.Code} ({SeverityName(descriptor.Severity)}): {descriptor.Title}";

    public static string Markdown()
    {
        var page = new StringBuilder();
        page.Append("# Diagnostics\n\n");
        page.Append("Every diagnostic the compiler can report, with what it means. Generated from\n");
        page.Append("`src/Stainless.Compiler/Source/Codes.cs` by `stainless explain --markdown`;\n");
        page.Append("edit that file, not this one.\n\n");
        page.Append($"{Codes.All.Count} codes: ");
        page.Append($"{Codes.All.Count(d => d.Severity == Severity.Error)} errors and ");
        page.Append($"{Codes.All.Count(d => d.Severity == Severity.Warning)} warnings.\n");

        string? band = null;
        foreach (var descriptor in Codes.All.OrderBy(d => d.Code, StringComparer.Ordinal))
        {
            string here = descriptor.Code[..4];
            if (here != band)
            {
                band = here;
                page.Append($"\n## {band}xx\n\n");
                page.Append("| Code | Severity | Means |\n");
                page.Append("|---|---|---|\n");
            }
            page.Append($"| {descriptor.Code} | {SeverityName(descriptor.Severity)} | ");
            page.Append(descriptor.Title.Replace("|", "\\|"));
            page.Append(" |\n");
        }
        return page.ToString();
    }

    private static string SeverityName(Severity severity) => severity switch
    {
        Severity.Error => "error",
        Severity.Warning => "warning",
        _ => "note",
    };
}
