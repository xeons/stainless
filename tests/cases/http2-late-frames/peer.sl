// SPDX-License-Identifier: 0BSD
// A peer that answers the first requests with a head and no body, which the
// client resets, and then sends DATA and HEADERS on the first of those
// streams long after its reset before answering the last request. Its
// header blocks share one HPACK table, so a late block the client skipped
// would leave the last answer undecodable. It joins Standard.Net.Http for
// the frame writers and HPACK.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// What the peer saw, for the scenario to print once it has finished.
internal sealed class Http2LateRecord
{
    internal nuint Resets = 0u;
    internal String GoAway = "none";

    internal Http2LateRecord() { }
}

internal Http2Buffer EncodeHttp2LateBlock(HpackEncoder encoder, String status, bool late)
{
    var block = new Http2Buffer(64u);
    encoder.EncodeHpackField(block, ":status", status);
    if (late)
        encoder.EncodeHpackField(block, "x-late", "yes");
    return block;
}

internal void PlayHttp2LatePeer(TcpListener listener, nuint abandoned, Http2LateRecord record)
{
    if (!listener.Pending(5000))
        return;
    TcpClient client = listener.Accept();
    client.Underlying.SetReceiveTimeout(10000);
    var frames = new Http2FrameReader(new HttpBufferedReader(client, 65536u));
    var preface = new byte[24u];
    if (frames.ReadAllHttp2Bytes(preface, 24u) != 24u)
    {
        client.Close();
        return;
    }
    var opening = new Http2Buffer(64u);
    WriteHttp2Settings(opening, new List<uint>());
    WriteHttp2SettingsAck(opening);
    WriteAllHttpBytes(client, opening.Storage, 0u, opening.Length);

    var encoder = new HpackEncoder(HpackDefaultTableSize);
    nuint requests = 0u;
    while (true)
    {
        Http2ReadStatus status = frames.ReadHttp2Frame(Http2MaxAllowedFrameSize, out Http2Frame? read);
        if (status != Http2ReadStatus.Frame)
            break;
        var frame = (Http2Frame)read;
        switch (frame.Type)
        {
            case Http2FrameType.Headers:
            {
                requests++;
                var output = new Http2Buffer(128u);
                if (requests <= abandoned)
                {
                    WriteHttp2HeaderBlock(output, frame.StreamId, EncodeHttp2LateBlock(encoder, "200", false),
                                          false, Http2DefaultMaxFrameSize);
                }
                else
                {
                    var late = "late".ToBytes();
                    WriteHttp2Data(output, 1u, late, 0u, late.Length, false);
                    WriteHttp2HeaderBlock(output, 1u, EncodeHttp2LateBlock(encoder, "200", true), true,
                                          Http2DefaultMaxFrameSize);
                    WriteHttp2HeaderBlock(output, frame.StreamId, EncodeHttp2LateBlock(encoder, "204", true),
                                          true, Http2DefaultMaxFrameSize);
                }
                WriteAllHttpBytes(client, output.Storage, 0u, output.Length);
                break;
            }
            case Http2FrameType.RstStream:
                record.Resets++;
                break;
            case Http2FrameType.GoAway:
                record.GoAway = DescribeHttp2ErrorCode(frame.ReadHttp2Word(4u));
                break;
        }
    }
    client.Close();
}

internal HttpRequestMessage CreateHttp2LateRequest(String uri)
{
    var request = new HttpRequestMessage(HttpMethod.Get, uri);
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    return request;
}

/// Abandons `abandoned` responses, each reset by the client, then sends one
/// more request, ahead of whose answer come frames on the first stream.
public String RunHttp2LateScenario(nuint abandoned)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return "no listener";
    TcpListener listener = listening.Value;
    var record = new Http2LateRecord();
    var peer = new Thread(() => PlayHttp2LatePeer(listener, abandoned, record));
    var client = new HttpClient(new HttpClientHandler());
    client.Timeout = TimeSpan.FromSeconds(5);
    String uri = "http://127.0.0.1:" + Text.FromInteger((long)listener.LocalEndPoint.Port) + "/";

    nuint reset = 0u;
    for (nuint i = 0u; i < abandoned; i++)
    {
        var sent = client.Send(CreateHttp2LateRequest(uri), HttpCompletionOption.ResponseHeadersRead,
                               out HttpFailure failure);
        if (sent.Ok)
        {
            sent.Value.Dispose();
            reset++;
        }
    }
    var answered = client.Send(CreateHttp2LateRequest(uri), HttpCompletionOption.ResponseContentRead,
                               out HttpFailure lastFailure);
    String outcome = "";
    if (answered.Ok)
    {
        HttpResponseMessage response = answered.Value;
        outcome = Text.FromInteger((long)(int)response.StatusCode) + ", x-late: " +
                  ", ".Join(response.Headers.GetValues("x-late"));
    }
    else
    {
        outcome = $"{answered.Error}";
        if (lastFailure.ProtocolErrorCode != 0)
            outcome += " " + DescribeHttp2ErrorCode((uint)lastFailure.ProtocolErrorCode);
        outcome += " (" + lastFailure.Message + ")";
    }
    client.Dispose();
    peer.Join();
    listener.Close();
    return Text.FromInteger((long)reset) + " abandoned; then " + outcome + "\n    the peer saw: " +
           Text.FromInteger((long)record.Resets) + " RST_STREAM; GOAWAY " + record.GoAway;
}
