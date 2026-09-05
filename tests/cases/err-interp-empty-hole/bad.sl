// SPDX-License-Identifier: 0BSD
module Bad;

// `{}` names no value to write.
int Main() {
    String written = $"nothing {}";
    return (int)written.ByteLength();
}
