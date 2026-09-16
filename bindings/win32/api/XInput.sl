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

// xinput1_4.dll: game controllers.
//
// Eight entry points and four structs, which is the whole of XInput. It reads
// like an afterthought next to DirectInput and that is its virtue: a
// controller is polled, it has a fixed set of controls, and there is nothing
// to enumerate, configure or negotiate.
//
// **Only an XInput device.** That means an Xbox controller and the very large
// number of pads that pretend to be one. A flight stick with eleven axes, a
// racing wheel with a clutch, and an old DirectInput joystick are none of
// them, and the answer for those is `IDirectInput8`, which is not bound.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l xinput`, or `Win32.Gamepad`,
// which names it with a pragma.
//
// See `Win32.Gamepad` for the conveniences over these.
module Win32.XInput;

#if WINDOWS

// ================================================================= structs

/// `XINPUT_GAMEPAD`: every control on the pad, in one reading.
///
/// The sticks are signed and run to 32767 in each direction, which means -32768
/// is reachable and +32768 is not; the triggers are unsigned bytes. Both are
/// raw -- no dead zone has been applied, and `Win32.Gamepad` is where that
/// happens.
public struct XINPUT_GAMEPAD
{
    /// The buttons, as the `XINPUT_GAMEPAD_*` bits.
    public ushort wButtons;

    /// 0 to 255. `XINPUT_GAMEPAD_TRIGGER_THRESHOLD` is where Microsoft
    /// suggests calling it pressed.
    public byte bLeftTrigger;

    public byte bRightTrigger;

    /// -32768 to 32767, positive right and positive up.
    public short sThumbLX;
    public short sThumbLY;
    public short sThumbRX;
    public short sThumbRY;
}

/// `XINPUT_STATE`. The packet number changes only when something on the pad
/// changed, so a program that keeps the last one can skip the work when the
/// two agree -- which is cheaper than comparing the gamepad structs.
public struct XINPUT_STATE
{
    public uint dwPacketNumber;
    public XINPUT_GAMEPAD Gamepad;
}

/// `XINPUT_VIBRATION`: the two motors, 0 to 65535 each.
///
/// They are not the same motor. The left is a heavy weight and gives a low
/// rumble; the right is lighter and gives a buzz. Setting both to the same
/// number does not give "medium".
public struct XINPUT_VIBRATION
{
    public ushort wLeftMotorSpeed;
    public ushort wRightMotorSpeed;
}

/// `XINPUT_CAPABILITIES`: what this device has.
///
/// The `Gamepad` field is a mask rather than a reading -- a bit or a nonzero
/// field means the control exists, not that it is being pressed.
public struct XINPUT_CAPABILITIES
{
    public byte Type;
    public byte SubType;
    public ushort Flags;
    public XINPUT_GAMEPAD Gamepad;
    public XINPUT_VIBRATION Vibration;
}

/// `XINPUT_BATTERY_INFORMATION`.
public struct XINPUT_BATTERY_INFORMATION
{
    public byte BatteryType;
    public byte BatteryLevel;
}

/// `XINPUT_KEYSTROKE`: a button as a keyboard-shaped event, for a menu that
/// wants presses and repeats rather than a state to poll.
public struct XINPUT_KEYSTROKE
{
    public ushort VirtualKey;
    public char16 Unicode;
    public ushort Flags;
    public byte UserIndex;
    public byte HidCode;
}

// ============================================================== entry points

public extern "C" __stdcall
{
    // Both of these return a Win32 error code rather than an HRESULT:
    // ERROR_SUCCESS when there is a pad, ERROR_DEVICE_NOT_CONNECTED when the
    // slot is empty. **Do not poll an empty slot every frame** -- the call is
    // slow when nothing is there, because it goes looking, and Microsoft's own
    // guidance is to check one disconnected slot per second at most.
    uint XInputGetState(uint dwUserIndex, XINPUT_STATE* pState);
    uint XInputSetState(uint dwUserIndex, XINPUT_VIBRATION* pVibration);

    uint XInputGetCapabilities(uint dwUserIndex, uint dwFlags,
                               XINPUT_CAPABILITIES* pCapabilities);

    uint XInputGetBatteryInformation(uint dwUserIndex, byte devType,
                                     XINPUT_BATTERY_INFORMATION* pBatteryInformation);

    uint XInputGetKeystroke(uint dwUserIndex, uint dwReserved,
                            XINPUT_KEYSTROKE* pKeystroke);

    // The audio endpoints a headset plugged into the pad appears as, as
    // strings `Standard.Media.Audio` could open. Each count is in and out: pass
    // the buffer size, get the length used.
    uint XInputGetAudioDeviceIds(uint dwUserIndex, char16* pRenderDeviceId,
                                 uint* pRenderCount, char16* pCaptureDeviceId,
                                 uint* pCaptureCount);

    // Deprecated since Windows 10 and declared for completeness. It used to
    // mute the pads while a program was in the background; the modern answer
    // is to stop polling.
    void XInputEnable(int enable);
}

// ================================================================ constants

/// How many pads XInput knows about. The index is 0 to 3 and there is no
/// enumeration: a program walks the four.
public const uint XUSER_MAX_COUNT = 4u;

/// `ERROR_SUCCESS`.
public const uint ERROR_SUCCESS = 0u;

/// `ERROR_DEVICE_NOT_CONNECTED`: the slot is empty. Not a failure.
public const uint ERROR_DEVICE_NOT_CONNECTED = 1167u;

// ------------------------------------------------------------------ buttons

public const ushort XINPUT_GAMEPAD_DPAD_UP = 0x0001u;
public const ushort XINPUT_GAMEPAD_DPAD_DOWN = 0x0002u;
public const ushort XINPUT_GAMEPAD_DPAD_LEFT = 0x0004u;
public const ushort XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008u;
public const ushort XINPUT_GAMEPAD_START = 0x0010u;
public const ushort XINPUT_GAMEPAD_BACK = 0x0020u;
public const ushort XINPUT_GAMEPAD_LEFT_THUMB = 0x0040u;
public const ushort XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080u;
public const ushort XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100u;
public const ushort XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200u;
public const ushort XINPUT_GAMEPAD_A = 0x1000u;
public const ushort XINPUT_GAMEPAD_B = 0x2000u;
public const ushort XINPUT_GAMEPAD_X = 0x4000u;
public const ushort XINPUT_GAMEPAD_Y = 0x8000u;

// ---------------------------------------------------------------- dead zones

/// What Microsoft suggests treating as "the stick is centred". A stick at rest
/// does not read zero, and a program that does not apply one of these drifts.
public const short XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE = 7849;
public const short XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE = 8689;

/// And where a trigger counts as pressed.
public const byte XINPUT_GAMEPAD_TRIGGER_THRESHOLD = 30;

// ------------------------------------------------------------------- devices

/// `XINPUT_DEVTYPE_GAMEPAD`: the only device type there is.
public const byte XINPUT_DEVTYPE_GAMEPAD = 0x01;

public const byte XINPUT_DEVSUBTYPE_UNKNOWN = 0x00;
public const byte XINPUT_DEVSUBTYPE_GAMEPAD = 0x01;
public const byte XINPUT_DEVSUBTYPE_WHEEL = 0x02;
public const byte XINPUT_DEVSUBTYPE_ARCADE_STICK = 0x03;
public const byte XINPUT_DEVSUBTYPE_FLIGHT_STICK = 0x04;
public const byte XINPUT_DEVSUBTYPE_DANCE_PAD = 0x05;
public const byte XINPUT_DEVSUBTYPE_GUITAR = 0x06;
public const byte XINPUT_DEVSUBTYPE_GUITAR_ALTERNATE = 0x07;
public const byte XINPUT_DEVSUBTYPE_DRUM_KIT = 0x08;
public const byte XINPUT_DEVSUBTYPE_GUITAR_BASS = 0x0B;
public const byte XINPUT_DEVSUBTYPE_ARCADE_PAD = 0x13;

/// `XINPUT_CAPS_*`: what the device reports it can do.
public const ushort XINPUT_CAPS_VOICE_SUPPORTED = 0x0004u;
public const ushort XINPUT_CAPS_FFB_SUPPORTED = 0x0001u;
public const ushort XINPUT_CAPS_WIRELESS = 0x0002u;
public const ushort XINPUT_CAPS_PMD_SUPPORTED = 0x0008u;
public const ushort XINPUT_CAPS_NO_NAVIGATION = 0x0010u;

/// `XINPUT_FLAG_GAMEPAD`: ask `XInputGetCapabilities` about pads only. Zero
/// asks about every device type, of which there is currently one.
public const uint XINPUT_FLAG_GAMEPAD = 0x00000001u;

// ------------------------------------------------------------------ battery

public const byte BATTERY_DEVTYPE_GAMEPAD = 0x00;
public const byte BATTERY_DEVTYPE_HEADSET = 0x01;

/// The pad is not connected, so there is nothing to report.
public const byte BATTERY_TYPE_DISCONNECTED = 0x00;

/// Wired, so there is no battery rather than a full one.
public const byte BATTERY_TYPE_WIRED = 0x01;

public const byte BATTERY_TYPE_ALKALINE = 0x02;
public const byte BATTERY_TYPE_NIMH = 0x03;
public const byte BATTERY_TYPE_UNKNOWN = 0xFF;

/// Four levels and no percentage: that is all the hardware reports.
public const byte BATTERY_LEVEL_EMPTY = 0x00;
public const byte BATTERY_LEVEL_LOW = 0x01;
public const byte BATTERY_LEVEL_MEDIUM = 0x02;
public const byte BATTERY_LEVEL_FULL = 0x03;

// ------------------------------------------------------------------ keystroke

public const ushort XINPUT_KEYSTROKE_KEYDOWN = 0x0001u;
public const ushort XINPUT_KEYSTROKE_KEYUP = 0x0002u;
public const ushort XINPUT_KEYSTROKE_REPEAT = 0x0004u;

/// `VK_PAD_*`: the virtual key codes `XInputGetKeystroke` reports.
public const ushort VK_PAD_A = 0x5800u;
public const ushort VK_PAD_B = 0x5801u;
public const ushort VK_PAD_X = 0x5802u;
public const ushort VK_PAD_Y = 0x5803u;
public const ushort VK_PAD_RSHOULDER = 0x5804u;
public const ushort VK_PAD_LSHOULDER = 0x5805u;
public const ushort VK_PAD_LTRIGGER = 0x5806u;
public const ushort VK_PAD_RTRIGGER = 0x5807u;
public const ushort VK_PAD_DPAD_UP = 0x5810u;
public const ushort VK_PAD_DPAD_DOWN = 0x5811u;
public const ushort VK_PAD_DPAD_LEFT = 0x5812u;
public const ushort VK_PAD_DPAD_RIGHT = 0x5813u;
public const ushort VK_PAD_START = 0x5814u;
public const ushort VK_PAD_BACK = 0x5815u;
public const ushort VK_PAD_LTHUMB_PRESS = 0x5816u;
public const ushort VK_PAD_RTHUMB_PRESS = 0x5817u;

#endif
