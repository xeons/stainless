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

module Standard.Process;

import Standard.Collections;

// --------------------------------------------------------------- streaming

/// A program running with both its output streams captured, read as they fill.
///
/// **What `RunProcess` cannot do.** `RunProcess` does not answer until the child has exited,
/// so a build taking a minute says nothing for a minute and then says all of
/// it at once. This hands over what has arrived so far, as often as it is
/// asked -- which is what a window showing a build as it happens needs, and
/// the only difference between the two.
///
///     var started = OpenProcess("stainless", ["build"]);
///     if (started.Ok)
///     {
///         var child = started.Value;
///         while (child.ReadAvailableOutput())
///         {
///             Show(child.TakeOutput());
///             Complain(child.TakeErrors());
///         }
///         Console.WriteLine(
///             "exit " + Text.FromInteger(child.WaitForExit().GetValueOrDefault(-1)));
///     }
///
/// **`ReadAvailableOutput` waits**, and that is deliberate: it answers when there is
/// something to hand over or when the child has closed both streams, and never
/// immediately with nothing. So the loop above blocks rather than spinning,
/// and belongs on a thread of its own when there is a window to keep painting.
///
/// **Both streams are watched together**, which is not a detail a caller could
/// add afterwards. A pipe holds about 64KB, and a reader that drains one to
/// the end while the child fills the other is waiting for a child that is
/// waiting for the reader. That is why this hands back two strings rather than
/// being two objects with a `ReadAvailableOutput` each.
public class RunningProcess
{
    byte* _handle;

    /// Whether either stream may still produce something. False once the child
    /// has closed both, which is what ends the loop.
    bool _more;

    /// Made by `OpenProcess` alone: the handle is the runtime's and there is no way
    /// to come by a valid one otherwise.
    RunningProcess(byte* started)
    {
        _handle = started;
        _more = true;
    }

    /// Reaped if it was never waited for, now or when it exits, and the pipes
    /// go with it -- a read end left open is a child blocked forever on a full
    /// one. Input not yet written is dropped.
    ~RunningProcess() { sl_process_release(_handle); }

    /// What the operating system calls it.
    public long Id => sl_process_id(_handle);

    /// Takes in whatever the child has written since the last call, and
    /// answers whether there may be more after this one.
    ///
    /// False means both streams are closed and everything they held has
    /// already been handed over, so the last `Take` before it is not missing
    /// anything.
    public bool ReadAvailableOutput()
    {
        if (!_more)
            return false;
        _more = sl_process_pump(_handle);
        return _more;
    }

    /// What the child wrote to its output since this was last asked, and
    /// nothing at all the next time.
    ///
    /// **Taken rather than read.** The buffer is emptied, because a caller
    /// showing output as it arrives wants each line once; `RunProcess` is the one
    /// that answers with the whole of it at the end.
    public String TakeOutput() => sl_process_take_output(_handle);

    /// The same for what it wrote to its error stream.
    public String TakeErrors() => sl_process_take_errors(_handle);

    /// Waits for it to finish, and answers with the code it left.
    ///
    /// **After `ReadAvailableOutput` has answered false**, not before: waiting on a child
    /// whose output pipe is full is the deadlock the pumping exists to avoid,
    /// arriving from the other side. Asking twice is harmless and answers the
    /// same both times.
    ///
    /// @failure ProcessError.Failed  the wait itself failed, so there is no
    ///                               code to report
    /// @see RunningProcess.ReadAvailableOutput
    public Result<int, ProcessError> WaitForExit()
    {
        int status = sl_process_wait(_handle, out int exitCode);
        if (status != 0)
            return Fail(ToProcessError(status));
        return Ok(exitCode);
    }

    /// Asks it to stop, the way Ctrl-C would. It may decline.
    public bool Stop() => sl_process_signal(_handle, false);

    /// Makes it stop. It cannot decline, and gets no chance to tidy up.
    public bool Kill() => sl_process_signal(_handle, true);
}
