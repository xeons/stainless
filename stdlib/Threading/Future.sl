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

/// A value another thread is still computing.
///
///     var answer = new Future<int>(() => Compute(input));
///     // ... do something else ...
///     int value = answer.GetResult(); // blocks until it is there
///
/// **This is a future without `async`.** `GetResult` blocks, which costs nothing here
/// that it does not cost anywhere else: Stainless has real OS threads and
/// permits blocking, so waiting needs no coroutine transform and no colour in
/// any signature. See §12 of docs/concurrency.md for why that is the whole of
/// the difference between this and a `Task<T>`.
///
/// **It is the unstructured half, and it is third.** `parallel` and `spawn`
/// have no handle to lose and no join to forget, and a `for parallel` loop
/// beats both for data. A `Future<T>` earns its place only where the result is
/// wanted somewhere the scope that started it cannot reach -- returned from a
/// function, stored in a field, waited on by whoever gets there first. That
/// freedom is the cost: no lexical join means nothing checks what the body
/// touches.
///
/// **One thread per future**, detached, which is the honest price of having no
/// scope to pool against. Dozens of these are fine and thousands are not; a
/// program that wants thousands wants a different mechanism than this one.
///
/// **The future cannot be destroyed while its thread runs.** The box handed to
/// the thread holds a reference to it, so the last release happens on the
/// worker after the value has landed -- which is what lets the destructor free
/// the condition variable without checking whether anyone is still waiting on
/// it.
///
/// @typeparam T  what the body produces, and what every `GetResult` answers with
public threadsafe class Future<T>
{
    byte* _mutex;
    byte* _condition;
    T _value;
    bool _filled;

    /// Starts `body` on a thread of its own. It may already have finished when
    /// this returns.
    public Future(IProducer<T> body)
    {
        _mutex = sl_mutex_new();
        _condition = sl_condition_new();
        _filled = false;

        sl_thread_detach(StartBoxed(new Pending<T>(body, this)));
    }

    /// The value, waiting for it if it is not there yet. Asking twice is
    /// harmless and the second ask does not block: a future is filled once and
    /// then read as often as you like, by as many threads as you like.
    public T GetResult()
    {
        sl_mutex_lock(_mutex);
        while (!_filled)
            sl_condition_wait(_condition, _mutex);
        var value = _value;
        sl_mutex_unlock(_mutex);
        return value;
    }

    /// Whether the value has landed. False here means nothing a moment later,
    /// so this answers "is there anything else worth doing first" and never
    /// "is it safe to skip the wait".
    public bool IsReady
    {
        get
        {
            sl_mutex_lock(_mutex);
            var filled = _filled;
            sl_mutex_unlock(_mutex);
            return filled;
        }
    }

    /// Stores the result and wakes everyone waiting. Called by the worker, and
    /// visible to this module only: a future is filled by its own body once,
    /// and filling one from outside would make `GetResult` a lie.
    void SetResult(T value)
    {
        sl_mutex_lock(_mutex);
        _value = value;
        _filled = true;
        sl_mutex_unlock(_mutex);

        // Broadcast outside the lock: a waiter woken while it is still held
        // would only block again trying to take it.
        sl_condition_broadcast(_condition);
    }

    ~Future()
    {
        sl_condition_free(_condition);
        sl_mutex_free(_mutex);
    }
}
