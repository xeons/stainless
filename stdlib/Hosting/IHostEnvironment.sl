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

module Standard.Hosting;

/// Where the host runs. .NET's `IHostEnvironment`.
public interface IHostEnvironment
{
    /// `Production` unless `STAINLESS_ENVIRONMENT` says otherwise:
    /// `Development` and `Staging` are the other names in use.
    String EnvironmentName { get; }

    /// The directory configuration files are read from: the working
    /// directory when the host was built.
    String ContentRootPath { get; }

    /// The program's name, from its path.
    String ApplicationName { get; }
}
