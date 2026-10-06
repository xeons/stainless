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

namespace Stainless.Source;

/// <summary>
/// One thing the compiler can report: its code, how severe it is, and what it
/// means in a line.
///
/// Declared once, in <see cref="Codes"/>, and named by every place that
/// reports it. The message stays at the place, since it names what that place
/// found; the title is what the code means wherever it is said, and is what
/// the inventory lists.
/// </summary>
public sealed class DiagnosticDescriptor
{
    public string Code { get; }
    public Severity Severity { get; }
    public string Title { get; }

    internal DiagnosticDescriptor(string code, Severity severity, string title)
    {
        Code = code;
        Severity = severity;
        Title = title;
    }

    public override string ToString() => Code;
}
