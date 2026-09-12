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

namespace Stainless.Driver;

/// <summary>
/// What a dependency will accept: a range of versions, written the way every
/// other package manager writes one.
///
/// A bare version means the caret: <c>1.2.0</c> is <c>^1.2.0</c>, which takes
/// any later release that promises to be compatible. That follows Cargo rather
/// than npm, and the reason to pick a side is that the bare spelling is the one
/// people type -- so it should mean the thing they almost always want, rather
/// than pinning a patch release for ever by accident. <c>=1.2.0</c> is how to
/// say the other thing.
///
/// Several clauses separated by commas are ANDed together.
/// </summary>
public sealed record VersionRequirement
{
    /// <summary>The text this was parsed from, so a diagnostic can quote it.</summary>
    public required string Text { get; init; }

    /// <summary>
    /// The bounds, ANDed together. Internal rather than private because a
    /// record's own copy constructor reaches it; not 'required', because a
    /// required member may not be less visible than the type holding it.
    /// Nothing outside this assembly can name <see cref="Clause"/> anyway,
    /// which is what actually keeps the shape closed.
    ///
    /// Empty means every version, which is what <see cref="Any"/> is.
    /// </summary>
    internal IReadOnlyList<Clause> Clauses { get; init; } = [];

    /// <summary>Accepts every version there is.</summary>
    public static VersionRequirement Any { get; } = new() { Text = "*", Clauses = [] };

    internal sealed record Clause(Comparison Op, SemanticVersion Version);

    internal enum Comparison { Equal, Greater, GreaterOrEqual, Less, LessOrEqual }

    public static bool TryParse(string text, out VersionRequirement? requirement, out string error)
    {
        requirement = null;
        error = "";

        string trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            error = "a version requirement cannot be empty";
            return false;
        }

        if (trimmed is "*" or "any")
        {
            requirement = Any with { Text = trimmed };
            return true;
        }

        var clauses = new List<Clause>();

        foreach (string part in trimmed.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            string clause = part.Trim();
            if (clause.Length == 0) continue;
            if (!TryParseClause(clause, clauses, out error)) return false;
        }

        if (clauses.Count == 0)
        {
            error = $"'{text}' is not a version requirement";
            return false;
        }

        requirement = new VersionRequirement { Text = trimmed, Clauses = clauses };
        return true;
    }

    /// <summary>Longest operator first, so '>=' is never read as '>'.</summary>
    private static readonly (string Prefix, Comparison Op)[] Operators =
    [
        (">=", Comparison.GreaterOrEqual),
        ("<=", Comparison.LessOrEqual),
        ("==", Comparison.Equal),
        (">", Comparison.Greater),
        ("<", Comparison.Less),
        ("=", Comparison.Equal),
    ];

    private static bool TryParseClause(string clause, List<Clause> into, out string error)
    {
        error = "";

        foreach (var (prefix, op) in Operators)
        {
            if (!clause.StartsWith(prefix, StringComparison.Ordinal)) continue;

            if (!TryParsePartial(clause[prefix.Length..].Trim(), out var version, out _, out error))
                return false;

            into.Add(new Clause(op, version!));
            return true;
        }

        char shorthand = clause[0];
        string rest = shorthand is '^' or '~' ? clause[1..].Trim() : clause;

        if (!TryParsePartial(rest, out var bound, out int given, out error)) return false;

        into.Add(new Clause(Comparison.GreaterOrEqual, bound!));
        into.Add(new Clause(Comparison.Less, Ceiling(bound!, shorthand, given)));
        return true;
    }

    /// <summary>
    /// Where a caret or a tilde stops.
    ///
    /// The caret keeps the leftmost non-zero number: <c>^1.2.3</c> accepts 1.9
    /// and not 2.0, and <c>^0.2.3</c> accepts 0.2.9 and not 0.3.0 -- because
    /// below 1.0 the minor is doing the major's job, which is a convention every
    /// registry has converged on. The tilde keeps the minor whatever the numbers
    /// are.
    /// </summary>
    private static SemanticVersion Ceiling(SemanticVersion bound, char shorthand, int given)
    {
        var release = bound with { PreRelease = [], Build = "" };

        // '~1.2.3' and '~1.2' both mean the 1.2 series; '~1' means the whole of
        // 1. What differs is how many numbers were actually written.
        if (shorthand == '~')
            return given >= 2
                ? release with { Minor = release.Minor + 1, Patch = 0 }
                : release with { Major = release.Major + 1, Minor = 0, Patch = 0 };

        if (release.Major > 0)
            return release with { Major = release.Major + 1, Minor = 0, Patch = 0 };

        if (release.Minor > 0)
            return release with { Minor = release.Minor + 1, Patch = 0 };

        // ^0.0.3 is the strictest case there is: nothing with a zero major and a
        // zero minor claims compatibility with anything, so only that patch matches.
        return release with { Patch = release.Patch + 1 };
    }

    /// <summary>
    /// Reads '1', '1.2' or '1.2.3', filling the missing numbers with zero and
    /// reporting how many were actually written -- which is what tells a tilde
    /// whether it was given a minor to hold on to.
    /// </summary>
    private static bool TryParsePartial(
        string text, out SemanticVersion? version, out int given, out string error)
    {
        version = null;
        given = 0;
        error = "";

        string core = text;
        string tail = "";

        int cut = core.IndexOfAny(['-', '+']);
        if (cut >= 0)
        {
            tail = core[cut..];
            core = core[..cut];
        }

        given = core.Split('.').Length;

        string padded = given switch
        {
            1 => core + ".0.0",
            2 => core + ".0",
            _ => core,
        };

        return SemanticVersion.TryParse(padded + tail, out version, out error);
    }

    /// <summary>
    /// Whether a version is acceptable.
    ///
    /// A prerelease is only ever matched by a requirement that named one with
    /// the same three numbers. Without that rule '^1.0.0' would quietly take
    /// '2.0.0-alpha', because it compares below 2.0.0 -- which is true, and is
    /// not what anybody means by it.
    /// </summary>
    public bool Accepts(SemanticVersion version)
    {
        if (Clauses.Count == 0) return true;

        if (version.IsPreRelease && !Clauses.Any(c =>
                c.Version.IsPreRelease &&
                c.Version.Major == version.Major &&
                c.Version.Minor == version.Minor &&
                c.Version.Patch == version.Patch))
            return false;

        foreach (var clause in Clauses)
        {
            int order = version.CompareTo(clause.Version);

            bool ok = clause.Op switch
            {
                Comparison.Equal => order == 0,
                Comparison.Greater => order > 0,
                Comparison.GreaterOrEqual => order >= 0,
                Comparison.Less => order < 0,
                Comparison.LessOrEqual => order <= 0,
                _ => false,
            };

            if (!ok) return false;
        }

        return true;
    }

    public override string ToString() => Text;
}
