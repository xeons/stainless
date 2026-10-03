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

module Standard.DependencyInjection;

/// Says which class `GetService` makes for an instantiation of a generic
/// interface that nothing registered: `[DefaultImplementation("App.Logger")]`
/// on `ILogger<T>` makes `App.Logger<T>` for any `T`. The class MUST take the
/// interface's type parameters in the same order.
///
/// It is how one declaration serves every instantiation, which .NET does by
/// registering an open generic -- impossible here, where an instantiation is
/// made by the compiler.
public attribute DefaultImplementation
{
    String TypeName;
}
