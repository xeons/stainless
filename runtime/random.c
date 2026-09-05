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
 * Entropy from the operating system, and nothing else.
 *
 * The generator itself is written in Stainless (Standard.Random): it is
 * arithmetic, it wants to be seeded and reproduced deliberately, and a
 * generator in C would be one more thing the language cannot read. What has to
 * be here is the seed, because only the platform has one.
 *
 * This is the OS's cryptographic source on both platforms. That does not make
 * `Standard.Random` cryptographic -- it is a fast PRNG, and its output is
 * predictable from its state by design. Use the platform directly if the
 * distinction matters.
 */

#include "stainless.h"

#include <stddef.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt")
#else
#  include <errno.h>
#  include <stdio.h>
#  include <sys/types.h>
#  if defined(__linux__)
#    include <sys/random.h>
#  endif
#endif

/*
 * Fills a buffer with bytes from the platform's entropy source, reporting
 * whether it managed.
 *
 * A failure is reported rather than papered over with a clock reading: a
 * caller that wanted unpredictability and silently got the time would be worse
 * off than one told it could not have any.
 */
_Bool sl_random_bytes(void *buffer, size_t length)
{
    if (buffer == NULL || length == 0) return length == 0;

#ifdef _WIN32
    return BCryptGenRandom(NULL, (PUCHAR)buffer, (ULONG)length,
                           BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
#elif defined(__linux__)
    unsigned char *at = (unsigned char *)buffer;
    size_t left = length;

    while (left > 0) {
        /* getrandom can return short, and can be cut short by a signal. */
        ssize_t got = getrandom(at, left, 0);
        if (got < 0) {
            if (errno == EINTR) continue;
            break;
        }
        at += got;
        left -= (size_t)got;
    }

    if (left == 0) return 1;

    /* Fall through to the device, for a kernel too old for the call. */
    FILE *source = fopen("/dev/urandom", "rb");
    if (source == NULL) return 0;

    size_t read = fread(at, 1, left, source);
    fclose(source);
    return read == left;
#else
    FILE *source = fopen("/dev/urandom", "rb");
    if (source == NULL) return 0;

    size_t read = fread(buffer, 1, length, source);
    fclose(source);
    return read == length;
#endif
}

/* One 64-bit value's worth, which is what seeding a generator wants. */
long long sl_random_seed(void)
{
    long long seed = 0;
    if (sl_random_bytes(&seed, sizeof seed)) return seed;

    sl_fail("the operating system would not supply any entropy");
    return 0;
}
