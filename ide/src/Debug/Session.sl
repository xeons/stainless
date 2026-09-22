// Stainless - an experimental general-purpose language.
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

// The thread that owns the debuggee, and the queue the window reaches it
// through.
//
// One thread owns the whole session. Windows requires `WaitForDebugEvent` and
// `ContinueDebugEvent` on the thread that created the debuggee; `ptrace`
// requires every request from the thread that attached. So the engine is
// built, driven and torn down on that one thread, and the window MUST NOT
// touch it.
//
// What crosses is small:
//
//     window  -> session     a command in a queue
//     session -> window      a `Snapshot`, through `Application.Post`
//
// `RequestBreak`, and the waking half of `Stop`, are the exception: they call
// `Engine.RequestBreak` from the window's thread, because the session's thread
// is blocked inside `Continue` and cannot be asked for anything. That call is
// safe for the reason `ITarget.RequestBreak` gives.
module Ide.Debugging;

import Standard.Collections;
import Standard.Text;
import Standard.Threading;
import Standard.Path;
import Forms;
import Debugger;

/// What the window has asked the session to do next.
public enum DebugCommand
{
    /// Nothing; only a reason to have woken up.
    Settle,
    Continue,
    StepIn,
    StepOver,
    StepOut,
    /// Kill it and end the session.
    Stop,
    /// Start watching an expression, or stop watching one.
    AddWatch,
    RemoveWatch,
}

/// One thing the window has asked for, and what it was about.
///
/// A class rather than the enum alone because a watch command carries either
/// the expression or the row it is about, and a queue of bare enums has
/// nowhere to put it.
class PendingCommand
{
    public DebugCommand Command;

    /// The expression, for `AddWatch`.
    public String Expression;

    /// The row, for `RemoveWatch`.
    public nuint Row;

    public PendingCommand(DebugCommand command, String expression, nuint row)
    {
        Command = command;
        Expression = expression;
        Row = row;
    }
}

/// Told about each stop, on the window's thread.
public closure void SnapshotHandler(Snapshot taken);

/// Told about each line the session or the program produced, on the window's
/// thread.
public closure void OutputHandler(String line);

/// Told which line a breakpoint bound to, on the window's thread. A
/// `boundLine` of zero means no code was found for it.
public closure void BindingHandler(String file, uint line, uint boundLine);

/// What the two threads share.
class CommandQueue
{
    public List<PendingCommand> Pending;

    /// True once the session has finished. Nothing more is accepted.
    public bool IsClosed;

    public CommandQueue()
    {
        Pending = new List<PendingCommand>();
        IsClosed = false;
    }
}

/// A debugging session: one process, one thread, one engine.
public class DebugSession
{
    Monitor<CommandQueue> _commands;

    SnapshotHandler _onSnapshot;
    OutputHandler _onOutput;
    BindingHandler _onBinding;

    /// The engine, once the session's thread has handed it across.
    ///
    /// Posted rather than assigned, so the only thread that writes this field
    /// is the one that reads it. `RequestBreak` is the only call made on it
    /// from here.
    Engine? _engine;

    /// What the window believes is going on. Written on the window's thread
    /// only, by `Start` and by each arriving snapshot.
    RunState _state;

    public DebugSession(SnapshotHandler onSnapshot, OutputHandler onOutput,
                        BindingHandler onBinding)
    {
        _commands = new Monitor<CommandQueue>(new CommandQueue());
        _onSnapshot = onSnapshot;
        _onOutput = onOutput;
        _onBinding = onBinding;
        _engine = null;
        _state = RunState.Idle;
    }

    public RunState State => _state;

    public bool IsActive => _state == RunState.Running
                         || _state == RunState.Stopped;

    public bool IsStopped => _state == RunState.Stopped;

    // -------------------------------------------------------------- starting

    /// Launches `path` under the debugger with these breakpoints.
    ///
    /// The breakpoints and the watches are copied into plain lists first.
    /// Everything the worker needs MUST be read on the thread that starts it; a
    /// `BreakpointStore` read from two threads is the bug this file exists to
    /// prevent. Which ones bound comes back through the binding handler.
    ///
    /// The watches are seeded rather than queued so that the first stop already
    /// has them: queueing would answer the first snapshot with an empty pane
    /// and fill it on the second.
    public bool Start(String path, List<SourceBreakpoint> breakpoints,
                      List<String> watches)
    {
        if (IsActive)
            return false;

        var files = new List<String>();
        var lines = new List<uint>();
        var conditions = new List<String>();
        for (nuint i = 0u; i < breakpoints.Count; i++)
        {
            if (!breakpoints[i].Enabled)
                continue;
            files.Add(breakpoints[i].File);
            lines.Add(breakpoints[i].Line);
            conditions.Add(breakpoints[i].Condition);
        }

        var wanted = new List<String>();
        for (nuint i = 0u; i < watches.Count; i++)
            wanted.Add(watches[i]);

        _state = RunState.Running;
        _engine = null;
        ReopenQueue();

        var worker = new Thread(() => RunSession(path, files, lines, conditions,
                                              wanted));
        worker.Detach();
        return true;
    }

    // ------------------------------------------------- what the window asks for

    public void ContinueExecution() => QueueCommand(DebugCommand.Continue);
    public void StepIn() => QueueCommand(DebugCommand.StepIn);
    public void StepOver() => QueueCommand(DebugCommand.StepOver);
    public void StepOut() => QueueCommand(DebugCommand.StepOut);

    /// Starts watching an expression, from the next snapshot on.
    ///
    /// Queued rather than done here: the engine belongs to the session's
    /// thread, and a watch that is refused is refused there. A stopped session
    /// answers with a fresh snapshot without moving the program, so the row
    /// appears at once.
    public void AddWatch(String expression) => QueueCommand(DebugCommand.AddWatch,
                                                 expression, 0u);

    public void RemoveWatchAt(nuint row)
        => QueueCommand(DebugCommand.RemoveWatch, "", row);

    /// Interrupts a running program.
    ///
    /// Nothing is queued. The session's thread is waiting for an event, and
    /// the stop this produces is that event; it arrives as an ordinary
    /// snapshot.
    public bool RequestBreak()
    {
        var engine = _engine;
        if (engine == null || _state != RunState.Running)
            return false;
        return ((Engine)engine).RequestBreak();
    }

    /// Ends the session, whether the program is stopped or running.
    ///
    /// Killing it is an engine call, so it belongs to the session's thread.
    /// When the program is running that thread is blocked in a wait, so the
    /// command goes into the queue and the program is interrupted to bring the
    /// thread back to read it.
    public void Stop()
    {
        if (!IsActive)
            return;
        bool wasRunning = _state == RunState.Running;
        QueueCommand(DebugCommand.Stop);
        if (wasRunning)
            RequestBreak();
    }

    void QueueCommand(DebugCommand command) => QueueCommand(command, "", 0u);

    void QueueCommand(DebugCommand command, String expression, nuint row)
    {
        var held = _commands.Lock();
        if (held.Value.IsClosed)
            return;
        held.Value.Pending.Add(new PendingCommand(command, expression, row));
        held.Pulse();
    }

    void ReopenQueue()
    {
        var held = _commands.Lock();
        held.Value.Pending.Clear();
        held.Value.IsClosed = false;
    }

    // ------------------------------------------ arriving on the window's thread

    /// Each snapshot, before the window's own handler sees it, so `State` is
    /// already right when that handler reads it.
    void OnSnapshotArrived(Snapshot taken)
    {
        _state = taken.State;
        if (taken.State == RunState.Ended)
            _engine = null;
        _onSnapshot(taken);
    }

    void OnEngineCreated(Engine engine) => _engine = engine;

    void OnOutputWritten(String line) => _onOutput(line);

    void OnBreakpointBound(String file, uint line, uint chosen)
        => _onBinding(file, line, chosen);

    // ---------------------------------------------- the session's own thread

    /// Everything below here runs on the session's thread, and nothing above
    /// it does.
    void RunSession(String path, List<String> files, List<uint> lines,
                 List<String> conditions, List<String> watches)
    {
        var made = MakeTarget();
        if (!made.Ok)
        {
            AbandonSession("could not start a debugger: " + made.Error);
            return;
        }

        // Qualified: `Image` alone is the Forms picture control, and both
        // modules are imported here.
        var read = Debugger.Image.FromFile(path);
        if (!read.Ok)
        {
            AbandonSession("could not read " + path + ": " + read.Error);
            return;
        }

        var image = read.Value;
        var info = new DwarfInfo(image);
        String bad = info.Read();
        if (bad.ByteLength() != 0u)
        {
            AbandonSession("could not read the debug information: " + bad);
            return;
        }

        var target = made.Value;
        var tables = ReadEveryLineTable(info);
        var engine = new Engine(target, image, info, tables);
        Application.Post(() => OnEngineCreated(engine));

        // A program with no DWARF still runs, stopping at addresses rather
        // than lines. On Windows an ordinary `-g` build writes CodeView into a
        // .pdb and carries no DWARF, which is a misconfigured build rather
        // than a broken debugger.
        if (info.IsEmpty)
            PostOutput("this binary carries no DWARF, so there are no lines."
                + " Build it with --debug-format dwarf.");

        PlantBreakpoints(engine, tables, files, lines, conditions);

        for (nuint i = 0u; i < watches.Count; i++)
        {
            String problem = engine.AddWatch(watches[i]);
            if (problem.ByteLength() != 0u)
                PostOutput(watches[i] + ": " + problem);
        }

        var started = engine.Start(path, "");
        if (!started.Ok)
        {
            AbandonSession("could not launch " + path + ": " + started.Error);
            return;
        }

        if (engine.SlideKnown && engine.Slide != 0u)
            PostOutput("image slid by 0x" + FormatHexadecimal((ulong)engine.Slide));

        var stop = started.Value;
        while (true)
        {
            DrainOutput(engine);
            SendSnapshot(engine, target, stop);

            if (stop.Kind == StopKind.Exited || stop.Kind == StopKind.NotRunning)
                break;

            var next = TakeCommand();
            if (next.Command == DebugCommand.Stop)
            {
                engine.Terminate();
                PostOutput("Debugging stopped.");
                ReportExit(0);
                break;
            }

            stop = PerformCommand(engine, next, stop);
        }

        CloseQueue();
    }

    /// Does one command, and answers where the program ended up.
    ///
    /// A command that does not move the program MUST answer the stop it was
    /// given, so that the loop re-reports the same place: a watch added while
    /// stopped fills its row without the caret moving. A fresh `Paused` carries
    /// no address, and a snapshot taken at one empties every pane.
    Stop PerformCommand(Engine engine, PendingCommand next, Stop stop)
    {
        switch (next.Command)
        {
            case DebugCommand.StepIn:
                return engine.StepIn(stop.Thread);

            case DebugCommand.StepOver:
                return engine.StepOver(stop.Thread);

            case DebugCommand.StepOut:
                return engine.StepOut(stop.Thread);

            case DebugCommand.Continue:
                return engine.Continue();

            case DebugCommand.AddWatch:
            {
                String problem = engine.AddWatch(next.Expression);
                if (problem.ByteLength() != 0u)
                    PostOutput(next.Expression + ": " + problem);
                return stop;
            }

            case DebugCommand.RemoveWatch:
                engine.RemoveWatchAt(next.Row);
                return stop;

            default:
                // `Settle` and anything unrecognised report where the program
                // already is. An unmatched command MUST NOT move it.
                return stop;
        }
    }

    /// Blocks until the window asks for something.
    PendingCommand TakeCommand()
    {
        var held = _commands.Lock();

        // In a loop: both platforms permit a spurious wake, and a pulse says
        // only that something changed.
        while (held.Value.Pending.IsEmpty && !held.Value.IsClosed)
            held.Wait();

        if (held.Value.Pending.IsEmpty)
            return new PendingCommand(DebugCommand.Stop, "", 0u);

        var next = held.Value.Pending[0u];
        held.Value.Pending.RemoveAt(0u);
        return next;
    }

    /// Finds code for each breakpoint, plants it, and reports where it landed.
    void PlantBreakpoints(Engine engine, List<LineTable> tables, List<String> files,
                   List<uint> lines, List<String> conditions)
    {
        for (nuint i = 0u; i < files.Count; i++)
        {
            String file = files[i];
            uint line = lines[i];
            String condition = conditions[i];

            nuint at = 0u;
            uint chosen = 0u;
            if (!FindLineAddress(tables, file, line, &at, &chosen))
            {
                PostOutput("no code for " + Standard.Path.GetFileName(file) + ":"
                    + Standard.Text.FromInteger((long)line)
                    + ", so it will not be hit.");
                Application.Post(() => OnBreakpointBound(file, line, 0u));
                continue;
            }

            var planted = engine.Add(at, Standard.Path.GetFileName(file) + ":"
                                         + Standard.Text.FromInteger((long)line));

            String problem = engine.Condition(planted, condition);
            if (problem.ByteLength() != 0u)
            {
                PostOutput(Standard.Path.GetFileName(file) + ":"
                    + Standard.Text.FromInteger((long)line) + ": " + condition
                    + ": " + problem + " -- it will stop every time.");
            }

            Application.Post(() => OnBreakpointBound(file, line, chosen));
        }
    }

    /// What the program has written, one line at a time.
    void DrainOutput(Engine engine)
    {
        var wrote = engine.TakeOutput();
        for (nuint i = 0u; i < wrote.Count; i++)
        {
            // Taken into a local so each post carries its own copy.
            String line = wrote[i];
            Application.Post(() => OnOutputWritten(line));
        }
    }

    /// Takes a snapshot and sends it across.
    void SendSnapshot(Engine engine, ITarget target, Stop stop)
    {
        var taken = TakeSnapshot(engine, target, stop);
        Application.Post(() => OnSnapshotArrived(taken));
    }

    /// The session could not be set up at all.
    void AbandonSession(String why)
    {
        PostOutput(why);
        ReportExit(-1);
        CloseQueue();
    }

    void ReportExit(int code)
    {
        var over = new Snapshot(RunState.Ended);
        over.Kind = StopKind.Exited;
        over.ExitCode = code;
        Application.Post(() => OnSnapshotArrived(over));
    }

    void PostOutput(String line)
    {
        Application.Post(() => OnOutputWritten(line));
    }

    /// Stops anything further being queued, and wakes anyone waiting.
    void CloseQueue()
    {
        var held = _commands.Lock();
        held.Value.IsClosed = true;
        held.PulseAll();
    }
}
