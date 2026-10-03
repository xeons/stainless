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

/// The environment a host registers.
public sealed class HostEnvironment : IHostEnvironment
{
    String _environmentName;
    String _contentRootPath;
    String _applicationName;

    public HostEnvironment(String environmentName, String contentRootPath, String applicationName)
    {
        _environmentName = environmentName;
        _contentRootPath = contentRootPath;
        _applicationName = applicationName;
    }

    public String EnvironmentName => _environmentName;
    public String ContentRootPath => _contentRootPath;
    public String ApplicationName => _applicationName;

    /// Whether this is the `Development` environment.
    public bool IsDevelopment => _environmentName.EqualsIgnoreCaseAscii("Development");

    /// Whether this is the `Production` environment.
    public bool IsProduction => _environmentName.EqualsIgnoreCaseAscii("Production");
}
