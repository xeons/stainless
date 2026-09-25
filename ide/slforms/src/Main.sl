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

// Form files, turned into their generated halves without the IDE.
//
//   slforms <form-or-directory>...            write every stale .designer.sl
//   slforms --check <form-or-directory>...    write nothing; fail if one is stale
//   slforms --format <form-or-directory>...   also rewrite each form in the
//                                             writer's layout
//
// Built from the designer's own sources, so there is one reader of the format.
module Slforms;

import Standard.Collections;
import Standard.Console;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.Path;
import Standard.Text;
import Ide.Designer;

int Main()
{
    var arguments = Env.GetArguments();
    bool checking = false;
    bool formatting = false;
    var forms = new List<String>();

    for (nuint i = 0u; i < arguments.Length; i++)
    {
        String argument = arguments[i];
        if (argument == "--check")
        {
            checking = true;
            continue;
        }
        if (argument == "--format")
        {
            formatting = true;
            continue;
        }
        if (argument.StartsWith("-"))
        {
            Console.WriteError("slforms: '" + argument + "' is not an option");
            return 2;
        }

        if (!Directory.Exists(argument))
        {
            forms.Add(argument);
            continue;
        }

        var found = FindFormFiles(argument);
        if (!found.Ok)
        {
            Console.WriteError("slforms: " + found.Error);
            return 1;
        }
        forms.AddRange(found.Value);
    }

    if (forms.Count == 0u)
    {
        Console.WriteError("usage: slforms [--check | --format] <form-or-directory>...");
        return 2;
    }

    if (checking)
        return CheckFormSources(forms);

    if (formatting)
    {
        int formatted = FormatFormFiles(forms);
        if (formatted != 0)
            return formatted;
    }

    var written = RegenerateFormSources(forms);
    if (!written.Ok)
    {
        Console.WriteError(written.Error);
        return 1;
    }
    Console.WriteLine("slforms: " + Text.FromInteger((long)written.Value) + " of " +
                      Text.FromInteger((long)forms.Count) + " written");
    return 0;
}

/// Answers 1 and names each form whose generated half is missing or differs.
int CheckFormSources(List<String> forms)
{
    int status = 0;
    foreach (var path in forms)
    {
        var read = ReadFormDocument(path);
        if (!read.Ok)
        {
            Console.WriteError(read.Error.Describe(path));
            status = 1;
            continue;
        }

        String expected = GenerateFormSource(read.Value, Path.GetFileName(path));
        var existing = File.ReadAllText(FindDesignerPath(path));
        if (!existing.Ok || existing.Value != expected)
        {
            Console.WriteError(path + ": the generated half is stale; run slforms");
            status = 1;
        }
    }
    return status;
}

int FormatFormFiles(List<String> forms)
{
    foreach (var path in forms)
    {
        var read = ReadFormDocument(path);
        if (!read.Ok)
        {
            Console.WriteError(read.Error.Describe(path));
            return 1;
        }

        var saved = SaveFormDocument(read.Value, path);
        if (!saved.Ok)
        {
            Console.WriteError(saved.Error);
            return 1;
        }
    }
    return 0;
}
