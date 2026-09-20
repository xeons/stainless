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

// Breakpoints and run control: the half that needs a live process.
//
// **The slide is the only thing the reading half could not know.** Everything
// in the DWARF is an address the linker chose; the loader may put the image
// somewhere else, and every translation between the two is a subtraction by
// one number this file learns when the process starts. A debugger that forgets
// it works perfectly on Windows, where the preferred base is usually honoured,
// and misses every breakpoint on Linux, where a position-independent
// executable never lands at zero.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// `int3`, the one-byte instruction that stops a process.
///
/// One byte matters: a longer trap would overwrite the instruction after the
/// one being trapped, so restoring it would need to know how long that was --
/// which is a disassembler, for a problem this size.
const byte Int3 = 0xCC;

/// One planted breakpoint.
public class Breakpoint
{
    /// Where it is, in the running process rather than in the file.
    public nuint Address;

    /// The byte that was there, which must go back before the instruction can
    /// execute.
    public byte Original;

    public bool Planted;

    /// What a person asked for, kept so a report can name it.
    public String Where;

    public Breakpoint(nuint address, String where)
    {
        Address = address;
        Original = 0;
        Planted = false;
        Where = where;
    }
}

/// Why the engine came back.
public enum StopKind
{
    /// It has not started or has already finished.
    NotRunning,
    /// A breakpoint this engine planted.
    Breakpoint,
    /// One instruction, after a step.
    Step,
    /// Something the program did.
    Fault,
    /// It ran to the end.
    Exited,
    /// Break All: somebody asked it to stop while it was running.
    ///
    /// The platform cannot tell this from a fault. An injected `int3` and a
    /// `SIGSTOP` both arrive as a stop at an address nothing was planted at;
    /// only the engine knows it asked.
    Paused,
}

/// What the engine was doing when it stopped.
public class Stop
{
    public StopKind Kind;
    public uint Thread;
    public nuint Address;
    public uint Code;
    public int ExitCode;

    /// The breakpoint that fired, when one did.
    public Breakpoint? At;

    public Stop(StopKind kind)
    {
        Kind = kind;
        Thread = 0u;
        Address = 0u;
        Code = 0u;
        ExitCode = 0;
        At = null;
    }
}

/// A place in the source, as the line table gave it.
///
/// A pair rather than a formatted `file.sl:41`. Splitting one back apart means
/// guessing which colon separates them, and a Windows drive letter has an
/// opinion about that.
public class SourcePosition
{
    public String File;
    public uint Line;

    /// False when the address has no line at all, which is what says the code
    /// belongs to the runtime rather than to the program.
    public bool Known;

    public SourcePosition(String file, uint line, bool known)
    {
        File = file;
        Line = line;
        Known = known;
    }
}

/// A function, with the unit it was described in.
///
/// Both together because neither is useful alone: a local's type is a reference
/// form, and a reference only resolves through its own unit's table.
public class Subprogram
{
    public Unit InUnit;
    public Die Die;

    public Subprogram(Unit unit, Die die)
    {
        InUnit = unit;
        Die = die;
    }
}

/// A debugging session: an image, its DWARF, and the process it is running.
public class Engine
{
    ITarget _target;
    Image _image;
    DwarfInfo _info;
    List<LineTable> _tables;
    List<Breakpoint> _breakpoints;

    /// Runtime address minus link-time address. Zero until the process starts.
    nuint _slide;
    bool _slideKnown;

    /// The breakpoint whose original byte is currently back in place because
    /// the process is standing on it, and the thread doing the standing.
    ///
    /// **This is the case everybody gets wrong once.** Continuing from a
    /// breakpoint means executing the instruction it replaced, which means the
    /// trap byte cannot be there -- and putting it back afterwards means
    /// knowing when afterwards is. The answer is one single-step, and this
    /// field is what remembers why the step is happening.
    Breakpoint? _steppingOver;
    uint _steppingThread;

    /// Whether the single step now in flight is one somebody asked for.
    ///
    /// Getting off a breakpoint is a step too, by the same mechanism: the trap
    /// is lifted, one instruction runs, the trap goes back. Both arrive as the
    /// same event, and only this says which.
    bool _stepIsWanted;

    /// Whether the next unexplained stop is one `RequestBreak` asked for.
    ///
    /// Written by whichever thread called Break All, read by the session's own.
    /// See `RequestBreak` for why that needs no lock.
    bool _breakWanted;

    /// What the program has written through `OutputDebugString`, or its
    /// platform equivalent, since anybody last asked.
    ///
    /// Collected rather than handed to a callback: a callback would run with
    /// the process stopped, where a debugger must do as little as possible.
    ///
    /// The program's own stdout and stderr do not arrive here. Redirecting
    /// those needs the target seam to set up pipes.
    List<String> _output;

    public Engine(ITarget target, Image image, DwarfInfo info,
                  List<LineTable> tables)
    {
        _target = target;
        _image = image;
        _info = info;
        _tables = tables;
        _breakpoints = new List<Breakpoint>();
        _slide = 0u;
        _slideKnown = false;
        _steppingOver = null;
        _steppingThread = 0u;
        _stepIsWanted = false;
        _breakWanted = false;
        _output = new List<String>();
    }

    /// Everything the program has written since this was last called, and
    /// empties the list.
    public List<String> TakeOutput()
    {
        var so_far = _output;
        _output = new List<String>();
        return so_far;
    }

    public List<Breakpoint> Breakpoints => _breakpoints;
    public nuint Slide => _slide;
    public bool SlideKnown => _slideKnown;

    /// A link-time address as the running process sees it.
    public nuint ToRuntime(nuint linked) => linked + _slide;

    /// And back, which is what a stop address has to be turned into before the
    /// line table can be asked about it.
    public nuint ToLinked(nuint running) => running - _slide;

    /// Records a breakpoint. It is planted when the process starts, or at once
    /// if it already has.
    public Breakpoint Add(nuint linkedAddress, String where)
    {
        var made = new Breakpoint(linkedAddress, where);
        _breakpoints.Add(made);
        if (_slideKnown)
            PlantOne(made);
        return made;
    }

    /// Starts the program and runs it to its first stop.
    public Result<Stop, String> Start(String path, String arguments)
    {
        var started = _target.Launch(path, arguments);
        if (!started.Ok)
            return Fail(started.Error);

        // Waits rather than continuing. `Continue` resumes first, which is
        // right from a stop the caller has been told about; a just-launched
        // process has not been told about anything. Under ptrace the launch
        // has already reaped the exec's SIGTRAP, so resuming here would let
        // the program run before its image base was read.
        return Ok(WaitForStop());
    }

    /// Asks a running program to stop, from a thread that is not this one.
    ///
    /// The only method on this class another thread MAY call. The session's
    /// own thread is blocked inside `Continue` and cannot be asked for
    /// anything.
    ///
    /// The flag is set before the target is asked, and the order matters. The
    /// stop cannot arrive before the system call that causes it, and that call
    /// is a barrier on both platforms, so a thread that sees the stop has
    /// already seen the flag. No lock is needed.
    public bool RequestBreak()
    {
        if (!_target.IsRunning)
            return false;
        _breakWanted = true;
        if (_target.RequestBreak())
            return true;

        // Nothing was interrupted, so nothing will arrive to clear it.
        _breakWanted = false;
        return false;
    }

    /// Runs until something stops it.
    ///
    /// Every path here MUST resume. A stopped target waits for a `Resume` that
    /// answers the event it reported; without one it does not run and the next
    /// wait sits until it times out.
    public Stop Continue()
    {
        // A breakpoint the process is standing on has to be stepped off before
        // anything can run, and that resumes as part of doing it.
        if (_steppingOver != null)
            StepOffBreakpoint();
        else
            _target.Resume(true);
        return WaitForStop();
    }

    /// Turns one platform event into a stop, or null to keep going.
    Stop? Interpret(DebugEvent happened)
    {
        switch (happened)
        {
            case Started started:
            {
                // **The one number the reading half could not know.**
                _slide = started.imageBase - _image.PreferredBase;
                _slideKnown = true;
                PlantEvery();
                _target.Resume(true);
                return null;
            }

            case Exited ended:
            {
                var stop = new Stop(StopKind.Exited);
                stop.ExitCode = ended.code;
                return stop;
            }

            case Stopped where:
                return InterpretStop(where.thread, where.address, where.code,
                                     where.firstChance);

            case Output wrote:
                _output.Add(wrote.text);
                _target.Resume(true);
                return null;

            case Nothing:
                // A timeout, or an event this engine does not act on. Either
                // way the process is waiting to be let go.
                _target.Resume(true);
                return null;

            default:
                _target.Resume(true);
                return null;
        }
    }

    Stop? InterpretStop(uint thread, nuint address, uint code,
                        bool firstChance)
    {
        // Asked for, so not a fault. Tested before the breakpoint cases: a
        // program interrupted while sitting on a planted trap is a real race,
        // and the answer there is still that it paused.
        if (_breakWanted)
        {
            _breakWanted = false;
            var paused = new Stop(StopKind.Paused);
            paused.Thread = thread;
            paused.Address = address;
            return paused;
        }

        // A single step, which this engine only ever asks for in order to get
        // off a breakpoint it is standing on.
        if (code == StepExceptionCode())
        {
            // Whatever the step was for, a breakpoint that was lifted to let
            // it happen goes back now.
            if (_steppingOver != null)
            {
                PlantOne((Breakpoint)_steppingOver);
                _steppingOver = null;
            }

            // The processor clears the trap flag itself when it takes the
            // exception, so there is nothing to turn off -- only something not
            // to turn on again.
            if (!_stepIsWanted)
            {
                _target.Resume(true);
                return null;
            }

            _stepIsWanted = false;
            var stop = new Stop(StopKind.Step);
            stop.Thread = thread;
            stop.Address = address;
            return stop;
        }

        if (code == BreakpointExceptionCode())
        {
            // **The trap has already executed, so the program counter is one
            // byte past it.** Reporting the address the exception carried is
            // right; leaving the register where it is means resuming into the
            // middle of the instruction the trap replaced.
            var hit = FindBreakpoint(address);
            if (hit != null)
            {
                RewindOnto(thread, address);
                UnplantOne((Breakpoint)hit);
                _steppingOver = hit;
                _steppingThread = thread;

                var stop = new Stop(StopKind.Breakpoint);
                stop.Thread = thread;
                stop.Address = address;
                stop.At = hit;
                return stop;
            }
        }

        // Something the program did. A first-chance exception is handed back so
        // the program's own handler can have it; a second-chance one is the end.
        var fault = new Stop(StopKind.Fault);
        fault.Thread = thread;
        fault.Address = address;
        fault.Code = code;
        return fault;
    }

    /// Puts the trap byte back and single-steps off it.
    void StepOffBreakpoint()
    {
        var one = _steppingOver;
        if (one == null)
            return;
        _target.SetSingleStep(_steppingThread, true);
        _target.Resume(true);
    }

    void PlantEvery()
    {
        for (nuint i = 0u; i < _breakpoints.Count; i++)
            PlantOne(_breakpoints[i]);
    }

    /// Saves the byte that is there and writes the trap.
    bool PlantOne(Breakpoint one)
    {
        if (one.Planted)
            return true;

        nuint at = ToRuntime(one.Address);
        byte[] saved = new byte[1];
        if (!_target.ReadMemory(at, saved, 1u))
            return false;

        // Already trapped -- two breakpoints on one address, or a re-plant that
        // never unplanted. Saving 0xCC as the original is how a breakpoint
        // becomes permanent.
        if (saved[0u] == Int3)
        {
            one.Planted = true;
            return true;
        }

        one.Original = saved[0u];
        byte[] trap = [Int3];
        if (!_target.WriteMemory(at, trap, 1u))
            return false;

        one.Planted = true;
        return true;
    }

    bool UnplantOne(Breakpoint one)
    {
        if (!one.Planted)
            return true;
        byte[] back = [one.Original];
        bool ok = _target.WriteMemory(ToRuntime(one.Address), back, 1u);
        one.Planted = false;
        return ok;
    }

    Breakpoint? FindBreakpoint(nuint runtimeAddress)
    {
        for (nuint i = 0u; i < _breakpoints.Count; i++)
        {
            if (ToRuntime(_breakpoints[i].Address) == runtimeAddress)
                return _breakpoints[i];
        }
        return null;
    }

    /// Puts the program counter back on to the trapped instruction.
    void RewindOnto(uint thread, nuint address)
    {
        Registers registers;
        registers.Pc = 0u;
        registers.StackPointer = 0u;
        registers.FramePointer = 0u;
        if (!_target.ReadRegisters(thread, &registers))
            return;
        registers.Pc = address;
        _target.WriteRegisters(thread, &registers);
    }

    // ------------------------------------------------------------- stepping

    /// One machine instruction.
    ///
    /// The building block of everything below, and the only thing here that
    /// does not consult the line table.
    public Stop StepInstruction(uint thread)
    {
        _stepIsWanted = true;

        if (_steppingOver != null)
        {
            // Already standing on a breakpoint: the step off it *is* the step
            // that was asked for, so this does not add a second one.
            StepOffBreakpoint();
            return WaitForStop();
        }

        _target.SetSingleStep(thread, true);
        _target.Resume(true);
        return WaitForStop();
    }

    /// Runs until one of this engine's breakpoints or something worse.
    Stop WaitForStop()
    {
        while (true)
        {
            var happened = _target.Wait(60000u);
            var answer = Interpret(happened);
            if (answer != null)
                return (Stop)answer;
        }
    }

    /// Steps one source line, entering any function that has line information
    /// and running straight through any that has none.
    ///
    /// **Running through a function with no lines is the point, not a
    /// shortcut.** Under `-g` the C runtime is compiled `-O0 -g` too, so
    /// stepping into `sl_retain` is a thing that can happen -- and a step that
    /// lands in the allocator is a step nobody asked for. A function this
    /// engine has no lines for is stepped over whole.
    public Stop StepIn(uint thread) => StepLine(thread, false);

    /// Steps one source line, running whole any function that is called.
    public Stop StepOver(uint thread) => StepLine(thread, true);

    Stop StepLine(uint thread, bool over)
    {
        Registers start;
        start.Pc = 0u;
        start.StackPointer = 0u;
        start.FramePointer = 0u;
        if (!_target.ReadRegisters(thread, &start))
            return new Stop(StopKind.NotRunning);

        String startLine = LineKeyAt(start.Pc);

        // **Where the current function is, which is how a call is recognised.**
        //
        // The obvious test is that the stack pointer went down, and it is
        // wrong: a function's own prologue pushes the frame pointer, so the
        // first instruction of every function looks like a call was taken.
        // Stepping into `Total` then "arrived" at `Total` again and stopped
        // dead on its opening line, and stepping over it read a saved `rbp`
        // where it expected a return address and planted a breakpoint on
        // nothing.
        //
        // Leaving the function's address range is what a call actually is.
        nuint low = 0u;
        nuint high = 0u;
        bool bounded = FunctionRangeAt(start.Pc, &low, &high);

        // A bound on the work rather than on the answer: a single source line
        // is a few dozen instructions, and a loop that never leaves it means
        // something is wrong that a debugger should not hang over.
        for (int guard = 0; guard < 200000; guard++)
        {
            var stop = StepInstruction(thread);
            if (stop.Kind != StopKind.Step)
                return stop;

            Registers now;
            now.Pc = 0u;
            now.StackPointer = 0u;
            now.FramePointer = 0u;
            if (!_target.ReadRegisters(thread, &now))
                return stop;

            bool inside = bounded && now.Pc >= low && now.Pc < high;
            if (!inside)
            {
                // Deeper: a call. The program counter is at the callee's first
                // instruction, so the cell the stack pointer names is the
                // return address `call` pushed -- and nothing has pushed over
                // it yet, which is why the range test has to be what gets us
                // here.
                if (now.StackPointer < start.StackPointer)
                {
                    bool known = LineKeyAt(now.Pc).ByteLength() != 0u;
                    if (over || !known)
                    {
                        var ran = RunToReturn(thread, now.StackPointer);
                        if (ran.Kind != StopKind.Step)
                            return ran;
                        continue;
                    }
                    // Stepping in, and the callee has lines: the step ends at
                    // its first instruction.
                    //
                    // **Not at its `prologue_end`**, which is where a
                    // breakpoint on the function belongs and is a different
                    // question. Running there means a temporary breakpoint,
                    // and a temporary breakpoint at an address chosen from the
                    // line table without proving it is inside this function is
                    // 0xCC written into somebody else's code. It is worth
                    // doing and worth doing carefully; see the note in
                    // `debug/README.md`.
                    return AtLine(stop, now.Pc);
                }

                // Shallower, or sideways with no range to judge by: the frame
                // returned, and the step ends wherever the caller is.
                return AtLine(stop, now.Pc);
            }

            String here = LineKeyAt(now.Pc);
            if (here.ByteLength() != 0u && here != startLine)
                return AtLine(stop, now.Pc);
        }

        return new Stop(StopKind.Step);
    }

    /// Runs to the end of the current function.
    public Stop StepOut(uint thread)
    {
        var frames = WalkStack(_target, thread);
        if (frames.Count < 2u)
        {
            // Nothing above this frame: running out of it is running to the
            // end of the program.
            return Continue();
        }
        return RunToAddress(thread, frames[1u].Pc);
    }

    /// Runs until the address the stack pointer is pointing at is reached,
    /// which is how a call is stepped over.
    Stop RunToReturn(uint thread, nuint stackPointer)
    {
        byte[] cell = new byte[8];
        if (!_target.ReadMemory(stackPointer, cell, 8u))
            return new Stop(StopKind.Step);
        return RunToAddress(thread, (nuint)LittleEndianWord(cell));
    }

    /// A breakpoint that exists for one stop.
    ///
    /// It goes through the same planting as a real one, so the step-off dance
    /// applies to it as well -- which is why it is removed *after* the stop
    /// rather than before resuming.
    Stop RunToAddress(uint thread, nuint runtimeAddress)
    {
        var already = FindBreakpoint(runtimeAddress);
        if (already != null)
            return Continue();          // there is already one there

        var temporary = new Breakpoint(ToLinked(runtimeAddress), "");
        _breakpoints.Add(temporary);
        PlantOne(temporary);

        var stop = Continue();

        if (_steppingOver == temporary)
        {
            // It fired. Step off it before taking it away, or the original byte
            // never goes back -- and say the step is wanted, or the same flag
            // that keeps `Continue` from stopping on housekeeping swallows this
            // one and the wait runs to the end of the program.
            _stepIsWanted = true;
            StepOffBreakpoint();
            WaitForStop();
        }
        UnplantOne(temporary);
        RemoveBreakpoint(temporary);

        // A stop at the temporary breakpoint is a completed step rather than a
        // breakpoint the caller asked for.
        if (stop.Kind == StopKind.Breakpoint && stop.At == temporary)
        {
            var done = new Stop(StopKind.Step);
            done.Thread = stop.Thread;
            done.Address = stop.Address;
            return done;
        }
        return stop;
    }

    /// The subprogram containing an address, and the unit it belongs to.
    ///
    /// Both, because an entry is only meaningful beside its unit: a reference
    /// form resolves through the unit's table, and the type of a local is a
    /// reference.
    public Subprogram? SubprogramAt(nuint runtimeAddress)
    {
        nuint linked = ToLinked(runtimeAddress);
        for (nuint u = 0u; u < _info.Units.Count; u++)
        {
            var one = _info.Units[u];
            for (nuint i = 0u; i < one.Dies.Count; i++)
            {
                var each = one.Dies[i];
                if (each.Tag != TagSubprogram)
                    continue;
                nuint from = 0u;
                nuint to = 0u;
                if (each.Range(&from, &to) && linked >= from && linked < to)
                    return new Subprogram(one, each);
            }
        }
        return null;
    }

    /// The runtime address range of the function containing an address.
    public bool FunctionRangeAt(nuint runtimeAddress, nuint* low, nuint* high)
    {
        nuint linked = ToLinked(runtimeAddress);
        for (nuint u = 0u; u < _info.Units.Count; u++)
        {
            var unit = _info.Units[u];
            for (nuint i = 0u; i < unit.Dies.Count; i++)
            {
                var die = unit.Dies[i];
                if (die.Tag != TagSubprogram)
                    continue;
                nuint from = 0u;
                nuint to = 0u;
                if (die.Range(&from, &to) && linked >= from && linked < to)
                {
                    *low = ToRuntime(from);
                    *high = ToRuntime(to);
                    return true;
                }
            }
        }
        return false;
    }

    void RemoveBreakpoint(Breakpoint one)
    {
        for (nuint i = 0u; i < _breakpoints.Count; i++)
        {
            if (_breakpoints[i] == one)
            {
                _breakpoints.RemoveAt(i);
                return;
            }
        }
    }

    Stop AtLine(Stop stop, nuint pc)
    {
        stop.Address = pc;
        return stop;
    }

    /// Which source line an address is on.
    public SourcePosition PositionAt(nuint runtimeAddress)
    {
        nuint linked = ToLinked(runtimeAddress);
        for (nuint u = 0u; u < _tables.Count; u++)
        {
            var row = _tables[u].RowCovering(linked);
            if (row == null)
                continue;
            var here = (LineRow)row;
            return new SourcePosition(_tables[u].FileName(here.File),
                                      here.Line, true);
        }
        return new SourcePosition("", 0u, false);
    }

    /// A file and line as one string, for telling two positions apart.
    ///
    /// Empty when the address has no line at all, which is what says a function
    /// belongs to the runtime rather than to the program.
    String LineKeyAt(nuint runtimeAddress)
    {
        var here = PositionAt(runtimeAddress);
        if (!here.Known)
            return "";
        return here.File + ":" + Standard.Text.FromInteger((long)here.Line);
    }

    /// Where a stop happened, as a source line -- the whole point of the
    /// reading half being here.
    public String Describe(nuint runtimeAddress)
    {
        var here = PositionAt(runtimeAddress);
        if (here.Known)
            return here.File + ":" + Standard.Text.FromInteger((long)here.Line);
        return "0x" + FormatHexadecimal((ulong)ToLinked(runtimeAddress))
             + " (no line)";
    }

    /// The function an address fell in, or "".
    public String FunctionAt(nuint runtimeAddress)
    {
        nuint linked = ToLinked(runtimeAddress);
        for (nuint u = 0u; u < _info.Units.Count; u++)
        {
            var unit = _info.Units[u];
            for (nuint i = 0u; i < unit.Dies.Count; i++)
            {
                var die = unit.Dies[i];
                if (die.Tag != TagSubprogram)
                    continue;
                nuint low = 0u;
                nuint high = 0u;
                if (die.Range(&low, &high) && linked >= low && linked < high)
                    return die.Name;
            }
        }
        return "";
    }

    public void Terminate() => _target.Terminate();
}
