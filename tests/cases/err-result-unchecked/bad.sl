// SPDX-License-Identifier: 0BSD
module Bad;

enum Why { None = 0, Bad = 1 }

Result<int, Why> Get(int n) { return Ok(n); }

// Nothing has established that it succeeded.
int Unchecked() {
    var r = Get(1);
    return r.Value;
}

// It is known to have succeeded, so Error is the wrong half.
int WrongHalf() {
    var r = Get(1);
    if (r.Ok) { return (int)r.Error; }
    return 0;
}

// The proof was about the value the local held before the assignment.
int Reassigned() {
    var r = Get(1);
    if (!r.Ok) { return 0; }
    r = Get(2);
    return r.Value;
}

// A call result is not something a check can be about.
int NotHeld() { return Get(1).Value; }

// One value does not say what both type arguments are.
int Inferred() {
    var r = Ok(1);
    return 0;
}

// The language owns these two names at module level.
int Ok(int n) { return n; }

int Main() { return 0; }
