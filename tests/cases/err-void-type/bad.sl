// SPDX-License-Identifier: 0BSD
module Bad;

// 'void' is the absence of a value, so the only place it can be written is
// what a function returns. Everywhere else it named storage for nothing and
// reached the emitter as 'alloca void' or a struct with a 'void' member,
// neither of which is IR that exists -- so the answer was a message about
// generated text rather than about the program.

struct Holder {
    public void Nothing;
}

void Fine() { }

void Takes(void nothing) { }

Result<int, void> Fails() { return Ok(1); }

int Main() {
    void local;
    return 0;
}
