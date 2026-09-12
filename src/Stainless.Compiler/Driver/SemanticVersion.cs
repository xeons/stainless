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

using System.Globalization;

namespace Stainless.Driver;

/// <summary>
/// A package's version, in the shape semver gave the word.
///
/// This is a promise a person makes, and it is worth being clear about what it
/// is not: nothing here proves that 1.2.3 lays a class out the way 1.2.2 did.
/// A human decides what to call a release, and a human can be wrong about it.
/// <see cref="AbiDigest"/> is the other half -- a fact the compiler computes
/// from the layouts themselves -- and the two answer different questions. This
/// one answers "should I take the upgrade"; that one answers "is this binary
/// the one I compiled against".
/// </summary>
public sealed record SemanticVersion : IComparable<SemanticVersion>
{
    public required int Major { get; init; }
    public required int Minor { get; init; }
    public required int Patch { get; init; }

    /// <summary>
    /// The dot-separated identifiers after a '-', or empty for a release.
    ///
    /// A prerelease sorts *below* the release it leads to, which is the one
    /// rule about it that surprises people: 1.0.0-alpha is older than 1.0.0.
    /// </summary>
    public IReadOnlyList<string> PreRelease { get; init; } = [];

    /// <summary>
    /// Whatever followed a '+'. Kept so a version round-trips as written, and
    /// ignored everywhere else: semver says build metadata has no bearing on
    /// which version is newer, and two versions differing only here are the
    /// same version.
    /// </summary>
    public string Build { get; init; } = "";

    public bool IsPreRelease => PreRelease.Count > 0;

    public static bool TryParse(string text, out SemanticVersion? version, out string error)
    {
        version = null;
        error = "";

        string rest = text.Trim();
        if (rest.Length == 0)
        {
            error = "a version cannot be empty";
            return false;
        }

        string build = "";
        int plus = rest.IndexOf('+');
        if (plus >= 0)
        {
            build = rest[(plus + 1)..];
            rest = rest[..plus];
        }

        string[] pre = [];
        int dash = rest.IndexOf('-');
        if (dash >= 0)
        {
            string tail = rest[(dash + 1)..];
            rest = rest[..dash];

            if (tail.Length == 0)
            {
                error = $"'{text}' has a '-' with no prerelease after it";
                return false;
            }

            pre = tail.Split('.');
            foreach (string identifier in pre)
                if (identifier.Length == 0)
                {
                    error = $"'{text}' has an empty prerelease identifier";
                    return false;
                }
        }

        string[] parts = rest.Split('.');
        if (parts.Length != 3)
        {
            error = $"'{text}' is not a version; a version is three numbers, as in '1.2.3'";
            return false;
        }

        var numbers = new int[3];
        for (int i = 0; i < 3; i++)
        {
            if (!int.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out numbers[i]))
            {
                error = $"'{text}' is not a version; '{parts[i]}' is not a number";
                return false;
            }
        }

        version = new SemanticVersion
        {
            Major = numbers[0],
            Minor = numbers[1],
            Patch = numbers[2],
            PreRelease = pre,
            Build = build,
        };
        return true;
    }

    public static SemanticVersion Parse(string text) =>
        TryParse(text, out var version, out string error)
            ? version!
            : throw new FormatException(error);

    public int CompareTo(SemanticVersion? other)
    {
        if (other is null) return 1;

        int order = Major.CompareTo(other.Major);
        if (order != 0) return order;
        order = Minor.CompareTo(other.Minor);
        if (order != 0) return order;
        order = Patch.CompareTo(other.Patch);
        if (order != 0) return order;

        // A release outranks any prerelease of the same numbers.
        if (PreRelease.Count == 0) return other.PreRelease.Count == 0 ? 0 : 1;
        if (other.PreRelease.Count == 0) return -1;

        for (int i = 0; i < Math.Min(PreRelease.Count, other.PreRelease.Count); i++)
        {
            order = ComparePreRelease(PreRelease[i], other.PreRelease[i]);
            if (order != 0) return order;
        }

        // A longer run of identifiers wins when the shared prefix is equal:
        // alpha.1 is newer than alpha.
        return PreRelease.Count.CompareTo(other.PreRelease.Count);
    }

    /// <summary>
    /// Numeric identifiers compare as numbers and rank below alphanumeric ones;
    /// everything else compares as ASCII. That is semver's rule, and it is what
    /// puts rc above beta above alpha without anyone having to say so.
    /// </summary>
    private static int ComparePreRelease(string left, string right)
    {
        bool leftNumeric = IsNumeric(left);
        bool rightNumeric = IsNumeric(right);

        if (leftNumeric && rightNumeric)
            return ulong.Parse(left, CultureInfo.InvariantCulture)
                .CompareTo(ulong.Parse(right, CultureInfo.InvariantCulture));

        if (leftNumeric) return -1;
        if (rightNumeric) return 1;

        return string.CompareOrdinal(left, right);
    }

    private static bool IsNumeric(string text) =>
        text.Length > 0 && text.All(char.IsAsciiDigit);

    public bool Equals(SemanticVersion? other) => CompareTo(other) == 0;

    public override int GetHashCode() =>
        HashCode.Combine(Major, Minor, Patch, string.Join('.', PreRelease));

    public static bool operator <(SemanticVersion a, SemanticVersion b) => a.CompareTo(b) < 0;
    public static bool operator >(SemanticVersion a, SemanticVersion b) => a.CompareTo(b) > 0;
    public static bool operator <=(SemanticVersion a, SemanticVersion b) => a.CompareTo(b) <= 0;
    public static bool operator >=(SemanticVersion a, SemanticVersion b) => a.CompareTo(b) >= 0;

    public override string ToString()
    {
        string text = $"{Major}.{Minor}.{Patch}";
        if (PreRelease.Count > 0) text += "-" + string.Join('.', PreRelease);
        if (Build.Length > 0) text += "+" + Build;
        return text;
    }
}
