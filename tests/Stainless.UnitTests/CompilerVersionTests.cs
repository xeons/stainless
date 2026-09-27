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

using System.Text.RegularExpressions;
using Stainless.Driver;
using Xunit;

namespace Stainless.UnitTests;

public class CompilerVersionTests
{
    [Fact]
    public void TheInformationalVersionIsTheNumberAndTheCommit()
    {
        Assert.Matches(new Regex(@"^\d+\.\d+\.\d+(\+[0-9a-f]{7,}(-dirty)?)?$"), CompilerVersion.Informational);
        Assert.StartsWith(CompilerVersion.Number, CompilerVersion.Informational, StringComparison.Ordinal);
    }

    [Fact]
    public void TheMajorAndMinorAreTheVersionPrefix()
    {
        string props = File.ReadAllText(Path.Combine(Repository.Root, "Directory.Build.props"));
        string prefix = Regex.Match(props, @"<VersionPrefix>([^<]+)</VersionPrefix>").Groups[1].Value;

        Assert.NotEmpty(prefix);
        Assert.StartsWith(prefix + ".", CompilerVersion.Number, StringComparison.Ordinal);
    }
}
