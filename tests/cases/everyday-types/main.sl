// SPDX-License-Identifier: 0BSD
//
// C#'s everyday value types: Version, Guid, Lazy<T>, Uri, DateOnly and
// TimeOnly. A struct among them implements IEquatable, IComparable and
// IHashable, and so sorts and keys a set without becoming an interface.
module EverydayTypes;

import Standard.Console;
import Standard.Collections;
import Standard.Time;

String Yes(bool value) => value ? "yes" : "no";

void Versions()
{
    if (Version.Parse("1.4.2") is not Ok parsed)
        return;
    var v = parsed.Value;
    Console.WriteLine("version " + v.ToString() + " " + v.ToString(2) + " " + Text.FromInteger((long)v.Build) + " " +
        Text.FromInteger((long)new Version(3, 1).Build) + " " + Yes(v > new Version(1, 4)) + " " +
        Yes(Version.Parse("1") is Fail) + " " + Yes(Version.Parse("1.x") is Fail));

    Version[] versions = [new Version(2, 0), new Version(1, 4, 2), new Version(1, 4), new Version(1, 10)];
    Sort(versions);
    String order = "";
    foreach (var each in versions)
        order += each.ToString() + " ";
    var seen = new HashSet<Version>();
    seen.Add(v);
    Console.WriteLine("sorted " + order + Yes(seen.Contains(new Version(1, 4, 2))));
}

void Guids()
{
    var random = Guid.NewGuid();
    var ordered = Guid.CreateVersion7();
    Console.WriteLine("guid v" + Text.FromInteger((long)random.Version) + " v" + Text.FromInteger((long)ordered.Version) +
        " variant " + Text.FromInteger((long)random.Variant) + " " + Text.FromInteger((long)random.ToString().ByteLength()) +
        " " + Yes(random != ordered) + " " + Text.FromInteger((long)sizeof(Guid)));

    if (Guid.Parse("{00112233-4455-6677-8899-AABBCCDDEEFF}") is not Ok parsed)
        return;
    var g = parsed.Value;
    Console.WriteLine(g.ToString() + " " + g.ToString("N") + " " + g.ToString("B") + " " + g.ToString("P"));

    var bytes = g.ToByteArray();
    Console.WriteLine("bytes " + Text.FromInteger((long)bytes[0]) + " " + Text.FromInteger((long)bytes[3]) + " " +
        Text.FromInteger((long)bytes[4]) + " " + Text.FromInteger((long)bytes[15]) + " " + Yes(new Guid(bytes) == g) + " " +
        Yes(Guid.Empty < g) + " " + Yes(Guid.Parse("00112233445566778899aabbccddeeff") is Ok) + " " +
        Yes(Guid.Parse("not a guid") is Fail) + " " + Guid.AllBitsSet.ToString("N"));
}

void Lazies()
{
    var made = new List<String>();
    var lazy = new Lazy<String>(() =>
    {
        made.Add("made");
        return "value";
    });
    Console.WriteLine("lazy " + Yes(lazy.IsValueCreated) + " " + lazy.Value + " " + lazy.Value + " " +
        Yes(lazy.IsValueCreated) + " " + Text.FromInteger((long)made.Count));

    var ready = new Lazy<int>(42);
    var single = new Lazy<int>(() => 7, false);
    var racing = new Lazy<int>(() => 9, LazyThreadSafetyMode.PublicationOnly);
    Console.WriteLine("modes " + Text.FromInteger((long)ready.Value) + " " + Text.FromInteger((long)single.Value) + " " +
        Text.FromInteger((long)racing.Value) + " " + Yes(ready.IsValueCreated));
}

void Uris()
{
    var page = new Uri("HTTPS://User@Example.COM:443/docs/./guide/../guide/intro.html?v=2#top");
    Console.WriteLine("uri " + page.AbsoluteUri);
    Console.WriteLine(page.Scheme + " " + page.UserInfo + " " + page.Host + " " + Text.FromInteger((long)page.Port) + " " +
        Yes(page.IsDefaultPort) + " " + page.AbsolutePath + " " + page.Query + " " + page.Fragment + " " +
        page.GetLeftPart(UriPartial.Authority));
    String segments = "";
    foreach (var s in page.Segments)
        segments += "[" + s + "]";
    Console.WriteLine(segments);

    var rfc = new Uri("http://a/b/c/d;p?q");
    String resolved = "";
    String[] references = ["g", "./g", "/g", "?y", "g#s", "..", "../g", "../../../g", "g/../h"];
    foreach (var reference in references)
        resolved += new Uri(rfc, reference).AbsoluteUri + " ";
    Console.WriteLine(resolved);

    var spaced = new Uri("http://localhost:8080/a%20b c");
    Console.WriteLine(spaced.AbsoluteUri + " " + Text.FromInteger((long)spaced.Port) + " " + Yes(spaced.IsLoopback) + " " +
        spaced.LocalPath);
    var file = new Uri("C:\\Temp\\my file.txt");
    Console.WriteLine(file.AbsoluteUri + " " + Yes(file.IsFile) + " " + new Uri("\\\\server\\share\\x.txt").AbsoluteUri);

    var relative = new Uri("../images/logo.png", UriKind.Relative);
    Console.WriteLine(Yes(relative.IsAbsoluteUri) + " " + relative.ToString() + " " +
        Uri.EscapeDataString("a b&c=d/é") + " " + Uri.UnescapeDataString("a%20b%26c%3Dd%2F%C3%A9"));
    Console.WriteLine(Yes(Uri.IsWellFormedUriString("https://x.y/", UriKind.Absolute)) + " " +
        Yes(Uri.IsWellFormedUriString("not a uri", UriKind.Absolute)) + " " +
        Yes(Uri.TryCreate("http://x:99999/", UriKind.Absolute) is Fail));

    var root = new Uri("http://site/docs/guide/");
    Console.WriteLine(root.MakeRelativeUri(new Uri("http://site/docs/api/list.html?x=1")).ToString() + " " +
        Yes(root.IsBaseOf(new Uri("http://site/docs/guide/intro/"))) + " " +
        Yes(root.IsBaseOf(new Uri("http://site/other"))) + " " +
        Yes(new Uri("http://A.com/x#one") == new Uri("http://a.com/x#two")) + " " +
        Text.FromInteger((long)new Uri("mailto:someone@example.com").Port));
}

void Dates()
{
    var d = new DateOnly(2024, 1, 31);
    Console.WriteLine("date " + d.ToString() + " " + d.AddMonths(1).ToString() + " " + d.AddDays(366).ToString() + " " +
        new DateOnly(2024, 2, 29).AddYears(1).ToString() + " " + Text.FromInteger((long)d.DayOfWeek) + " " +
        Text.FromInteger((long)d.DayOfYear) + " " + Text.FromInteger((long)d.DayNumber));
    Console.WriteLine(DateOnly.MinValue.ToString() + " " + DateOnly.MaxValue.ToString() + " " +
        Yes(DateOnly.Parse("2023-02-29") is Fail) + " " +
        (DateOnly.Parse("2024-12-25") is Ok christmas ? christmas.Value.ToString() : "?"));
    var (year, month, day) = d;
    Console.WriteLine(Text.FromInteger((long)year) + "/" + Text.FromInteger((long)month) + "/" + Text.FromInteger((long)day));

    var t = new TimeOnly(22, 30);
    int wrapped;
    var later = t.Add(TimeSpan.FromHours(3), out wrapped);
    Console.WriteLine("time " + t.ToString() + " " + later.ToString() + " " + Text.FromInteger((long)wrapped) + " " +
        Yes(new TimeOnly(23, 0).IsBetween(t, later)) + " " + (later - t).Format() + " " +
        new TimeOnly(1, 2, 3, 450).ToString());
    Console.WriteLine((TimeOnly.Parse("07:05:09.25") is Ok read ? read.Value.ToString() : "?") + " " +
        Yes(TimeOnly.Parse("24:00") is Fail) + " " + TimeOnly.MaxValue.ToString());

    var when = d.ToDateTime(new TimeOnly(8, 15));
    DateOnly[] dates = [new DateOnly(2025, 1, 1), new DateOnly(2020, 6, 1), new DateOnly(2022, 3, 3)];
    Sort(dates);
    Console.WriteLine(when.FormatDate() + "T" + when.FormatTime() + " " + dates[0].ToString() + " " + dates[2].ToString());
}

int Main()
{
    Versions();
    Guids();
    Lazies();
    Uris();
    Dates();
    return 0;
}
