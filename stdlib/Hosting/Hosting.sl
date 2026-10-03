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

/// A program that runs services until it is told to stop. .NET's Generic
/// Host, `Microsoft.Extensions.Hosting`.
///
///     public int Main(String[] args)
///     {
///         var builder = Host.CreateApplicationBuilder(args);
///         builder.Services.AddHostedService<Worker>();
///         var host = try builder.Build();
///         return host.Run();
///     }
///
/// `Run` starts every `IHostedService` in the order registered, waits for
/// Ctrl-C, `SIGTERM` or `StopApplication`, stops them in the reverse order
/// within `ShutdownTimeout`, lets go of every service, and answers the exit
/// code for `Main` to return. There is no `async`: a `BackgroundService` runs
/// on a thread of its own, and a `CancellationToken` asks it to finish.
module Standard.Hosting;

import Standard.Collections;
import Standard.DependencyInjection;
import Standard.Threading;

/// Something the host starts and stops. .NET's `IHostedService`.
public interface IHostedService
{
    /// Starts the service, and returns once it has: the host starts the next
    /// one when this returns. `token` is cancelled if starting is abandoned.
    void Start(CancellationToken token);

    /// Stops the service, and returns once it has, or once `token` is
    /// cancelled because the shutdown timeout ran out.
    void Stop(CancellationToken token);
}

/// A hosted service whose work is one long `Execute` on a thread of its own.
/// .NET's `BackgroundService`.
///
///     public sealed class Worker : BackgroundService
///     {
///         ILogger<Worker> _logger;
///         public Worker(ILogger<Worker> logger) { _logger = logger; }
///
///         protected override void Execute(CancellationToken stopping)
///         {
///             while (!stopping.WaitFor(1000u))
///                 _logger.LogInformation("working");
///         }
///     }
public abstract class BackgroundService : IHostedService
{
    CancellationTokenSource? _stopping;
    ManualResetEvent? _finished;
    Thread? _thread;

    /// The service's work. `stopping` is cancelled when the host stops; the
    /// work SHOULD return soon after, which `stopping.WaitFor` makes easy.
    protected abstract void Execute(CancellationToken stopping);

    /// Starts `Execute` on a thread of its own, and returns at once.
    public virtual void Start(CancellationToken token)
    {
        var stopping = new CancellationTokenSource();
        var finished = new ManualResetEvent(false);
        _stopping = stopping;
        _finished = finished;
        var service = this;
        var stoppingToken = stopping.Token;
        _thread = new Thread(() =>
        {
            service.Execute(stoppingToken);
            finished.Set();
        });
    }

    /// Cancels `Execute`'s token and waits for it to return, or for `token`
    /// to be cancelled. A thread still running then is let go of rather than
    /// waited for.
    public virtual void Stop(CancellationToken token)
    {
        CancellationTokenSource? stopping = _stopping;
        ManualResetEvent? finished = _finished;
        Thread? thread = _thread;
        if (stopping == null || finished == null || thread == null)
            return;

        stopping.Cancel();
        while (!finished.WaitFor(20u))
        {
            if (token.IsCancellationRequested)
            {
                thread.Detach();
                _thread = null;
                return;
            }
        }
        thread.Join();
        _thread = null;
    }
}

/// Registers `T` as a hosted service, made when the host starts; call it as
/// `services.AddHostedService<T>()`.
///
/// @typeparam T  the service, made as any registered class is
public ServiceCollection AddHostedService<T>(ServiceCollection services)
    where T : class, IHostedService
{
    services.AddSingleton<IHostedService, T>();
    return services;
}
