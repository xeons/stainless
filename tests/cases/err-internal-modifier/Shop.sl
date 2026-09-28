// SPDX-License-Identifier: 0BSD
module Shop;

internal class Ledger
{
}

public class Till
{
    internal int _opened;

    public Till()
    {
    }

    internal int Ring(int count) => count * 2;

    public int Total { get; internal set; }
}

internal int DoubleCount(int count) => count * 2;
