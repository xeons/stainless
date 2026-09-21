/*
 * Stainless - an experimental general-purpose language.
 * Copyright (C) 2026 Brandon Scott
 *
 * This file is part of the Stainless runtime library. It is free
 * software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any
 * later version.
 *
 * It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * As an additional permission under section 7 of that License, compiling
 * a program with Stainless does not by itself place that program under
 * the GNU General Public License. See LICENSE.RUNTIME.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Starting another program, waiting for it, and reading what it wrote.
 *
 * No shell. The program and its arguments are passed as a list, so a `>` or a
 * `|` or a space in a filename is a character the child receives rather than
 * something a shell would act on -- which is the whole of shell injection, and
 * it is designed out here rather than warned about.
 *
 * Two things in here are easy to get wrong and are worth reading before
 * changing anything:
 *
 * **The pipe deadlock.** A pipe holds about 64KB. A child that writes more
 * than that blocks until somebody reads, so a parent that waits for the child
 * before reading waits forever. Both ends are therefore drained *while* the
 * child runs, with poll(), and the wait happens after they close.
 *
 * **fork() in a threaded program.** Only async-signal-safe calls are legal
 * between fork and exec, because another thread may have held the malloc lock
 * at the moment of the fork and no thread exists in the child to release it.
 * So the child's half allocates nothing: the argv is built before the fork,
 * and what follows is dup2, close and execvp.
 */

#include "stainless.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <fcntl.h>
#  include <poll.h>
#  include <signal.h>
#  include <sys/wait.h>
#  include <unistd.h>
#endif

/* Reported to the caller as `ProcessError` in Standard.Process. */
#define SL_PROCESS_OK          0
#define SL_PROCESS_NOT_FOUND   1
#define SL_PROCESS_DENIED      2
#define SL_PROCESS_NO_RESOURCE 3
#define SL_PROCESS_FAILED      4

/*
 * A child that has been started and not yet reaped.
 *
 * Handed to Stainless as an opaque pointer rather than as an object, because
 * the class that holds it lives in the standard library and the runtime has no
 * way to name one. Its destructor calls sl_process_release.
 */
/*
 * A growable byte buffer, private to this file.
 *
 * Not an object and not the language's StringBuilder. A child's output has no
 * size to know in advance, so something here has to grow -- but it belongs to
 * the process rather than to the caller, which is what keeps a Stainless
 * object from crossing into C to be written through a layout agreed in two
 * places.
 */
typedef struct Buffer {
    uint8_t *bytes;
    size_t   length;
    size_t   capacity;
} Buffer;

static void buffer_append(Buffer *buffer, const uint8_t *data, size_t byteLength)
{
    if (byteLength == 0 || data == NULL) return;

    /* Both of these would wrap rather than fail: the size wanted, and the
     * doubling that reaches for it -- which on wrapping to zero would loop for
     * ever rather than merely allocate too little. */
    if (byteLength > SIZE_MAX - buffer->length) sl_fail("output is too large to hold");

    size_t wanted = buffer->length + byteLength;
    if (wanted > buffer->capacity) {
        size_t capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
        while (capacity < wanted) {
            if (capacity > SIZE_MAX / 2) { capacity = wanted; break; }
            capacity *= 2;
        }

        uint8_t *bytes = (uint8_t *)realloc(buffer->bytes, capacity);
        if (bytes == NULL) sl_fail("out of memory");

        buffer->bytes    = bytes;
        buffer->capacity = capacity;
    }

    memcpy(buffer->bytes + buffer->length, data, byteLength);
    buffer->length += byteLength;
}

/* What is in it, as a String, and the buffer emptied. The room is kept: a
 * reader taking a line at a time would otherwise reallocate on every call. */
static void *buffer_take(Buffer *buffer)
{
    void *text = sl_string_from_bytes(buffer->bytes, buffer->length);
    buffer->length = 0;
    return text;
}

static void buffer_free(Buffer *buffer)
{
    free(buffer->bytes);
    buffer->bytes    = NULL;
    buffer->length   = 0;
    buffer->capacity = 0;
}

typedef struct SlProcess {
#ifdef _WIN32
    HANDLE handle;
    DWORD  id;
    /* The read ends of the child's output, or NULL for a child whose streams
     * are this process's own. Closed as each reports end of file, so that a
     * pump can tell "nothing yet" from "nothing ever again". */
    HANDLE out;
    HANDLE err;
#else
    pid_t  id;
    /* The same, with -1 for absent -- which calloc does not give, so every
     * place that makes one of these sets them. Zero would be this process's
     * own standard input. */
    int    out;
    int    err;
#endif
    int  exitCode;
    _Bool finished;

    /* What the child has written and the caller has not taken yet. Zeroed by
     * the calloc that makes one of these. */
    Buffer outText;
    Buffer errText;
} SlProcess;

/* --------------------------------------------------------------- argv */

/*
 * The argument list, built one String at a time.
 *
 * A Stainless `String[]` could be walked from here, but that would put the
 * array's layout in two places; and on Windows the arguments have to be quoted
 * into one command line rather than passed as a vector, so the two platforms
 * want different things from the same list. Collecting first lets each do its
 * own.
 */
typedef struct SlArgs {
    char **items;
    size_t count;
    size_t capacity;
} SlArgs;

void *sl_process_args_new(void)
{
    SlArgs *args = (SlArgs *)calloc(1, sizeof(SlArgs));
    return args;
}

_Bool sl_process_args_add(void *handle, void *text)
{
    SlArgs *args = (SlArgs *)handle;
    if (args == NULL) return 0;

    if (args->count + 2 > args->capacity) {
        size_t wanted = args->capacity == 0 ? 8 : args->capacity * 2;
        char **grown = (char **)realloc(args->items, wanted * sizeof(char *));
        if (grown == NULL) return 0;

        args->items = grown;
        args->capacity = wanted;
    }

    /* Copied, and NUL-terminated: a String knows its own length and is not
     * required to have a terminator, and execvp wants one. */
    size_t length = text == NULL ? 0 : sl_string_byte_length(text);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) return 0;

    if (length > 0) memcpy(copy, sl_string_data((SlString *)text), length);
    copy[length] = '\0';

    args->items[args->count] = copy;
    args->count += 1;
    args->items[args->count] = NULL;
    return 1;
}

void sl_process_args_free(void *handle)
{
    SlArgs *args = (SlArgs *)handle;
    if (args == NULL) return;

    for (size_t i = 0; i < args->count; i += 1) free(args->items[i]);
    free(args->items);
    free(args);
}

/* ------------------------------------------------------------ the child */

#ifdef _WIN32

/*
 * The arguments, quoted into the one command line Windows takes.
 *
 * CreateProcess is handed a string, not a vector, and the child pulls a vector
 * back out of it -- so the quoting here and the unquoting there have to agree
 * or an argument with a space in it silently becomes two. These are the rules
 * the Microsoft C runtime's parser uses, which is what almost every program
 * ends up running.
 *
 * A backslash is ordinary except immediately before a quote, where it and the
 * run it belongs to are doubled. That is the rule that makes `C:\dir\` inside
 * quotes come out as a directory rather than as an escaped quote.
 */
static void quote(Buffer *line, const char *argument)
{
    size_t length = strlen(argument);
    _Bool plain = length > 0;

    for (size_t i = 0; i < length && plain; i += 1)
        if (argument[i] == ' ' || argument[i] == '\t' || argument[i] == '"') plain = 0;

    if (plain) {
        buffer_append(line, (const uint8_t *)argument, length);
        return;
    }

    buffer_append(line, (const uint8_t *)"\"", 1);

    for (size_t i = 0; i < length; i += 1) {
        size_t slashes = 0;
        while (i < length && argument[i] == '\\') { slashes += 1; i += 1; }

        if (i == length) {
            /* Trailing: doubled, because the closing quote follows. */
            for (size_t n = 0; n < slashes * 2; n += 1)
                buffer_append(line, (const uint8_t *)"\\", 1);
            break;
        }

        if (argument[i] == '"') {
            for (size_t n = 0; n < slashes * 2 + 1; n += 1)
                buffer_append(line, (const uint8_t *)"\\", 1);
        } else {
            for (size_t n = 0; n < slashes; n += 1)
                buffer_append(line, (const uint8_t *)"\\", 1);
        }

        buffer_append(line, (const uint8_t *)&argument[i], 1);
    }

    buffer_append(line, (const uint8_t *)"\"", 1);
}

static int classify(DWORD number)
{
    switch (number) {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
        case ERROR_INVALID_NAME:
        case ERROR_BAD_EXE_FORMAT:  return SL_PROCESS_NOT_FOUND;
        case ERROR_ACCESS_DENIED:   return SL_PROCESS_DENIED;
        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_OUTOFMEMORY:
        case ERROR_TOO_MANY_OPEN_FILES: return SL_PROCESS_NO_RESOURCE;
        default: return SL_PROCESS_FAILED;
    }
}

/*
 * One end of a pipe the child must not inherit.
 *
 * A parent that leaves its own read end inheritable gives the child a copy,
 * and the pipe then never reports end-of-file: there is still a writer, and it
 * is the process waiting to read.
 */
static _Bool privately(HANDLE handle)
{
    return SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0) != 0;
}

/*
 * Reads whatever is waiting on a pipe, without blocking.
 *
 * PeekNamedPipe first, because ReadFile on a pipe with nothing in it waits --
 * which is the deadlock this whole arrangement exists to avoid, arriving from
 * the other direction. Answers 0 when the writer is gone.
 */
static _Bool sip(HANDLE pipe, Buffer *into)
{
    DWORD waiting = 0;

    if (!PeekNamedPipe(pipe, NULL, 0, NULL, &waiting, NULL)) return 0;
    if (waiting == 0) return 1;

    uint8_t buffer[4096];
    DWORD got = 0;

    if (waiting > sizeof buffer) waiting = sizeof buffer;
    if (!ReadFile(pipe, buffer, waiting, &got, NULL) || got == 0) return 0;

    buffer_append(into, buffer, (size_t)got);
    return 1;
}

/* The command line CreateProcessW wants, as wide characters the caller frees. */
static wchar_t *commandLineFor(SlArgs *list)
{
    Buffer line = { NULL, 0, 0 };

    for (size_t i = 0; i < list->count; i += 1) {
        if (i > 0) buffer_append(&line, (const uint8_t *)" ", 1);
        quote(&line, list->items[i]);
    }

    /* sl_widen wants a NUL, and the buffer holds none. */
    buffer_append(&line, (const uint8_t *)"", 1);

    wchar_t *wide = sl_widen((const char *)line.bytes);
    buffer_free(&line);
    return wide;
}

#else

static int classify(int number)
{
    switch (number) {
        case ENOENT:
        case ENOTDIR: return SL_PROCESS_NOT_FOUND;
        case EACCES:
        case EPERM:   return SL_PROCESS_DENIED;
        case EAGAIN:
        case ENOMEM:
        case EMFILE:
        case ENFILE:  return SL_PROCESS_NO_RESOURCE;
        default:      return SL_PROCESS_FAILED;
    }
}

/*
 * The exit code a shell would report: the status for an ordinary exit, and
 * 128 + N for a signal, which is what bash does and what a caller comparing
 * against 0 already expects.
 */
static int coded(int status)
{
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}

/*
 * Forks, execs, and tells the parent whether the exec worked.
 *
 * The child cannot report a failed exec through its exit code: 127 is the
 * shell's convention for it, and it is also a perfectly ordinary code a real
 * program might return -- so a caller could not tell "no such program" from
 * "the program ran and answered 127". Which matters, because those want
 * different handling.
 *
 * So there is a third pipe, close-on-exec. A successful exec closes it and the
 * parent reads end-of-file; a failed one writes errno into it first. One pipe,
 * one read, and the answer is exact.
 *
 * `redirect` is the three descriptors to become stdin, stdout and stderr, each
 * -1 for "leave it alone", and `keep` is a descriptor the child must not
 * inherit -- the parent's end of a pipe it is about to be given the other half
 * of.
 */
static pid_t spawn(char **argv, const int redirect[3], const int *toClose, int count, int *why)
{
    int report[2];

    *why = 0;

    if (pipe(report) != 0) return -1;

    if (fcntl(report[1], F_SETFD, FD_CLOEXEC) != 0) {
        close(report[0]);
        close(report[1]);
        return -1;
    }

    pid_t child = fork();

    if (child < 0) {
        int number = errno;
        close(report[0]);
        close(report[1]);
        errno = number;
        return -1;
    }

    if (child == 0) {
        /* Async-signal-safe only, from here to the exec: another thread may
         * have held the malloc lock when the fork happened, and there is no
         * thread here to release it. Nothing below allocates. */
        for (int i = 0; i < 3; i += 1)
            if (redirect[i] >= 0) dup2(redirect[i], i);

        for (int i = 0; i < count; i += 1)
            if (toClose[i] >= 0) close(toClose[i]);

        close(report[0]);

        execvp(argv[0], argv);

        int failed = errno;
        ssize_t ignored = write(report[1], &failed, sizeof failed);
        (void)ignored;
        _exit(127);
    }

    close(report[1]);

    int failed = 0;
    ssize_t got;

    do {
        got = read(report[0], &failed, sizeof failed);
    } while (got < 0 && errno == EINTR);

    close(report[0]);

    /* Bytes mean the exec never happened, so there is a child to reap and no
     * process for the caller to wait on. */
    if (got == (ssize_t)sizeof failed) {
        int status = 0;
        while (waitpid(child, &status, 0) < 0 && errno == EINTR) { }

        *why = classify(failed);
        return -1;
    }

    return child;
}

#endif
/*
 * Starts a program with both its output streams captured, and its input
 * written and closed.
 *
 * The read ends stay on the handle, which is the whole difference from
 * sl_process_start: that one leaves the child with this process's streams and
 * has nothing to read. Here they are kept so sl_process_pump can be called as
 * often as a caller likes, and output arrives while the child is still writing
 * rather than after it has exited.
 */
void *sl_process_open(void *args, void *input, int *error)
{
    SlArgs *list = (SlArgs *)args;
    *error = SL_PROCESS_FAILED;

    if (list == NULL || list->count == 0) return NULL;

#ifdef _WIN32
    SECURITY_ATTRIBUTES shared;
    shared.nLength = sizeof shared;
    shared.lpSecurityDescriptor = NULL;
    shared.bInheritHandle = TRUE;

    HANDLE inRead = NULL, inWrite = NULL;
    HANDLE outRead = NULL, outWrite = NULL;
    HANDLE errRead = NULL, errWrite = NULL;

    if (!CreatePipe(&outRead, &outWrite, &shared, 0)) {
        *error = classify(GetLastError());
        return NULL;
    }

    if (!CreatePipe(&errRead, &errWrite, &shared, 0)) {
        DWORD why = GetLastError();
        CloseHandle(outRead); CloseHandle(outWrite);
        *error = classify(why);
        return NULL;
    }

    if (!CreatePipe(&inRead, &inWrite, &shared, 0)) {
        DWORD why = GetLastError();
        CloseHandle(outRead); CloseHandle(outWrite);
        CloseHandle(errRead); CloseHandle(errWrite);
        *error = classify(why);
        return NULL;
    }

    privately(outRead);
    privately(errRead);
    privately(inWrite);

    STARTUPINFOW startup;
    memset(&startup, 0, sizeof startup);
    startup.cb = sizeof startup;
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = inRead;
    startup.hStdOutput = outWrite;
    startup.hStdError = errWrite;

    wchar_t *line = commandLineFor(list);
    PROCESS_INFORMATION information;
    memset(&information, 0, sizeof information);

    BOOL started = line != NULL && CreateProcessW(
        NULL, line, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL,
        &startup, &information);

    DWORD why = started ? 0 : GetLastError();
    free(line);

    /* The parent's copies of the child's ends go now, whether or not it
     * started: while one is open the pipe still has a writer, and the reads
     * later would never see the end of it. */
    CloseHandle(outWrite);
    CloseHandle(errWrite);
    CloseHandle(inRead);

    if (!started) {
        CloseHandle(outRead); CloseHandle(errRead); CloseHandle(inWrite);
        *error = classify(why);
        return NULL;
    }

    CloseHandle(information.hThread);

    if (input != NULL) {
        const uint8_t *bytes = sl_string_data((SlString *)input);
        size_t length = sl_string_byte_length(input);
        size_t written = 0;

        while (written < length) {
            DWORD sent = 0;
            DWORD wanted = (DWORD)(length - written);

            if (!WriteFile(inWrite, bytes + written, wanted, &sent, NULL) || sent == 0)
                break;      /* the child stopped reading; its business, not ours */

            written += sent;
        }
    }

    CloseHandle(inWrite);

    SlProcess *made = (SlProcess *)calloc(1, sizeof(SlProcess));
    if (made == NULL) {
        CloseHandle(outRead); CloseHandle(errRead);
        TerminateProcess(information.hProcess, 1);
        CloseHandle(information.hProcess);
        *error = SL_PROCESS_NO_RESOURCE;
        return NULL;
    }

    made->handle = information.hProcess;
    made->id = information.dwProcessId;
    made->out = outRead;
    made->err = errRead;
    made->exitCode = -1;
    *error = SL_PROCESS_OK;
    return made;
#else
    int inPipe[2] = { -1, -1 };
    int outPipe[2];
    int errPipe[2];

    size_t inputLength = input == NULL ? 0 : sl_string_byte_length(input);

    if (input != NULL && pipe(inPipe) != 0) {
        *error = classify(errno);
        return NULL;
    }

    if (pipe(outPipe) != 0) {
        *error = classify(errno);
        if (inPipe[0] >= 0) { close(inPipe[0]); close(inPipe[1]); }
        return NULL;
    }

    if (pipe(errPipe) != 0) {
        *error = classify(errno);
        if (inPipe[0] >= 0) { close(inPipe[0]); close(inPipe[1]); }
        close(outPipe[0]);
        close(outPipe[1]);
        return NULL;
    }

    int redirect[3] = { inPipe[0], outPipe[1], errPipe[1] };
    int toClose[4] = { inPipe[1], outPipe[0], outPipe[1], errPipe[0] };

    int why = 0;
    pid_t child = spawn(list->items, redirect, toClose, 4, &why);

    if (child < 0) {
        *error = why != 0 ? why : classify(errno);
        if (inPipe[0] >= 0) { close(inPipe[0]); close(inPipe[1]); }
        close(outPipe[0]); close(outPipe[1]);
        close(errPipe[0]); close(errPipe[1]);
        return NULL;
    }

    if (inPipe[0] >= 0) close(inPipe[0]);
    close(outPipe[1]);
    close(errPipe[1]);

    if (inPipe[1] >= 0) {
        /* SIGPIPE would kill this process if the child exits without reading.
         * A short write is the child's business, not a reason to die. */
        void (*previous)(int) = signal(SIGPIPE, SIG_IGN);

        const uint8_t *bytes = sl_string_data((SlString *)input);
        size_t written = 0;

        while (written < inputLength) {
            ssize_t sent = write(inPipe[1], bytes + written, inputLength - written);
            if (sent <= 0) {
                if (sent < 0 && errno == EINTR) continue;
                break;
            }
            written += (size_t)sent;
        }

        close(inPipe[1]);
        signal(SIGPIPE, previous);
    }

    SlProcess *started = (SlProcess *)calloc(1, sizeof(SlProcess));
    if (started == NULL) {
        close(outPipe[0]); close(errPipe[0]);
        kill(child, SIGKILL);
        waitpid(child, NULL, 0);
        *error = SL_PROCESS_NO_RESOURCE;
        return NULL;
    }

    started->id = child;
    started->out = outPipe[0];
    started->err = errPipe[0];
    started->exitCode = -1;
    *error = SL_PROCESS_OK;
    return started;
#endif
}

/*
 * Reads whatever the child has written, waiting until there is something.
 *
 * Answers 1 when it appended anything or a stream may still produce more, and
 * 0 only once both are closed and there was nothing left -- so
 *
 *     while (sl_process_pump(handle, out, err)) { take what is in them }
 *
 * hands over every byte and then stops. Both pipes are watched together rather
 * than one and then the other, for the reason the two builders exist at all: a
 * pipe holds about 64KB, and a child that fills one waits for a reader that
 * would be waiting for the child.
 */
_Bool sl_process_pump(void *handle)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return 0;

#ifdef _WIN32
    for (;;) {
        if (process->out == NULL && process->err == NULL) return 0;

        size_t before = process->outText.length + process->errText.length;

        if (process->out != NULL && !sip(process->out, &process->outText)) {
            CloseHandle(process->out);
            process->out = NULL;
        }
        if (process->err != NULL && !sip(process->err, &process->errText)) {
            CloseHandle(process->err);
            process->err = NULL;
        }

        size_t after = process->outText.length + process->errText.length;

        if (after != before) return 1;
        if (process->out == NULL && process->err == NULL) return 0;

        /* Nothing waiting on either, and both still open: give the child the
         * processor rather than spinning on Peek. */
        Sleep(1);
    }
#else
    for (;;) {
        if (process->out < 0 && process->err < 0) return 0;

        struct pollfd watched[2];

        /* A negative fd is ignored and reports no events, which is what makes
         * one closed stream harmless here rather than a second code path. */
        watched[0].fd = process->out;
        watched[0].events = POLLIN;
        watched[1].fd = process->err;
        watched[1].events = POLLIN;

        if (poll(watched, 2, -1) < 0) {
            if (errno == EINTR) continue;
            return 0;
        }

        size_t before = process->outText.length + process->errText.length;

        for (int i = 0; i < 2; i += 1) {
            int reading = i == 0 ? process->out : process->err;

            if (reading < 0) continue;
            if ((watched[i].revents & (POLLIN | POLLHUP | POLLERR)) == 0) continue;

            uint8_t buffer[4096];
            ssize_t got = read(reading, buffer, sizeof buffer);

            if (got > 0) {
                buffer_append(
                    i == 0 ? &process->outText : &process->errText, buffer, (size_t)got);
                continue;
            }

            if (got < 0 && errno == EINTR) continue;

            /* Zero is the write end closed; anything else has gone wrong and
             * there is nothing further to read either way. */
            close(reading);
            if (i == 0) process->out = -1; else process->err = -1;
        }

        size_t after = process->outText.length + process->errText.length;

        if (after != before) return 1;
        if (process->out < 0 && process->err < 0) return 0;
    }
#endif
}

/*
 * Starts a program, reads both its streams to the end, and waits for it.
 *
 * The two builders are the caller's; this appends to them and never reads
 * them, so the standard library keeps ownership of both.
 *
 * **Written in terms of open and pump rather than beside them.** There were
 * two copies of the pipe setup and the drain loop, one per platform in each,
 * and the streaming half was the fourth. Four copies of "a pipe holds 64KB and
 * a child that fills one deadlocks" is three too many for them all to stay
 * right.
 */
int sl_process_run(void *args, void *input, void **outText, void **errText, int *exitCode)
{
    int error = SL_PROCESS_FAILED;

    *exitCode  = -1;
    *outText   = NULL;
    *errText   = NULL;

    void *handle = sl_process_open(args, input, &error);
    if (handle == NULL) return error;

    while (sl_process_pump(handle)) { }

    int status = sl_process_wait(handle, exitCode);

    /* Taken before the handle goes, since the buffers go with it. */
    *outText = sl_process_take_output(handle);
    *errText = sl_process_take_errors(handle);

    sl_process_release(handle);
    return status;
}

/* What the child wrote since this was last asked, and nothing the next time. */
void *sl_process_take_output(void *handle)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return sl_string_from_bytes(NULL, 0);
    return buffer_take(&process->outText);
}

void *sl_process_take_errors(void *handle)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return sl_string_from_bytes(NULL, 0);
    return buffer_take(&process->errText);
}
/* Starts a program and does not wait. The streams are the parent's. */
void *sl_process_start(void *args, int *error)
{
    SlArgs *list = (SlArgs *)args;
    *error = SL_PROCESS_FAILED;

    if (list == NULL || list->count == 0) return NULL;

#ifdef _WIN32
    wchar_t *line = commandLineFor(list);

    STARTUPINFOW startup;
    memset(&startup, 0, sizeof startup);
    startup.cb = sizeof startup;

    PROCESS_INFORMATION information;
    memset(&information, 0, sizeof information);

    /* Its streams are this process's, so nothing is redirected. */
    BOOL started = line != NULL && CreateProcessW(
        NULL, line, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &information);

    DWORD why = started ? 0 : GetLastError();
    free(line);

    if (!started) { *error = classify(why); return NULL; }

    CloseHandle(information.hThread);

    SlProcess *made = (SlProcess *)calloc(1, sizeof(SlProcess));
    if (made == NULL) {
        CloseHandle(information.hProcess);
        *error = SL_PROCESS_NO_RESOURCE;
        return NULL;
    }

    made->handle = information.hProcess;
    made->id = information.dwProcessId;
    made->out = NULL;
    made->err = NULL;
    made->exitCode = -1;
    *error = SL_PROCESS_OK;
    return made;
#else
    /* Its streams are this process's, so nothing is redirected and nothing of
     * the parent's has to be closed in it. */
    int redirect[3] = { -1, -1, -1 };
    int why = 0;

    pid_t child = spawn(list->items, redirect, NULL, 0, &why);

    if (child < 0) {
        *error = why != 0 ? why : classify(errno);
        return NULL;
    }

    SlProcess *started = (SlProcess *)calloc(1, sizeof(SlProcess));
    if (started == NULL) { *error = SL_PROCESS_NO_RESOURCE; return NULL; }

    started->id = child;
    started->out = -1;
    started->err = -1;
    started->exitCode = -1;
    *error = SL_PROCESS_OK;
    return started;
#endif
}

long sl_process_id(void *handle)
{
    SlProcess *process = (SlProcess *)handle;
    return process == NULL ? -1 : (long)process->id;
}

/* Waits for the child, or answers straight away if it has already been reaped. */
int sl_process_wait(void *handle, int *exitCode)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return SL_PROCESS_FAILED;

    if (process->finished) { *exitCode = process->exitCode; return SL_PROCESS_OK; }

#ifdef _WIN32
    if (WaitForSingleObject(process->handle, INFINITE) != WAIT_OBJECT_0)
        return SL_PROCESS_FAILED;

    DWORD code = 0;
    if (!GetExitCodeProcess(process->handle, &code)) return SL_PROCESS_FAILED;

    process->exitCode = (int)code;
    process->finished = 1;
    *exitCode = process->exitCode;
    return SL_PROCESS_OK;
#else
    int status = 0;
    while (waitpid(process->id, &status, 0) < 0) {
        if (errno != EINTR) return SL_PROCESS_FAILED;
    }

    process->exitCode = coded(status);
    process->finished = 1;
    *exitCode = process->exitCode;
    return SL_PROCESS_OK;
#endif
}

/*
 * Whether it has finished, without waiting for it.
 *
 * Answers 1 and fills the code when it has, 0 when it is still running, and -1
 * when the question could not be asked.
 */
int sl_process_poll(void *handle, int *exitCode)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return -1;

    if (process->finished) { *exitCode = process->exitCode; return 1; }

#ifdef _WIN32
    DWORD waited = WaitForSingleObject(process->handle, 0);
    if (waited == WAIT_TIMEOUT) return 0;
    if (waited != WAIT_OBJECT_0) return -1;

    DWORD code = 0;
    if (!GetExitCodeProcess(process->handle, &code)) return -1;

    process->exitCode = (int)code;
    process->finished = 1;
    *exitCode = process->exitCode;
    return 1;
#else
    int status = 0;
    pid_t answered = waitpid(process->id, &status, WNOHANG);

    if (answered == 0) return 0;
    if (answered < 0) return errno == EINTR ? 0 : -1;

    process->exitCode = coded(status);
    process->finished = 1;
    *exitCode = process->exitCode;
    return 1;
#endif
}

/* Asks it to stop, or makes it. */
_Bool sl_process_signal(void *handle, _Bool force)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL || process->finished) return 0;

#ifdef _WIN32
    /* Windows has no SIGTERM for a process that is not a console group of its
     * own, so both words mean the same thing here: it is stopped where it
     * stands and gets no chance to tidy up. Said plainly rather than pretended
     * about -- `Stop` cannot be polite on this platform.
     */
    (void)force;
    return TerminateProcess(process->handle, 1) != 0;
#else
    return kill(process->id, force ? SIGKILL : SIGTERM) == 0;
#endif
}

/*
 * Drops the handle.
 *
 * A child that was never waited for is reaped here, so that a `Process` let go
 * of does not leave a zombie for the rest of the run. It is not killed:
 * letting go of the handle says nothing about wanting it stopped.
 */
void sl_process_release(void *handle)
{
    SlProcess *process = (SlProcess *)handle;
    if (process == NULL) return;

    buffer_free(&process->outText);
    buffer_free(&process->errText);

#ifdef _WIN32
    /* A pipe the caller stopped reading partway through is still open, and a
     * read end left open is a child blocked forever on a full pipe. */
    if (process->out != NULL) CloseHandle(process->out);
    if (process->err != NULL) CloseHandle(process->err);
    if (process->handle != NULL) CloseHandle(process->handle);
#else
    if (process->out >= 0) close(process->out);
    if (process->err >= 0) close(process->err);

    if (!process->finished) {
        int status = 0;
        waitpid(process->id, &status, WNOHANG);
    }
#endif

    free(process);
}

/* ------------------------------------------------------------- signals */

/*
 * Whether an interrupt has arrived, asked rather than delivered.
 *
 * A handler runs between two instructions of whatever was executing, so almost
 * nothing is legal inside one: no allocation, no locks, and therefore no
 * Stainless code at all. What is legal is a store to a flag, so that is what
 * the handler does and this is how a program reads it.
 *
 * The loop that would have been a handler is then an ordinary `if` at the top
 * of the program's own loop, which is where a program can actually clean up.
 */
#ifndef _WIN32
static volatile sig_atomic_t interrupted;

static void note(int number)
{
    (void)number;
    interrupted = 1;
}
#else
static volatile long interrupted;

static BOOL WINAPI note(DWORD kind)
{
    if (kind == CTRL_C_EVENT || kind == CTRL_BREAK_EVENT || kind == CTRL_CLOSE_EVENT) {
        interrupted = 1;
        return TRUE;
    }
    return FALSE;
}
#endif

_Bool sl_signals_watch(void)
{
#ifdef _WIN32
    return SetConsoleCtrlHandler(note, TRUE) != 0;
#else
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = note;

    /* No SA_RESTART: a read the interrupt lands in should come back with EINTR
     * so the program gets to look at the flag, rather than resuming as if
     * nothing had happened.
     */
    return sigaction(SIGINT, &action, NULL) == 0 &&
           sigaction(SIGTERM, &action, NULL) == 0;
#endif
}

_Bool sl_signals_interrupted(void)
{
    return interrupted != 0;
}

void sl_signals_clear(void)
{
    interrupted = 0;
}
