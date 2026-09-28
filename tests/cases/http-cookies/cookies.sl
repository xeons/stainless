// SPDX-License-Identifier: 0BSD
// Cookies by RFC 6265: how Set-Cookie is read, which cookies a host may set,
// which are sent where, and when they die; then the same through a server,
// across a redirect, and with cookies turned off.
module HttpCookies;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;
import Standard.Text;
import Standard.Time;
import HttpTestServer;

void ShowStored(CookieContainer jar, String from, String header)
{
    nuint stored = jar.SetCookies(new Uri(from), header);
    Console.WriteLine(Text.FromInteger((long)stored) + " kept  " + from + "  " + header);
}

void ShowSent(CookieContainer jar, String to)
{
    String header = jar.GetCookieHeader(new Uri(to));
    Console.WriteLine("  to " + to + ": " + (header.IsEmpty ? "(none)" : header));
}

void ShowCookie(Cookie cookie)
{
    // A Max-Age is from now, so it is shown as the distance from now.
    String expires = "session";
    if (cookie.Expires is Some at)
    {
        long minutes = (long)((at.Value - DateTimeOffset.UtcNow).TotalMinutes + 0.5);
        expires = minutes < 1440 ? "in " + Text.FromInteger(minutes) + " minutes" : at.Value.FormatIso();
    }
    Console.WriteLine("  " + cookie.Name + "=" + cookie.Value + " domain " + cookie.Domain +
                      (cookie.IsHostOnly ? " (host only)" : "") + " path " + cookie.Path +
                      (cookie.Secure ? " secure" : "") + (cookie.HttpOnly ? " httponly" : "") +
                      (cookie.SameSite.IsEmpty ? "" : " samesite " + cookie.SameSite) +
                      " expires " + expires);
}

HttpTestReply RouteCookies(HttpTestRequest request)
{
    String sent = request.HasField("Cookie") ? request.GetField("Cookie") : "(none)";
    switch (request.Target)
    {
        case "/login":
            return HttpTestReply.CreateText(200, "OK",
                "Set-Cookie: session=abc; Path=/; HttpOnly\r\nSet-Cookie: pref=dark; Path=/app\r\n", "in");
        case "/logout":
            return HttpTestReply.CreateText(200, "OK", "Set-Cookie: session=gone; Max-Age=0; Path=/\r\n", "out");
        case "/hop":
            return HttpTestReply.CreateText(302, "Found",
                "Set-Cookie: hop=1; Path=/landing\r\nLocation: /landing\r\n", "hopping");
    }
    return HttpTestReply.CreateText(200, "OK", "", request.Target + " got " + sent);
}

void ShowFetched(HttpClient client, String uri)
{
    var sent = client.GetString(uri);
    Console.WriteLine("  " + (sent.Ok ? sent.Value : "failed: " + $"{sent.Error}"));
}

int Main()
{
    Console.WriteLine("-- which cookies a host may set");
    var jar = new CookieContainer();
    ShowStored(jar, "http://www.example.com/dir/page", "plain=1");
    ShowStored(jar, "http://www.example.com/dir/page", "wide=2; Path=/; Domain=example.com");
    ShowStored(jar, "http://www.example.com/", "dotted=3; Path=/; Domain=.EXAMPLE.com");
    ShowStored(jar, "http://www.example.com/", "elsewhere=4; Domain=other.com");
    ShowStored(jar, "http://www.example.com/", "sibling=4; Domain=api.example.com");
    ShowStored(jar, "http://www.example.com/", "suffix=5; Domain=com");
    ShowStored(jar, "http://www.example.co.uk/", "suffix=6; Domain=co.uk");
    ShowStored(jar, "http://co.uk/", "itself=6; Domain=co.uk");
    ShowStored(jar, "http://www.example.com/", "insecure=7; Secure");
    ShowStored(jar, "https://www.example.com/", "secure=7; Secure; Path=/");
    ShowStored(jar, "http://www.example.com/", "nameless");
    ShowStored(jar, "http://www.example.com/", "=empty");
    ShowStored(jar, "http://www.example.com/", "flags=8; HttpOnly; SameSite=Lax; Path=/");
    ShowStored(jar, "http://www.example.com/", "docs=9; Path=/docs");
    ShowStored(jar, "http://127.0.0.1/", "numeric=10; Domain=127.0.0.1");
    ShowStored(jar, "http://10.0.0.1/", "numeric=11; Domain=0.0.1");

    Console.WriteLine("-- when they expire");
    ShowStored(jar, "http://www.example.com/", "past=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT");
    ShowStored(jar, "http://www.example.com/", "future=1; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT");
    ShowStored(jar, "http://www.example.com/", "ageWins=1; Path=/; Max-Age=3600; Expires=Wed, 21 Oct 2015 07:28:00 GMT");
    ShowStored(jar, "http://www.example.com/", "dashes=1; Path=/; expires=Wednesday, 21-Oct-2099 07:28:00 GMT");
    ShowStored(jar, "http://www.example.com/", "loose=1; Path=/; Expires=21 oct 99 7:28:00");
    ShowStored(jar, "http://www.example.com/", "garbage=1; Path=/; Expires=not a date");
    ShowStored(jar, "http://www.example.com/", "doomed=1; Path=/");
    ShowStored(jar, "http://www.example.com/", "doomed=1; Path=/; Max-Age=0");
    ShowStored(jar, "http://www.example.com/", "listed=1; Path=/; Expires=Thu, 01 Jan 2099 00:00:00 GMT, second=2; Path=/");

    Console.WriteLine("-- what is sent where");
    ShowSent(jar, "http://www.example.com/");
    ShowSent(jar, "http://www.example.com/dir/other");
    ShowSent(jar, "https://www.example.com/docs/guide");
    ShowSent(jar, "http://www.example.com/docsx");
    ShowSent(jar, "http://sub.example.com/");
    ShowSent(jar, "http://example.com/");
    ShowSent(jar, "http://notexample.com/");
    ShowSent(jar, "http://127.0.0.1/");

    Console.WriteLine("-- as held");
    foreach (var cookie in jar.GetCookies(new Uri("https://www.example.com/docs/x")))
        ShowCookie(cookie);

    Console.WriteLine("-- replaced, keeping its place");
    ShowStored(jar, "http://www.example.com/", "wide=changed; Path=/; Domain=example.com");
    ShowSent(jar, "http://sub.example.com/");

    Console.WriteLine("-- added directly");
    var direct = new CookieContainer();
    Console.WriteLine("  without a domain: " + Text.FromBool(direct.Add(new Cookie("a", "1"))));
    Console.WriteLine("  with one: " + Text.FromBool(direct.Add(new Cookie("b", "2", "/", ".example.org"))));
    Console.WriteLine("  for a URI: " + Text.FromBool(direct.Add(new Uri("http://example.org/x/y"), new Cookie("c", "3"))));
    ShowSent(direct, "http://www.example.org/x/z");
    ShowSent(direct, "http://example.org/x/z");

    Console.WriteLine("-- through a server");
    HttpTestServer? started = HttpTestServer.StartServing(RouteCookies);
    if (started == null)
        return 1;
    HttpTestServer server = started;
    String origin = server.Origin;
    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(8);
    ShowFetched(client, origin + "/before");
    ShowFetched(client, origin + "/login");
    ShowFetched(client, origin + "/app/page");
    ShowFetched(client, origin + "/other");
    ShowFetched(client, origin + "/hop");
    ShowFetched(client, origin + "/logout");
    ShowFetched(client, origin + "/app/page");
    client.Dispose();

    var offHandler = new HttpClientHandler();
    offHandler.UseCookies = false;
    offHandler.CookieContainer.Add(new Uri(origin + "/"), new Cookie("ignored", "1"));
    var off = new HttpClient(offHandler);
    ShowFetched(off, origin + "/login");
    ShowFetched(off, origin + "/app/page");
    Console.WriteLine("  held while off: " + Text.FromInteger((long)offHandler.CookieContainer.Count));
    off.Dispose();

    server.StopServing();
    return 0;
}
