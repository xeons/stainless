// SPDX-License-Identifier: 0BSD
module Bad;

int Work() => 1;

int Main()
{
    int result = 0;
    spawn result = Work();      // nothing waits for this
    return result;
}
