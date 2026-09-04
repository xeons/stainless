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

using Stainless.Binding;
using Stainless.Driver;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Describes a library's public surface so another Stainless compilation can
/// bind against it.
///
/// Only what a separate compilation can actually use is written. Two things are
/// deliberately left out, and both are consequences of the language compiling a
/// whole program at once:
///
///   generics    a template emits nothing until it is instantiated, so a
///               consumer that has only the binary has nothing to call
///   interfaces  a dispatch table is indexed by a program-wide interface id,
///               and two separate compilations number them independently
///
/// Neither is an oversight to be filled in later by writing more of this file;
/// each is a decision about the language that would have to be made first.
/// </summary>
public static class MetadataWriter
{
    /// <summary>
    /// Where a warning about a type points when the type itself carries no
    /// span. A class is declared by syntax the symbol does not keep, so the
    /// nearest real location is one of its members.
    /// </summary>
    private static readonly SourceText Library = new("<library>", "");
    private static readonly SourceSpan LibrarySpan = new(Library, 0, 0);

    private static SourceSpan Where(ClassTypeSymbol type) =>
        type.Constructors.Concat(type.Methods).FirstOrDefault()?.Span ?? LibrarySpan;

    /// <summary>
    /// <paramref name="ownModules"/> is what this library actually declares.
    /// The standard library is compiled into every program, so describing it
    /// here would hand the consumer a second declaration of everything it
    /// already has.
    /// </summary>
    public static ModuleMetadata Write(
        BoundProgram program,
        string library,
        IReadOnlySet<string> ownModules,
        DiagnosticBag? diagnostics = null,
        bool sharedRuntime = false)
    {
        var types = new List<MetadataType>();

        foreach (var type in program.Modules
                     .Where(m => ownModules.Contains(m.Name))
                     .SelectMany(m => m.Types.Values)
                     .OrderBy(t => t.QualifiedName, StringComparer.Ordinal))
        {
            if (!type.IsPublic) continue;

            switch (type)
            {
                case ClassTypeSymbol classType when Crosses(classType):
                    types.Add(Describe(classType));
                    break;

                // Silence here would be found by the consumer, as a type that
                // is public and somehow not there. Better to say it once, where
                // the library is built.
                case ClassTypeSymbol excluded:
                    Report(diagnostics, excluded);
                    break;

                // A variant's cases are the whole of what it is, and the
                // metadata has no way to say them: what would cross is a tag and
                // a blob of bytes, which the consumer could construct, copy and
                // never switch on. Better to say so where the library is built.
                case VariantTypeSymbol variant:
                    diagnostics?.Warning("SL0441", variant.Span ?? default,
                        $"'{variant.QualifiedName}' is a variant, so it is not described in " +
                        "this library's metadata: its cases are what a consumer would switch " +
                        "on, and the metadata carries layouts rather than cases. A variant " +
                        "crosses a library boundary as source, not as a binary");
                    break;

                case UnionTypeSymbol union:
                    types.Add(Describe(union) with { Kind = MetadataKind.Union });
                    break;

                case StructTypeSymbol structType:
                    types.Add(Describe(structType));
                    break;

                case EnumTypeSymbol enumType:
                    types.Add(Describe(enumType));
                    break;
            }
        }

        // An alias is a name rather than a type, so it carries only the name it
        // resolved to. It crosses so that a library's public surface can be
        // spelled on the other side the way it is spelled here.
        foreach (var alias in program.Modules
                     .Where(m => ownModules.Contains(m.Name))
                     .SelectMany(m => m.Aliases.Values)
                     .Where(a => a.IsPublic && a.Target is not null && !a.Target.IsError())
                     .OrderBy(a => a.QualifiedName, StringComparer.Ordinal))
            types.Add(new MetadataType
            {
                Kind = MetadataKind.Alias,
                Module = alias.ModuleName,
                Name = alias.Name,
                Size = 0,
                Alignment = 1,
                AliasTarget = MetadataTypeNames.Write(alias.Target!),
            });

        if (diagnostics is not null)
            foreach (var template in program.Modules
                         .Where(m => ownModules.Contains(m.Name))
                         .SelectMany(m => m.GenericTypes.Values)
                         .Where(t => t.IsPublic))
                diagnostics.Warning("SL0419", template.Declaration.Span,
                    $"'{template.Name}' is generic, so it is not described in this library's " +
                    "metadata: a template emits nothing until it is instantiated, and a consumer " +
                    "with only the binary has nothing to instantiate. A generic crosses a library " +
                    "boundary as source, not as a binary");

        var functions = program.Modules
            .Where(m => ownModules.Contains(m.Name))
            .SelectMany(m => m.Functions)
            .Where(f => f.IsPublic && f.ContainingType is null &&
                        f.Linkage == LinkageKind.Stainless && f.TypeArguments.Count == 0)
            .OrderBy(f => f.ModuleName + "." + f.Name, StringComparer.Ordinal)
            .Select(Describe)
            .ToList();

        // Whatever is described has to be describable all the way down. A
        // field or a signature naming something the metadata left out would
        // reach the consumer as a name it cannot resolve, which is the failure
        // the warnings above exist to move to this side of the boundary.
        if (diagnostics is not null)
            CheckDescribable(types, functions, diagnostics, program, ownModules);

        return new ModuleMetadata
        {
            Library = library,
            SharedRuntime = sharedRuntime,
            Types = types,
            Functions = functions,
        };
    }

    /// <summary>
    /// Reports any part of the described surface that names a type the metadata
    /// does not carry.
    ///
    /// The names are compared as text on purpose: text is what crosses, and a
    /// name that does not round-trip is exactly what the consumer would fail on.
    /// </summary>
    private static void CheckDescribable(
        List<MetadataType> types,
        List<MetadataFunction> functions,
        DiagnosticBag diagnostics,
        BoundProgram program,
        IReadOnlySet<string> ownModules)
    {
        var known = types.Select(t => t.Module + "." + t.Name).ToHashSet(StringComparer.Ordinal);

        // A type this library did not declare is one the consumer reaches the
        // same way this compilation did: the standard library is compiled into
        // every program, and a referenced library has to be referenced by both
        // sides anyway. Describing those here would be declaring them twice.
        // What is genuinely unresolvable is an instantiated generic, whose name
        // is not something a consumer can write and whose template is not in the
        // binary -- and those are not in any module's table, so they are not
        // added here.
        foreach (var type in program.Modules
                     .Where(m => !ownModules.Contains(m.Name))
                     .SelectMany(m => m.Types.Values))
            known.Add(type.QualifiedName);

        var spans = program.Modules
            .SelectMany(m => m.Types.Values)
            .Where(t => t.Span is not null)
            .GroupBy(t => t.QualifiedName, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.First().Span!.Value, StringComparer.Ordinal);

        // A free function is not a type, and a warning without a place to point
        // at is one a reader cannot act on.
        foreach (var function in program.Modules
                     .Where(m => ownModules.Contains(m.Name))
                     .SelectMany(m => m.Functions)
                     .Where(f => f.ContainingType is null))
            spans.TryAdd(function.ModuleName + "." + function.Name, function.Span);

        var reported = new HashSet<string>(StringComparer.Ordinal);

        void Check(string owner, string what, string written)
        {
            string bare = written.TrimStart();
            if (bare.StartsWith("weak ", StringComparison.Ordinal)) bare = bare["weak ".Length..];
            bare = bare.TrimEnd('?', '*');
            while (bare.EndsWith("[]", StringComparison.Ordinal)) bare = bare[..^2];

            if (MetadataTypeNames.Read(bare, _ => null) is not null) return;   // a primitive
            if (known.Contains(bare)) return;
            if (!reported.Add(owner + "/" + bare)) return;

            diagnostics.Warning("SL0477",
                spans.TryGetValue(owner, out var at) ? at : default,
                $"'{owner}' is described in this library's metadata and {what} is " +
                $"'{written}', which is not. A consumer would read a name it cannot resolve; " +
                "keep it out of the public surface, or let it cross as source");
        }

        foreach (var type in types)
        {
            string owner = type.Module + "." + type.Name;

            foreach (var field in type.Fields)
                Check(owner, $"its field '{field.Name}'", field.Type);

            foreach (var method in type.Methods)
            {
                Check(owner, $"what '{method.Name}' returns", method.Returns);
                foreach (var parameter in method.Parameters)
                    Check(owner, $"'{method.Name}' takes '{parameter.Name}', which", parameter.Type);
            }
        }

        foreach (var function in functions)
        {
            string owner = function.Module + "." + function.Name;
            Check(owner, "what it returns", function.Returns);
            foreach (var parameter in function.Parameters)
                Check(owner, $"it takes '{parameter.Name}', which", parameter.Type);
        }
    }

    /// <summary>
    /// True for a class a separate compilation could actually use. An
    /// instantiated generic is excluded because its name — <c>Box&lt;int&gt;</c>
    /// — is not something a consumer can write, and the template it came from
    /// is not in the binary at all.
    /// </summary>
    private static bool Crosses(ClassTypeSymbol type) =>
        type.Template is null && !type.IsIntrinsic && type.Interfaces.Count == 0;

    private static void Report(DiagnosticBag? diagnostics, ClassTypeSymbol excluded)
    {
        if (diagnostics is null || excluded.IsIntrinsic) return;

        // An instantiation is silent: the template it came from is reported
        // once, where it was declared, rather than once per instantiation under
        // a name — `Box<int>` — that no source could have written anyway.
        if (excluded.Template is not null) return;

        diagnostics.Warning("SL0420", Where(excluded),
            $"'{excluded.QualifiedName}' implements an interface, so it is not described in " +
            "this library's metadata: a dispatch table is indexed by an interface id assigned " +
            "across a whole program, and this library and its consumer are two of those");
    }

    private static MetadataType Describe(ClassTypeSymbol type) => new()
    {
        Kind = MetadataKind.Class,
        Module = type.ModuleName,
        Name = type.SimpleName,
        Size = type.FieldsSize,
        Alignment = type.FieldsAlignment,
        TypeInfoSymbol = Mangler.TypeInfoSymbol(type),
        Base = type.BaseClass?.QualifiedName,
        Fields = type.Fields.Select(Describe).ToList(),

        // Constructors and the destructor are methods as far as a consumer is
        // concerned: symbols to call with the object as the receiver.
        Methods = type.Methods
            .Concat(type.Constructors)
            .Concat(type.Destructor is null ? [] : new[] { type.Destructor })
            .Where(m => m.IsPublic || m.Kind == FunctionKind.Destructor)
            .Select(Describe)
            .ToList(),
    };

    private static MetadataType Describe(StructTypeSymbol type) => new()
    {
        Kind = MetadataKind.Struct,
        Module = type.ModuleName,
        Name = type.SimpleName,
        Size = type.FieldsSize,
        Alignment = type.FieldsAlignment,
        IsOpaque = type.IsOpaque,
        Fields = type.Fields.Select(Describe).ToList(),
        Methods = type.Methods.Where(m => m.IsPublic).Select(Describe).ToList(),
    };

    private static MetadataType Describe(EnumTypeSymbol type) => new()
    {
        Kind = MetadataKind.Enum,
        Module = type.ModuleName,
        Name = type.SimpleName,
        Size = type.Size,
        Alignment = type.Alignment,
        Underlying = MetadataTypeNames.Write(type.UnderlyingType),
        Members = type.Members
            .Select(m => new MetadataEnumMember { Name = m.Name, Value = m.Value })
            .ToList(),
    };

    private static MetadataField Describe(FieldSymbol field) => new()
    {
        Name = field.Name,
        Type = MetadataTypeNames.Write(field.Type),
        Offset = field.Offset,
        IsPublic = field.IsPublic,
        IsBackingField = field.IsBackingField,
        BitWidth = field.BitWidth,
        BitOffset = field.BitOffset,
    };

    private static MetadataFunction Describe(FunctionSymbol function) => new()
    {
        Name = function.Name,
        Returns = MetadataTypeNames.Write(function.ReturnType),
        Symbol = function.MangledName,
        Kind = function.Kind,
        IsVariadic = function.IsVariadic,
        VirtualSlot = function.VirtualSlot,
        Accessor = function.Accessor?.Name,
        Module = function.ContainingType is null ? function.ModuleName : null,
        Parameters = function.Parameters
            .Where(p => !p.IsThis)
            .Select(p => new MetadataParameter
            {
                Name = p.Name,
                Type = MetadataTypeNames.Write(p.Type),
                Mode = p.Mode,
            })
            .ToList(),
    };
}
