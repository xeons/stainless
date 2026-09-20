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

// Everything a stop is worth knowing, read once and handed over.
//
// Every call into a target MUST come from the one thread that launched it, so
// a window cannot ask the engine anything. A snapshot is taken on the
// session's thread while the program is stopped, and is numbers and text
// afterwards.
//
// `sldb snapshot` prints exactly this. A pane showing more than a snapshot
// holds is a pane no headless test covers, so anything the IDE needs MUST be
// added here first.
module Debugger;

import Standard.Collections;
import Standard.Text;
import Standard.Path;

/// One local or parameter, already read and already formatted.
public class ValueLine
{
    public String Name;

    /// What the type is called, as `Values.sl` describes it.
    public String TypeName;

    /// The value, formatted. Never a handle into the target: by the time this
    /// is read the process may be running again.
    public String Value;

    public bool IsParameter;

    public ValueLine(String name, String typeName, String value,
                     bool isParameter)
    {
        Name = name;
        TypeName = typeName;
        Value = value;
        IsParameter = isParameter;
    }
}

/// One watch expression, already read and already formatted.
///
/// A watch that could not be read is one of these too, with `Ok` false and the
/// reason in `Value`. Half the watches in a session are out of scope at any
/// moment, so every reader of these MUST keep the row and show the reason: a
/// list that drops them says there are fewer watches than there are, and moves
/// the rest under the pointer at every step.
public class WatchLine
{
    /// What was typed, unchanged. It is the row's identity.
    public String Expression;

    /// What the type is called, or "" when there is no value.
    public String TypeName;

    /// The value, formatted -- or why there is none.
    public String Value;

    public bool Ok;

    public WatchLine(String expression, String typeName, String value, bool ok)
    {
        Expression = expression;
        TypeName = typeName;
        Value = value;
        Ok = ok;
    }
}

/// One frame of the call stack.
public class FrameLine
{
    /// Zero is where the program stopped; each one after it called the one
    /// below.
    public int Depth;

    /// The function, or "" when the address is in code with no description --
    /// the C runtime, or the system's own libraries.
    public String Function;

    public String File;
    public uint Line;
    public bool HasSource;

    public nuint Pc;

    public FrameLine(int depth, String function, String file, uint line,
                     bool hasSource, nuint pc)
    {
        Depth = depth;
        Function = function;
        File = file;
        Line = line;
        HasSource = hasSource;
        Pc = pc;
    }
}

/// One thread of the debuggee.
public class ThreadLine
{
    public uint Id;

    /// Whether this is the thread the stop was reported on, and the one every
    /// other pane is about.
    public bool IsCurrent;

    /// Whether the engine can read this thread at all. False for a thread the
    /// platform lists but does not let a debugger touch -- on Linux, every one
    /// the program started after the launch.
    public bool CanRead;

    /// Where it is, when it could be read. `Function` is "" for an address in
    /// code nothing describes.
    public String Function;
    public String File;
    public uint Line;
    public bool HasSource;
    public nuint Pc;

    public ThreadLine(uint id, bool isCurrent, bool canRead)
    {
        Id = id;
        IsCurrent = isCurrent;
        CanRead = canRead;
        Function = "";
        File = "";
        Line = 0u;
        HasSource = false;
        Pc = 0u;
    }
}

/// What a session is doing, as far as anything watching it can tell.
public enum RunState
{
    /// Nothing has been launched.
    Idle,
    /// A process exists and is running; nothing may be read from it.
    Running,
    /// A process exists and is stopped. The only state a snapshot is taken in.
    Stopped,
    /// It finished, or was stopped for good.
    Ended,
}

/// Everything one stop is worth knowing.
public class Snapshot
{
    public RunState State;

    /// Why it stopped. Meaningless unless `State` is `Stopped` or `Ended`.
    public StopKind Kind;

    public uint Thread;
    public nuint Address;

    /// Where it stopped, in the source. `HasSource` is false for an address in
    /// the runtime, or in a program built without debug information at all.
    public String File;
    public uint Line;
    public bool HasSource;

    public String Function;

    /// The exit code, when `Kind` is `Exited`.
    public int ExitCode;

    /// The platform's exception number, when `Kind` is `Fault`.
    public uint FaultCode;

    public List<FrameLine> Frames;
    public List<ValueLine> Locals;

    /// The watch expressions, in the order they were added, every one of them
    /// answered.
    public List<WatchLine> Watches;

    /// Every thread of the debuggee, the current one first.
    public List<ThreadLine> Threads;

    /// Something worth saying that is not a failure -- that a program carries
    /// no DWARF, that the image base was never learned. Empty when there is
    /// nothing to say.
    public String Note;

    public Snapshot(RunState state)
    {
        State = state;
        Kind = StopKind.NotRunning;
        Thread = 0u;
        Address = 0u;
        File = "";
        Line = 0u;
        HasSource = false;
        Function = "";
        ExitCode = 0;
        FaultCode = 0u;
        Frames = new List<FrameLine>();
        Locals = new List<ValueLine>();
        Watches = new List<WatchLine>();
        Threads = new List<ThreadLine>();
        Note = "";
    }
}

/// Reads a stopped process into a snapshot.
///
/// MUST be called on the session's own thread. Registers, memory and the stack
/// are all calls into the target; the snapshot is the only thing that may
/// travel.
///
/// A stop the program did not survive still gets a snapshot. A window has to
/// be told that it exited with 0, and an empty pane does not say it.
public Snapshot TakeSnapshot(Engine engine, ITarget target, Stop stop)
{
    var taken = new Snapshot(stop.Kind == StopKind.Exited
                             ? RunState.Ended : RunState.Stopped);
    taken.Kind = stop.Kind;
    taken.Thread = stop.Thread;
    taken.Address = stop.Address;
    taken.ExitCode = stop.ExitCode;
    taken.FaultCode = stop.Code;

    if (stop.Kind == StopKind.Exited || stop.Kind == StopKind.NotRunning)
        return taken;

    var here = engine.PositionAt(stop.Address);
    taken.File = here.File;
    taken.Line = here.Line;
    taken.HasSource = here.Known;
    taken.Function = engine.FunctionAt(stop.Address);

    FillFrames(taken, engine, target, stop.Thread);
    FillLocals(taken, engine, target, stop.Thread, stop.Address);
    FillWatches(taken, engine, target, stop.Thread, stop.Address);
    FillThreads(taken, engine, target, stop.Thread);
    return taken;
}

/// The call stack, one line per frame.
void FillFrames(Snapshot into, Engine engine, ITarget target, uint thread)
{
    var frames = WalkStack(target, thread, engine.Unwinder, engine.Slide);
    for (nuint i = 0u; i < frames.Count; i++)
    {
        var frame = frames[i];

        // Every frame above the first holds a return address, which is the
        // instruction after the call. Stepping back one byte asks the line
        // table about the call itself.
        nuint asking = i == 0u ? frame.Pc : frame.Pc - 1u;

        var at = engine.PositionAt(asking);
        into.Frames.Add(new FrameLine(frame.Depth,
                                      engine.FunctionAt(asking),
                                      at.File, at.Line, at.Known, frame.Pc));
    }
}

/// Every parameter and local in scope where the program stopped.
///
/// In scope, not merely declared in the function: a variable inside a loop or a
/// bare `{ }` sits in a `DW_TAG_lexical_block`, and a block whose code does not
/// cover the stop declares nothing that exists yet.
void FillLocals(Snapshot into, Engine engine, ITarget target, uint thread,
                nuint pc)
{
    var found = engine.SubprogramAt(pc);
    if (found == null)
        return;

    var where = (Subprogram)found;

    Registers frame;
    frame.Pc = 0u;
    frame.StackPointer = 0u;
    frame.FramePointer = 0u;
    if (!target.ReadRegisters(thread, &frame))
        return;

    var children = VariablesInScopeAt(where.InUnit, where.Die,
                                      engine.ToLinked(pc));
    for (nuint i = 0u; i < children.Count; i++)
    {
        var one = children[i];
        var described = DescribeType(where.InUnit, one);
        into.Locals.Add(new ValueLine(
            one.Name, described.Name,
            ReadValue(engine, target, where.InUnit, one, where.Die, frame),
            one.Tag == TagFormalParameter));
    }
}

/// Every watch expression, read in the frame the program stopped in.
///
/// One line per watch whether or not it could be read. See `WatchLine`.
void FillWatches(Snapshot into, Engine engine, ITarget target, uint thread,
                 nuint pc)
{
    var watches = engine.Watches;
    if (watches.IsEmpty)
        return;

    var found = engine.SubprogramAt(pc);

    Registers frame;
    frame.Pc = 0u;
    frame.StackPointer = 0u;
    frame.FramePointer = 0u;

    if (found == null || !target.ReadRegisters(thread, &frame))
    {
        for (nuint i = 0u; i < watches.Count; i++)
            into.Watches.Add(new WatchLine(watches[i], "",
                "there is no frame here to read it in", false));
        return;
    }

    var where = (Subprogram)found;
    for (nuint i = 0u; i < watches.Count; i++)
        into.Watches.Add(ReadWatch(engine, target, where.InUnit, where.Die,
                                   frame, watches[i]));
}

/// Every thread, and where each of them is.
///
/// **Where a thread is costs one read of its registers**, which is the one
/// thing worth having about a thread that is not the current one: an id on its
/// own says a program has four threads and nothing about what any of them is
/// doing.
void FillThreads(Snapshot into, Engine engine, ITarget target, uint current)
{
    var threads = target.Threads();
    for (nuint i = 0u; i < threads.Count; i++)
    {
        uint id = threads[i];
        var line = new ThreadLine(id, id == current, target.CanRead(id));

        if (!line.CanRead)
        {
            into.Threads.Add(line);
            continue;
        }

        Registers registers;
        registers.Pc = 0u;
        registers.StackPointer = 0u;
        registers.FramePointer = 0u;
        if (!target.ReadRegisters(id, &registers))
        {
            // Listed and readable a moment ago, and gone now. A thread may end
            // between being counted and being asked about.
            line.CanRead = false;
            into.Threads.Add(line);
            continue;
        }

        line.Pc = registers.Pc;
        DescribeThread(line, engine, target, id, registers.Pc);
        into.Threads.Add(line);
    }
}

/// Where a thread is, in terms of the program rather than of the system.
///
/// **A waiting thread is inside the system, not inside the program**, and its
/// program counter says `ntdll` or `libc`. A thread pane that reports that
/// reports the same address for every idle thread in every program. So the
/// stack is walked to the first frame that has a source line, which is the
/// line of the program's own code the thread is waiting at.
///
/// The raw address is still what `Pc` holds: it is where the thread actually
/// is, and a caller wanting that should not have to undo this.
void DescribeThread(ThreadLine line, Engine engine, ITarget target, uint id,
                    nuint pc)
{
    var here = engine.PositionAt(pc);
    if (here.Known)
    {
        line.File = here.File;
        line.Line = here.Line;
        line.HasSource = true;
        line.Function = engine.FunctionAt(pc);
        return;
    }

    var frames = WalkStack(target, id, engine.Unwinder, engine.Slide);
    for (nuint i = 0u; i < frames.Count; i++)
    {
        // Every frame above the first holds a return address, so the line
        // table is asked about the byte before it -- the call, not what it
        // comes back to.
        nuint asking = i == 0u ? frames[i].Pc : frames[i].Pc - 1u;

        var at = engine.PositionAt(asking);
        if (!at.Known)
            continue;

        line.File = at.File;
        line.Line = at.Line;
        line.HasSource = true;
        line.Function = engine.FunctionAt(asking);
        return;
    }

    // Nothing in the whole stack is code this program was built from, which is
    // a thread the system started for its own reasons.
    line.Function = engine.FunctionAt(pc);
}

// ====================================================== setting a session up

/// Every unit's line table, in unit order.
///
/// A unit with no `DW_AT_stmt_list` gets an empty table rather than being
/// skipped, so a table's index is its unit's index.
public List<LineTable> ReadEveryLineTable(DwarfInfo info)
{
    var made = new List<LineTable>();
    for (nuint i = 0u; i < info.Units.Count; i++)
    {
        var root = info.Units[i].Root;
        if (root == null || !((Die)root).Has(AtStmtList))
        {
            made.Add(new LineTable());
            continue;
        }
        nuint at = (nuint)((Die)root).NumberOf(AtStmtList, 0u);
        made.Add(ReadLineTable(info.LineSection, at, info.LineStrSection,
                               info.StrSection));
    }
    return made;
}

/// The link-time address a file and a line name, and the line chosen.
///
/// The chosen line is not always the one asked for: a line with no code on it
/// resolves to the first statement at or after it. A caller SHOULD show the
/// difference, or a breakpoint binds somewhere else without saying so.
public bool FindLineAddress(List<LineTable> tables, String file, uint line,
                            nuint* address, uint* chosen)
{
    for (nuint u = 0u; u < tables.Count; u++)
    {
        for (nuint f = 0u; f < tables[u].Files.Count; f++)
        {
            if (!IsTheSameSourceFile(tables[u].Files[f], file))
                continue;
            if (tables[u].AddressForLine(f, line, address, chosen))
                return true;
        }
    }
    return false;
}
