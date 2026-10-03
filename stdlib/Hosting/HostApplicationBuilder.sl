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

import Standard.Configuration;
import Standard.DependencyInjection;
import Standard.Env;
import Standard.Logging;
import Standard.Path;

/// The services, their configuration and their logging, built into a host.
/// .NET's `HostApplicationBuilder`.
public sealed class HostApplicationBuilder
{
    ConfigurationError? _failure;

    /// What the host will make. Register hosted services here.
    public ServiceCollection Services = new ServiceCollection();

    /// The settings, read when the builder was made: `appsettings.json`, then
    /// `appsettings.{EnvironmentName}.json`, both optional, then environment
    /// variables, then the command line.
    public Configuration Configuration = new Configuration();

    /// Where log messages go, and at what level. The console, with the levels
    /// the `Logging` section of the configuration names, unless changed.
    public LoggingBuilder Logging = new LoggingBuilder();

    /// Where the host runs.
    public HostEnvironment Environment;

    internal HostApplicationBuilder(String[] arguments)
    {
        String root = CurrentDirectory();
        String environment = GetEnvironmentVariableOrDefault("STAINLESS_ENVIRONMENT", "Production");
        String program = GetProcessPath();
        long slash = program.LastIndexOf("/");
        long backslash = program.LastIndexOf("\\");
        long cut = slash > backslash ? slash : backslash;
        String name = cut < 0 ? program : program.Substring((nuint)cut + 1u);
        Environment = new HostEnvironment(environment, root, name);

        var built = new ConfigurationBuilder()
            .AddJsonFile(Path.Join(root, "appsettings.json"), optional: true)
            .AddJsonFile(Path.Join(root, "appsettings." + environment + ".json"), optional: true)
            .AddEnvironmentVariables()
            .AddCommandLine(arguments)
            .Build();
        if (built.Ok)
            Configuration = built.Value;
        else
            _failure = built.Error;

        Logging.AddConsole().AddConfiguration(Configuration.GetSection("Logging"));
    }

    /// The host, its services checked as `BuildServiceProvider` checks them.
    ///
    /// @returns the host, or every problem with the configuration files or the
    ///          registrations, one per line
    public Result<Host, String> Build()
    {
        ConfigurationError? failure = _failure;
        if (failure != null)
            return Fail(failure.Message);

        var lifetime = new HostApplicationLifetime();
        var logging = Logging;
        Services.AddSingletonInstance<Configuration>(Configuration);
        Services.AddSingletonInstance<IConfiguration>(Configuration);
        Services.AddSingletonInstance<IHostEnvironment>(Environment);
        Services.AddSingletonInstance<IHostApplicationLifetime>(lifetime);
        Services.AddSingleton<ILoggerFactory>((ServiceProvider provider) => logging.Build());

        var built = Services.BuildServiceProvider();
        if (!built.Ok)
            return Fail(built.Error.Message);
        return Ok(new Host(built.Value, lifetime, Environment));
    }
}
