// SPDX-License-Identifier: 0BSD
//
// A library whose class has `init` and `required` members, a constructor that
// sets them, a primary constructor and a static automatic property. What the
// consumer may write is decided by the metadata, which has to say all of it.
module Library.Accounts;

public class Account
{
    public required String Owner { get; init; }
    public int Id { get; init; }
    public required int Limit;

    public Account() { }

    [SetsRequiredMembers]
    public Account(String owner)
    {
        Owner = owner;
        Limit = 10;
    }

    public static int Opened { get; set; }
}

public class Ledger(String name)
{
    public String Name => name;
}
