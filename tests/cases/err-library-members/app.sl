// SPDX-License-Identifier: 0BSD
//
// What the library declared `init` and `required` stays so across the
// boundary: the metadata carries both.
module App;

import Library.Accounts;

int Main()
{
    var made = new Account { Owner = "ada" };
    var named = new Account("bob");
    named.Id = 4;
    return 0;
}
