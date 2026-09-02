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
 * Console output. Writes a String's bytes exactly as they are: the text is
 * already UTF-8, so nothing is transcoded on the way out.
 */

#include "stainless.h"

#include <stdio.h>

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
