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

module Standard;

/// Something that can be finished with before its last reference goes.
/// .NET's `System.IDisposable`.
///
/// **A destructor already frees what an object holds** when the last
/// reference to it goes, so most types need neither this nor a call to it.
/// `Dispose` is for the moment that comes earlier: a response whose
/// connection should go back to its pool while the response is still held, a
/// client others share that should refuse further work, a registration to
/// undo while its owner lives on. A type that has one SHOULD let it be called
/// more than once, and SHOULD do it from its destructor too, so that
/// forgetting it costs nothing but promptness.
public interface IDisposable
{
    /// Releases now what would otherwise be released at the last reference.
    void Dispose();
}
