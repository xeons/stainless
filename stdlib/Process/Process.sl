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
///     if (done.Succeeded) { Console.WriteLine(done.StandardOutput.Trim()); }
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
public Result<ProcessResult, ProcessError> RunProcess(String program, String[] arguments)
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
public Result<ProcessResult, ProcessError> RunProcess(
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

    ProcessResult done;
    done.ExitCode = exitCode;
    done.StandardOutput = output;
    done.StandardError = errors;
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
    public Result<int, ProcessError> WaitForExit()
    {
        int status = sl_process_wait(_handle, out int exitCode);
        if (status != 0)
            return Fail(ToProcessError(status));
        return Ok(exitCode);
    }

    /// The code it left, if it has finished, without waiting for it.
    ///
    /// A method rather than a property because asking reaps a child that has
    /// exited, which is not what a property may do.
    ///
    ///     while (child.TryGetExitCode().IsEmpty) { DoSomethingElse(); }
    public Optional<int> TryGetExitCode()
    {
        int answer = sl_process_poll(_handle, out int exitCode);
        if (answer == 1)
            return Some(exitCode);
        return None;
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
public Result<RunningProcess, ProcessError> OpenProcess(String program, String[] arguments)
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
public Result<RunningProcess, ProcessError> OpenProcess(
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
    return Ok(new RunningProcess(started));
}
