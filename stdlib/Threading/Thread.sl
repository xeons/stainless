// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Threading;

/// One OS thread, started and joinable.
///
/// This is the unstructured option, and it is deliberately second: `parallel`
/// and `spawn` cover the common case with no handle to lose, no join to
/// forget, and a compiler check that a job cannot outlive the frame it
/// borrows. Reach for a `Thread` when the work has no lexical scope -- a
/// listener that runs for the life of the program, a background writer draining
/// a queue.
///
/// **The ownership rule is different, and it is the whole difference.** A
/// `spawn`ed job *borrows* the parent's frame, which is sound because the
/// closing brace cannot be passed until the job has finished. A thread has no
/// such brace, so whatever it touches has to outlive it: a `threadsafe` object
/// held in a `static readonly`, or a block the thread frees itself. Passing a
/// pointer to a local and returning is a use-after-free the compiler does not
/// yet catch.
///
/// **The destructor joins.** A `Thread` that goes out of scope unjoined blocks
/// there until its thread finishes, which is C++'s `jthread` and is the safe
/// default: the alternative is a thread still running against storage that has
/// gone. Say `Detach()` when you mean to let it run loose.
public class Thread
{
    byte* _handle;

    /// Starts a thread running `body`, which carries whatever it captured.
    ///
    ///     var writer = new Thread(() => Drain(queue));
    ///
    /// This is the one to reach for. Capture is by value, so the closure holds
    /// its own copy of everything it named and there is no frame for it to
    /// outlive -- which is the hazard the `Job` form below leaves open and
    /// nothing checks.
    public Thread(Action body)
    {
        _handle = StartBoxed(new Running(body));
    }

    /// Starts a thread running `body(argument)`. Stainless has no static
    /// methods -- a module is the static class -- so the constructor is the
    /// place this goes.
    ///
    /// The raw form, for a body that is already a C-shaped callback or an
    /// argument that is already a block. `argument` is not owned, not counted
    /// and not checked: keeping it alive for as long as the thread runs is
    /// yours to arrange, and passing the address of a local and returning is a
    /// use-after-free. Prefer the closure above.
    public Thread(Job body, byte* argument)
    {
        _handle = sl_thread_start(body, argument);
    }

    /// Waits for it to finish. Doing it twice is harmless, which is what lets
    /// the destructor be a backstop.
    ///
    /// @see Thread.Detach
    public void Join()
    {
        if (_handle != null)
        {
            sl_thread_join(_handle);
            _handle = null;
        }
    }

    /// Gives up the handle without waiting. The thread runs on and cleans up
    /// after itself; nothing can join it afterwards.
    ///
    /// @see Thread.Join
    public void Detach()
    {
        if (_handle != null)
        {
            sl_thread_detach(_handle);
            _handle = null;
        }
    }

    /// Whether this handle still refers to a thread -- false after `Join` or
    /// `Detach`. It does not say whether the thread is still running.
    public bool IsJoinable => _handle != null;

    ~Thread() { Join(); }
}
