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

module Standard.Drawing;

import Standard.Collections;
import Standard.Text;
import Standard.File;
import Standard.IO;

/// The imaging library, loaded once and shared.
///
/// **Public so that a program can ask before it tries.** A tool that writes a
/// chart wants to say "install libgd" at startup rather than at the end of a
/// long computation, and `IsAvailable` is how it finds out.
public static class Imaging
{
    static Backend? s_loaded = null;
    static bool s_tried = false;

    /// The backend, loading it if this is the first call, or null when there is
    /// none to load.
    ///
    /// **`Backend` is `threadsafe` because it is frozen, not because it locks.**
    /// Every field is a function pointer written in the constructor and never
    /// again, so there is no content for two threads to race over -- which is
    /// the same ground `String` is admitted on, and the assertion the word is
    /// for (§9.5). A `Backend` is safe for any number of threads to call at
    /// once; the backing libraries are, too.
    ///
    /// **What is not covered is this function's own first call.** Two threads
    /// reaching it together would each load the library and one of the two
    /// objects would be dropped, which leaks a module handle and nothing else.
    /// That is a stated limit rather than an oversight: a lock here would put
    /// `Standard.Threading` underneath a module that otherwise depends on
    /// nothing at all.
    static Backend? Current
    {
        get
        {
            if (s_tried)
                return s_loaded;
            s_tried = true;

            var made = new Backend();
            if (made.Ready)
                s_loaded = made;
            return s_loaded;
        }
    }

    /// Whether there is an imaging library on this machine.
    ///
    /// Loads it, so the first call is where the cost is and every `Image` after
    /// it is free.
    public static bool IsAvailable => Current != null;

    /// The name of the library behind it, for a program that reports what it
    /// found. `""` when there is none.
    public static String BackendName
    {
        get
        {
            if (Current == null)
                return "";
#if WINDOWS
            return "GDI+";
#else
            return "libgd";
#endif
        }
    }

    /// The one accessor `Image` uses. Not public: a `Backend` is this
    /// module's own vocabulary and nothing outside could do anything with one.
    static Backend? CurrentBackend => Current;
}
