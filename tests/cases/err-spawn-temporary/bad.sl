// SPDX-License-Identifier: 0BSD
module Bad;

int Length(String text) => (int)text.ByteLength();

int Main()
{
    int n = 0;
    parallel
    {
        // The String dies at the end of this statement, before the job runs.
        n = spawn Length("a" + "b");
    }
    return n;
}
