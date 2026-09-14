// SPDX-License-Identifier: 0BSD
//
// A resource script compiled for a target with no resource directory.
//
// It is not dropped: the compiler puts the compiled `.res` in the binary's
// `.rsrc` section as ordinary data, and `Standard.Resources` walks it. What
// does not travel is the part where the *system* reads a resource on the
// program's behalf, so SL0700 names the types that needed one.
module NoResourceSection;

int Main() { return 0; }
