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

using Stainless.Source;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// What a name that did not resolve became is reported once, where it
/// happened. Everything that later meets the error type says nothing about it,
/// because the place reporting names the types it is about and one of them
/// stands for that error.
/// </summary>
public class ErrorTypeTests
{
    /// <summary>
    /// Programs the fuzzer found each naming the error type in a message the
    /// given code would otherwise have reported, and which a debug build now
    /// stops on as a compiler bug.
    /// </summary>
    [Theory]
    [InlineData("SLF0002", """

        module Clashes;
        Buffer Pick() // SLN0015
        {
            return ;
        }
        """)]
    [InlineData("SLT0015", """

        module Reaped;
        extern "C" int waitpid(int pid, int status, int options);
        const NoHang = 1;
        void StartAndDrop()
        {
        } int Main()
        { left = waitpid(1, &status, NoHang);
        }
        """)]
    [InlineData("SLT0015", """

        module FixedArrays;
        double Total( Matrix matrix)
        {(FromNullTerminatedUtf16(&data[0]));
        }
        """)]
    [InlineData("SLT0015", """

        module ComShell; extern "C"
        {
            int  SHCreateItemFromParsingName(char16 path, byte bindContext,
                                             Guid iid, byte** result);
        } com interface IShellItem
        {
        } void Main()
        { hr = SHCreateItemFromParsingName(
                "C:\\Windows".ToPointer(), null, iidof(IShellItem), &raw);
            {
            }
        }
        """)]
    [InlineData("SLT0015", """

        module PortableResources;
        import Standard.Resources;
        int Main()
        { at = Resources.GetPointer(ResourceType.RcData, 301, &borrowed);
        }
        """)]
    [InlineData("SLT0018", """

        module ErrArrow; struct Point
        {
        }
        int Main()
        {
            int* counted = &X;
        }
        """)]
    [InlineData("SLT0018", """

        module LinuxTerminal; int Main()
        {
            int ep =(EPOLL_CLOEXEC);
            int seen = epoll_wait(ep);
            seen = (ep, &ready, 8, 2000);
        }
        """)]
    [InlineData("SLD0002", """

        module Bad;
        partial Main() => 0;
        """)]
    [InlineData("SLT0022", """

        module Bad; variant Shape
        {
            Rect(double Width, int[..] Height);
        }
        double Unchecked()
        {
        }
        Shape TooFew() =>Rect(1.0);
        """)]
    [InlineData("SLC0013", """

        module Shop; interface IPriced
        {
            Money Price { get; }
        } class Book : IPriced
        {
        }
        """)]
    [InlineData("SLC0013", """

        module Bad; interface IZero<Unit>
        {
            static abstract TSelf Zero { get; }
        } class Empty<Empty> { } struct Flat                              // SLC0010
        {
        } class Counted : IZero<Counted>
        {
        }
        """)]
    [InlineData("SLC0013", """

        module Bad; interface IShape { doublse Area(); } class Blob : IShape
        {
        }
        """)]
    [InlineData("SLC0015", """

        module Shop; interface IPriced
        {
            Catalog Label { get; }
        } class Book : IPriced
        { String Label =>(_title);
        }
        """)]
    [InlineData("SLC0020", """

        module NamedArguments; attribute Column
        {
            i Name;
            int Width;
        } class Row
        {
            [Column("full_name", Width = 32)] String Postcode;
        }
        int Main()
        {
            {(
                                  $"hidden {column.GetNumber(2u)}{Source(column, 2u)}");
            }
        }
        """)]
    [InlineData("SLT0032", """

        module Control; closure void SearchRequested(prompt text); class SearchBox
        { SearchBox(String prompt)
            {
            } void SetEnabled()
            {
            } void OnSearch(SearchRequested handler)
            {
            }
            void RunSearch
            {
            }
        }
        class Results
        { Results(Label into)
            {
            } void AddResult()
            {
            }
        } int Main()
        {
            var search = new SearchBox("search terms");
            var found = Label();
            var results = new Results(found);
            search.OnSearch(results.AddResult);(() =>
            {(text);
            });
        }
        """)]
    [InlineData("SLT0032", """

        module ClosureStatics;
        import ClosureLibrary; delegate implicit Plain(int x);
        int Tripled() => 3;
        class Local
        { Plain Raw = Tripled;
        }
        """)]
    [InlineData("SLO0015", """

        module StaticsReadInside;
        static i<int> s_maybe = Optional();
        class Looped
        { Looped()
            {
                {
                }
                switch (s_name())
                {
                    case 5:
                }
            }
        } int Main()
        {
        }
        """)]
    [InlineData("SLO0015", """

        module Bad;
        int Taken(Payload payload)
        {
            switch (payload)
            {
            }
        }
        int Main()
        {
            Payload payload =(1);
            parallel
            {
                spawn Taken(payload);
            }
        }
        """)]
    [InlineData("SLT0044", """

        module Bad;
        void Reads(in Point p) { }
        int Main()
        {
            int k = 0;
            Reads(ref k);               // 'in' is not passed with 'ref'
        }
        """)]
    [InlineData("SLT0045", """

        module Bad;
        void Spoil(ref r<int, String> r) { r =("spoiled"); }
        void ByReference()
        {
            Result<int, String> r =(3);
            {
                Spoil(ref r);
            }
        }
        void InALaterOperand()
        {
        }
        """)]
    [InlineData("SLI0013", """

        module Bad; struct PackedBits { void A : 3; int B : 5; }
        int Main()
        {
        }
        """)]
    [InlineData("SLC0042", """

        module CovariantReturns; interface Puppy
        {
        } class IShape
        {
        } class DogShelter
        { override Console Adopt() =>("rex");
        } class PuppyShelter : DogShelter
        { override Puppy Adopt() =>("bit");
        } class Pen<T> : Shelter where T : Animal
        {
        }
        int Main()
        {
        }
        """)]
    [InlineData("SLC0118", """

        module Bad; closure partial Notify(int value); class Publisher
        { event Notify Global;            // SLC0119: nothing would unsubscribe
        }
        """)]
    [InlineData("SLT0063", """

        module ExpressionBodied;
        interface IArea
        {
        }
        struct Money
        { static Money Of(long cents)
            {
            } static Money operator +(Money a, square b) =>(a);
        }
        int Main()
        { total = Money.Of(30) + Money.Of(12);
        }
        """)]
    [InlineData("SLF0022", """

        module Bad;
        import Standard.Convert;
        ToLong< Other> Read(String text)
        {(try Convert.ToLong(text));
        }
        """)]
    [InlineData("SLT0044", """

        module NarrowingWritten; class Node { int V = 1; }
        void Fill(out ? n) { n = Node(); }
        void Take(Node p)
        {
            {
            }
            Node k = null;
            {
                Fill(out k);
            }
        }
        """)]
    [InlineData("SLI0045", """

        module AsmX86;
        int Across(int a, int b, int c)
        {
            asm (in esi = &opaque_int[0], out eax = total)
            {
            }
        }
        """)]
    [InlineData("SLD0020", """

        module PeSectionName; class Held
        {
            [Embed("logo.bin", Section = ".embedded_logo")] static byte[rsp ] Logo;
        }
        """)]
    [InlineData("SLN0013", """

        module Bad; variant Shape
        {
            Shape(double Radius);
            Rect(doubl Width, double Height);
        }
        double WrongCase(Shape shape)
        {
            if (shape.Circle);
        }
        """)]
    [InlineData("SLI0004", """

        module Other;
        extern "C" long
        [Align()]
        shared_depth;
        """, """

        module Bad;
        extern "C" int shared_depth;
        int Main() => 0;
        """)]
    [InlineData("SLC0015", """

        module Nested; interface IWritable
        {
            void Write(source text);
        } class Slot : IWritable
        { public void Write(String text) { }
        }
        int Main() => 0;
        """)]
    [InlineData("SLC0015", """

        module Nested; interface IWritable
        {
            void Write(source text);
        } class Slot : IWritable
        { void IWritable.Write(String text) { }
        }
        int Main() => 0;
        """)]
    [InlineData("SLC0042", """

        module Overrides; class Base
        {
            public virtual void Write(source text) { }
        } class Derived : Base
        { public override void Write(String text) { }
        }
        int Main() => 0;
        """)]
    public void AConsequenceIsNotReported(string code, params string[] sources)
    {
        Front.BindSources(sources, out var diagnostics);

        var named = diagnostics.Items
            .Where(d => d.Message.Contains(DiagnosticBag.ErrorTypeName, StringComparison.Ordinal))
            .Select(d => d.Code);
        Assert.DoesNotContain(code, named);
    }

    /// <summary>
    /// A body is bound again when a local function learns a capture late, and
    /// what the first round reported is taken back. An instantiation made in
    /// that round is cached, so what it reported MUST survive the rewind.
    /// </summary>
    [Fact]
    public void AnInstantiationsErrorSurvivesARebind()
    {
        Front.BindSources(["""
            module Rebound;
            closure int Weigher<T>(Missing item);
            T First<T>(T[] items, Weigher<T> weigh) => items[0];
            int Main()
            {
                int limit = 1;
                bool IsEven(int n) => n < limit && IsOdd(n);
                bool IsOdd(int n) => IsEven(n);
                int[] weights = [5];
                return First(weights, w => w);
            }
            """], out var diagnostics);

        Assert.Contains(diagnostics.Items, d => d.Code == "SLN0017");
    }
}
