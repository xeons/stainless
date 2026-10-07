// SPDX-License-Identifier: 0BSD
//
// A 'var' whose initializer chooses between lambdas has nothing to infer a
// type from, and says so. Found by the fuzzer, as an InvalidCastException:
// the declaration took the switch for the lambda it chose.
module ErrVarChoosesLambdas;

int Main()
{
    int n = 1;
    var chosen = n switch          // SLT0061
    {
        _ => x => x,
    };
    return 0;
}