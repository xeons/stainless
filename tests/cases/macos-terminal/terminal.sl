// SPDX-License-Identifier: 0BSD
//
// The macOS terminal and event bindings, measured against Darwin's headers and
// then used.
//
// Every constant and every size is compared with what probe.c says the header
// says, because a misfiled number in a binding is a program that reads the
// wrong field. `termios` is the one most worth checking: its flags are eight
// bytes here and four on Linux, so a layout copied from the other is wrong
// in every field after the first.
//
// The terminal half runs under a pipe, which is what a test harness gives it,
// so raw mode is expected to be refused. The kqueue half runs for real: a
// wakeup another thread would send, a timer, and a file being written to.
module MacTerminal;

import Standard.Console;
import Standard.File;
import MacOS.Terminal;
import MacOS.Termios;
import MacOS.Events;

extern "C"
{
    long probe_sizeof_termios();
    long probe_offset_c_cc();
    long probe_offset_c_ispeed();
    long probe_sizeof_winsize();
    long probe_sizeof_kevent();
    long probe_offset_udata();
    long probe_nccs();
    long probe_echo();
    long probe_icanon();
    long probe_isig();
    long probe_iexten();
    long probe_icrnl();
    long probe_ixon();
    long probe_istrip();
    long probe_brkint();
    long probe_inpck();
    long probe_opost();
    long probe_csize();
    long probe_cs8();
    long probe_vmin();
    long probe_vtime();
    long probe_tcsadrain();
    long probe_tcsaflush();
    long probe_tiocgwinsz();
    long probe_evfilt_read();
    long probe_evfilt_write();
    long probe_evfilt_vnode();
    long probe_evfilt_proc();
    long probe_evfilt_signal();
    long probe_evfilt_timer();
    long probe_evfilt_user();
    long probe_ev_add();
    long probe_ev_delete();
    long probe_ev_enable();
    long probe_ev_disable();
    long probe_ev_oneshot();
    long probe_ev_clear();
    long probe_ev_dispatch();
    long probe_ev_error();
    long probe_ev_eof();
    long probe_note_trigger();
    long probe_note_seconds();
    long probe_note_useconds();
    long probe_note_nseconds();
    long probe_note_delete();
    long probe_note_write();
    long probe_note_extend();
    long probe_note_attrib();
    long probe_note_link();
    long probe_note_rename();
    long probe_note_revoke();
    long probe_o_evtonly();
    long probe_o_cloexec();
    long probe_eintr();
    long probe_eagain();
}

/// Zero when the binding agrees with the header, and one when it does not.
int Check(String name, long bound, long header)
{
    if (bound == header)
        return 0;
    Console.WriteLine($"{name}: the binding says {bound}, the header says {header}");
    return 1;
}

public int Main()
{
    int wrong = 0;
    wrong += Check("sizeof(termios)", (long)sizeof(termios), probe_sizeof_termios());
    wrong += Check("offsetof(termios, c_cc)", (long)offsetof(termios, c_cc), probe_offset_c_cc());
    wrong += Check("offsetof(termios, c_ispeed)", (long)offsetof(termios, c_ispeed), probe_offset_c_ispeed());
    wrong += Check("sizeof(winsize)", (long)sizeof(winsize), probe_sizeof_winsize());
    wrong += Check("sizeof(kevent_t)", (long)sizeof(kevent_t), probe_sizeof_kevent());
    wrong += Check("offsetof(kevent_t, udata)", (long)offsetof(kevent_t, udata), probe_offset_udata());
    wrong += Check("NCCS", (long)NCCS, probe_nccs());
    wrong += Check("ECHO", (long)ECHO, probe_echo());
    wrong += Check("ICANON", (long)ICANON, probe_icanon());
    wrong += Check("ISIG", (long)ISIG, probe_isig());
    wrong += Check("IEXTEN", (long)IEXTEN, probe_iexten());
    wrong += Check("ICRNL", (long)ICRNL, probe_icrnl());
    wrong += Check("IXON", (long)IXON, probe_ixon());
    wrong += Check("ISTRIP", (long)ISTRIP, probe_istrip());
    wrong += Check("BRKINT", (long)BRKINT, probe_brkint());
    wrong += Check("INPCK", (long)INPCK, probe_inpck());
    wrong += Check("OPOST", (long)OPOST, probe_opost());
    wrong += Check("CSIZE", (long)CSIZE, probe_csize());
    wrong += Check("CS8", (long)CS8, probe_cs8());
    wrong += Check("VMIN", (long)VMIN, probe_vmin());
    wrong += Check("VTIME", (long)VTIME, probe_vtime());
    wrong += Check("TCSADRAIN", (long)TCSADRAIN, probe_tcsadrain());
    wrong += Check("TCSAFLUSH", (long)TCSAFLUSH, probe_tcsaflush());
    wrong += Check("TIOCGWINSZ", (long)TIOCGWINSZ, probe_tiocgwinsz());
    wrong += Check("EVFILT_READ", (long)EVFILT_READ, probe_evfilt_read());
    wrong += Check("EVFILT_WRITE", (long)EVFILT_WRITE, probe_evfilt_write());
    wrong += Check("EVFILT_VNODE", (long)EVFILT_VNODE, probe_evfilt_vnode());
    wrong += Check("EVFILT_PROC", (long)EVFILT_PROC, probe_evfilt_proc());
    wrong += Check("EVFILT_SIGNAL", (long)EVFILT_SIGNAL, probe_evfilt_signal());
    wrong += Check("EVFILT_TIMER", (long)EVFILT_TIMER, probe_evfilt_timer());
    wrong += Check("EVFILT_USER", (long)EVFILT_USER, probe_evfilt_user());
    wrong += Check("EV_ADD", (long)EV_ADD, probe_ev_add());
    wrong += Check("EV_DELETE", (long)EV_DELETE, probe_ev_delete());
    wrong += Check("EV_ENABLE", (long)EV_ENABLE, probe_ev_enable());
    wrong += Check("EV_DISABLE", (long)EV_DISABLE, probe_ev_disable());
    wrong += Check("EV_ONESHOT", (long)EV_ONESHOT, probe_ev_oneshot());
    wrong += Check("EV_CLEAR", (long)EV_CLEAR, probe_ev_clear());
    wrong += Check("EV_DISPATCH", (long)EV_DISPATCH, probe_ev_dispatch());
    wrong += Check("EV_ERROR", (long)EV_ERROR, probe_ev_error());
    wrong += Check("EV_EOF", (long)EV_EOF, probe_ev_eof());
    wrong += Check("NOTE_TRIGGER", (long)NOTE_TRIGGER, probe_note_trigger());
    wrong += Check("NOTE_SECONDS", (long)NOTE_SECONDS, probe_note_seconds());
    wrong += Check("NOTE_USECONDS", (long)NOTE_USECONDS, probe_note_useconds());
    wrong += Check("NOTE_NSECONDS", (long)NOTE_NSECONDS, probe_note_nseconds());
    wrong += Check("NOTE_DELETE", (long)NOTE_DELETE, probe_note_delete());
    wrong += Check("NOTE_WRITE", (long)NOTE_WRITE, probe_note_write());
    wrong += Check("NOTE_EXTEND", (long)NOTE_EXTEND, probe_note_extend());
    wrong += Check("NOTE_ATTRIB", (long)NOTE_ATTRIB, probe_note_attrib());
    wrong += Check("NOTE_LINK", (long)NOTE_LINK, probe_note_link());
    wrong += Check("NOTE_RENAME", (long)NOTE_RENAME, probe_note_rename());
    wrong += Check("NOTE_REVOKE", (long)NOTE_REVOKE, probe_note_revoke());
    wrong += Check("O_EVTONLY", (long)O_EVTONLY, probe_o_evtonly());
    wrong += Check("O_CLOEXEC", (long)O_CLOEXEC, probe_o_cloexec());
    wrong += Check("EINTR", (long)EINTR, probe_eintr());
    wrong += Check("EAGAIN", (long)EAGAIN, probe_eagain());
    Console.WriteLine($"constants and layouts that disagree with the headers: {wrong}");

    // --------------------------------------------------------- the terminal

    Console.WriteLine($"tty      {IsTerminal(Terminal.Output)}");
    var mode = Mode.EnterRawMode(Terminal.Input);
    Console.WriteLine($"raw      refused {!mode.Ok}");
    var (rows, columns) = Size(Terminal.Output);
    Console.WriteLine($"size     {rows} {columns}");

    // ------------------------------------------------------------ the loop

    int kq = kqueue();
    Console.WriteLine($"made     {kq >= 0}");

    kevent_t[4] changes;
    kevent_t[8] ready;
    timespec now;
    now.tv_sec = 0L;
    now.tv_nsec = 0L;
    timespec second;
    second.tv_sec = 2L;
    second.tv_nsec = 0L;

    // A user event: no descriptor behind it, fired by NOTE_TRIGGER.
    changes[0].ident = 42u;
    changes[0].filter = EVFILT_USER;
    changes[0].flags = (ushort)(EV_ADD | EV_CLEAR);
    changes[0].fflags = 0u;
    changes[0].data = 0;
    changes[0].udata = null;
    Console.WriteLine($"added    {kevent(kq, &changes[0], 1, null, 0, null) == 0}");
    Console.WriteLine($"quiet    {kevent(kq, null, 0, &ready[0], 8, &now) == 0}");

    changes[0].flags = 0;
    changes[0].fflags = NOTE_TRIGGER;
    kevent(kq, &changes[0], 1, null, 0, null);
    int seen = kevent(kq, null, 0, &ready[0], 8, &second);
    Console.WriteLine($"woken    {seen == 1} ident {ready[0].ident} user {ready[0].filter == EVFILT_USER}");

    // A one-shot timer, its period in milliseconds.
    changes[0].ident = 99u;
    changes[0].filter = EVFILT_TIMER;
    changes[0].flags = (ushort)(EV_ADD | EV_ONESHOT);
    changes[0].fflags = 0u;
    changes[0].data = 20;
    seen = kevent(kq, &changes[0], 1, &ready[0], 8, &second);
    Console.WriteLine($"fired    {seen == 1} timer {ready[0].filter == EVFILT_TIMER}");

    // A file, watched for being written to.
    String path = "/tmp/stainless-macos-terminal.txt";
    File.WriteAllText(path, "first");
    int watched = open(path.ToPointer(), O_EVTONLY | O_CLOEXEC);
    changes[0].ident = (nuint)watched;
    changes[0].filter = EVFILT_VNODE;
    changes[0].flags = (ushort)(EV_ADD | EV_CLEAR);
    changes[0].fflags = NOTE_ALL_EDITS;
    changes[0].data = 0;
    Console.WriteLine($"watching {watched >= 0} {kevent(kq, &changes[0], 1, null, 0, null) == 0}");

    File.AppendAllText(path, " and second");
    seen = kevent(kq, null, 0, &ready[0], 8, &second);
    Console.WriteLine($"changed  {seen == 1} written {(ready[0].fflags & (NOTE_WRITE | NOTE_EXTEND)) != 0u}");

    close(watched);
    File.Delete(path);
    close(kq);
    return 0;
}
