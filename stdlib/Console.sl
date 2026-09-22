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

/// Standard input and output, as text.
///
/// Bytes cross unchanged in both directions. A `String` is already UTF-8, so
/// nothing is transcoded on the way out, and input is read as bytes and taken
/// to be UTF-8 -- which is what a program piped a UTF-8 file needs, and is
/// wrong for a Windows console typed into by hand, where the active code page
/// arrives instead. Reading typed non-ASCII there wants `ReadConsoleW`.
///
/// A Windows console also keeps the C runtime's text mode, where Ctrl-Z ends
/// typed input and LF is shown as CR LF. A pipe or a file does not.
///
/// This module is not imported automatically. Printing is a choice, and a
/// program that never prints has no reason to carry `Write` in scope.
module Standard.Console;

// The runtime's, declared here and called directly. `String` crosses as the
// pointer it is, and the two that answer with one hand back a reference the
// caller owns.
extern "C"
{
    void sl_console_write(String text);
    void sl_console_write_line(String text);
    void sl_console_write_error(String text);
    void sl_console_flush();

    String? sl_console_read_line();
    String  sl_console_read_all();
    bool    sl_console_at_end();
}

// ------------------------------------------------------------------ writing

/// Text, with nothing after it.
public void Write(String text) => sl_console_write(text);

/// Text and a newline.
public void WriteLine(String text) => sl_console_write_line(text);

/// Text and a newline, on stderr.
///
/// The newline is not optional here as it is for stdout. A diagnostic is a
/// whole line by the time anything reads it, and stderr is unbuffered, so a
/// partial one would interleave with whatever wrote next.
public void WriteError(String text) => sl_console_write_error(text);

/// Pushes what is buffered out to the operating system.
///
/// stdout is line buffered at a terminal and block buffered into a pipe, so a
/// program whose output another program is reading may so far have written
/// nothing the reader can see. A process killed rather than returned from
/// loses whatever is still held.
public void Flush() => sl_console_flush();

// ------------------------------------------------------------------ reading

/// One line without its terminator, or null at the end of input.
///
/// Null rather than empty, because a blank line and no line at all are
/// different answers and a loop reading until there is nothing left has to
/// tell them apart.
public String? ReadLine() => sl_console_read_line();

/// Everything left on stdin, as one string.
public String ReadToEnd() => sl_console_read_all();

/// Whether stdin has reached its end.
///
/// It reads a byte to find out and pushes it back, so it answers only when
/// the stream has something to say: on one that is open and idle it waits.
public bool AtEnd() => sl_console_at_end();
