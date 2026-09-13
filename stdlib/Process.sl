// Stainless - an experimental systems language.
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
/// out rather than warned about -- and it is why there is no `Run(String
/// commandLine)` here to reach for by mistake.
///
///     var done = try Run("git", ["rev-parse", "HEAD"]);
///     if (done.Ok()) { Console.WriteLine(done.Output.Trim()); }
///
/// `Run` waits and captures; `Start` hands back a `Process` to wait on later.
/// Both read the child's streams while it runs, which is not optional: a pipe
/// holds about 64KB, so a parent that waits before reading waits forever on a
/// child that writes more than that.
module Standard.Process;

import Standard.Collections;

extern "C" {
    byte* sl_process_args_new();
    bool  sl_process_args_add(byte* args, String text);
    void  sl_process_args_free(byte* args);

    int   sl_process_run(byte* args, String? input, StringBuilder outText,
                         StringBuilder errText, out int exitCode);

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
public enum ProcessError {
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
public struct Completed {
    /// Zero by convention means success; 128 + N means a signal killed it,
    /// which is what a shell reports too.
    public int ExitCode;

    /// Everything it wrote to its output, as one String.
    public String Output;

    /// And to its error stream, kept separate so that a program which prints
    /// progress there does not corrupt what was being captured.
    public String Errors;

    /// The usual question, spelled once.
    public bool Ok() { return ExitCode == 0; }
}

/// The argument list a call needs, built once and freed however it ends.
byte* Assemble(String program, String[] arguments) {
    byte* args = sl_process_args_new();
    if (args == null) { return null; }

    if (!sl_process_args_add(args, program)) {
        sl_process_args_free(args);
        return null;
    }

    foreach (var argument in arguments) {
        if (!sl_process_args_add(args, argument)) {
            sl_process_args_free(args);
            return null;
        }
    }

    return args;
}

ProcessError Coded(int number) {
    switch (number) {
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
///     var done = try Run("git", ["status", "--short"]);
///
/// `arguments` does **not** include the program's own name; that is `program`,
/// and it is what a PATH lookup is done on when it has no separator in it.
public Result<Completed, ProcessError> Run(String program, String[] arguments) {
    return Run(program, arguments, null);
}

/// The same, with something written to the program's input first.
///
/// The pipe is closed once `input` has been written, which is what makes a
/// program reading to end-of-input stop rather than wait. A child that exits
/// without reading is not an error here: the write stops and the run goes on.
public Result<Completed, ProcessError> Run(
    String program, String[] arguments, String? input
) {
    byte* args = Assemble(program, arguments);
    if (args == null) { return Fail(ProcessError.NoResource); }

    var output = new StringBuilder();
    var errors = new StringBuilder();

    int status = sl_process_run(args, input, output, errors, out int exitCode);
    sl_process_args_free(args);

    if (status != 0) { return Fail(Coded(status)); }

    Completed done;
    done.ExitCode = exitCode;
    done.Output = output.ToText();
    done.Errors = errors.ToText();
    return Ok(done);
}

// ---------------------------------------------------------------- starting

/// A program that was started and has not been waited for.
///
/// Its streams are this process's own, so what it prints goes where this
/// program's output goes. `Run` is the one that captures.
public class Process {
    byte* handle;

    /// Made by `Start` alone: the handle is the runtime's and there is no way
    /// to come by a valid one otherwise.
    Process(byte* started) { handle = started; }

    /// Reaped here if it was never waited for, so that letting go of a
    /// `Process` does not leave a zombie for the rest of the run. It is not
    /// killed: letting go says nothing about wanting it stopped.
    ~Process() { sl_process_release(handle); }

    /// What the operating system calls it.
    public long Id() { return sl_process_id(handle); }

    /// Waits for it to finish, and answers with the code it left.
    ///
    /// Asking twice is harmless and answers the same both times.
    public Result<int, ProcessError> Wait() {
        int status = sl_process_wait(handle, out int exitCode);
        if (status != 0) { return Fail(Coded(status)); }
        return Ok(exitCode);
    }

    /// The code it left, if it has finished, without waiting for it.
    ///
    ///     while (child.Finished().IsEmpty()) { DoSomethingElse(); }
    public Optional<int> Finished() {
        int answer = sl_process_poll(handle, out int exitCode);
        if (answer == 1) { return Some(exitCode); }
        return None;
    }

    /// Asks it to stop, the way Ctrl-C would. It may decline.
    public bool Stop() { return sl_process_signal(handle, false); }

    /// Makes it stop. It cannot decline, and gets no chance to tidy up.
    public bool Kill() { return sl_process_signal(handle, true); }

    /// Starts a program without waiting for it.
    public static Result<Process, ProcessError> Start(String program, String[] arguments) {
        byte* args = Assemble(program, arguments);
        if (args == null) { return Fail(ProcessError.NoResource); }

        byte* started = sl_process_start(args, out int error);
        sl_process_args_free(args);

        if (started == null) { return Fail(Coded(error)); }
        return Ok(new Process(started));
    }
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
///     Signals.Watch();
///     while (!Signals.Interrupted()) { DoAPieceOfWork(); }
///     Console.WriteLine("stopping");
public static class Signals {
    /// Starts noticing interrupts. Until this is called they end the program,
    /// which is the right default for something that has nothing to tidy.
    public static bool Watch() { return sl_signals_watch(); }

    /// Whether one has arrived since the last `Clear`.
    public static bool Interrupted() { return sl_signals_interrupted(); }

    /// Forgets the one that arrived, for a program that means to carry on.
    public static void Clear() { sl_signals_clear(); }
}
