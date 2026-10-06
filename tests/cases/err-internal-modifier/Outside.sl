// SPDX-License-Identifier: 0BSD
//
// 'internal' is its module's, exactly as no word at all is.
module Outside;

import Shop;

public int Main()
{
    var till = new Till();
    till.Total = 3;                       // SL0249
    var ledger = new Shop.Ledger();       // SL0249
    return till.Ring(2)                   // SL0249
        + till._opened                    // SL0249
        + Shop.DoubleCount(1);            // SL0229
}
