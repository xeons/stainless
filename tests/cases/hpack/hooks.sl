// SPDX-License-Identifier: 0BSD
// HPACK is internal to Standard.Net.Http, so this file joins the module to
// drive the encoder and decoder directly.
module Standard.Net.Http;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

internal String FormatTestHex(byte[] data, nuint count)
{
    var text = new StringBuilder();
    for (nuint i = 0u; i < count; i++)
    {
        uint octet = (uint)data[i];
        text.Append("0123456789abcdef".Substring((nuint)(octet >> 4), 1u));
        text.Append("0123456789abcdef".Substring((nuint)(octet & 0xFu), 1u));
    }
    return text.ToText();
}

internal byte[] ParseTestHex(String hex)
{
    var bytes = new byte[hex.ByteLength() / 2u];
    for (nuint i = 0u; i < bytes.Length; i++)
    {
        int high = ParseHttpHexadecimalDigit(hex.GetByteAt(2u * i));
        int low = ParseHttpHexadecimalDigit(hex.GetByteAt(2u * i + 1u));
        bytes[i] = (byte)(high * 16 + low);
    }
    return bytes;
}

internal void ShowTestTable(HpackDynamicTable table)
{
    for (nuint i = 1u; i <= table.Count; i++)
    {
        HpackField entry = table.GetHpackEntry(i);
        Console.WriteLine("    [" + Text.FromInteger((long)i) + "] (s = " + Text.FromInteger((long)entry.Size) +
                          ") " + entry.Name + ": " + entry.Value);
    }
    Console.WriteLine("    size: " + Text.FromInteger((long)table.Size));
}

/// Encodes `fields` with `encoder`, compares with the RFC's bytes, decodes
/// the RFC's bytes with `decoder`, and shows what each table then holds.
internal void CheckTestBlock(String label, HpackEncoder encoder, HpackDecoder decoder, List<String> fields,
                             String expected)
{
    var output = new Http2Buffer(64u);
    encoder.BeginHpackHeaderBlock(output);
    for (nuint i = 0u; i + 1u < fields.Count; i += 2u)
        encoder.EncodeHpackField(output, fields[i], fields[i + 1u]);
    String encoded = FormatTestHex(output.Storage, output.Length);
    Console.WriteLine(label + ": encoded " + (encoded == expected ? "as the RFC" : "differently: " + encoded));

    byte[] block = ParseTestHex(expected);
    var decoded = new List<HpackField>();
    HpackStatus status = decoder.DecodeHpackHeaderBlock(block, 0u, block.Length, decoded);
    Console.WriteLine("  decoded: " + $"{status}");
    bool same = decoded.Count * 2u == fields.Count;
    for (nuint i = 0u; i < decoded.Count; i++)
    {
        Console.WriteLine("    " + decoded[i].Name + ": " + decoded[i].Value);
        if (same && (decoded[i].Name != fields[2u * i] || decoded[i].Value != fields[2u * i + 1u]))
            same = false;
    }
    Console.WriteLine("  the fields encoded: " + Text.FromBool(same));
    Console.WriteLine("  decoder's table:");
    ShowTestTable(decoder.Table);
    bool tablesAgree = encoder.Table.Size == decoder.Table.Size && encoder.Table.Count == decoder.Table.Count;
    Console.WriteLine("  encoder's table agrees: " + Text.FromBool(tablesAgree));
}

internal List<String> CreateTestFields(String joined)
{
    var fields = new List<String>();
    foreach (var line in joined.Split('\n'))
    {
        long colon = line.IndexOf(": ");
        if (colon == 0)
        {
            long second = line.Substring(1u).IndexOf(": ");
            colon = second + 1;
        }
        fields.Add(line.Substring(0u, (nuint)colon));
        fields.Add(line.Substring((nuint)colon + 2u));
    }
    return fields;
}

internal void CheckTestSingle(String label, String expected, HpackIndexing indexing, String name, String value,
                              bool indexed)
{
    var encoder = new HpackEncoder(HpackDefaultTableSize);
    encoder.UsesHuffman = false;
    var output = new Http2Buffer(64u);
    if (indexed)
        encoder.EncodeHpackField(output, name, value);
    else
        encoder.EncodeHpackLiteral(output, name, value, indexing);
    String encoded = FormatTestHex(output.Storage, output.Length);
    Console.WriteLine(label + ": encoded " + (encoded == expected ? "as the RFC" : "differently: " + encoded));

    var decoder = new HpackDecoder(HpackDefaultTableSize, 65536u);
    byte[] block = ParseTestHex(expected);
    var decoded = new List<HpackField>();
    HpackStatus status = decoder.DecodeHpackHeaderBlock(block, 0u, block.Length, decoded);
    Console.WriteLine("  decoded: " + $"{status}" + ", " + decoded[0u].Name + ": " + decoded[0u].Value);
    ShowTestTable(decoder.Table);
}

internal String DecodeTestBlock(String hex, nuint tableLimit, nuint listLimit)
{
    var decoder = new HpackDecoder(tableLimit, listLimit);
    byte[] block = ParseTestHex(hex);
    var decoded = new List<HpackField>();
    HpackStatus status = decoder.DecodeHpackHeaderBlock(block, 0u, block.Length, decoded);
    String shown = $"{status}";
    foreach (var field in decoded)
        shown += ", " + field.Name + ": " + field.Value;
    shown += " (table " + Text.FromInteger((long)decoder.Table.Count) + " entries, max " +
             Text.FromInteger((long)decoder.Table.MaxSize) + ")";
    return shown;
}

internal String EncodeTestHuffman(String text)
{
    var output = new Http2Buffer(16u);
    EncodeHpackHuffman(text, output);
    return FormatTestHex(output.Storage, output.Length);
}

internal String RoundTripTestHuffman(byte[] bytes, nuint count)
{
    String text = count == 0u ? "" : Text.FromBytes(&bytes[0u], count);
    var output = new Http2Buffer(16u);
    EncodeHpackHuffman(text, output);
    if (output.Length != MeasureHpackHuffman(text))
        return "measured wrong";
    if (!DecodeHpackHuffman(output.Storage, 0u, output.Length, out String back))
        return "refused";
    return back == text ? "same" : "different";
}

public void RunHpackCases()
{
    Console.WriteLine("-- C.2 field representations");
    CheckTestSingle("C.2.1", "400a637573746f6d2d6b65790d637573746f6d2d686561646572", HpackIndexing.Incremental,
                    "custom-key", "custom-header", false);
    CheckTestSingle("C.2.2", "040c2f73616d706c652f70617468", HpackIndexing.WithoutIndexing,
                    ":path", "/sample/path", false);
    CheckTestSingle("C.2.3", "100870617373776f726406736563726574", HpackIndexing.NeverIndexed,
                    "password", "secret", false);
    CheckTestSingle("C.2.4", "82", HpackIndexing.Incremental, ":method", "GET", true);

    String first = ":method: GET\n:scheme: http\n:path: /\n:authority: www.example.com";
    String second = first + "\ncache-control: no-cache";
    String third = ":method: GET\n:scheme: https\n:path: /index.html\n:authority: www.example.com\n" +
                   "custom-key: custom-value";

    Console.WriteLine("-- C.3 requests, no Huffman");
    var plainEncoder = new HpackEncoder(HpackDefaultTableSize);
    plainEncoder.UsesHuffman = false;
    var plainDecoder = new HpackDecoder(HpackDefaultTableSize, 65536u);
    CheckTestBlock("C.3.1", plainEncoder, plainDecoder, CreateTestFields(first),
                   "828684410f7777772e6578616d706c652e636f6d");
    CheckTestBlock("C.3.2", plainEncoder, plainDecoder, CreateTestFields(second),
                   "828684be58086e6f2d6361636865");
    CheckTestBlock("C.3.3", plainEncoder, plainDecoder, CreateTestFields(third),
                   "828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565");

    Console.WriteLine("-- C.4 requests, Huffman");
    var encoder = new HpackEncoder(HpackDefaultTableSize);
    var decoder = new HpackDecoder(HpackDefaultTableSize, 65536u);
    CheckTestBlock("C.4.1", encoder, decoder, CreateTestFields(first), "828684418cf1e3c2e5f23a6ba0ab90f4ff");
    CheckTestBlock("C.4.2", encoder, decoder, CreateTestFields(second), "828684be5886a8eb10649cbf");
    CheckTestBlock("C.4.3", encoder, decoder, CreateTestFields(third),
                   "828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf");

    String firstResponse = ":status: 302\ncache-control: private\ndate: Mon, 21 Oct 2013 20:13:21 GMT\n" +
                           "location: https://www.example.com";
    String secondResponse = ":status: 307\ncache-control: private\ndate: Mon, 21 Oct 2013 20:13:21 GMT\n" +
                            "location: https://www.example.com";
    String thirdResponse = ":status: 200\ncache-control: private\ndate: Mon, 21 Oct 2013 20:13:22 GMT\n" +
                           "location: https://www.example.com\ncontent-encoding: gzip\n" +
                           "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1";

    Console.WriteLine("-- C.5 responses, no Huffman, a 256-octet table");
    var plainResponses = new HpackEncoder(256u);
    plainResponses.UsesHuffman = false;
    var plainResponseDecoder = new HpackDecoder(256u, 65536u);
    CheckTestBlock("C.5.1", plainResponses, plainResponseDecoder, CreateTestFields(firstResponse),
                   "4803333032580770726976617465611d4d6f6e2c203231204f637420323031332032303a31333a323120474d54" +
                   "6e1768747470733a2f2f7777772e6578616d706c652e636f6d");
    CheckTestBlock("C.5.2", plainResponses, plainResponseDecoder, CreateTestFields(secondResponse),
                   "4803333037c1c0bf");
    CheckTestBlock("C.5.3", plainResponses, plainResponseDecoder, CreateTestFields(thirdResponse),
                   "88c1611d4d6f6e2c203231204f637420323031332032303a31333a323220474d54c05a04677a69707738666f6f" +
                   "3d4153444a4b48514b425a584f5157454f50495541585157454f49553b206d61782d6167653d333630303b2076" +
                   "657273696f6e3d31");

    Console.WriteLine("-- C.6 responses, Huffman, a 256-octet table");
    var responses = new HpackEncoder(256u);
    var responseDecoder = new HpackDecoder(256u, 65536u);
    CheckTestBlock("C.6.1", responses, responseDecoder, CreateTestFields(firstResponse),
                   "488264025885aec3771a4b6196d07abe941054d444a8200595040b8166e082a62d1bff6e919d29ad171863c78f" +
                   "0b97c8e9ae82ae43d3");
    CheckTestBlock("C.6.2", responses, responseDecoder, CreateTestFields(secondResponse), "4883640effc1c0bf");
    CheckTestBlock("C.6.3", responses, responseDecoder, CreateTestFields(thirdResponse),
                   "88c16196d07abe941054d444a8200595040b8166e084a62d1bffc05a839bd9ab77ad94e7821dd7f2e6c7b335df" +
                   "dfcd5b3960d5af27087f3672c1ab270fb5291f9587316065c003ed4ee5b1063d5007");

    Console.WriteLine("-- Huffman");
    nuint same = 0u;
    var single = new byte[1u];
    for (nuint value = 0u; value < 256u; value++)
    {
        single[0u] = (byte)value;
        if (RoundTripTestHuffman(single, 1u) == "same")
            same++;
    }
    Console.WriteLine("each of 256 byte values alone: " + Text.FromInteger((long)same) + " round trips");
    var every = new byte[512u];
    for (nuint i = 0u; i < every.Length; i++)
        every[i] = (byte)(i % 256u);
    Console.WriteLine("all 256 twice over in one string: " + RoundTripTestHuffman(every, every.Length));
    Console.WriteLine("the empty string: " + RoundTripTestHuffman(every, 0u));
    Console.WriteLine("\"a\" is " + EncodeTestHuffman("a") + ", \"www.example.com\" is " +
                      EncodeTestHuffman("www.example.com"));

    Console.WriteLine("-- the decoder refuses");
    Console.WriteLine("index 0: " + DecodeTestBlock("80", 4096u, 65536u));
    Console.WriteLine("an index past both tables: " + DecodeTestBlock("be", 4096u, 65536u));
    Console.WriteLine("a name index past both tables: " + DecodeTestBlock("7f000161", 4096u, 65536u));
    Console.WriteLine("a size update past the limit: " + DecodeTestBlock("3fe13f", 4096u, 65536u));
    Console.WriteLine("a size update after a field: " + DecodeTestBlock("8220", 4096u, 65536u));
    Console.WriteLine("an integer past 2^32: " + DecodeTestBlock("ffffffffffff7f", 4096u, 65536u));
    Console.WriteLine("an integer cut off: " + DecodeTestBlock("ff80", 4096u, 65536u));
    Console.WriteLine("a string past the block: " + DecodeTestBlock("40056162", 4096u, 65536u));
    Console.WriteLine("Huffman holding EOS: " + DecodeTestBlock("00016184ffffffff", 4096u, 65536u));
    Console.WriteLine("Huffman padded past 7 bits: " + DecodeTestBlock("000161821fff", 4096u, 65536u));
    Console.WriteLine("Huffman padded with zeros: " + DecodeTestBlock("000161" + "8118", 4096u, 65536u));
    Console.WriteLine("Huffman padded rightly: " + DecodeTestBlock("000161" + "811f", 4096u, 65536u));

    Console.WriteLine("-- limits");
    Console.WriteLine("a list over 70 octets: " +
                      DecodeTestBlock("400161016240016301644001650166", 4096u, 70u));
    Console.WriteLine("a size update to 0 then 256: " + DecodeTestBlock("203fe10182", 4096u, 65536u));

    Console.WriteLine("-- the encoder");
    var secrets = new HpackEncoder(HpackDefaultTableSize);
    secrets.UsesHuffman = false;
    var output = new Http2Buffer(64u);
    secrets.EncodeHpackField(output, "authorization", "Basic c2VjcmV0");
    secrets.EncodeHpackField(output, "cookie", "id=1");
    secrets.EncodeHpackField(output, "proxy-authorization", "Basic eA==");
    secrets.EncodeHpackField(output, "x-plain", "kept");
    Console.WriteLine("secrets never indexed: " + FormatTestHex(output.Storage, output.Length));
    Console.WriteLine("  entries kept: " + Text.FromInteger((long)secrets.Table.Count));

    output.Clear();
    secrets.LimitHpackTableSize(0u);
    secrets.LimitHpackTableSize(8192u);
    secrets.BeginHpackHeaderBlock(output);
    secrets.EncodeHpackField(output, "x-plain", "kept");
    Console.WriteLine("shrunk to 0 and grown to the default: " + FormatTestHex(output.Storage, output.Length));
    var shrinkDecoder = new HpackDecoder(HpackDefaultTableSize, 65536u);
    var decoded = new List<HpackField>();
    HpackStatus shrinkStatus = shrinkDecoder.DecodeHpackHeaderBlock(output.Storage, 0u, output.Length, decoded);
    Console.WriteLine("  decoded: " + $"{shrinkStatus}" + ", table max " +
                      Text.FromInteger((long)shrinkDecoder.Table.MaxSize));

    output.Clear();
    var large = new StringBuilder();
    for (int i = 0; i < 2100; i++)
        large.Append("x");
    secrets.EncodeHpackField(output, "x-large", large.ToText());
    Console.WriteLine("a value past half the table is not indexed: first octet " +
                      FormatTestHex(output.Storage, 1u) + ", entries " +
                      Text.FromInteger((long)secrets.Table.Count));
}
