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

using Stainless.Driver;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// What a link failure is explained as. The explanation decides where the
/// reader goes looking, so the one thing it must not do is name a cause the
/// program does not have: a Stainless function missing because its library was
/// not linked was once blamed on an <c>extern "C"</c> nobody had written.
/// </summary>
public class LinkDiagnosisTests
{
    private const string MissingStainless =
        "lld-link: error: undefined symbol: _SL3Lib5TotalS15Standard_int___Ei\n" +
        ">>> referenced by app.o:(main)";

    private const string MissingC =
        "lld-link: error: undefined symbol: sqlite3_open\n>>> referenced by app.o:(main)";

    [Fact]
    public void AStainlessNameIsNotCalledExternC()
    {
        string text = LinkDiagnosis.Explain(MissingStainless, "app.ll");

        Assert.DoesNotContain("extern \"C\"", text);
        Assert.Contains("Stainless", text);
        Assert.DoesNotContain("compiler bug", text);
    }

    [Fact]
    public void AReferenceWithNoLibraryBesideItIsNamed()
    {
        string text = LinkDiagnosis.Explain(MissingStainless, "app.ll", ["Lib.dll"]);

        Assert.Contains("'Lib.dll'", text);
        Assert.DoesNotContain("extern \"C\"", text);
    }

    [Fact]
    public void ACNameStillIsExternC()
    {
        string text = LinkDiagnosis.Explain(MissingC, "app.ll");

        Assert.Contains("extern \"C\"", text);
        Assert.DoesNotContain("'_SL'", text);
    }

    [Theory]
    // i686 Windows puts the target's own underscore in front of the mangled one.
    [InlineData("lld-link: error: undefined symbol: __SL3Lib5TotalS15Standard_int___Ei")]
    [InlineData("app.c:(.text+0x1c): undefined reference to `_SL3Lib5TotalS15Standard_int___Ei'")]
    [InlineData("error LNK2019: unresolved external symbol _SL3Lib5TotalS15Standard_int___Ei referenced in function main")]
    public void EveryLinkerSpellingIsRead(string output) =>
        Assert.DoesNotContain("extern \"C\"", LinkDiagnosis.Explain(output, "app.ll"));

    [Fact]
    public void BothAreExplainedWhenBothAreMissing()
    {
        string text = LinkDiagnosis.Explain(MissingStainless + "\n" + MissingC, "app.ll");

        Assert.Contains("extern \"C\"", text);
        Assert.Contains("'_SL'", text);
    }

    [Fact]
    public void AnythingElseIsStillTheCompilers()
    {
        string text = LinkDiagnosis.Explain("error: invalid IR", "app.ll");
        Assert.Contains("compiler bug", text);
    }
}
