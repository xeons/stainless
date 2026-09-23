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

/// A set of jobs that must all finish before the scope does.
///
/// This is the join counter behind `parallel`, exposed as a class until the
/// syntax exists. `Join` does not return until every job submitted to this
/// scope has run, and the calling thread runs queued work while it waits
/// rather than idling.
///
/// **Nothing is checked yet.** A job receives a raw pointer, so keeping the
/// object it points at alive across the join is on you -- holding it in a
/// local of the function that owns the scope is enough, since the scope joins
/// before that function returns. Step 6 of docs/concurrency.md is what turns
/// this from a convention into a rule.
public class TaskScope
{
    byte* _handle;

    /// Opens a scope. Starts the thread pool if this is the first one, which
    /// is what `StartPool` can do earlier and with a chosen size.
    ///
    /// @see Threading.StartPool
    public TaskScope() => _handle = sl_scope_begin();

    /// Queues a job. It may already be running when this returns.
    ///
    /// @param job       the work a pool thread runs
    /// @param argument  what it is handed, uninterpreted. It is not owned and not counted, so
    ///                  it MUST outlive the join.
    /// @see TaskScope.Join
    public void Run(Job job, byte* argument)
    {
        sl_scope_submit(_handle, job, argument);
    }

    /// Waits for every job submitted so far. Doing it twice is harmless, which
    /// is what lets the destructor be a backstop for a scope nobody joined.
    public void Join()
    {
        if (_handle != null)
        {
            sl_scope_end(_handle);
            _handle = null;
        }
    }

    ~TaskScope() { Join(); }
}
