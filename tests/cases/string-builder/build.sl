// SPDX-License-Identifier: 0BSD
module Build;

import Standard.Console;

int Main() {
    var builder = new StringBuilder();
    Console.WriteLine("empty=" + Text.FromBool(builder.IsEmpty()));

    for (int i = 0; i < 5; i = i + 1) {
        builder.AppendInteger(i);
        builder.Append(",");
    }
    Console.WriteLine(builder.ToText());
    Console.WriteLine("length=" + Text.FromInteger(builder.ByteLength()));

    builder.AppendLine("");
    builder.Append("tail");
    builder.AppendDouble(1.5);
    Console.Write(builder.ToText());
    Console.WriteLine("");

    // ToText snapshots; the builder keeps going afterwards.
    String snapshot = builder.ToText();
    builder.Clear();
    Console.WriteLine("cleared=" + Text.FromBool(builder.IsEmpty()));
    Console.WriteLine("snapshot kept " + Text.FromInteger(snapshot.ByteLength()) + " bytes");
    return 0;
}
