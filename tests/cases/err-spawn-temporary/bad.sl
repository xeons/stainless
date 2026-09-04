// SPDX-License-Identifier: 0BSD
module Bad;

int Length(String text) { return (int)text.ByteLength(); }

int Main() {
    int n = 0;
    parallel {
        // The String dies at the end of this statement, before the job runs.
        spawn n = Length("a" + "b");
    }
    return n;
}
