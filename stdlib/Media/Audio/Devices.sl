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

module Standard.Media.Audio;

/// The backend, held.
///
/// A class rather than module-level storage, because a module has no static of
/// its own to keep one in (SLN0004) and the loading has to happen exactly once.
/// The functions below are the surface; this is where the handle lives.
static class Devices
{
    static Backend? s_loaded = null;
    static bool s_tried = false;

    /// The backend, loading it on the first call, or null when there is none.
    ///
    /// The first call is not itself synchronized, which is the same stated
    /// limit `Standard.Drawing` has and for the same reason: two threads
    /// reaching it together would each load the library and one of the two
    /// objects would be dropped, which leaks a module handle and nothing else.
    /// A lock here would put `Standard.Threading` underneath a module that
    /// otherwise depends on nothing.
    public static Backend? Current
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
}
