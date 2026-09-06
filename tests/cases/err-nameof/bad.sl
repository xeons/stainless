// SPDX-License-Identifier: 0BSD
module Bad;

// `nameof` takes something with a name and answers with the last name in it.
// Both halves of that are checked: there has to be a name written, and it has
// to be a name of something.

int Main() {
    int counter = 0;

    // Nothing here has a name.
    var sum = nameof(counter + 1);

    // A name, of nothing.
    var missing = nameof(mispelled);

    // The right spelling of the wrong thing: `Count` is not a member here.
    var member = nameof(counter.Count);
    return 0;
}
