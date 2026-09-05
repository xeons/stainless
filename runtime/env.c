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
 * The environment: variables, the working directory, and the arguments the
 * program was started with.
 *
 * Everything here speaks UTF-8, which on Windows means going through the wide
 * API and converting. The narrow one would hand back whatever the active code
 * page says, and a String is UTF-8 by definition -- a path with a name outside
 * the code page would arrive as question marks rather than as itself.
 */

#include "stainless.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <unistd.h>
extern char **environ;
#endif

/* --------------------------------------------------------------- arguments */

/*
 * What main() was handed, kept for the whole run.
 *
 * The entry point stores these before anything else, and the strings are the
 * ones the C runtime owns -- they outlive the program's use of them, so no
 * copy is needed and none is made.
 */
static int    argumentCount;
static char **argumentValues;

void sl_args_set(int count, char **values)
{
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

/* -------------------------------------------------------------- variables */

/*
 * The value of a variable, or NULL when it is not set.
 *
 * "Not set" and "set to nothing" are different answers, and both platforms can
 * tell them apart -- so this does too, and the library turns the first into a
 * null String rather than an empty one.
 */
void *sl_env_get(void *name)
{
    const char *wanted = (const char *)sl_string_pointer(name);
    if (wanted == NULL) return NULL;

#ifdef _WIN32
    wchar_t *wide = sl_widen(wanted);
    if (wide == NULL) return NULL;

    /* Asked twice: once for the length, once for the value. A variable that
     * grew in between would be truncated, so the second call's own answer is
     * what is trusted. */
    DWORD units = GetEnvironmentVariableW(wide, NULL, 0);
    if (units == 0) { free(wide); return NULL; }

    wchar_t *value = (wchar_t *)malloc((size_t)units * sizeof(wchar_t));
    if (value == NULL) { free(wide); sl_fail("out of memory"); }

    DWORD written = GetEnvironmentVariableW(wide, value, units);
    free(wide);

    if (written == 0 || written >= units) { free(value); return NULL; }

    char *text = sl_narrow(value);
    free(value);
    if (text == NULL) return NULL;

    void *result = sl_string_from_null_terminated(text);
    free(text);
    return result;
#else
    const char *value = getenv(wanted);
    return value == NULL ? NULL : sl_string_from_null_terminated(value);
#endif
}

/* Sets a variable for this process, or removes it when the value is null. */
_Bool sl_env_set(void *name, void *value)
{
    const char *wanted = (const char *)sl_string_pointer(name);
    if (wanted == NULL) return 0;

    const char *text = value == NULL ? NULL : (const char *)sl_string_pointer(value);

#ifdef _WIN32
    wchar_t *wideName = sl_widen(wanted);
    if (wideName == NULL) return 0;

    wchar_t *wideValue = text == NULL ? NULL : sl_widen(text);
    _Bool ok = SetEnvironmentVariableW(wideName, wideValue) != 0;

    free(wideName);
    free(wideValue);
    return ok;
#else
    if (text == NULL) return unsetenv(wanted) == 0;
    return setenv(wanted, text, 1) == 0;
#endif
}

/* The builder's text, and the builder let go. It was allocated +1. */
static void *builder_result(SlStringBuilder *builder)
{
    void *text = sl_string_builder_to_string(builder);
    sl_release(builder);
    return text;
}

/*
 * Every variable's name, as one String with a newline after each.
 *
 * One String rather than an array because the runtime has no convenient way to
 * build a Stainless array of references, and the library splits it in a line
 * of Stainless. A name cannot contain a newline on either platform, so nothing
 * is lost in the round trip.
 */
void *sl_env_names(void)
{
    SlStringBuilder *names = (SlStringBuilder *)sl_string_builder_new();

#ifdef _WIN32
    wchar_t *block = GetEnvironmentStringsW();
    if (block == NULL) return builder_result(names);

    for (wchar_t *at = block; *at != L'\0'; ) {
        size_t length = wcslen(at);

        /* A name beginning with '=' is Windows' per-drive working directory
         * ("=C:"), which is not a variable anybody set. */
        if (*at != L'=') {
            wchar_t *equals = wcschr(at, L'=');
            if (equals != NULL) {
                *equals = L'\0';
                char *text = sl_narrow(at);
                *equals = L'=';

                if (text != NULL) {
                    sl_string_builder_append_bytes(names, (const uint8_t *)text, strlen(text));
                    sl_string_builder_append_bytes(names, (const uint8_t *)"\n", 1);
                    free(text);
                }
            }
        }

        at += length + 1;
    }

    FreeEnvironmentStringsW(block);
#else
    for (char **at = environ; at != NULL && *at != NULL; at += 1) {
        const char *equals = strchr(*at, '=');
        if (equals == NULL) continue;

        sl_string_builder_append_bytes(names, (const uint8_t *)*at, (size_t)(equals - *at));
        sl_string_builder_append_bytes(names, (const uint8_t *)"\n", 1);
    }
#endif

    return builder_result(names);
}

/* ------------------------------------------------------ working directory */

void *sl_env_current_directory(void)
{
#ifdef _WIN32
    DWORD units = GetCurrentDirectoryW(0, NULL);
    if (units == 0) return sl_string_from_null_terminated("");

    wchar_t *wide = (wchar_t *)malloc((size_t)units * sizeof(wchar_t));
    if (wide == NULL) sl_fail("out of memory");

    DWORD written = GetCurrentDirectoryW(units, wide);
    if (written == 0 || written >= units) { free(wide); return sl_string_from_null_terminated(""); }

    char *text = sl_narrow(wide);
    free(wide);
    if (text == NULL) return sl_string_from_null_terminated("");

    void *result = sl_string_from_null_terminated(text);
    free(text);
    return result;
#else
    char buffer[4096];
    if (getcwd(buffer, sizeof buffer) == NULL) return sl_string_from_null_terminated("");
    return sl_string_from_null_terminated(buffer);
#endif
}

_Bool sl_env_set_current_directory(void *path)
{
    const char *text = (const char *)sl_string_pointer(path);
    if (text == NULL) return 0;

#ifdef _WIN32
    wchar_t *wide = sl_widen(text);
    if (wide == NULL) return 0;

    _Bool ok = SetCurrentDirectoryW(wide) != 0;
    free(wide);
    return ok;
#else
    return chdir(text) == 0;
#endif
}
