// SPDX-License-Identifier: 0BSD
// A peer that opens every window and then stops reading, so that the
// client's writes fill the socket and stay there. It may flood PINGs while
// it is not reading, and it reads again only when the scenario says, noting
// what had got through. It joins Standard.Net.Http for the frame writers.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// The size of the body each scenario tries to send: far more than the
/// socket buffers on either side hold.
internal const nuint Http2StallBodyLength = 67108864u;

/// What the peer and the requests saw, for the scenario to print.
internal sealed class Http2StallRecord
{
    internal AtomicBool Drain = new AtomicBool(false);
    internal AtomicBool Sent = new AtomicBool(false);
    internal AtomicBool SecondSent = new AtomicBool(false);
    internal String Outcome = "";
    internal long Elapsed = 0;
    internal String SecondOutcome = "";
    internal long SecondElapsed = 0;
    internal nuint Acks = 0u;
    internal nuint DataBytes = 0u;
    internal String GoAway = "none";

    internal Http2StallRecord() { }
}

/// Serves one connection: SETTINGS with every window open, then nothing
/// read until `record.Drain`, with `pings` PINGs sent meanwhile.
internal void PlayHttp2StalledPeer(TcpListener listener, nuint pings, Http2StallRecord record)
{
    if (!listener.Pending(5000))
        return;
    TcpClient client = listener.Accept();
    client.Underlying.SetReceiveTimeout(10000);
    client.Underlying.SetSendTimeout(10000);
    var frames = new Http2FrameReader(new HttpBufferedReader(client, 65536u));
    var preface = new byte[24u];
    if (frames.ReadAllHttp2Bytes(preface, 24u) != 24u)
    {
        client.Close();
        return;
    }
    var opening = new Http2Buffer(64u);
    var settings = new List<uint>();
    settings.Add((uint)Http2Setting.InitialWindowSize);
    settings.Add((uint)Http2MaxWindowSize);
    WriteHttp2Settings(opening, settings);
    WriteHttp2SettingsAck(opening);
    WriteHttp2WindowUpdate(opening, 0u, (uint)(Http2MaxWindowSize - Http2DefaultWindowSize));
    WriteAllHttpBytes(client, opening.Storage, 0u, opening.Length);

    if (pings > 0u)
    {
        Sleep(300u);
        var flood = new Http2Buffer(pings * 17u + 16u);
        var opaque = "pingpong".ToBytes();
        for (nuint i = 0u; i < pings; i++)
            WriteHttp2Ping(flood, opaque, false);
        WriteAllHttpBytes(client, flood.Storage, 0u, flood.Length);
    }

    while (!record.Drain.Read())
        Sleep(20u);

    while (true)
    {
        Http2ReadStatus status = frames.ReadHttp2Frame(Http2MaxAllowedFrameSize, out Http2Frame? read);
        if (status != Http2ReadStatus.Frame)
            break;
        var frame = (Http2Frame)read;
        if (frame.Type == Http2FrameType.Ping && frame.HasFlag(Http2FlagAck))
            record.Acks++;
        if (frame.Type == Http2FrameType.Data)
            record.DataBytes += frame.Length;
        if (frame.Type == Http2FrameType.GoAway)
        {
            record.GoAway = DescribeHttp2ErrorCode(frame.ReadHttp2Word(4u));
            break;
        }
        if (frame.Type == Http2FrameType.RstStream)
            break;
    }
    client.Close();
}

internal HttpRequestMessage CreateHttp2StallRequest(HttpMethod method, String uri)
{
    var request = new HttpRequestMessage(method, uri);
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    return request;
}

internal String DescribeHttp2StallOutcome(Result<HttpResponseMessage, HttpError> sent, HttpFailure failure)
{
    if (sent.Ok)
        return Text.FromInteger((long)(int)sent.Value.StatusCode);
    String outcome = $"{sent.Error}";
    if (failure.ProtocolErrorCode != 0)
        outcome += " " + DescribeHttp2ErrorCode((uint)failure.ProtocolErrorCode);
    return outcome + " (" + failure.Message + ")";
}

internal void SendHttp2StalledPost(HttpClient client, String uri, Http2StallRecord record)
{
    var request = CreateHttp2StallRequest(HttpMethod.Post, uri);
    request.Content = new ByteArrayContent(new byte[Http2StallBodyLength]);
    var watch = new Stopwatch();
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    record.Elapsed = watch.Elapsed.Nanoseconds / 1000000;
    record.Outcome = DescribeHttp2StallOutcome(sent, failure);
    record.Sent.Write(true);
}

internal void SendHttp2SecondGet(HttpClientHandler handler, String uri, Http2StallRecord record)
{
    var second = new HttpClient(handler, false);
    second.Timeout = TimeSpan.FromMilliseconds(300);
    var watch = new Stopwatch();
    var sent = second.Send(CreateHttp2StallRequest(HttpMethod.Get, uri),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    record.SecondElapsed = watch.Elapsed.Nanoseconds / 1000000;
    record.SecondOutcome = DescribeHttp2StallOutcome(sent, failure);
    second.Dispose();
    record.SecondSent.Write(true);
}

/// Runs one scenario and says how both ends took it.
///
/// - "stalled": a POST whose body cannot all be written times out on time,
///   and the rest of the body is never sent.
/// - "second": a GET sent while that POST holds the connection's write turn
///   times out on its own deadline rather than the POST's.
/// - "flood": PINGs sent while the client cannot write end the connection
///   with ENHANCE_YOUR_CALM rather than queueing an answer to each.
public String RunHttp2StallScenario(String scenario)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return "no listener";
    TcpListener listener = listening.Value;
    var record = new Http2StallRecord();
    nuint pings = scenario == "flood" ? 5000u : 0u;
    var peer = new Thread(() => PlayHttp2StalledPeer(listener, pings, record));

    var handler = new HttpClientHandler();
    var first = new HttpClient(handler, false);
    first.Timeout = TimeSpan.FromMilliseconds(scenario == "stalled" ? 800 : 1500);
    String uri = "http://127.0.0.1:" + Text.FromInteger((long)listener.LocalEndPoint.Port) + "/";
    var sender = new Thread(() => SendHttp2StalledPost(first, uri, record));

    Thread? getter = null;
    if (scenario == "second")
    {
        Sleep(300u);
        getter = new Thread(() => SendHttp2SecondGet(handler, uri, record));
    }
    else
    {
        record.SecondSent.Write(true);
    }

    // A client that hangs is let go after a while, so that the case ends.
    for (int waited = 0; waited < 3000 && !(record.Sent.Read() && record.SecondSent.Read()); waited += 20)
        Sleep(20u);
    bool returned = record.Sent.Read() && record.SecondSent.Read();
    record.Drain.Write(true);
    sender.Join();
    if (getter is Thread thread)
        thread.Join();
    first.Dispose();
    handler.Dispose();
    peer.Join();
    listener.Close();

    String result = "returned before the peer read again: " + Text.FromBool(returned);
    switch (scenario)
    {
        case "stalled":
            result += "; " + record.Outcome + ", within 2 s: " + Text.FromBool(record.Elapsed < 2000) +
                      "\n    the whole body reached the peer: " +
                      Text.FromBool(record.DataBytes >= Http2StallBodyLength);
            break;
        case "second":
            result += "\n    the GET: " + record.SecondOutcome + ", within 1 s: " +
                      Text.FromBool(record.SecondElapsed < 1000);
            break;
        case "flood":
            result += "; " + record.Outcome + "\n    PING acks the peer read, at most 1000: " +
                      Text.FromBool(record.Acks <= 1000u);
            break;
    }
    return result;
}
