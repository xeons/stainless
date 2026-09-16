// SPDX-License-Identifier: 0BSD
module Bad;

// `try` passes a failure to the caller, so it needs something that could have
// failed.
Result<int, int> Main2()
{
    int n = try 5;
    return Ok(n);
}

int Main() => 0;
