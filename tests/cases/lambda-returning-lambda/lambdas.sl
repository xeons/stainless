// SPDX-License-Identifier: 0BSD
module Lambdas;

import Standard.Console;
import Standard.Collections;

// A lambda whose body is a lambda gives a type parameter the inner one's
// natural type: a closure taking nothing and returning what its body does.
int Main()
{
    var numbers = new List<int>();
    numbers.Add(3);
    numbers.Add(4);

    var makers = numbers.Select((p) => () => p * 10).ToArray();
    var first = numbers.Select((p) => () => p + 1).ToArray()[0];

    Console.WriteLine($"{makers[0]()} {makers[1]()} {first()}");
    return 0;
}
