// SPDX-License-Identifier: 0BSD
//
// Two constructors with one signature, both written with '=>'. Refused where
// they are declared. Found by the fuzzer, as IR defining the constructor
// twice, which LLVM's verifier rejected.
module ErrConstructorDuplicateArrow;

class Accumulator
{
    double _total;
    Accumulator() => _total = 0.0;
    Accumulator() => _total = 1.0;      // SLN0006
}

int Main() => 0;