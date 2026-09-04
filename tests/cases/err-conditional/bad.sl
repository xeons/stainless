// SPDX-License-Identifier: 0BSD
//
// A name is a name: this one is checked before anything has been declared, so
// it is the shape that is wrong rather than the position.
#define 9lives

module Bad;

// This one is in the right shape and the wrong place.
#define LATE

#if WINDOWS
#else
#elif LINUX
#endif

#endif

#pragma once

#if
#endif

#if WINDOWS &&
#endif

#if NEVER_CLOSED

int Main() { return 0; }
