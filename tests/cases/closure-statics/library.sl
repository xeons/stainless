// SPDX-License-Identifier: 0BSD
module ClosureLibrary;

public closure int IntFn(int x);

public static readonly IntFn s_doubled = (int x) => x * 2;

public class Handlers
{
    public static IntFn Offset = (int x) => x + 100;
}
