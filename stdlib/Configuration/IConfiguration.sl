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

module Standard.Configuration;

import Standard.Collections;

/// What both a whole configuration and a section of it answer.
/// .NET's `IConfiguration`.
public interface IConfiguration
{
    /// The value at `key`, below this one, or null.
    ///
    /// @param key  a path, its parts joined with `:`
    String? GetValue(String key);

    /// The section at `key`, below this one. A section nothing is under exists
    /// all the same, and answers null for every value.
    ///
    /// @param key  a path, its parts joined with `:`
    ConfigurationSection GetSection(String key);

    /// The sections directly below this one, in the order first written.
    List<ConfigurationSection> GetChildren();
}
