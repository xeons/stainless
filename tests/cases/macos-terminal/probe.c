/*
 * What Darwin's headers actually say, so MacOS.Termios and MacOS.Events can
 * be measured against them rather than against anyone's memory.
 */

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <termios.h>

long long probe_sizeof_termios(void)  { return sizeof(struct termios); }
long long probe_offset_c_cc(void)     { return offsetof(struct termios, c_cc); }
long long probe_offset_c_ispeed(void) { return offsetof(struct termios, c_ispeed); }
long long probe_sizeof_winsize(void)  { return sizeof(struct winsize); }
long long probe_sizeof_kevent(void)   { return sizeof(struct kevent); }
long long probe_offset_udata(void)    { return offsetof(struct kevent, udata); }

long long probe_nccs(void)   { return NCCS; }
long long probe_echo(void)   { return ECHO; }
long long probe_icanon(void) { return ICANON; }
long long probe_isig(void)   { return ISIG; }
long long probe_iexten(void) { return IEXTEN; }
long long probe_icrnl(void)  { return ICRNL; }
long long probe_ixon(void)   { return IXON; }
long long probe_istrip(void) { return ISTRIP; }
long long probe_brkint(void) { return BRKINT; }
long long probe_inpck(void)  { return INPCK; }
long long probe_opost(void)  { return OPOST; }
long long probe_csize(void)  { return CSIZE; }
long long probe_cs8(void)    { return CS8; }
long long probe_vmin(void)   { return VMIN; }
long long probe_vtime(void)  { return VTIME; }
long long probe_tcsadrain(void) { return TCSADRAIN; }
long long probe_tcsaflush(void) { return TCSAFLUSH; }
long long probe_tiocgwinsz(void) { return TIOCGWINSZ; }

long long probe_evfilt_read(void)   { return EVFILT_READ; }
long long probe_evfilt_write(void)  { return EVFILT_WRITE; }
long long probe_evfilt_vnode(void)  { return EVFILT_VNODE; }
long long probe_evfilt_proc(void)   { return EVFILT_PROC; }
long long probe_evfilt_signal(void) { return EVFILT_SIGNAL; }
long long probe_evfilt_timer(void)  { return EVFILT_TIMER; }
long long probe_evfilt_user(void)   { return EVFILT_USER; }
long long probe_ev_add(void)      { return EV_ADD; }
long long probe_ev_delete(void)   { return EV_DELETE; }
long long probe_ev_enable(void)   { return EV_ENABLE; }
long long probe_ev_disable(void)  { return EV_DISABLE; }
long long probe_ev_oneshot(void)  { return EV_ONESHOT; }
long long probe_ev_clear(void)    { return EV_CLEAR; }
long long probe_ev_dispatch(void) { return EV_DISPATCH; }
long long probe_ev_error(void)    { return EV_ERROR; }
long long probe_ev_eof(void)      { return EV_EOF; }
long long probe_note_trigger(void) { return NOTE_TRIGGER; }
long long probe_note_seconds(void) { return NOTE_SECONDS; }
long long probe_note_useconds(void) { return NOTE_USECONDS; }
long long probe_note_nseconds(void) { return NOTE_NSECONDS; }
long long probe_note_delete(void) { return NOTE_DELETE; }
long long probe_note_write(void)  { return NOTE_WRITE; }
long long probe_note_extend(void) { return NOTE_EXTEND; }
long long probe_note_attrib(void) { return NOTE_ATTRIB; }
long long probe_note_link(void)   { return NOTE_LINK; }
long long probe_note_rename(void) { return NOTE_RENAME; }
long long probe_note_revoke(void) { return NOTE_REVOKE; }
long long probe_o_evtonly(void)   { return O_EVTONLY; }
long long probe_o_cloexec(void)   { return O_CLOEXEC; }
long long probe_eintr(void)       { return EINTR; }
long long probe_eagain(void)      { return EAGAIN; }
