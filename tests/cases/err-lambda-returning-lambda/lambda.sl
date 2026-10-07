// SPDX-License-Identifier: 0BSD
//
// A lambda that returns a lambda, passed where a generic function infers its
// type arguments. It is refused for what it is. Found by the fuzzer, as an
// InvalidCastException binding the declaration around it.
module ErrLambdaReturningLambda;

import Standard.Collections;

int Main()
{
    var numbers = new List<int>();
    numbers.Add(3);
    var doubled = Select(numbers, n => n => 2);     // SLG0005
    return 0;
}