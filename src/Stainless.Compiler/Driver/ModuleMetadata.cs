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

using System.Text.Json;
using System.Text.Json.Serialization;
using Stainless.Binding;

namespace Stainless.Driver;

/// <summary>
/// The public surface of a compiled library, as the thing that consumes it
/// needs to see.
///
/// Stainless has no headers, and inside one compilation it needs none: every
/// declaration is visible because every file is compiled together. A library is
/// where that stops being true. The consumer is a separate compilation with no
/// access to the source, so something has to carry what the source would have
/// said — layouts, signatures, and the linker names to call.
///
/// This is that something, and it is deliberately not a header: it is generated
/// rather than written, it is never edited, and it cannot drift from the library
/// it describes because it is emitted from the same bound program.
/// </summary>
public sealed record ModuleMetadata
{
    /// <summary>
    /// Bumped whenever the shape below changes. A consumer refuses a version it
    /// does not know rather than reading fields that have moved.
    /// </summary>
    public const int CurrentVersion = 1;

    public int Version { get; init; } = CurrentVersion;

    /// <summary>The library this describes, for a diagnostic that can name it.</summary>
    public required string Library { get; init; }

    public required List<MetadataType> Types { get; init; }
    public required List<MetadataFunction> Functions { get; init; }

    private static readonly JsonSerializerOptions Format = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public string ToJson() => JsonSerializer.Serialize(this, Format);

    /// <summary>Reads a metadata file, or explains why it could not be read.</summary>
    public static ModuleMetadata? Read(string path, out string error)
    {
        error = "";

        try
        {
            var metadata = JsonSerializer.Deserialize<ModuleMetadata>(
                File.ReadAllText(path), Format);

            if (metadata is null)
            {
                error = $"'{path}' is empty";
                return null;
            }

            if (metadata.Version != CurrentVersion)
            {
                error = $"'{path}' was written by a different compiler " +
                        $"(metadata version {metadata.Version}, this one reads {CurrentVersion})";
                return null;
            }

            return metadata;
        }
        catch (Exception e) when (e is IOException or JsonException)
        {
            error = $"could not read '{path}': {e.Message}";
            return null;
        }
    }
}

/// <summary>What kind of declaration a metadata entry describes.</summary>
public enum MetadataKind { Class, Struct, Enum, Union, Alias }

public sealed record MetadataType
{
    public required MetadataKind Kind { get; init; }
    public required string Module { get; init; }
    public required string Name { get; init; }

    /// <summary>Size and alignment of the fields, without any object header.</summary>
    public required int Size { get; init; }
    public required int Alignment { get; init; }

    public List<MetadataField> Fields { get; init; } = [];
    public List<MetadataFunction> Methods { get; init; } = [];

    /// <summary>The underlying integer of an enum, and its members.</summary>
    public string? Underlying { get; init; }
    public List<MetadataEnumMember> Members { get; init; } = [];

    /// <summary>
    /// The TypeInfo symbol a consumer allocates through. A class is made with
    /// <c>sl_alloc(TypeInfo*)</c>, so the library's table has to be reachable by
    /// name rather than rebuilt on the other side — rebuilding it would give the
    /// object a destructor from the wrong binary.
    /// </summary>
    public string? TypeInfoSymbol { get; init; }

    /// <summary>
    /// The qualified name of the class this one derives from, or null.
    ///
    /// A consumer cannot derive from a library's class -- the layout is compiled
    /// there and the dispatch table would be built here -- but it can still hold
    /// one, upcast it, ask what it is, and cast it back. All four need the
    /// relation, and none of them needs anything else about it.
    /// </summary>
    public string? Base { get; init; }

    /// <summary>
    /// True for a type declared with no body. A consumer may point at one and
    /// do nothing else with it, which is the same rule its own compilation had.
    /// </summary>
    public bool IsOpaque { get; init; }

    /// <summary>
    /// For <see cref="MetadataKind.Alias"/>, the type it names. Aliases cross
    /// so that a library's public surface can be spelled on the other side the
    /// way it is spelled here; the type is the same type either way.
    /// </summary>
    public string? AliasTarget { get; init; }
}

public sealed record MetadataField
{
    public required string Name { get; init; }
    public required string Type { get; init; }
    public required int Offset { get; init; }
    public required bool IsPublic { get; init; }

    /// <summary>True for the storage behind a property, which is not nameable.</summary>
    public bool IsBackingField { get; init; }

    /// <summary>
    /// For a bit-field, how wide it is and where in its storage unit it starts.
    /// Both have to cross: a consumer that knew only the byte offset would read
    /// the whole unit and get its neighbours with it.
    /// </summary>
    public int? BitWidth { get; init; }
    public int BitOffset { get; init; }
}

public sealed record MetadataEnumMember
{
    public required string Name { get; init; }
    public required ulong Value { get; init; }
}

public sealed record MetadataFunction
{
    public required string Name { get; init; }
    public required string Returns { get; init; }
    public required List<MetadataParameter> Parameters { get; init; }

    /// <summary>The linker name. Everything else here exists to type-check the call.</summary>
    public required string Symbol { get; init; }

    public FunctionKind Kind { get; init; } = FunctionKind.Function;
    public bool IsVariadic { get; init; }

    /// <summary>
    /// The dispatch slot, or -1 for a method called by name.
    ///
    /// It has to cross: a consumer that called a virtual method directly would
    /// reach the declaration rather than the object's own implementation, which
    /// is the one bug this whole mechanism exists to prevent.
    /// </summary>
    public int VirtualSlot { get; init; } = -1;

    /// <summary>The property this is an accessor of, if it is one.</summary>
    public string? Accessor { get; init; }

    /// <summary>The module a free function belongs to; null for a method.</summary>
    public string? Module { get; init; }
}

public sealed record MetadataParameter
{
    public required string Name { get; init; }
    public required string Type { get; init; }

    /// <summary>
    /// How it is passed. It is part of the signature rather than a note about
    /// it: a consumer that called a 'ref int' by value would hand the callee an
    /// integer where it expects the address of one.
    /// </summary>
    public Syntax.ParameterMode Mode { get; init; } = Syntax.ParameterMode.Value;
}
