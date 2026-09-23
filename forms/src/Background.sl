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

// Slow work off the UI thread, and the answer back onto it.
//
// This is the layer nearly every program should use, and `Application.Post` is
// the plumbing under it. Two closures: one that runs on a thread of its own,
// one that runs on the UI thread with what the first returned.
module Forms;

import Standard.Threading;

/// Work that runs off the UI thread, and a continuation that runs back on it.
///
///     void OnFetchClick()
///     {
///         var city = _city.Text;          // read on the UI thread
///         _fetch.Enabled = false;
///
///         Background.Run(
///             () => FetchWeather(city),   // off the UI thread
///             weather =>                  // back on it
///             {
///                 _forecast.Text = weather;
///                 _fetch.Enabled = true;
///             });
///     }
///
/// **This is what a UI program wants instead of `async`.** The work blocks, on
/// a thread that is allowed to, and the answer arrives through the loop the
/// program already has. Nothing changes colour, no signature grows a keyword,
/// and there is no state machine anywhere -- which is what having real threads
/// buys, and the whole of §12 of docs/concurrency.md.
///
/// **Why it is safe to name a control in the continuation.** Both arguments are
/// closures, so each holds its own copy of what it captured. The continuation
/// crosses to the worker and comes back, but only its reference count is touched
/// off the UI thread and counts are atomic; the controls inside it are reached
/// only when it is called, which only ever happens on the thread that owns them.
/// That is the shape the sendability rule wants rather than one it merely
/// tolerates: you do not reach a widget from a worker, you hand a closure to the
/// thread that owns it.
///
/// **Read what you need from the UI before you start**, as `city` is above. The
/// work closure runs on another thread, and a control read from there is the bug
/// this whole arrangement exists to avoid.
///
/// **One thread per call**, detached, the same price `Future<T>` pays and for
/// the same reason: the pool is fixed-size and this work usually blocks, so
/// putting it there would starve every `for parallel` in the program. Dozens of
/// these are fine. A program wanting thousands wants something else.
public static class Background
{
    /// Runs `work` on a thread of its own, then `then` on the UI thread with
    /// what it returned.
    ///
    /// `T` is worked out from the closures, so neither the type argument nor
    /// the parameter types are written at the call.
    public static void Run<T>(IProducer<T> work, IConsumer<T> then)
    {
        var worker = new Thread(() =>
        {
            var value = work.Invoke();
            Application.Post(() => then.Invoke(value));
        });
        worker.Detach();
    }

    /// The same, for work with nothing to hand back -- saving a file, sending
    /// a request whose only answer is that it finished.
    public static void Run(Action work, Action then)
    {
        var worker = new Thread(() =>
        {
            work();
            Application.Post(then);
        });
        worker.Detach();
    }
}
