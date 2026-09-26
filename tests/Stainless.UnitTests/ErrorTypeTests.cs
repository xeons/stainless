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
    [InlineData("SL0223", """

        module Clashes;
        Buffer Pick() // SL0273
        {
            return ;
        }
        """)]
    [InlineData("SL0262", """

        module Reaped;
        extern "C" int waitpid(int pid, int status, int options);
        const NoHang = 1;
        void StartAndDrop()
        {
        } int Main()
        { left = waitpid(1, &status, NoHang);
        }
        """)]
    [InlineData("SL0262", """

        module FixedArrays;
        double Total( Matrix matrix)
        {(FromNullTerminatedUtf16(&data[0]));
        }
        """)]
    [InlineData("SL0262", """

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
    [InlineData("SL0262", """

        module PortableResources;
        import Standard.Resources;
        int Main()
        { at = Resources.GetPointer(ResourceType.RcData, 301, &borrowed);
        }
        """)]
    [InlineData("SL0265", """

        module ErrArrow; struct Point
        {
        }
        int Main()
        {
            int* counted = &X;
        }
        """)]
    [InlineData("SL0265", """

        module LinuxTerminal; int Main()
        {
            int ep =(EPOLL_CLOEXEC);
            int seen = epoll_wait(ep);
            seen = (ep, &ready, 8, 2000);
        }
        """)]
    [InlineData("SL0281", """

        module Bad;
        partial Main() => 0;
        """)]
    [InlineData("SL0289", """

        module Bad; variant Shape
        {
            Rect(double Width, int[..] Height);
        }
        double Unchecked()
        {
        }
        Shape TooFew() =>Rect(1.0);
        """)]
    [InlineData("SL0305", """

        module Shop; interface IPriced
        {
            Money Price { get; }
        } class Book : IPriced
        {
        }
        """)]
    [InlineData("SL0305", """

        module Bad; interface IZero<Unit>
        {
            static abstract TSelf Zero { get; }
        } class Empty<Empty> { } struct Flat                              // SL0302
        {
        } class Counted : IZero<Counted>
        {
        }
        """)]
    [InlineData("SL0305", """

        module Bad; interface IShape { doublse Area(); } class Blob : IShape
        {
        }
        """)]
    [InlineData("SL0307", """

        module Shop; interface IPriced
        {
            Catalog Label { get; }
        } class Book : IPriced
        { String Label =>(_title);
        }
        """)]
    [InlineData("SL0344", """

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
    [InlineData("SL0361", """

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
    [InlineData("SL0361", """

        module ClosureStatics;
        import ClosureLibrary; delegate implicit Plain(int x);
        int Tripled() => 3;
        class Local
        { Plain Raw = Tripled;
        }
        """)]
    [InlineData("SL0377", """

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
    [InlineData("SL0377", """

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
    [InlineData("SL0446", """

        module Bad;
        void Reads(in Point p) { }
        int Main()
        {
            int k = 0;
            Reads(ref k);               // 'in' is not passed with 'ref'
        }
        """)]
    [InlineData("SL0447", """

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
    [InlineData("SL0471", """

        module Bad; struct PackedBits { void A : 3; int B : 5; }
        int Main()
        {
        }
        """)]
    [InlineData("SL0502", """

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
    [InlineData("SL0549", """

        module Bad; closure partial Notify(int value); class Publisher
        { event Notify Global;            // SL0550: nothing would unsubscribe
        }
        """)]
    [InlineData("SL0565", """

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
    [InlineData("SL0570", """

        module Bad;
        import Standard.Convert;
        ToLong< Other> Read(String text)
        {(try Convert.ToLong(text));
        }
        """)]
    [InlineData("SL0598", """

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
    [InlineData("SL0720", """

        module AsmX86;
        int Across(int a, int b, int c)
        {
            asm (in esi = &opaque_int[0], out eax = total)
            {
            }
        }
        """)]
    [InlineData("SL0730", """

        module PeSectionName; class Held
        {
            [Embed("logo.bin", Section = ".embedded_logo")] static byte[rsp ] Logo;
        }
        """)]
    [InlineData("SL0247", """

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
    [InlineData("SL0295", """

        module Other;
        extern "C" long
        [Align()]
        shared_depth;
        """, """

        module Bad;
        extern "C" int shared_depth;
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
}
