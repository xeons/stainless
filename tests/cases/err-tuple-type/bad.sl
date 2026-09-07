// SPDX-License-Identifier: 0BSD
module Bad;

// One type in parentheses is that type, not a tuple of one. Written as a
// return type, where a cast could not have been meant, so the parser is
// certainly reading a type here.
(int) Single() { return 3; }

int Main() { return Single(); }
