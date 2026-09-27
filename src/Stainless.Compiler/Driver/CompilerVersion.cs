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

using System.Reflection;

namespace Stainless.Driver;

/// <summary>
/// What this build of the compiler calls itself, as the build stamped it.
///
/// The major and minor are <c>VersionPrefix</c> in Directory.Build.props, and
/// the third part is the commit count; tools/Version.proj is the rule.
/// </summary>
public static class CompilerVersion
{
    /// <summary>
    /// The version with the commit it was built from, such as
    /// <c>0.1.474+7f05eda</c>, or <c>0.1.474+7f05eda-dirty</c> for a tree
    /// that differed from it.
    /// </summary>
    public static string Informational { get; } =
        typeof(CompilerVersion).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
        ?? Number;

    /// <summary>The three-part version, such as <c>0.1.474</c>.</summary>
    public static string Number =>
        typeof(CompilerVersion).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
}
