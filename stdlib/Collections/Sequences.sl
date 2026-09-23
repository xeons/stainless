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

/// Queues, stacks, linked lists and sorted maps.
///
/// All four are backed by arrays, which is not the usual choice for the last
/// two. It is the right one here: ARC cannot collect a cycle, so a doubly linked
/// list of objects would leak unless every back-link were weak, and a weak
/// reference is not usable without a way to prove it is still there. Links as
/// indices into a pool have neither problem, and are faster besides.
module Standard.Collections;


