// SPDX-License-Identifier: 0BSD
//
// The ids resources.rc files things under, and resources.sl asks for.
//
// A plain C header, because that is what a resource script includes. There is
// no way to share these with the Stainless side -- Stainless has no #include --
// so resources.sl declares the same numbers as `const int`, and the two lists
// are short enough to read against each other.
#define IDS_TITLE     201
#define IDS_SUBTITLE  202
#define IDS_READY     203
#define IDR_BANNER    301
