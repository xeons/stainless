// SPDX-License-Identifier: 0BSD
// A peer that speaks HTTP/2 wrongly on purpose, one way per scenario, and
// notes the GOAWAY or RST_STREAM the client answers with. It joins
// Standard.Net.Http for the frame writers and HPACK.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// What the peer saw, for the scenario to print once it has finished.
internal sealed class Http2ScriptRecord
{
    internal List<String> Seen = new List<String>();

    internal Http2ScriptRecord() { }
}

/// The frames that end a scenario's first exchange: what the peer says in
/// place of the server preface, and what it answers the request with.
internal Http2Buffer CreateHttp2ScriptOpening(String scenario)
{
    var output = new Http2Buffer(64u);
    var settings = new List<uint>();
    switch (scenario)
    {
        case "the first frame is not SETTINGS":
            WriteHttp2Ping(output, "notfirst".ToBytes(), false);
            return output;
        case "SETTINGS of seven octets":
            output.WriteHttp2FrameHeader(7u, Http2FrameType.Settings, 0u, 0u);
            for (int i = 0; i < 7; i++)
                output.WriteByte(0u);
            return output;
        case "SETTINGS with ENABLE_PUSH 1":
            settings.Add((uint)Http2Setting.EnablePush);
            settings.Add(1u);
            break;
    }
    WriteHttp2Settings(output, settings);
    WriteHttp2SettingsAck(output);
    return output;
}

internal Http2Buffer EncodeHttp2ScriptBlock(List<String> fields)
{
    var encoder = new HpackEncoder(HpackDefaultTableSize);
    var block = new Http2Buffer(64u);
    for (nuint i = 0u; i + 1u < fields.Count; i += 2u)
        encoder.EncodeHpackLiteral(block, fields[i], fields[i + 1u], HpackIndexing.WithoutIndexing);
    return block;
}

internal List<String> CreateHttp2ScriptFields(String first, String firstValue, String second, String secondValue)
{
    var fields = new List<String>();
    fields.Add(first);
    fields.Add(firstValue);
    if (!second.IsEmpty)
    {
        fields.Add(second);
        fields.Add(secondValue);
    }
    return fields;
}

internal Http2Buffer CreateHttp2ScriptAnswer(String scenario)
{
    var output = new Http2Buffer(256u);
    switch (scenario)
    {
        case "a frame past SETTINGS_MAX_FRAME_SIZE":
        {
            var large = new byte[20000u];
            WriteHttp2Data(output, 1u, large, 0u, large.Length, true);
            break;
        }
        case "HEADERS interrupted before CONTINUATION":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "", ""));
            output.WriteHttp2FrameHeader(block.Length, Http2FrameType.Headers, 0u, 1u);
            output.WriteArray(block.Storage, 0u, block.Length);
            WriteHttp2Ping(output, "between!".ToBytes(), false);
            break;
        }
        case "PUSH_PROMISE with push disabled":
            output.WriteHttp2FrameHeader(5u, Http2FrameType.PushPromise, Http2FlagEndHeaders, 1u);
            output.WriteUInt32(2u);
            output.WriteByte(0x82u);
            break;
        case "DATA on a stream already ended":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "", ""));
            WriteHttp2HeaderBlock(output, 1u, block, true, Http2DefaultMaxFrameSize);
            var late = "late".ToBytes();
            WriteHttp2Data(output, 1u, late, 0u, late.Length, false);
            break;
        }
        case "DATA past the stream's window":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "", ""));
            WriteHttp2HeaderBlock(output, 1u, block, false, Http2DefaultMaxFrameSize);
            var chunk = new byte[16000u];
            for (int i = 0; i < 5; i++)
                WriteHttp2Data(output, 1u, chunk, 0u, chunk.Length, false);
            break;
        }
        case "a header block HPACK cannot decode":
            output.WriteHttp2FrameHeader(1u, Http2FrameType.Headers, Http2FlagEndHeaders | Http2FlagEndStream, 1u);
            output.WriteByte(0x80u);
            break;
        case "an upper-case field name":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "Content-Type",
                                                                               "text/plain"));
            WriteHttp2HeaderBlock(output, 1u, block, true, Http2DefaultMaxFrameSize);
            break;
        }
        case "a connection-specific field":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "connection",
                                                                               "close"));
            WriteHttp2HeaderBlock(output, 1u, block, true, Http2DefaultMaxFrameSize);
            break;
        }
        case "a response without :status":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields("content-type", "text/plain", "",
                                                                               ""));
            WriteHttp2HeaderBlock(output, 1u, block, true, Http2DefaultMaxFrameSize);
            break;
        }
        case "a body short of its content-length":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "content-length",
                                                                               "10"));
            WriteHttp2HeaderBlock(output, 1u, block, false, Http2DefaultMaxFrameSize);
            var body = "short".ToBytes();
            WriteHttp2Data(output, 1u, body, 0u, body.Length, true);
            break;
        }
        case "a WINDOW_UPDATE of zero":
            WriteHttp2WindowUpdate(output, 0u, 0u);
            break;
        case "HEADERS on a stream the server opened":
        {
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "", ""));
            WriteHttp2HeaderBlock(output, 2u, block, true, Http2DefaultMaxFrameSize);
            break;
        }
        case "RST_STREAM on a stream never opened":
            WriteHttp2RstStream(output, 5u, 0u);
            break;
        case "an unknown frame type, then a response":
        {
            output.WriteHttp2FrameHeader(3u, (Http2FrameType)0x20, 0u, 1u);
            output.WriteByte(1u);
            output.WriteByte(2u);
            output.WriteByte(3u);
            Http2Buffer block = EncodeHttp2ScriptBlock(CreateHttp2ScriptFields(":status", "200", "", ""));
            WriteHttp2HeaderBlock(output, 1u, block, false, Http2DefaultMaxFrameSize);
            var body = "fine".ToBytes();
            WriteHttp2Data(output, 1u, body, 0u, body.Length, true);
            break;
        }
    }
    return output;
}

/// Serves one connection: the preface, the opening, the request's HEADERS,
/// the answer; then notes what comes back until the client closes.
internal void PlayHttp2Script(TcpListener listener, String scenario, Http2ScriptRecord record)
{
    if (!listener.Pending(5000))
    {
        record.Seen.Add("no connection");
        return;
    }
    TcpClient client = listener.Accept();
    client.Underlying.SetReceiveTimeout(5000);
    var frames = new Http2FrameReader(new HttpBufferedReader(client, 65536u));
    var preface = new byte[24u];
    if (frames.ReadAllHttp2Bytes(preface, 24u) != 24u)
    {
        record.Seen.Add("no preface");
        client.Close();
        return;
    }
    Http2Buffer opening = CreateHttp2ScriptOpening(scenario);
    WriteAllHttpBytes(client, opening.Storage, 0u, opening.Length);

    bool answered = false;
    while (true)
    {
        Http2ReadStatus status = frames.ReadHttp2Frame(Http2MaxAllowedFrameSize, out Http2Frame? read);
        if (status != Http2ReadStatus.Frame)
            break;
        var frame = (Http2Frame)read;
        switch (frame.Type)
        {
            case Http2FrameType.Headers:
                if (!answered && frame.HasFlag(Http2FlagEndHeaders))
                {
                    answered = true;
                    Http2Buffer answer = CreateHttp2ScriptAnswer(scenario);
                    WriteAllHttpBytes(client, answer.Storage, 0u, answer.Length);
                }
                break;
            case Http2FrameType.RstStream:
                record.Seen.Add("RST_STREAM on stream " + Text.FromInteger((long)frame.StreamId) + ", " +
                                DescribeHttp2ErrorCode(frame.ReadHttp2Word(0u)));
                break;
            case Http2FrameType.GoAway:
                record.Seen.Add("GOAWAY " + DescribeHttp2ErrorCode(frame.ReadHttp2Word(4u)));
                break;
        }
    }
    client.Close();
}

/// Runs one scenario: a request in h2c with prior knowledge to a peer that
/// misbehaves as the scenario says, and a line saying how both ends took it.
public String RunHttp2RefusalScenario(String scenario)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return "no listener";
    TcpListener listener = listening.Value;
    var record = new Http2ScriptRecord();
    var peer = new Thread(() => PlayHttp2Script(listener, scenario, record));

    var handler = new HttpClientHandler();
    handler.InitialHttp2StreamWindowSize = 65535;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(5);
    var request = new HttpRequestMessage(HttpMethod.Get,
                                         "http://127.0.0.1:" + Text.FromInteger((long)listener.LocalEndPoint.Port) + "/");
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    // The window is only overrun if the body is not read while it arrives,
    // since reading it gives window back.
    bool streamed = scenario == "DATA past the stream's window";
    HttpCompletionOption option = streamed ? HttpCompletionOption.ResponseHeadersRead
                                           : HttpCompletionOption.ResponseContentRead;
    var sent = client.Send(request, option, out HttpFailure failure);
    String outcome = "";
    HttpError error = sent.Ok ? HttpError.None : sent.Error;
    if (sent.Ok)
    {
        HttpResponseMessage response = sent.Value;
        if (streamed)
            Sleep(300u);
        var body = response.Content.ReadAsString();
        if (body.Ok)
            outcome = Text.FromInteger((long)(int)response.StatusCode) + " \"" + body.Value + "\"";
        else
            error = body.Error;
    }
    if (error != HttpError.None)
    {
        outcome = $"{error}";
        if (failure.ProtocolErrorCode != 0)
            outcome += " " + DescribeHttp2ErrorCode((uint)failure.ProtocolErrorCode);
        outcome += " (" + failure.Message + ")";
    }
    client.Dispose();
    peer.Join();
    listener.Close();
    String seen = record.Seen.IsEmpty ? "nothing" : "; ".Join(record.Seen.ToArray());
    return outcome + "\n    the peer saw: " + seen;
}
