// SPDX-License-Identifier: 0BSD
module Bad;

variant Shape
{
    Circle(double radius);
    Square;
}

// `goto case` names a section of the switch it is in, by a constant one of
// its labels has; `goto default` names the default.

void Outside()
{
    // Not in a switch at all.
    goto case 1;
}

void Missing(int n)
{
    switch (n)
    {
        case 1:
            // No section is labelled 2.
            goto case 2;
        case 3:
            // A section is named by a constant, and a variable is not one.
            goto case n;
        default:
            break;
    }
}

void NoDefault(int n)
{
    switch (n)
    {
        case 1:
            goto default;
    }
}

// A variant's section is entered knowing which case the value holds.
void OverAVariant(Shape shape)
{
    switch (shape)
    {
        case Circle:
            goto case Square;
        default:
            break;
    }
}

int Main() => 0;
