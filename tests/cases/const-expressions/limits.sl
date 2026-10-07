// SPDX-License-Identifier: 0BSD
//
// A second module, so a constant is named across modules and before the
// declaration that names it has been read.
module Limits;

public const int Most = Unit * 10 + 10;
public const int Unit = 10;
