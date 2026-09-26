// SPDX-License-Identifier: 0BSD
//
// Several modules may declare one C variable, as several C files may, and one
// of them may define it. It is one symbol and one address.
module ExternVariablesShared;

import Standard.Console;
import SharedOwner;
import SharedReader;

extern "C" int shared_total;

int Main()
{
    BumpFromReader();
    shared_total++;
    Console.WriteLine($"{shared_total} {ReadFromOwner()}");
    return 0;
}
