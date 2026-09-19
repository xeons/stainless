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
        return Ok(Continue());
    }

    /// Runs until something stops it.
    public Stop Continue()
    {
        while (true)
        {
            // A breakpoint the process is standing on has to be stepped off
            // before anything can run.
            if (_steppingOver != null)
                StepOffBreakpoint();

            var happened = _target.Wait(60000u);
            var answer = Interpret(happened);
            if (answer != null)
                return (Stop)answer;
        }
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
        // A single step, which this engine only ever asks for in order to get
        // off a breakpoint it is standing on.
        if (code == StepExceptionCode())
        {
            if (_steppingOver != null)
            {
                PlantOne((Breakpoint)_steppingOver);
                _steppingOver = null;
                // The processor clears the trap flag itself when it takes the
                // exception, so there is nothing to turn off -- only something
                // not to turn on again.
                _target.Resume(true);
                return null;
            }

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

    /// Where a stop happened, as a source line -- the whole point of the
    /// reading half being here.
    public String Describe(nuint runtimeAddress)
    {
        nuint linked = ToLinked(runtimeAddress);
        for (nuint u = 0u; u < _tables.Count; u++)
        {
            var row = _tables[u].RowCovering(linked);
            if (row == null)
                continue;
            var here = (LineRow)row;
            return _tables[u].FileName(here.File) + ":"
                 + Standard.Text.FromInteger((long)here.Line);
        }
        return "0x" + FormatHexadecimal((ulong)linked) + " (no line)";
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
