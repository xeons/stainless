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

module Standard.Process;

import Standard.Collections;

// ----------------------------------------------------------------- signals

/// Ctrl-C, asked for rather than delivered.
///
/// A signal handler runs between two instructions of whatever was executing,
/// so almost nothing is legal inside one: no allocation, no locks, and
/// therefore no Stainless at all. What is legal is a store to a flag, so that
/// is what the handler does, and this is where a program reads it -- at the
/// top of its own loop, where it can actually tidy up.
///
///     Signals.StartWatching();
///     while (!Signals.Interrupted) { DoAPieceOfWork(); }
///     Console.WriteLine("stopping");
public static class Signals
{
    /// Starts noticing interrupts. Until this is called they end the program,
    /// which is the right default for something that has nothing to tidy.
    public static bool StartWatching() => sl_signals_watch();

    /// Whether one has arrived since the last `ClearInterrupt`.
    public static bool Interrupted => sl_signals_interrupted();

    /// Forgets the one that arrived, for a program that means to carry on.
    public static void ClearInterrupt() => sl_signals_clear();
}
