// SPDX-License-Identifier: 0BSD
module X509Case;

import Standard.Security.Cryptography.X509Certificates;

void CheckHostname(X509Certificate2 certificate, String host, bool want)
{
    bool got = certificate.MatchesHostname(host);
    Check($"host '{host}' {(want ? "matches" : "refused")}", got == want);
}

void MatchHostnames()
{
    // DNS:www.example.com, DNS:example.com; the common name is www.example.com.
    X509Certificate2 good = LoadFixture("good", GoodPem);
    CheckHostname(good, "www.example.com", true);
    CheckHostname(good, "example.com", true);
    CheckHostname(good, "WWW.Example.COM", true);
    CheckHostname(good, "www.example.com.", true);
    CheckHostname(good, "other.example.com", false);
    CheckHostname(good, "www.example.com.evil", false);
    CheckHostname(good, "wwww.example.com", false);
    CheckHostname(good, "", false);
    CheckHostname(good, ".", false);
    CheckHostname(good, "www..example.com", false);
    CheckHostname(good, "*.example.com", false);
    CheckHostname(good, "www.example.com..", false);

    // DNS:*.example.com, DNS:*.a.example.com.
    X509Certificate2 wildcard = LoadFixture("wildcard", WildcardPem);
    CheckHostname(wildcard, "foo.example.com", true);
    CheckHostname(wildcard, "FOO.EXAMPLE.COM.", true);
    CheckHostname(wildcard, "b.a.example.com", true);
    CheckHostname(wildcard, "example.com", false);
    CheckHostname(wildcard, "a.b.example.com", false);
    CheckHostname(wildcard, ".example.com", false);
    CheckHostname(wildcard, "*.example.com", false);
    Check("host wildcard refused when wildcards are not allowed",
          !wildcard.MatchesHostname("foo.example.com", false));

    // IP:192.0.2.1, IP:2001:db8::1, DNS:ip.example.com; the common name is 192.0.2.1.
    X509Certificate2 ip = LoadFixture("ip", IpPem);
    CheckHostname(ip, "192.0.2.1", true);
    CheckHostname(ip, "2001:db8::1", true);
    CheckHostname(ip, "[2001:db8::1]", true);
    CheckHostname(ip, "2001:DB8:0:0:0:0:0:1", true);
    CheckHostname(ip, "2001:0db8::0:1", true);
    CheckHostname(ip, "ip.example.com", true);
    CheckHostname(ip, "192.0.2.2", false);
    CheckHostname(ip, "192.0.2.01", false);
    CheckHostname(ip, "192.0.2", false);
    CheckHostname(ip, "192.0.2.1.", false);
    CheckHostname(ip, "::ffff:192.0.2.1", false);
    CheckHostname(ip, "2001:db8::1::", false);
    CheckHostname(ip, "2001:db8:::1", false);
    CheckHostname(ip, "[2001:db8::1", false);

    // A DNS name that spells an address does not match an address entry.
    X509Certificate2 constrained = LoadFixture("ncip", NcIpPem);
    CheckHostname(constrained, "198.51.100.7", true);
    CheckHostname(constrained, "198.51.100.8", false);

    // No DNS name at all: the common name is never consulted.
    X509Certificate2 root = LoadFixture("root", RootPem);
    CheckHostname(root, "Stainless Test Root", false);
}
