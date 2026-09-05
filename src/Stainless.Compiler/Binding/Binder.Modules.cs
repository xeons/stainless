// Stainless - an experimental systems language.
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
/// Passes 1 and 3: which module each file belongs to, and what each
/// file can see of the others.
///
/// They are separated by pass 2 because a type must be declared before
/// an import can be resolved to it. Finding <c>Main</c> is here too: it
/// is the same question of which module holds what, asked last.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 1

    private void DeclareModules(IReadOnlyList<CompilationUnitSyntax> units)
    {
        foreach (var unit in units)
        {
            if (unit.ModuleName is null)
            {
                diagnostics.Error("SL0332", new SourceSpan(unit.File, 0, 0),
                    "this file does not say which module it belongs to; " +
                    "start it with a declaration such as 'module App.Thing;'");
                continue;
            }

            string name = unit.ModuleName.Text;

            // Several files may declare the same module and merge into it, as C#
            // namespaces do. Each still gets its own scope, because imports are
            // written per file.
            if (!_modules.TryGetValue(name, out var module))
            {
                module = new ModuleSymbol(name);
                _modules[name] = module;
            }

            var scope = new FileScope(module);
            _builtins.AutoImportInto(scope);
            _units.Add((scope, unit));
        }
    }

    // ============================================================ pass 3

    private void ResolveImports()
    {
        foreach (var (scope, unit) in _units)
        {
            foreach (var import in unit.Imports)
            {
                if (!_modules.TryGetValue(import.Name.Text, out var target))
                {
                    diagnostics.Error("SL0202", import.Span,
                        $"module '{import.Name.Text}' was not found among the compiled sources");
                    continue;
                }

                if (target == scope.Module)
                {
                    diagnostics.Warning("SL0203", import.Span,
                        "a file does not need to import its own module");
                    continue;
                }

                string key = import.Alias ?? import.Name.Last;
                scope.Imports[key] = target;

                // The full dotted name always works too, so `import A.B;` lets you
                // write both `B.Thing` and `A.B.Thing`.
                scope.Imports[import.Name.Text] = target;
            }
        }
    }

    // ------------------------------------------------------------ entry point

    private FunctionSymbol? FindEntryPoint()
    {
        var candidates = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Name == "Main" && f.ContainingType is null && f.HasBody)
            .ToList();

        if (candidates.Count == 0) return null;

        if (candidates.Count > 1)
        {
            diagnostics.Error("SL0280", candidates[1].Span,
                "more than one 'Main' was found: " +
                string.Join(", ", candidates.Select(c => c.ModuleName + ".Main")));
            return candidates[0];
        }

        var entry = candidates[0];
        bool returnsInt = entry.ReturnType is PrimitiveTypeSymbol { Kind: PrimitiveKind.Int };
        if (!returnsInt && !entry.ReturnType.IsVoid())
            diagnostics.Error("SL0281", entry.Span,
                $"'Main' must return 'int' or 'void', not '{entry.ReturnType.Name}'");

        // `Main()` or `Main(String[] args)`, and nothing else. The second is
        // how a program reads its command line; the name of the parameter is
        // the program's business, the type is not.
        if (entry.Parameters.Count > 1 ||
            (entry.Parameters.Count == 1 && !IsStringArray(entry.Parameters[0].Type)))
            diagnostics.Error("SL0282", entry.Span,
                "'Main' takes either nothing or 'String[]' -- the arguments the " +
                "program was started with, without the program's own name");

        return entry;
    }

    private bool IsStringArray(TypeSymbol type) =>
        type is ArrayTypeSymbol array && _builtins.IsString(array.Element);
}
