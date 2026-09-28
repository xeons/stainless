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

using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Driver;

/// <summary>
/// The standard-library modules a program reaches, so that only those are
/// parsed, bound, lowered and emitted.
///
/// A module is reached by an import, or by a qualified name that spells it,
/// from a file that is itself reached. The roots are the program's own files
/// and the modules the compiler names on its own: the auto-imported ones, and
/// the two it fills with built-in declarations. A whole module is kept or
/// dropped, never a file of one, because a module's files see each other's
/// declarations without importing anything.
/// </summary>
public static class LibraryClosure
{
    /// <summary>What every program has, whatever it names.</summary>
    private static readonly string[] s_roots =
    [
        Builtins.StandardModuleName,
        Builtins.TextModuleName,
        "Standard.Collections",
        Builtins.BitsModuleName,
        Builtins.ComModuleName,
    ];

    private const string ReflectionModuleName = "Standard.Reflection";

    /// <summary>The library's files that <paramref name="program"/> reaches, in their original order.</summary>
    public static List<LexedSource> ReachedFiles(
        IReadOnlyList<LexedSource> library, IReadOnlyList<LexedSource> program)
    {
        var byModule = library
            .GroupBy(f => f.ModuleName, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.Ordinal);

        var reached = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Queue<LexedSource>(program);

        void Reach(string module)
        {
            if (!byModule.TryGetValue(module, out var files) || !reached.Add(module)) return;
            foreach (var file in files)
                pending.Enqueue(file);
        }

        foreach (string root in s_roots)
            Reach(root);

        while (pending.TryDequeue(out var file))
        {
            foreach (string import in file.Imports)
                Reach(import);

            foreach (string path in file.NamePaths)
                Reach(path);

            if (file.MentionsReflection)
                Reach(ReflectionModuleName);
        }

        return library.Where(f => reached.Contains(f.ModuleName)).ToList();
    }
}
