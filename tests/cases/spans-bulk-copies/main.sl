// SPDX-License-Identifier: 0BSD
//
// Bulk copies, clears and fills: one `memmove` or `memset` for an element
// with no counted reference, a counting loop for one with, and the same
// answers from both.
module SpanBulkCopies;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

class Tag
{
    public int Id;
    public Tag(int id) => Id = id;
    ~Tag() { Console.WriteLine("~Tag " + Text.FromInteger(Id)); }
}

struct Point
{
    public int X;
    public long Y;
    public Point(int x, long y)
    {
        X = x;
        Y = y;
    }
}

struct Named
{
    public int Key;
    public String Name;
    public Named(int key, String name)
    {
        Key = key;
        Name = name;
    }
}

String ShowBytes(ReadOnlySpan<byte> values)
{
    String text = "[";
    foreach (byte v in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger((long)v);
    return text + "]";
}

String ShowPoints(ReadOnlySpan<Point> values)
{
    String text = "[";
    foreach (Point p in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger(p.X) + "/" + Text.FromInteger(p.Y);
    return text + "]";
}

String ShowTags(ReadOnlySpan<Tag?> values)
{
    String text = "[";
    foreach (Tag? t in values)
        text += (text == "[" ? "" : " ") + (t is Tag tag ? Text.FromInteger(tag.Id) : "-");
    return text + "]";
}

String ShowNamed(ReadOnlySpan<Named> values)
{
    String text = "[";
    foreach (Named n in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger(n.Key) + n.Name;
    return text + "]";
}

String ShowList<T>(List<T> list, Func<T, String> show)
{
    String text = "[";
    for (nuint i = 0u; i < list.Count; i++)
        text += (i == 0u ? "" : " ") + show(list[i]);
    return text + "]";
}

void CopyBytes()
{
    byte[] bytes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    bytes[0:6].CopyTo(bytes[2:]);
    Console.WriteLine("bytes forward:  " + ShowBytes(bytes));

    bytes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    bytes[3:].CopyTo(bytes);
    Console.WriteLine("bytes backward: " + ShowBytes(bytes));

    byte[] small = new byte[3];
    Console.WriteLine("too short: " + (bytes[:4].TryCopyTo(small) ? "copied" : "refused"));
    Console.WriteLine("fits: " + (bytes[:3].TryCopyTo(small) ? "copied" : "refused") +
        " " + ShowBytes(small));

    byte[] none = [];
    ReadOnlySpan<byte> empty = none;
    empty.CopyTo(small);
    Console.WriteLine("empty copy: " + ShowBytes(small) + " " +
        Text.FromInteger((long)empty.ToArray().Length));

    Span<byte> middle = bytes[2:8];
    middle.Fill(9);
    Console.WriteLine("fill: " + ShowBytes(bytes));
    middle.Clear();
    Console.WriteLine("clear: " + ShowBytes(bytes));
    Console.WriteLine("to array: " + ShowBytes(bytes[1:4].ToArray()));
}

void CopyPoints()
{
    var points = new Point[6];
    for (int i = 0; i < 6; i++)
        points[(nuint)i] = new Point(i, (long)i * 100);

    points[0:4].CopyTo(points[1:]);
    Console.WriteLine("points forward:  " + ShowPoints(points));

    points[2:].CopyTo(points);
    Console.WriteLine("points backward: " + ShowPoints(points));

    Span<Point> some = points[1:4];
    some.Fill(new Point(7, 70));
    Console.WriteLine("fill: " + ShowPoints(points));
    some.Clear();
    Console.WriteLine("clear: " + ShowPoints(points));
}

void CopyTags()
{
    Tag?[] tags = [new Tag(1), new Tag(2), new Tag(3), new Tag(4)];
    var copies = new Tag?[4];
    ReadOnlySpan<Tag?> all = tags;
    all.CopyTo(copies);
    Console.WriteLine("tags copied: " + ShowTags(copies));

    tags[0:3].CopyTo(tags[1:]);
    Console.WriteLine("tags forward: " + ShowTags(tags));
    tags[1:].CopyTo(tags);
    Console.WriteLine("tags backward: " + ShowTags(tags));

    Span<Tag?> view = copies;
    view.Fill(tags[0u]);
    Console.WriteLine("fill: " + ShowTags(copies));
    view.Clear();
    Console.WriteLine("clear: " + ShowTags(copies));

    Named[] named = [new Named(1, "a"), new Named(2, "b"), new Named(3, "c")];
    named[0:2].CopyTo(named[1:]);
    Console.WriteLine("named: " + ShowNamed(named));
}

void ChangeLists()
{
    var bytes = new List<byte>();
    for (int i = 0; i < 10; i++)
        bytes.Add((byte)i);
    bytes.Insert(2u, 99);
    bytes.RemoveAt(5u);
    bytes.RemoveRange(0u, 2u);
    bytes.InsertRange(1u, [7, 7, 7]);
    bytes.AddRange(bytes);
    Console.WriteLine("byte list: " + ShowList(bytes, (b) => Text.FromInteger((long)b)) +
        " " + ShowBytes(bytes.ToArray()));
    var into = new byte[24];
    bytes.CopyTo(into, 1u);
    Console.WriteLine("copied into: " + ShowBytes(into));

    var points = new List<Point>();
    for (int i = 0; i < 6; i++)
        points.Add(new Point(i, (long)-i));
    points.Insert(0u, new Point(42, 42));
    points.RemoveAt(3u);
    points.InsertRange(2u, points);
    Console.WriteLine("point list: " + ShowPoints(points.ToArray()));

    var tags = new List<Tag?>();
    for (int i = 10; i < 15; i++)
        tags.Add(new Tag(i));
    tags.Insert(1u, new Tag(20));
    tags.RemoveAt(0u);
    tags.RemoveRange(1u, 2u);
    tags.AddRange(tags);
    Console.WriteLine("tag list: " + ShowTags(tags.ToArray()));
    tags.Clear();
    Console.WriteLine("cleared");
}

int Main()
{
    CopyBytes();
    CopyPoints();
    CopyTags();
    ChangeLists();
    return 0;
}
