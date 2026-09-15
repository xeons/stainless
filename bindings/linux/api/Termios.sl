// SPDX-License-Identifier: 0BSD

// The terminal line discipline, declared and nothing else.
//
// A raw binding: entry points, structs and constants under the names the
// headers give them, so that anything in `man 3 termios` is here under the
// same spelling. `Linux.Terminal` is the layer that makes them usable.
//
// **Linux, and not POSIX in general.** The *calls* are POSIX. `struct termios`
// is not: glibc's has `c_line` and two speed fields that the BSDs and macOS do
// not, and `NCCS` is 32 here and 20 there. A file claiming to be POSIX would be
// wrong about the layout on two platforms out of three, so this one says
// `#if LINUX` and means x86-64 glibc.
//
// Three things a Windows reader will trip over:
//
//   - **The terminal is a file descriptor**, and the same one the program
//     reads and writes. 0, 1 and 2 are standard input, output and error, and
//     `isatty` is how a program asks whether any of them is a terminal at all
//     rather than a pipe.
//   - **Line editing belongs to the terminal, not the program.** By default
//     the driver collects a line, handles backspace and echoes what was typed;
//     `read` returns nothing until Enter. "Raw mode" is switching that off.
//   - **The window size is not in the terminal state.** It is an `ioctl`, and
//     it changes under a running program -- which is what `SIGWINCH` is for.
module Linux.Termios;

#if LINUX

// ================================================================= the types

/// `cc_t`, one control character.
public using cc_t = byte;

/// `speed_t` and `tcflag_t`, both 32 bits on Linux.
public using speed_t = uint;
public using tcflag_t = uint;

/// How many control characters `c_cc` holds. 32 on Linux; 20 on the BSDs,
/// which is the sort of difference that makes this file Linux's.
public const nuint NCCS = 32u;

/// `struct termios`, exactly as glibc lays it out.
///
/// `sizeof` is 60: four 32-bit flag words, one byte of `c_line`, 32 bytes of
/// `c_cc`, then two speeds. The three bytes of padding between `c_cc` and
/// `c_ispeed` are the compiler's, and are there in C too.
public struct termios
{
    public tcflag_t c_iflag;        // input modes
    public tcflag_t c_oflag;        // output modes
    public tcflag_t c_cflag;        // control modes
    public tcflag_t c_lflag;        // local modes
    public cc_t c_line;         // line discipline
    public byte[32] c_cc;           // control characters
    public speed_t c_ispeed;
    public speed_t c_ospeed;
}

/// `struct winsize`, what `TIOCGWINSZ` answers with.
///
/// The pixel fields are almost always zero: a terminal emulator knows its
/// character grid and rarely bothers to report anything else.
public struct winsize
{
    public ushort ws_row;
    public ushort ws_col;
    public ushort ws_xpixel;
    public ushort ws_ypixel;
}

// ============================================================== local modes

/// Echo input characters. Off is what a password prompt wants.
public const tcflag_t ECHO = 0x0008u;

/// Canonical mode: the driver collects a line and hands it over on Enter.
/// Off is what "raw" mostly means -- a read answers as soon as a key arrives.
public const tcflag_t ICANON = 0x0002u;

/// Turn Ctrl-C, Ctrl-Z and Ctrl-\ into signals. Off is how a program takes
/// them as ordinary keys.
public const tcflag_t ISIG = 0x0001u;

/// Enable input processing of the implementation's own. Rarely wanted.
public const tcflag_t IEXTEN = 0x8000u;

// ============================================================== input modes

/// Translate a carriage return to a newline on input. Off in raw mode, so
/// that Enter arrives as the 13 it really is.
public const tcflag_t ICRNL = 0x0100u;

/// Ctrl-S and Ctrl-Q flow control. Off, so those keys reach the program.
public const tcflag_t IXON = 0x0400u;

/// Strip the eighth bit. Off, because text is UTF-8.
public const tcflag_t ISTRIP = 0x0020u;

/// Break as an interrupt, and parity marking.
public const tcflag_t BRKINT = 0x0002u;
public const tcflag_t INPCK  = 0x0010u;

// ============================================================= output modes

/// Enable output processing -- which is what turns a newline into carriage
/// return plus newline. Off in raw mode, so a program writes both itself.
public const tcflag_t OPOST = 0x0001u;

// ============================================================ control modes

/// Character size mask, and the eight-bit setting.
public const tcflag_t CSIZE = 0x0030u;
public const tcflag_t CS8   = 0x0030u;

// =========================================================== the c_cc slots

/// The fewest bytes a read may answer with. Zero means "however many are
/// there", which with `VTIME` zero means "do not wait at all".
public const nuint VMIN = 6u;

/// How long to wait, in tenths of a second. Zero with `VMIN` zero is a poll.
public const nuint VTIME = 5u;

// ============================================================== when to act

/// Change the settings now, without waiting for output to drain.
public const int TCSANOW = 0;

/// After everything written has been sent. The one to use when turning
/// settings back, so that what the program printed is not lost.
public const int TCSADRAIN = 1;

/// The same, and discard anything typed and not yet read.
public const int TCSAFLUSH = 2;

/// `ioctl` request for the window size.
public const nuint TIOCGWINSZ = 0x5413u;

// ================================================================ the calls

public extern "C"
{
    /// Reads the terminal's current settings. -1 and `errno` on failure, which
    /// for a descriptor that is not a terminal is `ENOTTY`.
    int tcgetattr(int fd, termios* state);

    /// Writes them back. `when` is one of the `TCSA*` constants.
    ///
    /// **It succeeds if *any* of the changes took**, which is C's mistake and
    /// is inherited here: a caller that must be sure reads the state back and
    /// compares.
    int tcsetattr(int fd, int when, termios* state);

    /// Waits for everything written to be sent.
    int tcdrain(int fd);

    /// Throws away what is queued. `queue` is 0 in, 1 out, 2 both.
    int tcflush(int fd, int queue);

    /// Whether the descriptor is a terminal. 1 or 0, and 0 also for a pipe,
    /// which is the question a program printing colour should ask first.
    int isatty(int fd);

    /// The terminal's name, or null. Not thread safe; there is no reason to
    /// call it twice.
    byte* ttyname(int fd);

    /// Everything else the terminal can be asked, including its size. Variadic
    /// in C, and the third argument is a pointer for every request here.
    int ioctl(int fd, nuint request, void* argument);

    /// Where glibc keeps this thread's `errno`.
    int* __errno_location();
}

/// `errno`, which every call above reports through rather than returning.
public int Errno() => *__errno_location();

#endif
