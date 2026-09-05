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

namespace Stainless.UnitTests;

/// <summary>
/// Where the repository is, for the tests that read it rather than a string.
///
/// Found by walking up from the test assembly until something that only the
/// repository has turns up. There is no environment variable to set and no
/// path to configure: a test that needed one would fail on the machine that
/// did not have it.
/// </summary>
public static class Repository
{
    public static string Root { get; } = Find();

    private static string Find()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "tests", "cases")))
                return directory.FullName;
            directory = directory.Parent;
        }

        throw new InvalidOperationException(
            "could not find the repository from " + AppContext.BaseDirectory);
    }
}
