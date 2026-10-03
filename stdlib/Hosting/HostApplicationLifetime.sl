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

import Standard.Threading;

/// When the host has started, is stopping and has stopped, and how to ask it
/// to stop. .NET's `IHostApplicationLifetime`.
public interface IHostApplicationLifetime
{
    /// Cancelled once every hosted service has started.
    CancellationToken ApplicationStarted { get; }

    /// Cancelled when the host begins to stop.
    CancellationToken ApplicationStopping { get; }

    /// Cancelled once every hosted service has stopped.
    CancellationToken ApplicationStopped { get; }

    /// Asks the host to stop, as Ctrl-C does. `Run` returns once it has.
    void StopApplication();

    /// What `Run` answers, for `Main` to return: 0 unless something sets it.
    int ExitCode { get; set; }
}

/// The lifetime a host registers.
public sealed threadsafe class HostApplicationLifetime : IHostApplicationLifetime
{
    CancellationTokenSource _started = new CancellationTokenSource();
    CancellationTokenSource _stopping = new CancellationTokenSource();
    CancellationTokenSource _stopped = new CancellationTokenSource();
    AtomicInt _exitCode = new AtomicInt(0);

    public CancellationToken ApplicationStarted => _started.Token;
    public CancellationToken ApplicationStopping => _stopping.Token;
    public CancellationToken ApplicationStopped => _stopped.Token;

    public void StopApplication() => _stopping.Cancel();

    public int ExitCode
    {
        get => _exitCode.Read();
        set => _exitCode.Write(value);
    }

    internal void NotifyStarted() => _started.Cancel();
    internal void NotifyStopped() => _stopped.Cancel();
}

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
