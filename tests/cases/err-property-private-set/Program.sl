// SPDX-License-Identifier: 0BSD
module Program;

import Model;

int Main() {
    var account = new Account();

    account.Deposit(10);        // fine: the module writes its own setter
    int shown = account.Balance;  // fine: the getter is public

    account.Balance = 500;      // not fine: the setter is not
    return shown + account.Secret;
}
