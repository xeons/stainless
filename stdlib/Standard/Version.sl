// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.


module Standard;

import Standard.Collections;

/// A version number of two to four parts: C#'s `System.Version`.
///
///     var version = Version.Parse("1.4.2").GetValue();
///     if (version >= new Version(1, 4)) { ... }
///
/// `Build` and `Revision` are -1 when the version was written without them,
/// and a version without a part comes before one with it: 1.4 is before 1.4.0.
public struct Version : IEquatable<Version>, IComparable<Version>, IHashable
{
    /// The first part.
    public int Major { get; }

    /// The second part.
    public int Minor { get; }

    /// The third part, or -1 when there is none.
    public int Build { get; }

    /// The fourth part, or -1 when there is none.
    public int Revision { get; }

    /// `major.minor`.
    public Version(int major, int minor) : this(major, minor, -1, -1) { }

    /// `major.minor.build`.
    public Version(int major, int minor, int build) : this(major, minor, build, -1) { }

    /// `major.minor.build.revision`. Aborts on a negative part, or on a later
    /// part given where an earlier one is missing.
    public Version(int major, int minor, int build, int revision)
    {
        if (major < 0 || minor < 0 || build < -1 || revision < -1 || (build == -1 && revision != -1))
            sl_fail("Version: a part is negative");

        Major = major;
        Minor = minor;
        Build = build;
        Revision = revision;
    }

    /// The high 16 bits of `Revision`.
    public short MajorRevision => (short)(Revision >> 16);

    /// The low 16 bits of `Revision`.
    public short MinorRevision => (short)(Revision & 0xFFFF);

    /// Reads two to four parts separated by dots.
    ///
    /// @param text  the version, as `ToString` writes it
    public static Result<Version, ParseError> Parse(String text)
    {
        if (text.IsEmpty)
            return Fail(ParseError.Empty);

        String[] parts = text.Split('.');
        if (parts.Length < 2u || parts.Length > 4u)
            return Fail(ParseError.Malformed);

        int[4] read;
        read[2] = -1;
        read[3] = -1;
        for (nuint i = 0u; i < parts.Length; i++)
        {
            if (ParseDecimal(parts[i]) is not Ok part)
                return Fail(ParseDecimal(parts[i]) is Fail(ParseError.OutOfRange) ? ParseError.OutOfRange : ParseError.Malformed);
            read[i] = part.Value;
        }
        return Ok(new Version(read[0], read[1], read[2], read[3]));
    }

    /// The parts that were given, joined by dots.
    public String ToString() => ToString(Revision >= 0 ? 4 : Build >= 0 ? 3 : 2);

    /// The first `fieldCount` parts, joined by dots. Aborts when that is more
    /// parts than there are.
    ///
    /// @param fieldCount  from 0 to 4
    public String ToString(int fieldCount)
    {
        int[4] all;
        all[0] = Major;
        all[1] = Minor;
        all[2] = Build;
        all[3] = Revision;

        if (fieldCount < 0 || fieldCount > 4 || (fieldCount > 0 && all[fieldCount - 1] < 0))
            sl_fail("Version.ToString: more fields than the version has");

        String text = "";
        for (int i = 0; i < fieldCount; i++)
            text += (i == 0 ? "" : ".") + Text.FromInteger((long)all[i]);
        return text;
    }

    /// Whether the two have the same parts.
    public bool Equals(Version other) =>
        Major == other.Major && Minor == other.Minor && Build == other.Build && Revision == other.Revision;

    /// Part by part, a missing part first.
    public int CompareTo(Version other)
    {
        if (Major != other.Major) return Major < other.Major ? -1 : 1;
        if (Minor != other.Minor) return Minor < other.Minor ? -1 : 1;
        if (Build != other.Build) return Build < other.Build ? -1 : 1;
        if (Revision != other.Revision) return Revision < other.Revision ? -1 : 1;
        return 0;
    }

    public nuint GetHashCode() =>
        MixHash(MixHash(MixHash(MixHash(0u, (ulong)Major), (ulong)Minor), (ulong)Build), (ulong)Revision);

    public static bool operator ==(Version left, Version right) => left.Equals(right);
    public static bool operator !=(Version left, Version right) => !left.Equals(right);
    public static bool operator <(Version left, Version right) => left.CompareTo(right) < 0;
    public static bool operator >(Version left, Version right) => left.CompareTo(right) > 0;
    public static bool operator <=(Version left, Version right) => left.CompareTo(right) <= 0;
    public static bool operator >=(Version left, Version right) => left.CompareTo(right) >= 0;
}
