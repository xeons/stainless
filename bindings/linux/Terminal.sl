// SPDX-License-Identifier: 0BSD

// The terminal: raw mode, the window size, the cursor and colour.
//
// A convenience layer over `Linux.Termios`. `Standard.Console` writes text and
// is what a program should use for that; this is for the things that are not
// writing text — reading a key without waiting for Enter, asking how wide the
// window is, moving the cursor, and turning the colour off again.
//
// It is called `Terminal` rather than `Console` for the reason the Win32 one
// is: a module is reached by its last name segment, so a `Linux.Console` would
// shadow `Standard.Console` in every file that imported it, and a program doing
// terminal work is exactly the program that also wants to print.
//
// **Colour here is ANSI escapes, not calls.** Every terminal Linux has spoken
// to in thirty years understands them, so there is nothing to bind: the
// sequences are written to the output like any other text. What does need
// binding is the state — raw mode and the size — which is `ioctl` and
// `termios`.
//
// **Ask `IsTerminal()` first.** Writing escapes into a pipe puts them in the
// file, and a program that pipes its output somewhere should print plain text.
// That is the same rule the Win32 module states, arrived at from the other
// direction: there every call simply fails when the output is redirected.
module Linux.Terminal;

#if LINUX

import Standard.Console;
import Linux.Termios;

/// The three descriptors, which are numbers rather than handles here.
public const int Input = 0;
public const int Output = 1;
public const int Error = 2;

/// Whether the descriptor is a terminal rather than a pipe or a file.
///
/// The question to ask before writing an escape sequence, and before assuming
/// there is anybody to read a prompt.
public bool IsTerminal(int fd) { return isatty(fd) == 1; }

// ================================================================= the size

/// How many rows and columns the terminal has.
///
/// It changes under a running program, so this is asked rather than
/// remembered. Answers `(0, 0)` when the descriptor is not a terminal.
public (int, int) Size(int fd) {
    winsize measured;
    measured.ws_row = 0;
    measured.ws_col = 0;

    if (ioctl(fd, TIOCGWINSZ, (void*)&measured) != 0) { return (0, 0); }
    return ((int)measured.ws_row, (int)measured.ws_col);
}

// ============================================================== raw mode

/// A terminal's settings, kept so they can be put back.
///
/// **Put them back.** A program that leaves the terminal in raw mode leaves
/// the shell it returns to unusable — no echo, no line editing, and Ctrl-C
/// doing nothing. A destructor is what makes that hard to forget.
public class Mode {
    termios saved;
    int fd;
    bool held;

    Mode(int descriptor, termios state) {
        fd = descriptor;
        saved = state;
        held = true;
    }

    /// Puts the settings back, if they have not been put back already.
    ///
    /// `TCSADRAIN` rather than `TCSAFLUSH`: what the program has printed
    /// should reach the screen before the terminal changes under it.
    public bool Restore() {
        if (!held) { return true; }
        held = false;

        termios state = saved;
        return tcsetattr(fd, TCSADRAIN, &state) == 0;
    }

    ~Mode() { Restore(); }

    /// Turns off everything that stands between a keystroke and the program:
    /// line collection, echo, signal keys, flow control and output
    /// translation. What comes back restores the terminal.
    ///
    ///     var mode = try Raw(Terminal.Input);
    ///     ...
    ///     mode.Restore();
    ///
    /// Or simply let it go out of scope, which does the same.
    public static Result<Mode, int> Raw(int fd) {
        termios before;
        if (tcgetattr(fd, &before) != 0) { return Fail(Errno()); }

        termios wanted = before;

        wanted.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        wanted.c_oflag &= ~OPOST;
        wanted.c_cflag |= CS8;
        wanted.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);

        // A read answers as soon as anything is there, and does not wait when
        // nothing is.
        wanted.c_cc[VMIN] = 1;
        wanted.c_cc[VTIME] = 0;

        if (tcsetattr(fd, TCSAFLUSH, &wanted) != 0) { return Fail(Errno()); }
        return Ok(new Mode(fd, before));
    }

    /// The same, but leaving signals and flow control alone: the terminal
    /// stops collecting lines and stops echoing, and Ctrl-C still interrupts.
    ///
    /// This is what a prompt wants. Raw is what a full-screen program wants.
    public static Result<Mode, int> Quiet(int fd) {
        termios before;
        if (tcgetattr(fd, &before) != 0) { return Fail(Errno()); }

        termios wanted = before;
        wanted.c_lflag &= ~(ECHO | ICANON);
        wanted.c_cc[VMIN] = 1;
        wanted.c_cc[VTIME] = 0;

        if (tcsetattr(fd, TCSAFLUSH, &wanted) != 0) { return Fail(Errno()); }
        return Ok(new Mode(fd, before));
    }

    /// Echo off and nothing else, for reading a password.
    public static Result<Mode, int> Hidden(int fd) {
        termios before;
        if (tcgetattr(fd, &before) != 0) { return Fail(Errno()); }

        termios wanted = before;
        wanted.c_lflag &= ~ECHO;

        if (tcsetattr(fd, TCSAFLUSH, &wanted) != 0) { return Fail(Errno()); }
        return Ok(new Mode(fd, before));
    }
}

// ================================================================== escapes

// Written rather than called. Everything below is text going to the output,
// which is why none of it can fail and none of it returns anything.

/// The two bytes every sequence below begins with: escape, then '['.
///
/// A function rather than a `const`, because a `const` holds a number, a bool,
/// a char or an enum. A String has storage and is reference counted, and the
/// literal here is one interned object however often it is named.
String Escape() { return "["; }

/// Puts the cursor at a row and column, both counting from 1 as the terminal
/// does — which is off by one from everything else here, and is the
/// terminal's convention rather than a choice.
public void MoveTo(int row, int column) {
    Console.Write($"{Escape()}{row};{column}H");
}

public void Up(int rows) { Console.Write($"{Escape()}{rows}A"); }
public void Down(int rows) { Console.Write($"{Escape()}{rows}B"); }
public void Right(int columns) { Console.Write($"{Escape()}{columns}C"); }
public void Left(int columns) { Console.Write($"{Escape()}{columns}D"); }

/// Clears the screen and puts the cursor at the top left.
public void Clear() { Console.Write($"{Escape()}2J{Escape()}H"); }

/// Clears from the cursor to the end of the line.
public void ClearLine() { Console.Write($"{Escape()}K"); }

public void HideCursor() { Console.Write($"{Escape()}?25l"); }
public void ShowCursor() { Console.Write($"{Escape()}?25h"); }

/// Switches to the alternate screen, which is what a full-screen program uses
/// so that the scrollback it found is still there when it leaves.
public void UseAlternateScreen() { Console.Write($"{Escape()}?1049h"); }
public void UseMainScreen() { Console.Write($"{Escape()}?1049l"); }

/// The eight colours every terminal has, as their foreground codes.
public enum Colour {
    Black = 30, Red = 31, Green = 32, Yellow = 33,
    Blue = 34, Magenta = 35, Cyan = 36, White = 37,
    Default = 39,
}

public void SetColour(Colour colour) { Console.Write($"{Escape()}{(long)colour}m"); }

public void SetBackground(Colour colour) { Console.Write($"{Escape()}{(long)colour + 10}m"); }

public void Bold(bool on) { Console.Write(on ? $"{Escape()}1m" : $"{Escape()}22m"); }

/// Puts every attribute back to what it was. The one to call before leaving,
/// so the shell does not inherit a colour.
public void Reset() { Console.Write($"{Escape()}0m"); }

#endif
