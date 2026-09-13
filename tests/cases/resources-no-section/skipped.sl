// SPDX-License-Identifier: 0BSD
//
// A resource script is a PE idea. Building this for Linux drops `skipped.rc`
// and warns (SL0700) rather than failing, so that one source tree with an icon
// and a manifest in it still builds everywhere without the build itself being
// put behind an `#if`.
module NoResourceSection;

int Main() { return 0; }
