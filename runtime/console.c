/*
 * Stainless - an experimental systems language.
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
 * Console input and output.
 *
 * Output writes a String's bytes exactly as they are: the text is already
 * UTF-8, so nothing is transcoded on the way out. Input reads bytes and takes
 * them to be UTF-8 for the same reason -- a program piped a UTF-8 file should
 * get back what was in it.
 *
 * That is a real limitation on Windows, where a console typed into by hand
 * hands over the active code page rather than UTF-8. A program that must read
 * typed non-ASCII wants ReadConsoleW; a program reading a pipe, which is the
 * usual case for anything with a command line, wants exactly this.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>

void sl_console_write(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stdout);
}

void sl_console_write_line(void *pointer)
{
    sl_console_write(pointer);
    fputc(0x0A, stdout);
}

void sl_console_write_error(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stderr);
    fputc(0x0A, stderr);
}

/* ----------------------------------------------------------------- input */

/*
 * One line, without its terminator, or NULL at end of input.
 *
 * NULL rather than an empty String, because a blank line and no line at all
 * are different answers and a loop needs to tell them apart. A trailing CR is
 * dropped as well as the LF, so a file with Windows endings read on Linux does
 * not leave one on the end of every line.
 */
void *sl_console_read_line(void)
{
    size_t capacity = 128;
    size_t length = 0;

    char *buffer = (char *)malloc(capacity);
    if (buffer == NULL) sl_fail("out of memory");

    for (;;) {
        int c = fgetc(stdin);

        if (c == EOF) {
            /* End of input with nothing read is the end; with something read,
             * that something is a final line with no terminator. */
            if (length == 0) { free(buffer); return NULL; }
            break;
        }

        if (c == 0x0A) break;

        if (length + 1 > capacity) {
            capacity *= 2;
            char *bigger = (char *)realloc(buffer, capacity);
            if (bigger == NULL) { free(buffer); sl_fail("out of memory"); }
            buffer = bigger;
        }

        buffer[length] = (char)c;
        length += 1;
    }

    if (length > 0 && buffer[length - 1] == 0x0D) length -= 1;

    void *line = sl_string_from_bytes((const uint8_t *)buffer, length);
    free(buffer);
    return line;
}

/* Everything left on stdin, as one String. Empty when there is nothing. */
void *sl_console_read_all(void)
{
    size_t capacity = 4096;
    size_t length = 0;

    char *buffer = (char *)malloc(capacity);
    if (buffer == NULL) sl_fail("out of memory");

    for (;;) {
        if (length == capacity) {
            capacity *= 2;
            char *bigger = (char *)realloc(buffer, capacity);
            if (bigger == NULL) { free(buffer); sl_fail("out of memory"); }
            buffer = bigger;
        }

        size_t got = fread(buffer + length, 1, capacity - length, stdin);
        length += got;
        if (got == 0) break;
    }

    void *text = sl_string_from_bytes((const uint8_t *)buffer, length);
    free(buffer);
    return text;
}

/* Whether stdin has reached its end. */
_Bool sl_console_at_end(void)
{
    int c = fgetc(stdin);
    if (c == EOF) return 1;

    ungetc(c, stdin);
    return 0;
}
