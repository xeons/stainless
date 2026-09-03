// SPDX-License-Identifier: 0BSD
module Bad;

public enum Colour { Red, Green, Blue }

int Main() {
    var colour = Colour.Green;
    switch (colour) {
        case Colour.Red:   return 1;
        case Colour.Green: return 2;
        case Colour.Red:   return 3;    // already covered
        default:           return 0;
    }
}
