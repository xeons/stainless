// SPDX-License-Identifier: 0BSD

// The terminal line discipline, declared and nothing else, as Darwin has it.
//
// The calls are the ones `Linux.Termios` declares and do the same things;
// `man 3 termios` is the reference for both. What differs is everything a
// program cannot see in the call: `tcflag_t` and `speed_t` are eight bytes
// here rather than four, `NCCS` is 20 rather than 32, there is no `c_line`,
// and most of the flags are other bits. `MacOS.Terminal` is the layer that
// makes them usable, and has the same functions as `Linux.Terminal`.
module MacOS.Termios;

#if MACOS

// ================================================================= the types

/// `cc_t`, one control character.
public using cc_t = byte;

/// `speed_t` and `tcflag_t`, both `unsigned long` on Darwin: eight bytes.
public using speed_t = ulong;
public using tcflag_t = ulong;

/// How many control characters `c_cc` holds.
public const nuint NCCS = 20u;

/// `struct termios`, exactly as Darwin lays it out.
///
/// `sizeof` is 72: four eight-byte flag words, 20 bytes of `c_cc`, four
/// bytes of padding the compiler puts there in C too, then two speeds.
public struct termios
{
    public tcflag_t c_iflag;        // input modes
    public tcflag_t c_oflag;        // output modes
    public tcflag_t c_cflag;        // control modes
    public tcflag_t c_lflag;        // local modes
    public byte[20] c_cc;           // control characters
    public speed_t c_ispeed;
    public speed_t c_ospeed;
}

/// `struct winsize`, what `TIOCGWINSZ` answers with. The same as Linux's.
public struct winsize
{
    public ushort ws_row;
    public ushort ws_col;
    public ushort ws_xpixel;
    public ushort ws_ypixel;
}

// ============================================================== local modes

/// Echo input characters. Off is what a password prompt wants.
public const tcflag_t ECHO = 0x00000008u;

/// Canonical mode: the driver collects a line and hands it over on Enter.
public const tcflag_t ICANON = 0x00000100u;

/// Turn Ctrl-C, Ctrl-Z and Ctrl-\ into signals.
public const tcflag_t ISIG = 0x00000080u;

/// Enable input processing of the implementation's own.
public const tcflag_t IEXTEN = 0x00000400u;

// ============================================================== input modes

/// Translate a carriage return to a newline on input.
public const tcflag_t ICRNL = 0x00000100u;

/// Ctrl-S and Ctrl-Q flow control.
public const tcflag_t IXON = 0x00000200u;

/// Strip the eighth bit.
public const tcflag_t ISTRIP = 0x00000020u;

/// Break as an interrupt, and parity checking.
public const tcflag_t BRKINT = 0x00000002u;
public const tcflag_t INPCK = 0x00000010u;

// ============================================================= output modes

/// Enable output processing, which turns a newline into carriage return plus
/// newline.
public const tcflag_t OPOST = 0x00000001u;

// ============================================================ control modes

/// Character size mask, and the eight-bit setting.
public const tcflag_t CSIZE = 0x00000300u;
public const tcflag_t CS8 = 0x00000300u;

// =========================================================== the c_cc slots

/// The fewest bytes a read may answer with.
public const nuint VMIN = 16u;

/// How long to wait, in tenths of a second.
public const nuint VTIME = 17u;

// ============================================================== when to act

public const int TCSANOW = 0;
public const int TCSADRAIN = 1;
public const int TCSAFLUSH = 2;

/// `ioctl` request for the window size: `_IOR('t', 104, struct winsize)`.
public const ulong TIOCGWINSZ = 0x40087468u;

// ================================================================ the calls

public extern "C"
{
    /// Reads the terminal's current settings. -1 and `errno` on failure, which
    /// for a descriptor that is not a terminal is `ENOTTY`.
    int tcgetattr(int fd, termios* state);

    /// Writes them back. **It succeeds if any of the changes took**, as on
    /// Linux.
    int tcsetattr(int fd, int when, termios* state);

    int tcdrain(int fd);
    int tcflush(int fd, int queue);

    /// Whether the descriptor is a terminal. 1 or 0.
    int isatty(int fd);

    byte* ttyname(int fd);

    /// Variadic in C, and on Apple silicon a variadic argument travels on the
    /// stack rather than in a register, so it is declared as one: the pointer
    /// to a `winsize` is otherwise read from wherever the stack points.
    int ioctl(int fd, ulong request, ...);

    /// Where Darwin keeps this thread's `errno`.
    int* __error();
}

/// `errno`, which every call above reports through rather than returning.
public int GetErrno() => *__error();

#endif
