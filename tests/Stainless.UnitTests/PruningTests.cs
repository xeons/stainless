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

using Stainless.Emit;
using Stainless.Lowering;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// A library module's functions are emitted only when something emitted names
/// them; the program's own always are. Every module here is verified, which is
/// what says nothing named was left out.
/// </summary>
public class PruningTests
{
    private const string Library = """
        module Shapes;

        public interface IArea
        {
            double Area();
        }

        public class Shape
        {
            public virtual String Describe() => "a shape";
        }

        public class Square : Shape, IArea
        {
            public override String Describe() => "a square";
            public double Area() => SquareOf(2.0);
        }

        double SquareOf(double side) => side * side;

        public int Used(int value) => Doubled(value);

        int Doubled(int value) => value * 2;

        public int NeverCalled(int value) => value + 1;
        """;

    private const string Program = """
        module Test;

        import Shapes;

        int OwnButUncalled() => 7;

        public int Main()
        {
            var square = new Square();
            IArea area = square;
            double measured = area.Area();
            return Used(2);
        }
        """;

    private static string Pruned()
    {
        var program = Front.BindSources([Library, Program], out var diagnostics);
        Assert.False(diagnostics.HasErrors, string.Join("; ", diagnostics.Items.Select(d => d.Message)));

        return Front.Verified(
            new LlvmEmitter(prunedModules: new HashSet<string>(["Shapes"]))
                .Emit(Lowerer.Lower(program))
                .ReplaceLineEndings("\n"));
    }

    private static bool Defines(string ir, string fragment) =>
        ir.Split('\n').Any(line => line.StartsWith("define ", StringComparison.Ordinal) &&
                                   line.Contains(fragment, StringComparison.Ordinal));

    [Fact]
    public void ALibraryFunctionNothingCallsIsLeftOut()
    {
        Assert.False(Defines(Pruned(), "6Shapes11NeverCalled"));
    }

    [Fact]
    public void ALibraryFunctionTheProgramCallsIsEmittedWithWhatItCalls()
    {
        string ir = Pruned();

        Assert.True(Defines(ir, "6Shapes4Used"));
        Assert.True(Defines(ir, "6Shapes7Doubled"));
    }

    [Fact]
    public void AnOverrideReachedOnlyThroughItsVirtualTableIsEmitted()
    {
        Assert.True(Defines(Pruned(), "6Shapes6Square8Describe"));
    }

    [Fact]
    public void AMethodReachedOnlyThroughAnInterfaceIsEmittedWithWhatItCalls()
    {
        string ir = Pruned();

        Assert.True(Defines(ir, "6Shapes6Square4Area"));
        Assert.True(Defines(ir, "6Shapes8SquareOf"));
    }

    [Fact]
    public void TheProgramsOwnFunctionsAreEmittedWhetherCalledOrNot()
    {
        Assert.True(Defines(Pruned(), "4Test14OwnButUncalled"));
    }

    [Fact]
    public void NothingIsPrunedUnlessAModuleIsNamed()
    {
        var program = Front.BindSources([Library, Program], out _);
        string ir = new LlvmEmitter().Emit(Lowerer.Lower(program)).ReplaceLineEndings("\n");

        Assert.True(Defines(ir, "6Shapes11NeverCalled"));
    }
}
