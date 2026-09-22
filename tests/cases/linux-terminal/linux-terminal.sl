// SPDX-License-Identifier: 0BSD
//
// The Linux terminal and event bindings.
//
// Everything here is checked against the headers rather than against
// documentation: `sizeof(termios)` is 60 because glibc's is, `epoll_event` is
// 12 because it is packed on x86-64, and every constant was printed from the
// real header before it was written down. A misfiled number in a binding is a
// program that reads the wrong field, which is much harder to find later than
// it is to check now.
//
// The terminal half runs under a pipe, which is what a test harness gives it —
// so `IsTerminal` is false here and the raw-mode calls are expected to be
// refused. That is the interesting case anyway: a program that writes escape
// sequences into a pipe puts them in the file.
module LinuxTerminal;

import Standard.Console;
import Linux.Terminal;
import Linux.Termios;
import Linux.Events;

public int Main()
{
    // ------------------------------------------------------------ the layout

    Console.WriteLine($"termios  {sizeof(termios)}");
    Console.WriteLine($"winsize  {sizeof(winsize)}");
    Console.WriteLine($"epoll    {sizeof(epoll_event)}");
    Console.WriteLine($"inotify  {sizeof(inotify_event)}");
    Console.WriteLine($"itimer   {sizeof(itimerspec)}");
    Console.WriteLine($"offsets  {offsetof(termios, c_cc)} {offsetof(termios, c_ispeed)}");

    // --------------------------------------------------------- the terminal

    // Under the harness the output is a pipe, so this is false and every
    // termios call is refused -- which is the answer a program should ask for
    // before writing an escape sequence anywhere.
    Console.WriteLine($"tty      {IsTerminal(Terminal.Output)}");

    var mode = Mode.EnterRawMode(Terminal.Input);
    Console.WriteLine($"raw      refused {!mode.Ok}");

    var (rows, columns) = Size(Terminal.Output);
    Console.WriteLine($"size     {rows} {columns}");

    // ------------------------------------------------------------ the loop

    // One epoll wait covering a wakeup from elsewhere and a timer, which is
    // the whole point: on Linux both are descriptors, so both go in the same
    // wait as a socket would.
    int ep = epoll_create1(EPOLL_CLOEXEC);
    int wake = eventfd(0u, EFD_CLOEXEC | EFD_NONBLOCK);

    epoll_event watched;
    watched.events = EPOLLIN;
    watched.data = 42u;

    Console.WriteLine($"made     {ep >= 0} {wake >= 0}");
    Console.WriteLine($"added    {epoll_ctl(ep, EPOLL_CTL_ADD, wake, &watched) == 0}");

    // Nothing has happened, so a zero timeout answers with nothing.
    epoll_event[8] ready;
    Console.WriteLine($"quiet    {epoll_wait(ep, &ready[0], 8, 0) == 0}");

    // Writing eight bytes to the eventfd is how one thread wakes another.
    ulong one = 1u;
    write(wake, (void*)&one, 8u);

    int seen = epoll_wait(ep, &ready[0], 8, 1000);
    Console.WriteLine($"woken    {seen == 1} data {ready[0].data} readable {(ready[0].events & EPOLLIN) != 0u}");

    // A timer is a descriptor that becomes readable when it fires.
    int timer = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC);

    itimerspec when;
    when.it_interval.tv_sec = 0L;
    when.it_interval.tv_nsec = 0L;
    when.it_value.tv_sec = 0L;
    when.it_value.tv_nsec = 20000000L;          // 20ms

    watched.data = 99u;
    Console.WriteLine($"timer    {timerfd_settime(timer, 0, &when, null) == 0}");
    epoll_ctl(ep, EPOLL_CTL_ADD, timer, &watched);

    seen = epoll_wait(ep, &ready[0], 8, 2000);
    Console.WriteLine($"fired    {seen >= 1}");

    // And a watcher on a directory.
    int watcher = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
    int wd = inotify_add_watch(watcher, "/tmp".ToPointer(), IN_ALL_EDITS);
    Console.WriteLine($"inotify  {watcher >= 0} {wd >= 0}");

    // Nothing has changed, and the descriptor was asked not to wait.
    byte[64] buffer;
    nint got = read(watcher, (void*)&buffer[0], 64u);
    Console.WriteLine($"nothing  {got < 0 && Events.GetErrno() == EAGAIN}");

    close(watcher);
    close(timer);
    close(wake);
    close(ep);
    return 0;
}
