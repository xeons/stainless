// SPDX-License-Identifier: 0BSD
//
// The consumer has the library's metadata and no source: every constructor
// below was written in a compilation this one never saw.
module App;

import Standard.Console;
import Standard.Text;
import Library.Geometry;

int Main()
{
    var point = new Point(3, 4);
    Console.WriteLine("point " + Text.FromInteger(point.X) + " " +
        Text.FromInteger(point.Sum));

    // The overload that delegates, which runs inside the library.
    Console.WriteLine("square " + Text.FromInteger(new Point(6).Sum));

    // A default the metadata carried, and a field no constructor wrote.
    var extent = new Extent(5u);
    Console.WriteLine("extent " + Text.FromInteger((long)extent.Area()) + " " +
        Text.FromInteger((long)extent.Margin));

    return 0;
}
