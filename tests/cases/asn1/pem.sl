// SPDX-License-Identifier: 0BSD
module Asn1Case;

import Standard.Console;
import Standard.Convert;
import Standard.Security.Cryptography;
import Standard.Time;

// certificate.pem is certificate.der as OpenSSL wrote it: LF line ends, 64
// columns and a newline after the END boundary.

[Embed("certificate.pem")]
static readonly byte[] CertificatePem;

String CreateTextFromBytes(byte[] bytes)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes);
    return built.ToText();
}

String DescribeRange(Range range) => $"{range.Start.Value}..{range.End.Value}";

void PemTests()
{
    String file = CreateTextFromBytes(CertificatePem);

    var found = PemEncoding.Find(file);
    if (found is Some block)
    {
        CheckText("pem label", block.Value.Label, "CERTIFICATE");
        Check("pem data is the der", ToHex(block.Value.Data) == ToHex(CertificateDer));
        CheckText(
            "pem location", DescribeRange(block.Value.Location), $"0..{file.ByteLength() - 1u}");
        CheckText("pem label location", DescribeRange(block.Value.LabelLocation), "11..22");
    }
    else
    {
        Check("pem found", false);
    }

    String written = PemEncoding.Write("CERTIFICATE", CertificateDer);
    Check("pem write matches openssl", written + "\n" == file);

    // In other text, with CRLF line ends.
    String crlf = "Subject: a certificate\r\n\r\n" + file.Replace("\n", "\r\n") + "trailer\r\n";
    var surrounded = PemEncoding.Find(crlf);
    if (surrounded is Some inText)
    {
        Check("pem in text", ToHex(inText.Value.Data) == ToHex(CertificateDer));
        CheckNumber("pem in text starts", (long)inText.Value.Location.Start.Value, 26);
    }
    else
    {
        Check("pem in text", false);
    }

    String mismatched = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END PRIVATE KEY-----\n";
    Check("pem refuses mismatched end", PemEncoding.Find(mismatched).IsEmpty);

    // A malformed block is passed over and the whole one after it is found.
    var after = PemEncoding.Find(mismatched + "-----BEGIN X-----\nAQID\n-----END X-----");
    if (after is Some next)
    {
        CheckText("pem after mismatch", $"{next.Value.Label} {ToHex(next.Value.Data)}", "X 010203");
    }
    else
    {
        Check("pem after mismatch", false);
    }

    Check(
        "pem refuses glued begin",
        PemEncoding.Find("x-----BEGIN X-----\nAQID\n-----END X-----").IsEmpty);
    Check(
        "pem refuses glued end",
        PemEncoding.Find("-----BEGIN X-----\nAQID\n-----END X-----x").IsEmpty);
    Check(
        "pem refuses bad base64",
        PemEncoding.Find("-----BEGIN X-----\nAQ*D\n-----END X-----").IsEmpty);
    Check(
        "pem refuses url alphabet",
        PemEncoding.Find("-----BEGIN X-----\nAQ_D\n-----END X-----").IsEmpty);
    Check(
        "pem refuses short group",
        PemEncoding.Find("-----BEGIN X-----\nAQI\n-----END X-----").IsEmpty);
    Check(
        "pem refuses bad label",
        PemEncoding.Find("-----BEGIN A  B-----\nAQID\n-----END A  B-----").IsEmpty);

    // Two blocks, walked with the end of the first.
    String two = PemEncoding.Write("A", Hex("01")) + "\n" + PemEncoding.Write("B", Hex("0203"));
    var first = PemEncoding.Find(two);
    if (first is Some one)
    {
        var second = PemEncoding.Find(two, one.Value.Location.End.Value);
        Check("pem second block", second is Some other && other.Value.Label == "B" &&
              ToHex(other.Value.Data) == "0203");
    }
    else
    {
        Check("pem second block", false);
    }

    String empty = PemEncoding.Write("EMPTY", new byte[0u]);
    CheckText("pem empty", empty.Replace("\n", "|"), "-----BEGIN EMPTY-----|-----END EMPTY-----");
    var emptyFound = PemEncoding.Find(empty);
    Check("pem empty found", emptyFound is Some nothing && nothing.Value.Data.Length == 0u);

    String wrapped = PemEncoding.Write("DATA", new byte[49u]);
    CheckNumber("pem wraps at 64", (long)wrapped.Split("\n").Length, 4);

    Check("label CERTIFICATE", PemEncoding.IsValidLabel("CERTIFICATE"));
    Check("label X509 CRL", PemEncoding.IsValidLabel("X509 CRL"));
    Check("label empty", PemEncoding.IsValidLabel(""));
    Check("label double space", !PemEncoding.IsValidLabel("A  B"));
    Check("label leading hyphen", !PemEncoding.IsValidLabel("-A"));
    Check("label trailing space", !PemEncoding.IsValidLabel("A "));
    PemTimeTests();
}

/// Finding is one forward pass. A bound of a second is some hundred times
/// what either takes, and a small fraction of what a search that rescans
/// the text for each boundary takes.
void PemTimeTests()
{
    var unclosed = new StringBuilder();
    for (nuint i = 0u; i < 16000u; i++)
        unclosed.Append("-----BEGIN A-----\n");
    unclosed.Append("-----END B-----\n");
    String text = unclosed.ToText();
    var watch = new Stopwatch();
    bool none = PemEncoding.Find(text).IsEmpty;
    Check("pem many unclosed boundaries", none && watch.Elapsed.TotalMilliseconds < 1000.0);

    var blocks = new StringBuilder();
    for (nuint i = 0u; i < 20000u; i++)
        blocks.Append("-----BEGIN X-----\nAQID\n-----END X-----\n");
    byte[] utf8 = blocks.ToText().ToBytes();
    watch = new Stopwatch();
    nuint count = 0u;
    nuint at = 0u;
    while (PemEncoding.FindUtf8(utf8, at) is Some block)
    {
        count++;
        at = block.Value.Location.End.Value;
    }
    Check("pem many blocks", count == 20000u && watch.Elapsed.TotalMilliseconds < 1000.0);
}
