// SPDX-License-Identifier: 0BSD
module Nested;

import Standard.Collections;
import Standard.Threading;

extern "C" int printf(byte* format, ...);

public class Box<T> {
    T value;
    public Box(T initial) { value = initial; }
    public T Get() { return value; }
}

int Main() {
    // The last two characters here are one shift operator to the lexer; only
    // the parser knows a type argument list is open and splits them.
    var boxes = new List<Box<int>>();
    boxes.Add(new Box<int>(7));
    boxes.Add(new Box<int>(35));

    int total = 0;
    for (nuint i = 0; i < boxes.Count(); i = i + 1) { total = total + boxes.At(i).Get(); }
    printf("total=%d\n", total);

    // Three deep.
    var deep = new Box<Box<Box<int>>>(new Box<Box<int>>(new Box<int>(9)));
    printf("deep=%d\n", deep.Get().Get().Get());

    // Six deep: the closing run is six characters, which the lexer hands over as
    // three '>>' tokens. Each list takes half of one and puts the rest back, so
    // neither the depth nor its parity matters.
    var six = new Box<Box<Box<Box<Box<Box<int>>>>>>(
        new Box<Box<Box<Box<Box<int>>>>>(
            new Box<Box<Box<Box<int>>>>(
                new Box<Box<Box<int>>>(
                    new Box<Box<int>>(
                        new Box<int>(42))))));
    printf("six=%d\n", six.Get().Get().Get().Get().Get().Get());

    // Five deep: two '>>' and a lone '>'.
    var five = new Box<Box<Box<Box<Box<int>>>>>(
        new Box<Box<Box<Box<int>>>>(
            new Box<Box<Box<int>>>(
                new Box<Box<int>>(
                    new Box<int>(7)))));
    printf("five=%d\n", five.Get().Get().Get().Get().Get());

    var guarded = new Mutex<List<Box<int>>>(boxes);
    { var g = guarded.Lock(); printf("guarded=%d\n", (int)g.Value().Count()); }

    printf("done\n");
    return 0;
}
