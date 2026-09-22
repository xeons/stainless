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

// Game controllers, as a program wants them.
//
// A convenience layer over `Win32.XInput`. It names xinput itself with a
// pragma, so a program compiling it needs no `-l`.
//
// Three things are added to the raw layer, and each is something every caller
// would otherwise write:
//
// - **A dead zone.** A stick at rest does not read zero. `Pad.LeftStick` is
//   radial-dead-zoned and scaled to -1.0 to 1.0, which is what a game actually
//   wants; `Pad.Raw` is there when it is not.
// - **Edges.** A menu cares that A was *pressed*, not that it is down. A
//   `Pad` remembers the previous reading, so `WasPressed` and `WasReleased`
//   are questions it can answer.
// - **Not polling an empty slot every frame.** `XInputGetState` on a slot with
//   nothing in it is slow -- it goes looking -- and a game that walks four
//   slots at 60 Hz spends real time on the three that are empty. A `Pad` that
//   found nothing waits a second before looking again.
module Win32.Gamepad;

import Standard.Text;
import Win32.XInput;

#if WINDOWS

#pragma comment(lib, "xinput")

extern "C"
{
    long sl_time_monotonic();
}

/// How long to leave an empty slot alone, in nanoseconds. One second, which is
/// Microsoft's own guidance.
const ulong RescanInterval = 1000000000u;

/// Which button, named rather than spelled as a bit.
///
/// The names are the ones on an Xbox pad, because that is what XInput
/// describes and a pad that pretends to be one has agreed to those positions.
public enum Button : ushort
{
    DPadUp = 0x0001u,
    DPadDown = 0x0002u,
    DPadLeft = 0x0004u,
    DPadRight = 0x0008u,
    Start = 0x0010u,
    Back = 0x0020u,
    LeftStick = 0x0040u,
    RightStick = 0x0080u,
    LeftShoulder = 0x0100u,
    RightShoulder = 0x0200u,
    A = 0x1000u,
    B = 0x2000u,
    X = 0x4000u,
    Y = 0x8000u,
}

/// A stick, as a direction and a magnitude rather than two numbers.
///
/// `X` and `Y` are -1.0 to 1.0 with the dead zone removed and the rest
/// rescaled, so a stick just outside the dead zone reads near zero rather than
/// jumping to a quarter. Positive Y is up, which is what the hardware reports
/// and the opposite of what a screen coordinate does.
public struct Stick
{
    public double X;
    public double Y;

    /// How far from centre, 0.0 to 1.0. Clamped to 1.0 at the corners, where
    /// the raw values would otherwise reach about 1.41 together.
    public double Magnitude
    {
        get
        {
            double length = ComputeSquareRoot(X * X + Y * Y);
            return length > 1.0 ? 1.0 : length;
        }
    }

    /// Whether the stick is outside its dead zone at all.
    public bool IsMoved => X != 0.0 || Y != 0.0;
}

extern "C" double sqrt(double x);

double ComputeSquareRoot(double value) => sqrt(value);

/// One controller slot, remembered between polls.
///
/// ```csharp
/// var pad = new Pad(0u);
/// while (running)
/// {
///     pad.Poll();
///     if (pad.WasPressed(Button.A)) { Jump(); }
///     Move(pad.LeftStick);
/// }
/// ```
///
/// **Made rather than found.** There is no enumeration in XInput: the slots
/// are 0 to 3 and a program makes a `Pad` for each one it cares about.
/// `IsConnected` is false until a poll finds something, and stays correct as
/// the pad is plugged and unplugged.
public class Pad
{
    uint _slot;
    XINPUT_STATE _state;
    ushort _previousButtons;
    bool _connected;
    bool _everPolled;
    ulong _nextScan;

    /// A pad for slot `slot`, which must be 0 to 3. Nothing is asked of the
    /// system until the first `PollState`.
    public Pad(uint slot)
    {
        _slot = slot;
        _previousButtons = (ushort)0;
        _connected = false;
        _everPolled = false;
        _nextScan = 0u;
    }

    /// Which slot this is.
    public uint Slot => _slot;

    /// Whether the last poll found a controller.
    public bool IsConnected => _connected;

    /// Reads the controller, and says whether one was there.
    ///
    /// Call this once a frame. An empty slot is only actually asked about once
    /// a second; in between, this answers false without touching the system.
    public bool PollState()
    {
        _previousButtons = _connected ? _state.Gamepad.wButtons : (ushort)0;

        if (!_connected && _everPolled && (ulong)sl_time_monotonic() < _nextScan)
            return false;

        _everPolled = true;

        XINPUT_STATE reading;
        uint code = XInputGetState(_slot, &reading);

        if (code != ERROR_SUCCESS)
        {
            _connected = false;
            _nextScan = (ulong)sl_time_monotonic() + RescanInterval;
            return false;
        }

        _state = reading;
        _connected = true;
        return true;
    }

    /// The whole reading, undead-zoned, for a caller that wants the numbers
    /// the hardware gave.
    public XINPUT_GAMEPAD Raw => _state.Gamepad;

    /// The packet number of the last reading. It changes only when something
    /// on the pad changed, so two equal readings in a row mean nothing moved.
    public uint Packet => _state.dwPacketNumber;

    /// Whether a button is down now.
    public bool IsDown(Button button) =>
        _connected && (_state.Gamepad.wButtons & (ushort)button) != 0u;

    /// Whether a button went down between the last two polls.
    public bool WasPressed(Button button) =>
        _connected && (_state.Gamepad.wButtons & (ushort)button) != 0u &&
        (_previousButtons & (ushort)button) == 0u;

    /// Whether a button came up between the last two polls.
    public bool WasReleased(Button button) =>
        (_previousButtons & (ushort)button) != 0u &&
        (!_connected || (_state.Gamepad.wButtons & (ushort)button) == 0u);

    /// The left stick, dead-zoned and scaled.
    public Stick LeftStick =>
        ScaleStick(_state.Gamepad.sThumbLX, _state.Gamepad.sThumbLY,
               XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

    /// The right stick, dead-zoned and scaled. Its dead zone is larger, which
    /// is the hardware's asymmetry rather than this module's.
    public Stick RightStick =>
        ScaleStick(_state.Gamepad.sThumbRX, _state.Gamepad.sThumbRY,
               XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);

    /// The left trigger, 0.0 to 1.0, with everything below the threshold read
    /// as nothing.
    public double LeftTrigger => ScaleTrigger(_state.Gamepad.bLeftTrigger);

    /// The right trigger, 0.0 to 1.0.
    public double RightTrigger => ScaleTrigger(_state.Gamepad.bRightTrigger);

    /// Sets both motors, 0.0 to 1.0 each, and says whether the pad took it.
    ///
    /// **The two motors are not the same.** The left is a heavy weight and
    /// gives a low rumble; the right is lighter and gives a buzz. Equal numbers
    /// do not give "medium", they give both at once.
    public bool SetRumble(double low, double high)
    {
        if (!_connected)
            return false;

        XINPUT_VIBRATION vibration;
        vibration.wLeftMotorSpeed = ScaleMotorSpeed(low);
        vibration.wRightMotorSpeed = ScaleMotorSpeed(high);
        return XInputSetState(_slot, &vibration) == ERROR_SUCCESS;
    }

    /// Both motors off. Worth calling before a program exits: the pad keeps
    /// buzzing after the process that set it has gone.
    public bool StopRumble() => SetRumble(0.0, 0.0);

    /// What kind of device this is -- one of the `XINPUT_DEVSUBTYPE_*` values.
    /// A wheel and a flight stick both arrive as XInput devices and report
    /// their shape here.
    public byte SubType
    {
        get
        {
            XINPUT_CAPABILITIES capabilities;
            if (XInputGetCapabilities(_slot, XINPUT_FLAG_GAMEPAD, &capabilities) != ERROR_SUCCESS)
                return XINPUT_DEVSUBTYPE_UNKNOWN;
            return capabilities.SubType;
        }
    }

    /// Whether the pad has motors to rumble at all. A wheel usually reports
    /// force feedback and a guitar reports nothing.
    public bool HasVibration
    {
        get
        {
            XINPUT_CAPABILITIES capabilities;
            if (XInputGetCapabilities(_slot, XINPUT_FLAG_GAMEPAD, &capabilities) != ERROR_SUCCESS)
                return false;
            return capabilities.Vibration.wLeftMotorSpeed != 0u ||
                   capabilities.Vibration.wRightMotorSpeed != 0u;
        }
    }

    /// How much battery is left: one of the `BATTERY_LEVEL_*` values, and
    /// `BATTERY_LEVEL_FULL` for a wired pad, which has no battery to be low.
    ///
    /// Four levels and no percentage, because four levels is what the hardware
    /// reports.
    public byte BatteryLevel
    {
        get
        {
            XINPUT_BATTERY_INFORMATION battery;
            if (XInputGetBatteryInformation(_slot, BATTERY_DEVTYPE_GAMEPAD, &battery) != ERROR_SUCCESS)
                return BATTERY_LEVEL_FULL;
            if (battery.BatteryType == BATTERY_TYPE_WIRED ||
                battery.BatteryType == BATTERY_TYPE_DISCONNECTED)
                return BATTERY_LEVEL_FULL;
            return battery.BatteryLevel;
        }
    }

    /// A radial dead zone, which is the right shape.
    ///
    /// The obvious implementation zeroes each axis on its own, and the result
    /// is a square hole: a stick pushed diagonally by a little registers on
    /// neither axis, and one pushed straight along an axis registers sooner
    /// than one pushed at 45 degrees. Measuring the length and scaling both
    /// axes together is what makes the stick feel round.
    Stick ScaleStick(short x, short y, short deadZone)
    {
        Stick stick;
        stick.X = 0.0;
        stick.Y = 0.0;

        if (!_connected)
            return stick;

        double horizontal = (double)x;
        double vertical = (double)y;
        double length = ComputeSquareRoot(horizontal * horizontal + vertical * vertical);
        double edge = (double)deadZone;

        if (length <= edge)
            return stick;

        // The full range is 32767, and what is left after the dead zone is
        // rescaled to fill it -- so the stick reaches 1.0 at the rim rather
        // than at 0.76 of it.
        double scale = (length - edge) / ((32767.0 - edge) * length);
        stick.X = horizontal * scale;
        stick.Y = vertical * scale;

        if (stick.X > 1.0)
            stick.X = 1.0;
        if (stick.X < -1.0)
            stick.X = -1.0;
        if (stick.Y > 1.0)
            stick.Y = 1.0;
        if (stick.Y < -1.0)
            stick.Y = -1.0;

        return stick;
    }

    double ScaleTrigger(byte value)
    {
        if (!_connected || value <= XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
            return 0.0;

        double threshold = (double)XINPUT_GAMEPAD_TRIGGER_THRESHOLD;
        return ((double)value - threshold) / (255.0 - threshold);
    }

    ushort ScaleMotorSpeed(double amount)
    {
        if (amount <= 0.0)
            return (ushort)0;
        if (amount >= 1.0)
            return (ushort)65535;
        return (ushort)(amount * 65535.0);
    }
}

/// A `Pad` for every slot, made once.
///
/// The usual shape for a game: four pads, polled together, with the ones that
/// are not plugged in costing nothing.
public Pad[] CreateAllPads()
{
    Pad[] pads = new Pad[XUSER_MAX_COUNT];
    for (nuint i = 0u; i < pads.Length; i++)
        pads[i] = new Pad((uint)i);
    return pads;
}

/// How many of `pads` found a controller, after polling every one.
public nuint PollAllPads(Pad[] pads)
{
    nuint found = 0u;
    for (nuint i = 0u; i < pads.Length; i++)
    {
        if (pads[i].PollState())
            found++;
    }
    return found;
}

/// A subtype as text, for a program that reports what it found.
public String DescribeSubType(byte subType)
{
    if (subType == XINPUT_DEVSUBTYPE_GAMEPAD)
        return "gamepad";
    if (subType == XINPUT_DEVSUBTYPE_WHEEL)
        return "wheel";
    if (subType == XINPUT_DEVSUBTYPE_ARCADE_STICK)
        return "arcade stick";
    if (subType == XINPUT_DEVSUBTYPE_FLIGHT_STICK)
        return "flight stick";
    if (subType == XINPUT_DEVSUBTYPE_DANCE_PAD)
        return "dance pad";
    if (subType == XINPUT_DEVSUBTYPE_GUITAR || subType == XINPUT_DEVSUBTYPE_GUITAR_ALTERNATE)
        return "guitar";
    if (subType == XINPUT_DEVSUBTYPE_GUITAR_BASS)
        return "bass guitar";
    if (subType == XINPUT_DEVSUBTYPE_DRUM_KIT)
        return "drum kit";
    if (subType == XINPUT_DEVSUBTYPE_ARCADE_PAD)
        return "arcade pad";
    return "unknown";
}

#endif
