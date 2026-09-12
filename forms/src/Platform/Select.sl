// Stainless - an experimental systems language.
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

// Which backend this program was built against.
//
// **The whole of the platform choice is this file**, and it is made at compile
// time rather than at run time: a program built for Windows links no GTK, and
// the `#if` is what says so. The LCL makes the same choice the same way, in
// `interfaces/lcl.pas`, by which unit is added to the `uses` clause.
//
// One function, because `IWidgetSet` is what the rest of the library talks to
// and this is the only place anything names an implementation of it.
module Forms;

import Forms.Platform;

#if WINDOWS
import Forms.Platform.Win32;
#endif

/// Makes the backend this program was compiled for.
///
/// Called once, by `Application.Initialize`. A program that wants a different
/// one -- a recording widget set under test, or a choice made at run time --
/// assigns `WidgetSet.Current` itself and never calls `Initialize`.
IWidgetSet MakeWidgetSet() {
#if WINDOWS
    return new Win32WidgetSet();
#else
    sl_fail("this build of Forms has no widget set: only Windows is implemented".ToPointer());
    return new Win32WidgetSet();
#endif
}
