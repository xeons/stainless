// SPDX-License-Identifier: 0BSD
module Bad;

// No [Flags], so this names one colour at a time and holds no set of them.
public enum Colour { Red, Green, Blue }

int Main() {
    var colour = Colour.Green;
    return colour.HasFlag(Colour.Red) ? 1 : 0;
}
