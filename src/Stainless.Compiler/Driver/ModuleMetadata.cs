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
    /// Whether this library reaches the runtime in one shared library or has a
    /// copy compiled into it.
    ///
    /// Both sides of a boundary must answer the same, or there are two
    /// allocators and two sets of reference counts again -- which is the bug the
    /// shared runtime exists to close, and would be a silent one. The consumer
    /// checks this and refuses a mismatch.
    /// </summary>
    public bool SharedRuntime { get; init; }

    /// <summary>
    /// Bumped whenever the shape below changes. A consumer refuses a version it
    /// does not know rather than reading fields that have moved.
    /// </summary>
    public const int CurrentVersion = 2;

    public int Version { get; init; } = CurrentVersion;

    /// <summary>The library this describes, for a diagnostic that can name it.</summary>
    public required string Library { get; init; }

    /// <summary>
    /// The package this library was built from, and the version it published
    /// itself as. Null for a library built straight from a command line, which
    /// has no package to be part of.
    ///
    /// This is what makes a dependency checkable rather than merely linkable: a
    /// consumer that asked for '^1.2' can be told it was handed 2.0 instead of
    /// discovering it at the first call.
    /// </summary>
    public string? Package { get; init; }

    public string? PackageVersion { get; init; }

    /// <summary>
    /// A fingerprint of everything below, from <see cref="Digest"/>.
    ///
    /// <see cref="PackageVersion"/> is what the library claims about itself, and
    /// a claim can be wrong -- a rebuild that moved a field and kept the number
    /// is exactly the mistake nobody notices. This is computed from the layouts
    /// themselves, so it cannot be. The lock file records what was resolved and
    /// the build compares, which turns "these offsets are stale" from a
    /// mis-read four bytes into a message.
    ///
    /// Written by <see cref="Sealed"/> rather than by whoever builds the record,
    /// so it is never a field somebody forgot to fill in.
    /// </summary>
    public string AbiDigest { get; init; } = "";

    public required List<MetadataType> Types { get; init; }
    public required List<MetadataFunction> Functions { get; init; }

    /// <summary>
    /// This metadata with its digests filled in: one per type, and one over the
    /// whole surface.
    ///
    /// Taken here, at the end, rather than as each piece is described, because a
    /// digest of part of a surface would be a digest of nothing in particular.
    /// </summary>
    public ModuleMetadata Sealed()
    {
        var described = this with
        {
            Types = Types.Select(t => t with { Digest = Driver.Digest.OfType(t) }).ToList(),
        };

        // The digest is over what is described, and a type's own digest is not
        // part of that -- so this reads nothing it is about to write.
        return described with { AbiDigest = Driver.Digest.OfMetadata(described) };
    }

    /// <summary>
    /// Recomputes the digest and says whether it is the one recorded.
    ///
    /// Worth asking separately from the lock file's copy, because it catches the
    /// other direction: a metadata file edited by hand, which is a thing this
    /// format's being readable makes easy and which nothing else would notice.
    /// </summary>
    public bool DigestMatches() =>
        AbiDigest.Length == 0 || Driver.Digest.OfMetadata(this) == AbiDigest;

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

            // A metadata file is readable JSON, which makes it editable JSON.
            // Editing one is how a consumer ends up compiling against a layout
            // the library does not have, and the digest is what notices.
            if (!metadata.DigestMatches())
            {
                error = $"'{path}' does not match its own digest, so it has been edited since it " +
                        "was written. Metadata is generated from the library it describes; " +
                        "rebuild the library rather than changing this file";
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

    /// <summary>
    /// This type's own fingerprint, from <see cref="Driver.Digest.OfType"/>.
    ///
    /// The library has one too, and this is what lets a mismatch name the type
    /// that moved. "Counter's layout changed" sends the reader somewhere;
    /// "something in shapes.dll changed" sends them looking.
    /// </summary>
    public string Digest { get; init; } = "";

    public List<MetadataField> Fields { get; init; } = [];
    public List<MetadataFunction> Methods { get; init; } = [];

    /// <summary>
    /// Declared <c>threadsafe</c>. It has to cross: a consumer deciding whether
    /// to warn about handing one to a thread is asking about the type, and the
    /// answer lives with the type rather than with the program using it.
    /// </summary>
    public bool IsThreadsafe { get; init; }

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
    /// Whether it belongs to the type rather than to an instance. It has to
    /// cross: a consumer that thought <c>FileStream.Open</c> took a receiver
    /// would pass one, and the callee would read it as the first argument.
    /// </summary>
    public bool IsStatic { get; init; }

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
