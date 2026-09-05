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

using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// <c>Standard.Threading</c>, from the compiler's side.
///
/// What the end-to-end case in <c>tests/cases/threading-classic</c> proves is
/// that the primitives behave: a semaphore limits, a barrier rendezvouses, a
/// guard unlocks. What it cannot prove is what the compiler *refuses*, because
/// a program that does not compile produces no output to compare -- so the
/// rules live here.
///
/// The rule that matters most: a synchronization primitive is
/// <c>[Shared]</c> and may therefore be a <c>static readonly</c>, which is
/// the only place an unstructured thread can reach anything. A guard is not,
/// because a guard belongs to the thread holding it.
/// </summary>
public class ThreadingTests
{
    private static string[] Module(string body) =>
        Front.ModuleCodes("import Standard.Threading;\n" + body);

    /// <summary>
    /// A function body, with the import where an import goes.
    ///
    /// <c>Front.BodyCodes</c> would put it inside <c>Main</c>, which is not
    /// where an import may be.
    /// </summary>
    private static string[] Body(string body) =>
        Module("int Main()\n{\n" + body + "\n    return 0;\n}");

    // ------------------------------------------- what may be a shared static

    [Theory]
    [InlineData("AtomicLong", "new AtomicLong(0)")]
    [InlineData("AtomicInt", "new AtomicInt(0)")]
    [InlineData("AtomicBool", "new AtomicBool(false)")]
    [InlineData("Mutex<long>", "new Mutex<long>(0)")]
    [InlineData("Monitor<long>", "new Monitor<long>(0)")]
    [InlineData("RwLock<long>", "new RwLock<long>(0)")]
    [InlineData("Semaphore", "new Semaphore(1)")]
    [InlineData("ManualResetEvent", "new ManualResetEvent(false)")]
    [InlineData("AutoResetEvent", "new AutoResetEvent(false)")]
    [InlineData("CountdownEvent", "new CountdownEvent(1)")]
    [InlineData("Barrier", "new Barrier(2u)")]
    public void ASynchronizedTypeMayBeAStatic(string type, string initializer)
    {
        Assert.Empty(Module($"static readonly {type} Value = {initializer};"));
    }

    /// <summary>
    /// And the ones that belong to one thread may not be.
    ///
    /// A guard is proof that *this* thread holds a lock, so a second thread
    /// reaching the same guard would be holding a lock it never took. A
    /// <c>Thread</c> handle is single-owner for the same reason a file handle
    /// is: two threads joining it would both free it.
    /// </summary>
    [Theory]
    [InlineData("Guard<long>")]
    [InlineData("MonitorGuard<long>")]
    [InlineData("ReadGuard<long>")]
    [InlineData("WriteGuard<long>")]
    [InlineData("SpinWait")]
    public void AThreadOwnedTypeMayNotBeAStatic(string type)
    {
        // The initializer is irrelevant -- the type is refused before it is
        // reached -- so a null one keeps each case to the thing being tested.
        Assert.Contains("SL0377", Module($"static readonly {type}? Value = null;"));
    }

    // --------------------------------------------------------- the surface

    /// <summary>
    /// Every method the library documents is actually callable.
    ///
    /// A stdlib type that binds proves only that its own body typechecks. This
    /// calls each one the way a program would, which is what catches an
    /// argument type that reads correctly and does not resolve.
    /// </summary>
    [Theory]
    [InlineData("var m = new Monitor<long>(0); var g = m.Lock(); g.Set(1); g.Pulse(); g.PulseAll();")]
    [InlineData("var m = new Monitor<long>(0); var g = m.Lock(); bool b = g.WaitFor(1u); long v = g.Value();")]
    [InlineData("var l = new RwLock<long>(0); var r = l.Read(); long v = r.Value();")]
    [InlineData("var l = new RwLock<long>(0); var w = l.Write(); w.Set(1);")]
    [InlineData("var l = new RwLock<long>(0); var r = l.TryRead(); var w = l.TryWrite();")]
    [InlineData("var s = new Semaphore(2); s.Wait(); s.Release(); s.ReleaseMany(2); bool t = s.TryWait();")]
    [InlineData("var s = new Semaphore(2); bool got = s.WaitFor(1u); long free = s.Available();")]
    [InlineData("var e = new ManualResetEvent(false); e.Set(); e.Wait(); e.Reset(); bool s = e.IsSet();")]
    [InlineData("var e = new AutoResetEvent(false); e.Set(); bool got = e.WaitFor(1u);")]
    [InlineData("var c = new CountdownEvent(2); bool last = c.Signal(); bool grew = c.TryAddCount(1); c.Wait();")]
    [InlineData("var c = new CountdownEvent(2); long left = c.CurrentCount(); bool ok = c.WaitFor(1u);")]
    [InlineData("var b = new Barrier(2u); long phase = b.SignalAndWait(); nuint n = b.ParticipantCount();")]
    [InlineData("var a = new AtomicLong(0); a.And(1); a.Or(2); a.Xor(3); a.Exchange(4);")]
    [InlineData("var a = new AtomicInt(0); a.Increment(); a.Decrement(); a.Add(2); bool ok = a.CompareExchange(0, 1);")]
    [InlineData("var s = new SpinWait(); s.Once(); nuint n = s.Count(); s.Reset();")]
    [InlineData("Threading.Sleep(1u); Threading.Yield(); nuint id = Threading.CurrentId();")]
    public void TheSurfaceResolves(string body)
    {
        Assert.Empty(Body(body));
    }

    /// <summary>
    /// A thread takes a plain function pointer, not a method and not a
    /// closure. That is what makes it a C thread entry with nothing in
    /// between, and it is why the argument is a <c>byte*</c>.
    /// </summary>
    [Fact]
    public void AThreadTakesAJobAndAPointer()
    {
        Assert.Empty(Module("""
            void Work(byte* argument) { }

            int Main() {
                var thread = new Thread(Work, null);
                bool live = thread.IsJoinable();
                thread.Join();
                thread.Detach();
                return 0;
            }
            """));
    }

    /// <summary>
    /// A guard is released by its scope, and there is no way to put one down
    /// early: assigning null to a non-nullable reference is refused, which is
    /// what pushes the release into a block where it belongs.
    /// </summary>
    [Fact]
    public void AGuardCannotBeDroppedByAssigningNull()
    {
        Assert.Contains("SL0265", Body("""
            var mutex = new Mutex<long>(0);
            var guard = mutex.Lock();
            guard = null;
            """));
    }

    /// <summary>
    /// <c>Monitor</c> is the library's, not a keyword and not the compiler's:
    /// a program may shadow it, as it may shadow any imported name.
    /// </summary>
    [Fact]
    public void MonitorIsAnOrdinaryName()
    {
        Assert.Empty(Module("""
            public class Monitor { public int Depth() { return 1; } }

            int Main() { return new Monitor().Depth() - 1; }
            """));
    }
}
