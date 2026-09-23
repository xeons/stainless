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

/// Running another program.
///
/// **There is no shell.** The program and its arguments are a list, so a `>`, a
/// `|` or a space in a filename is a character the child receives rather than
/// something a shell acts on. That is the whole of shell injection, designed
/// out rather than warned about -- and it is why there is no `RunProcess(String
/// commandLine)` here to reach for by mistake.
///
///     var done = try RunProcess("git", ["rev-parse", "HEAD"]);
///     if (done.Succeeded) { Console.WriteLine(done.Output.Trim()); }
///
/// `RunProcess` waits and captures; `Start` hands back a `Process` to wait on later.
/// Both read the child's streams while it runs, which is not optional: a pipe
/// holds about 64KB, so a parent that waits before reading waits forever on a
/// child that writes more than that.
module Standard.Process;

import Standard.Collections;

extern "C"
{
    byte* sl_process_args_new();
    bool  sl_process_args_add(byte* args, String text);
    void  sl_process_args_free(byte* args);

    int   sl_process_run(byte* args, String? input, out String outText,
                         out String errText, out int exitCode);

    byte* sl_process_open(byte* args, String? input, out int error);
    bool  sl_process_pump(byte* handle);
    String sl_process_take_output(byte* handle);
    String sl_process_take_errors(byte* handle);

    byte* sl_process_start(byte* args, out int error);
    long  sl_process_id(byte* handle);
    int   sl_process_wait(byte* handle, out int exitCode);
    int   sl_process_poll(byte* handle, out int exitCode);
    bool  sl_process_signal(byte* handle, bool force);
    void  sl_process_release(byte* handle);

    bool  sl_signals_watch();
    bool  sl_signals_interrupted();
    void  sl_signals_clear();
}

/// Why a program could not be started.
///
/// Only about *starting* it. A program that ran and failed is a `Completed`
/// with a non-zero `ExitCode`, which is an outcome rather than an error --
/// `grep` answering 1 for "no match" is the ordinary case, not a fault.
public enum ProcessError
{
    /// It started.
    None,

    /// No such program, on the PATH or at the path given.
    NotFound,

    /// It exists and this process may not run it.
    Denied,

    /// Out of processes, descriptors or memory.
    NoResource,

    /// It did not start, for a reason none of the above names.
    Failed,
}

/// What a finished program left behind.
public struct Completed
{
    /// Zero by convention means success; 128 + N means a signal killed it,
    /// which is what a shell reports too.
    public int ExitCode;

    /// Everything it wrote to its output, as one String.
    public String Output;

    /// And to its error stream, kept separate so that a program which prints
    /// progress there does not corrupt what was being captured.
    public String Errors;

    /// The usual question, spelled once.
    public bool Succeeded => ExitCode == 0;
}

/// The argument list a call needs, built once and freed however it ends.
byte* AssembleArguments(String program, String[] arguments)
{
    byte* args = sl_process_args_new();
    if (args == null)
        return null;

    if (!sl_process_args_add(args, program))
    {
        sl_process_args_free(args);
        return null;
    }

    foreach (var argument in arguments)
    {
        if (!sl_process_args_add(args, argument))
        {
            sl_process_args_free(args);
            return null;
        }
    }

    return args;
}

ProcessError ToProcessError(int number)
{
    switch (number)
    {
        case 0:  return ProcessError.None;
        case 1:  return ProcessError.NotFound;
        case 2:  return ProcessError.Denied;
        case 3:  return ProcessError.NoResource;
        default: return ProcessError.Failed;
    }
}

// ----------------------------------------------------------------- running

/// Runs a program to completion and answers with what it wrote and what it
/// returned.
///
///     var done = try RunProcess("git", ["status", "--short"]);
///
/// `arguments` does **not** include the program's own name; that is `program`,
/// and it is what a PATH lookup is done on when it has no separator in it.
///
/// @failure ProcessError.NotFound    no such program, on the PATH or at the
///                                   path given
/// @failure ProcessError.Denied      it is there and may not be run
/// @failure ProcessError.NoResource  out of processes, descriptors or memory
/// @failure ProcessError.Failed      it did not start, for a reason none of the
///                                   others names
/// @see OpenProcess
/// @seealso Process.Start
public Result<Completed, ProcessError> RunProcess(String program, String[] arguments)
{
    return RunProcess(program, arguments, null);
}

/// The same, with `input` written to the program's input.
///
/// It is written while the output is read, so a filter that answers as it
/// reads takes an input of any size. The pipe is closed once all of it is
/// written, which is what makes a program reading to end-of-input stop rather
/// than wait. A child that exits without reading is not an error here: the
/// rest is dropped and the run goes on.
///
/// Without `input` the program reads end of input at once, rather than this
/// program's own.
///
/// @failure ProcessError.NotFound    no such program, on the PATH or at the
///                                   path given
/// @failure ProcessError.Denied      it is there and may not be run
/// @failure ProcessError.NoResource  out of processes, descriptors or memory
/// @failure ProcessError.Failed      it did not start, for a reason none of the
///                                   others names
public Result<Completed, ProcessError> RunProcess(
    String program, String[] arguments, String? input
)
{
    byte* args = AssembleArguments(program, arguments);
    if (args == null)
        return Fail(ProcessError.NoResource);

    int status = sl_process_run(
        args, input, out String output, out String errors, out int exitCode);
    sl_process_args_free(args);

    if (status != 0)
        return Fail(ToProcessError(status));

    Completed done;
    done.ExitCode = exitCode;
    done.Output = output;
    done.Errors = errors;
    return Ok(done);
}

// ---------------------------------------------------------------- starting

/// A program that was started and has not been waited for.
///
/// Its streams are this process's own, so what it prints goes where this
/// program's output goes. `RunProcess` is the one that captures.
public class Process
{
    byte* _handle;

    /// Made by `Start` alone: the handle is the runtime's and there is no way
    /// to come by a valid one otherwise.
    Process(byte* started) => _handle = started;

    /// Reaped if it was never waited for, now or when it exits, so that
    /// letting go of a `Process` does not leave a zombie for the rest of the
    /// run. It is not killed: letting go says nothing about wanting it stopped.
    ~Process() { sl_process_release(_handle); }

    /// What the operating system calls it.
    public long Id => sl_process_id(_handle);

    /// Waits for it to finish, and answers with the code it left.
    ///
    /// Asking twice is harmless and answers the same both times.
    ///
    /// @failure ProcessError.Failed  the wait itself failed, so there is no
    ///                               code to report
    public Result<int, ProcessError> Wait()
    {
        int status = sl_process_wait(_handle, out int exitCode);
        if (status != 0)
            return Fail(ToProcessError(status));
        return Ok(exitCode);
    }

    /// The code it left, if it has finished, without waiting for it.
    ///
    ///     while (child.Finished.IsEmpty) { DoSomethingElse(); }
    public Optional<int> Finished
    {
        get
        {
            int answer = sl_process_poll(_handle, out int exitCode);
            if (answer == 1)
                return Some(exitCode);
            return None;
        }
    }

    /// Asks it to stop, the way Ctrl-C would. It may decline.
    public bool Stop() => sl_process_signal(_handle, false);

    /// Makes it stop. It cannot decline, and gets no chance to tidy up.
    public bool Kill() => sl_process_signal(_handle, true);

    /// Starts a program without waiting for it.
    ///
    /// @param program    what to run, looked up on the PATH when it has no
    ///                   separator in it
    /// @param arguments  what to hand it, without the program's own name in
    ///                   front
    /// @failure ProcessError.NotFound    no such program, on the PATH or at the
    ///                                   path given
    /// @failure ProcessError.Denied      it is there and may not be run
    /// @failure ProcessError.NoResource  out of processes, descriptors or
    ///                                   memory
    /// @failure ProcessError.Failed      it did not start, for a reason none of
    ///                                   the others names
    /// @see RunProcess
    public static Result<Process, ProcessError> Start(String program, String[] arguments)
    {
        byte* args = AssembleArguments(program, arguments);
        if (args == null)
            return Fail(ProcessError.NoResource);

        byte* started = sl_process_start(args, out int error);
        sl_process_args_free(args);

        if (started == null)
            return Fail(ToProcessError(error));
        return Ok(new Process(started));
    }
}

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
///         Console.WriteLine("exit " + Text.FromInteger(child.Wait().GetValueOrDefault(-1)));
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
public class Running
{
    byte* _handle;

    /// Whether either stream may still produce something. False once the child
    /// has closed both, which is what ends the loop.
    bool _more;

    /// Made by `OpenProcess` alone: the handle is the runtime's and there is no way
    /// to come by a valid one otherwise.
    Running(byte* started)
    {
        _handle = started;
        _more = true;
    }

    /// Reaped if it was never waited for, now or when it exits, and the pipes
    /// go with it -- a read end left open is a child blocked forever on a full
    /// one. Input not yet written is dropped.
    ~Running() { sl_process_release(_handle); }

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
    /// @see Running.ReadAvailableOutput
    public Result<int, ProcessError> Wait()
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

/// Starts a program with its output captured, to be read as it arrives.
///
/// `arguments` does **not** include the program's own name; that is `program`,
/// and it is what a PATH lookup is done on when it has no separator in it --
/// the same bargain `RunProcess` makes.
///
/// @failure ProcessError.NotFound    no such program, on the PATH or at the
///                                   path given
/// @failure ProcessError.Denied      it is there and may not be run
/// @failure ProcessError.NoResource  out of processes, descriptors, pipes or
///                                   memory
/// @failure ProcessError.Failed      it did not start, for a reason none of the
///                                   others names
/// @see RunProcess
public Result<Running, ProcessError> OpenProcess(String program, String[] arguments)
{
    return OpenProcess(program, arguments, null);
}

/// The same, with `input` written to the program's input.
///
/// What fits in the pipe is written before this returns, and the rest no
/// later than `ReadAvailableOutput` waits for output, so input of any size is safe to give a
/// filter that answers as it reads. The pipe is closed once all of it is written, which
/// is what makes a program reading to end-of-input stop rather than wait.
///
/// Without `input` the program reads end of input at once, rather than this
/// program's own.
///
/// @failure ProcessError.NotFound    no such program, on the PATH or at the
///                                   path given
/// @failure ProcessError.Denied      it is there and may not be run
/// @failure ProcessError.NoResource  out of processes, descriptors, pipes or
///                                   memory
/// @failure ProcessError.Failed      it did not start, for a reason none of the
///                                   others names
public Result<Running, ProcessError> OpenProcess(
    String program, String[] arguments, String? input
)
{
    byte* args = AssembleArguments(program, arguments);
    if (args == null)
        return Fail(ProcessError.NoResource);

    byte* started = sl_process_open(args, input, out int error);
    sl_process_args_free(args);

    if (started == null)
        return Fail(ToProcessError(error));
    return Ok(new Running(started));
}

// ----------------------------------------------------------------- signals

/// Ctrl-C, asked for rather than delivered.
///
/// A signal handler runs between two instructions of whatever was executing,
/// so almost nothing is legal inside one: no allocation, no locks, and
/// therefore no Stainless at all. What is legal is a store to a flag, so that
/// is what the handler does, and this is where a program reads it -- at the
/// top of its own loop, where it can actually tidy up.
///
///     Signals.StartWatching();
///     while (!Signals.Interrupted) { DoAPieceOfWork(); }
///     Console.WriteLine("stopping");
public static class Signals
{
    /// Starts noticing interrupts. Until this is called they end the program,
    /// which is the right default for something that has nothing to tidy.
    public static bool StartWatching() => sl_signals_watch();

    /// Whether one has arrived since the last `ClearInterrupt`.
    public static bool Interrupted => sl_signals_interrupted();

    /// Forgets the one that arrived, for a program that means to carry on.
    public static void ClearInterrupt() => sl_signals_clear();
}
