// SPDX-License-Identifier: 0BSD
module Model;

public class Account {
    // Readable anywhere, writable only inside this module.
    public int Balance { get; private set; }

    // Not public at all, so neither accessor crosses the module boundary.
    int Secret { get; set; }

    public Account() { Balance = 0; Secret = 0; }
    public void Deposit(int amount) { Balance = Balance + amount; }
}
