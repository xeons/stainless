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

/// Text over streams: the readers and writers that sit on `IStream`.
///
/// `Standard.IO` declared a second time, because streams and the text on top
/// of them are one module and two files' worth of code.
///
/// **A line ends at a newline, and a carriage return before it is not part of
/// it.** Text written on one platform is read on the other constantly, and a
/// reader that handed back a trailing `\r` would push that job onto every
/// caller. What is written is `NewLine`, which is `"\n"` unless set --
/// deliberately not the platform's, because a program that writes a file
/// should decide what is in it rather than inherit an answer from the machine
/// it happens to run on.
module Standard.IO;

import Standard.Text;
import Standard.Collections;
import Standard.Encoding;


