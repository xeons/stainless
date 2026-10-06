// SPDX-License-Identifier: 0BSD
//
// 'internal' is its module's, exactly as no word at all is.
module Outside;

import Shop;

public int Main()
{
    var till = new Till();
    till.Total = 3;                       // SLN0014
    var ledger = new Shop.Ledger();       // SLN0014
    return till.Ring(2)                   // SLN0014
        + till._opened                    // SLN0014
        + Shop.DoubleCount(1);            // SLN0011
}
