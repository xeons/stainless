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

using Xunit;

namespace Stainless.UnitTests;

// DiagnosticTests.CheckFailingCase over each quarter of the failing cases.
// Four classes because the runner runs a class's tests one after another and
// classes side by side.

public class FailingCasesFirst
{
    [Theory]
    [MemberData(nameof(DiagnosticTests.FailingCases), 0, DiagnosticTests.FailingCaseShards,
                MemberType = typeof(DiagnosticTests))]
    public void NoFailingCaseNamesTheErrorType(string name) => DiagnosticTests.CheckFailingCase(name);
}

public class FailingCasesSecond
{
    [Theory]
    [MemberData(nameof(DiagnosticTests.FailingCases), 1, DiagnosticTests.FailingCaseShards,
                MemberType = typeof(DiagnosticTests))]
    public void NoFailingCaseNamesTheErrorType(string name) => DiagnosticTests.CheckFailingCase(name);
}

public class FailingCasesThird
{
    [Theory]
    [MemberData(nameof(DiagnosticTests.FailingCases), 2, DiagnosticTests.FailingCaseShards,
                MemberType = typeof(DiagnosticTests))]
    public void NoFailingCaseNamesTheErrorType(string name) => DiagnosticTests.CheckFailingCase(name);
}

public class FailingCasesFourth
{
    [Theory]
    [MemberData(nameof(DiagnosticTests.FailingCases), 3, DiagnosticTests.FailingCaseShards,
                MemberType = typeof(DiagnosticTests))]
    public void NoFailingCaseNamesTheErrorType(string name) => DiagnosticTests.CheckFailingCase(name);
}