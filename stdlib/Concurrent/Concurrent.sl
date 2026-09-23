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

/// Collections more than one thread may hold at once.
///
/// Each one owns an ordinary collection from Standard.Collections, keeps it in a
/// field, and never lets a reference to it out. That last part is not a style
/// choice, it is the correctness argument:
///
/// **A caller who keeps what it was lent outlives the lock.** A lock protects
/// what it guards for as long as it is held, and nothing stops a caller storing
/// the object it was handed and using it after the guard is gone. Keeping the
/// collection in a field avoids that entirely: reading a field to call a method
/// on it borrows, and a borrow that never leaves cannot outlive anything.
///
/// This began as a stronger argument still, because reference counts were not
/// atomic and handing an object out of a lock corrupted its count. Counts are
/// atomic now, so that half is closed; the lifetime half is not, and it is the
/// half this design was already the answer to.
///
/// So these types lock a raw mutex directly rather than using `Mutex<T>` from
/// Standard.Threading, whose `Guard.Value` is exactly the hand-out that
/// cannot be made safe this way. See the note there.
///
/// The API differs from the single-threaded one in one further way, and it is
/// the important one: nothing here can be asked a question whose answer is
/// stale before it is read. There is no `Peek` and then `Dequeue`, because
/// between the two another thread may have taken it. Every operation that can
/// fail says so in its result.
module Standard.Concurrent;

import Standard.Collections;
import Standard.Threading;

extern "C"
{
    byte* sl_mutex_new();
    void  sl_mutex_free(byte* mutex);
    void  sl_mutex_lock(byte* mutex);
    void  sl_mutex_unlock(byte* mutex);

    byte* sl_condition_new();
    void  sl_condition_free(byte* condition);
    void  sl_condition_wait(byte* condition, byte* mutex);
    void  sl_condition_signal(byte* condition);
    void  sl_condition_broadcast(byte* condition);
}
