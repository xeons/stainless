// SPDX-License-Identifier: 0BSD
//
// The consumer has the library's metadata and no source.
module App;

import Standard.Console;
import Standard.Text;
import Library.Accounts;

int Main()
{
    var made = new Account { Owner = "ada", Limit = 5, Id = 3 };
    var named = new Account("bob");
    Account.Opened += 2;
    Console.WriteLine(made.Owner + " " + Text.FromInteger(made.Id + made.Limit));
    Console.WriteLine(named.Owner + " " + Text.FromInteger(named.Limit));
    Console.WriteLine(Text.FromInteger(Account.Opened) + " " + new Ledger("books").Name);
    return 0;
}
