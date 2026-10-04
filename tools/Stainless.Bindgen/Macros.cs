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

using System.Text;
using System.Text.RegularExpressions;

namespace Stainless.Bindgen;

/// <summary>
/// A framework's <c>#define</c> constants, which the AST does not hold.
///
/// <c>clang -E -dD</c> lists every definition with the file it was written
/// in. Each candidate is then asked of clang in the same translation unit as
/// the headers: <c>enum { v = (NAME) };</c> folds an integer constant to its
/// value, and <c>__typeof__((NAME)) t;</c> says what type it is. A macro that
/// is not an expression fails both and is not a constant.
/// </summary>
public static partial class Macros
{
    public const string ValuePrefix = "__sl_macro_value_";
    public const string TypePrefix = "__sl_macro_type_";

    /// <summary>The object-like definitions <c>-E -dD</c> wrote, each with the file it came from.</summary>
    public static List<(string Name, string File, string Body)> ReadDefinitions(string output)
    {
        var definitions = new List<(string, string, string)>();
        string file = "";

        foreach (string line in output.Split('\n'))
        {
            if (line.StartsWith("# ", StringComparison.Ordinal))
            {
                var marker = LineMarker().Match(line);
                if (marker.Success) file = marker.Groups[1].Value;
                continue;
            }

            if (!line.StartsWith("#define ", StringComparison.Ordinal)) continue;

            var definition = Definition().Match(line);
            if (!definition.Success) continue;

            string name = definition.Groups[1].Value;
            string body = definition.Groups[2].Value.Trim();
            if (IsCandidate(name, body)) definitions.Add((name, file, body));
        }

        return definitions;
    }

    [GeneratedRegex(@"^# \d+ ""([^""]*)""")]
    private static partial Regex LineMarker();

    /// <summary><c>#define NAME body</c>, and not <c>#define NAME(x) body</c>.</summary>
    [GeneratedRegex(@"^#define ([A-Za-z_][A-Za-z0-9_]*)(?:\s+(.*))?$")]
    private static partial Regex Definition();

    /// <summary>
    /// Whether a definition could be a constant at all: it has a body, is not
    /// the implementation's, and is not plainly an attribute or a statement.
    /// </summary>
    private static bool IsCandidate(string name, string body) =>
        body.Length > 0 &&
        !name.StartsWith("__", StringComparison.Ordinal) &&
        !body.Contains("__attribute__", StringComparison.Ordinal) &&
        !body.Contains('{') && !body.Contains(';') && !body.Contains('#') &&
        !Regex.IsMatch(body, @"\b(extern|static|inline|typedef|__declspec|struct|union|enum)\b");

    /// <summary>The lines that ask clang what each candidate is, numbered as the candidates are.</summary>
    public static string Probe(IReadOnlyList<(string Name, string File, string Body)> definitions)
    {
        var probe = new StringBuilder();
        for (int i = 0; i < definitions.Count; i++)
        {
            string name = definitions[i].Name;
            probe.Append($"enum {{ {ValuePrefix}{i} = ({name}) }};\n");
            probe.Append($"__typeof__(({name})) {TypePrefix}{i};\n");
        }

        return probe.ToString();
    }

    /// <summary>
    /// Each candidate with the type and value clang gave it, read from the
    /// probe's declarations in <paramref name="translation"/>.
    /// </summary>
    public static IEnumerable<CMacro> Resolve(
        Translation translation, IReadOnlyList<(string Name, string File, string Body)> definitions)
    {
        var values = new Dictionary<int, System.Numerics.BigInteger>();
        var types = new Dictionary<int, CType>();

        foreach (var declaration in translation.Declarations)
        {
            if (declaration is CEnumDecl enumeration)
                foreach (var member in enumeration.Members.Where(m => m.IsWritten && m.Name.StartsWith(ValuePrefix, StringComparison.Ordinal)))
                    values[int.Parse(member.Name[ValuePrefix.Length..], System.Globalization.CultureInfo.InvariantCulture)] = member.Value;

            if (declaration is CVariableDecl variable && variable.Name.StartsWith(TypePrefix, StringComparison.Ordinal))
                types[int.Parse(variable.Name[TypePrefix.Length..], System.Globalization.CultureInfo.InvariantCulture)] = variable.Type;
        }

        for (int i = 0; i < definitions.Count; i++)
        {
            if (!types.TryGetValue(i, out var type)) continue;
            var (name, file, body) = definitions[i];
            yield return new CMacro(name, file, body)
            {
                Type = type,
                Value = values.TryGetValue(i, out var value) ? value : null,
            };
        }
    }
}
