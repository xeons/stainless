// SPDX-License-Identifier: 0BSD
//
// There is no `record struct`. A record is its constructor, and a struct has
// none -- it is a plain C value, which is what lets one cross to C at all.
// Giving structs constructors is a decision about structs rather than a
// consequence of wanting records, so it has not been made.
module RecordStruct;

public record struct Size(int Width, int Height);

int Main() { return 0; }
