// SPDX-License-Identifier: 0BSD
//
// `Option<T>`, `OrderedDictionary<K, V>`, and the two things a `List` and a
// `StringBuilder` could not do.
module OptionOrdered;

import Standard.Collections;
import Standard.Console;

void Say(String label, String value) {
    Console.WriteLine(label + " = " + value);
}

// A value or none, for the types `T?` cannot describe. `nuint?` is refused
// because a value type has no spare bit to be null with; this costs a tag
// beside the value and nothing else.
Option<nuint> FirstEven(int[] values) {
    for (nuint i = 0u; i < values.Length; i = i + 1u) {
        if (values[i] % 2 == 0) { return Some(i); }
    }
    return None;
}

String Describe(Option<nuint> found) {
    switch (found) {
        case Some at: return "at " + Text.FromInteger((long)at.Value);
        case None:    return "none";
    }
}

public int Main() {
    // ------------------------------------------------------------- Option
    var evens = new int[3];
    evens[0u] = 1;
    evens[1u] = 4;
    evens[2u] = 6;

    Say("found", Describe(FirstEven(evens)));

    var odds = new int[2];
    odds[0u] = 1;
    odds[1u] = 3;

    Say("not-found", Describe(FirstEven(odds)));

    // The two readers that need no proof, because they supply their own.
    Say("has-value", Text.FromBool(FirstEven(evens).HasValue()));
    Say("no-value", Text.FromBool(FirstEven(odds).HasValue()));
    Say("value-or", Text.FromInteger((long)FirstEven(odds).ValueOr(99u)));
    Say("value-or-present", Text.FromInteger((long)FirstEven(evens).ValueOr(99u)));

    // ------------------------------------------------- OrderedDictionary
    var map = new OrderedDictionary<String, int>();
    map.Add("first", 1);
    map.Add("second", 2);
    map.Add("third", 3);

    Say("count", Text.FromInteger((long)map.Count()));
    Say("order", map.KeyAt(0u) + "," + map.KeyAt(1u) + "," + map.KeyAt(2u));
    Say("find", Text.FromInteger((long)map.Find("second", -1)));
    Say("missing", Text.FromInteger((long)map.Find("nope", -1)));
    Say("has", Text.FromBool(map.Has("third")) + "/" + Text.FromBool(map.Has("nope")));
    Say("index", Describe(map.IndexOf("third")) + "/" + Describe(map.IndexOf("nope")));

    // Replacing keeps the position, which is the point of the collection.
    map.Set("first", 10);
    Say("replaced", map.KeyAt(0u) + "=" + Text.FromInteger((long)map.ValueAt(0u)));

    // Setting something absent appends.
    map.Set("fourth", 4);
    Say("appended", map.KeyAt(3u) + "=" + Text.FromInteger((long)map.ValueAt(3u)));

    // Removing closes the gap and keeps the rest in order.
    Say("removed", Text.FromBool(map.Remove("second")));
    Say("after-remove", map.KeyAt(0u) + "," + map.KeyAt(1u) + "," + map.KeyAt(2u));
    Say("remove-missing", Text.FromBool(map.Remove("nope")));

    // A repeated key is kept rather than replaced: that is what `Add` says and
    // `Set` is the one that replaces.
    var repeated = new OrderedDictionary<String, int>();
    repeated.Add("x", 1);
    repeated.Add("x", 2);
    Say("repeated", Text.FromInteger((long)repeated.Count())
        + "/" + Text.FromInteger((long)repeated.Find("x", 0)));

    // ------------------------------------------------------ List edits
    var list = new List<String>();
    list.Add("b");
    list.Add("d");
    list.Insert(0u, "a");
    list.Insert(2u, "c");
    list.Insert(list.Count(), "e");

    var joined = new StringBuilder();
    for (nuint i = 0u; i < list.Count(); i = i + 1u) { joined.Append(list.At(i)); }
    Say("inserted", joined.ToText());

    list.RemoveAt(0u);
    list.RemoveAt(list.Count() - 1u);

    var left = new StringBuilder();
    for (nuint i = 0u; i < list.Count(); i = i + 1u) { left.Append(list.At(i)); }
    Say("removed-ends", left.ToText() + "/" + Text.FromInteger((long)list.Count()));

    // --------------------------------------------- StringBuilder appends
    var text = new StringBuilder();
    text.AppendByte((byte)'a');
    text.AppendByte((byte)'b');
    text.AppendChar('c');

    // A character above ASCII is more than one byte, which is the whole
    // reason AppendChar is not AppendByte.
    text.AppendChar((char32)0x1F600u);
    text.AppendChar((char32)0xE9u);

    Say("appended-text", text.ToText());
    Say("appended-bytes", Text.FromInteger((long)text.ByteLength()));

    // Anything that is not a scalar becomes U+FFFD, as everywhere else.
    var bad = new StringBuilder();
    bad.AppendChar((char32)0xD800u);
    Say("lone-surrogate", bad.ToText());

    return 0;
}
