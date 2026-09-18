// SPDX-License-Identifier: 0BSD
//
// Every chunk of the loop would read the same unsynchronized list. Warned
// about rather than refused: whether that is a race depends on what the body
// does with it, which no declaration can say.
module Bad;

import Standard.Collections;
import Standard.Threading;

extern "C" int printf(byte* format, ...);

int Main()
{
    var items = new List<int>();
    for (int i = 0; i < 10; i = i + 1)
        items.Add(i);

    var total = new AtomicLong(0);

    // Reading is safe here and writing would not be; the compiler can see
    // neither, so it says what it does know and leaves the choice.
    for parallel (int i = 0; i < 10; i = i + 1)
        total.Add((long)items[(nuint)i]);

    printf("total=%lld\n", total.Load());
    return 0;
}
