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
 * The arguments the program was started with.
 *
 * Only the arguments. Variables and the working directory are Stainless, in
 * stdlib/Env.sl, which calls the platform for itself. These stay because the
 * entry point hands them over before any Stainless code could run, and there
 * is nowhere earlier for a Stainless function to stand.
 */

#include "stainless.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <shellapi.h>
#  pragma comment(lib, "shell32")
#endif

/* --------------------------------------------------------------- arguments */

/*
 * What main() was handed, kept for the whole run.
 *
 * The entry point stores these before anything else, and the strings are the
 * ones the C runtime owns -- they outlive the program's use of them, so no
 * copy is needed and none is made.
 *
 * Except on Windows, where a narrow main() is handed its arguments in the
 * active code page and a character outside it arrives as a question mark.
 * There they are split again from the wide command line and kept as UTF-8,
 * for the whole run and so never freed.
 */
static int    argumentCount;
static char **argumentValues;

#ifdef _WIN32
static char **argumentsFromCommandLine(int *count)
{
    int wideCount = 0;
    wchar_t **wide = CommandLineToArgvW(GetCommandLineW(), &wideCount);
    if (wide == NULL) return NULL;

    char **values = (char **)calloc((size_t)wideCount + 1, sizeof(char *));
    if (values == NULL) sl_fail("out of memory");

    for (int i = 0; i < wideCount; i++) {
        values[i] = sl_narrow(wide[i]);
        if (values[i] == NULL) values[i] = "";
    }

    LocalFree(wide);
    *count = wideCount;
    return values;
}
#endif

void sl_args_set(int count, char **values)
{
#ifdef _WIN32
    int wideCount = 0;
    char **utf8 = argumentsFromCommandLine(&wideCount);

    if (utf8 != NULL) {
        count  = wideCount;
        values = utf8;
    }
#endif

    argumentCount  = count;
    argumentValues = values;
}

/* The program's own name is argv[0] and is not one of these. */
size_t sl_args_count(void)
{
    return argumentCount > 0 ? (size_t)(argumentCount - 1) : 0;
}

void *sl_args_at(size_t index)
{
    if (index + 1 >= (size_t)(argumentCount < 0 ? 0 : argumentCount))
        return sl_string_from_null_terminated("");

    return sl_string_from_null_terminated(argumentValues[index + 1]);
}

/*
 * Every argument as one String[], built here rather than in emitted IR.
 *
 * The compiler passes the TypeInfo it made for `String[]`, because the type
 * tables belong to the program and not to the runtime -- the destroy hook in
 * there is what releases the strings when the array goes. Doing it in one call
 * keeps a loop out of the entry point, which is the last place a subtle one
 * should live.
 */
void *sl_args_array(const SlTypeInfo *arrayType)
{
    size_t count = sl_args_count();

    SlArray *array = (SlArray *)sl_array_alloc(arrayType, count, sizeof(void *));
    void **elements = (void **)((uint8_t *)array + 32);

    /* Each String arrives +1 and the array takes that reference over; nothing
     * is retained again and nothing released here. */
    for (size_t i = 0; i < count; i += 1) elements[i] = sl_args_at(i);

    return array;
}

void *sl_args_program(void)
{
    if (argumentCount < 1 || argumentValues == NULL || argumentValues[0] == NULL)
        return sl_string_from_null_terminated("");

    return sl_string_from_null_terminated(argumentValues[0]);
}
