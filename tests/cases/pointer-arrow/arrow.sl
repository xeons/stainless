// `p->field`, which is what walking a struct pointer looks like everywhere else.
//
// A '.' has always reached through a pointer, so the arrow adds no power; what
// it adds is that it says so. Both spellings appear here on the same pointer and
// produce the same number, which is the property worth pinning.
module PointerArrow;

import Standard.Console;
import Standard.Text;

public struct Point {
    public int X;
    public int Y;
}

/// A window procedure's state block: the shape the arrow exists for.
public struct State {
    public Point Origin;
    public int   Count;
}

int Sum(Point* point) {
    return point->X + point->Y;
}

/// Writing through an arrow, which is the half a read alone would not prove.
void Advance(State* state, int by) {
    state->Count = state->Count + by;
    state->Origin.X = state->Origin.X + by;
}

/// An arrow, then a dot into the value it found.
int OriginX(State* state) {
    return state->Origin.X;
}

/// A compound assignment through one, since that reads the slot as well.
void Bump(Point* point) {
    point->Y += 6;
}

int Main() {
    Point point;
    point.X = 3;
    point.Y = 4;

    Console.WriteLine("sum: " + Text.FromInteger(Sum(&point)));

    Bump(&point);
    Console.WriteLine("bumped: " + Text.FromInteger(point.Y));

    State state;
    state.Origin = point;
    state.Count = 10;

    Advance(&state, 5);
    Console.WriteLine("count: " + Text.FromInteger(state.Count));
    Console.WriteLine("origin x: " + Text.FromInteger(OriginX(&state)));

    // The two spellings on one pointer, reaching the same field.
    State* through = &state;
    Console.WriteLine("dot: " + Text.FromInteger(through.Count)
        + ", arrow: " + Text.FromInteger(through->Count));

    return 0;
}
