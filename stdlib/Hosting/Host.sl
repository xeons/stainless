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

import Standard.DependencyInjection;
import Standard.Logging;
import Standard.Process;
import Standard.Threading;
import Standard.Time;

/// A built host. .NET's `IHost`.
public sealed class Host
{
    ServiceProvider _services;
    HostApplicationLifetime _lifetime;
    HostEnvironment _environment;

    /// How long hosted services have to stop before the host lets go of them.
    public TimeSpan ShutdownTimeout = TimeSpan.FromSeconds(5);

    internal Host(ServiceProvider services, HostApplicationLifetime lifetime, HostEnvironment environment)
    {
        _services = services;
        _lifetime = lifetime;
        _environment = environment;
    }

    /// A builder with the defaults: configuration from `appsettings.json`, the
    /// environment and `arguments`, and logging to the console.
    ///
    /// @param arguments  the program's command line, read as configuration
    public static HostApplicationBuilder CreateApplicationBuilder(String[] arguments) =>
        new HostApplicationBuilder(arguments);

    /// What the host made, and makes.
    public ServiceProvider Services => _services;

    /// Starts every hosted service, waits until Ctrl-C, `SIGTERM` or
    /// `StopApplication`, stops them in the reverse order, and lets go of every
    /// service.
    ///
    /// @returns the exit code a service set on the lifetime, 0 by default
    public int Run()
    {
        var logger = _services.GetRequiredService<ILoggerFactory>().CreateLogger("Standard.Hosting.Lifetime");
        var hosted = _services.GetServices<IHostedService>();

        for (nuint i = 0u; i < hosted.Length; i++)
            hosted[i].Start(CancellationToken.None);

        _lifetime.NotifyStarted();
        logger.LogInformation("Application started. Press Ctrl+C to shut down.");
        logger.LogInformation("Hosting environment: " + _environment.EnvironmentName);
        logger.LogInformation("Content root path: " + _environment.ContentRootPath);

        WaitForShutdown();
        logger.LogInformation("Application is shutting down...");

        var timeout = new CancellationTokenSource();
        timeout.CancelAfter((ulong)ShutdownTimeout.TotalMilliseconds);
        for (nuint i = hosted.Length; i > 0u; i--)
            hosted[i - 1u].Stop(timeout.Token);
        timeout.Cancel();

        _lifetime.NotifyStopped();
        int exitCode = _lifetime.ExitCode;
        _services.Dispose();
        return exitCode;
    }

    /// Blocks until something asks the host to stop: a signal or
    /// `StopApplication`, whichever comes first.
    void WaitForShutdown()
    {
        var stopping = _lifetime.ApplicationStopping;
        bool watching = Signals.StartWatching();
        while (!stopping.IsCancellationRequested)
        {
            if (watching)
            {
                if (Signals.WaitForInterrupt(100u))
                    _lifetime.StopApplication();
            }
            else
            {
                stopping.WaitFor(100u);
            }
        }
    }
}
