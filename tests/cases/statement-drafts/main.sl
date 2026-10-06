// SPDX-License-Identifier: 0BSD
//
// A value with no type of its own, written as a statement, is never made:
// what it was built from runs, for its effects, and the rest is dropped with
// SLL0001.
module StatementDrafts;

import Standard.Console;

int Next(String said)
{
    Console.WriteLine(said);
    return 1;
}

int Main()
{
    [Next("first"), Next("second")];
    Fail(Next("third"));
    (int x) => x + Next("never");
    Main;
    null;
    Console.WriteLine("done");
    return 0;
}
