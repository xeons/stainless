// SPDX-License-Identifier: 0BSD
// A peer whose SETTINGS change HEADER_TABLE_SIZE, perhaps more than once
// between the client's first request and its second, and which notes the
// dynamic table size updates the second request's header block begins with. It joins
// Standard.Net.Http for the frame writers and HPACK.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// What the peer saw, for the scenario to print once it has finished.
internal sealed class Http2TableRecord
{
    internal List<String> Updates = new List<String>();
    internal String Decoded = "no request";

    internal Http2TableRecord() { }
}

/// The size updates at the start of `block`, each an integer with a 5-bit
/// prefix (RFC 7541 section 6.3).
internal void ReadHttp2TableUpdates(byte[] block, nuint length, List<String> updates)
{
    nuint at = 0u;
    while (at < length && ((uint)block[at] & 0xE0u) == 0x20u)
    {
        ulong value = (ulong)((uint)block[at] & 0x1Fu);
        at++;
        if (value == 31u)
        {
            uint shift = 0u;
            while (at < length)
            {
                uint octet = (uint)block[at];
                at++;
                value += (ulong)(octet & 0x7Fu) << shift;
                shift += 7u;
                if ((octet & 0x80u) == 0u)
                    break;
            }
        }
        updates.Add(Text.FromInteger((long)value));
    }
}

/// Answers the request on `streamId` with a bare 204.
internal void AnswerHttp2TableRequest(TcpClient client, uint streamId)
{
    var block = new Http2Buffer(64u);
    new HpackEncoder(HpackDefaultTableSize).EncodeHpackLiteral(block, ":status", "204",
                                                             HpackIndexing.WithoutIndexing);
    var output = new Http2Buffer(64u);
    WriteHttp2HeaderBlock(output, streamId, block, true, Http2DefaultMaxFrameSize);
    WriteAllHttpBytes(client, output.Storage, 0u, output.Length);
}

/// Serves one connection of two requests. Once the first arrives it sends one
/// SETTINGS frame per entry of `frames`, each a list of HEADER_TABLE_SIZE
/// values, and answers only when every one is acknowledged: the client has
/// then applied them all, so the second request's block MUST reflect them.
/// Without the wait, a client that sends as soon as it has read one frame
/// would be right to begin with that frame's size alone.
internal void PlayHttp2TablePeer(TcpListener listener, List<List<uint>> frames, Http2TableRecord record)
{
    if (!listener.Pending(5000))
        return;
    TcpClient client = listener.Accept();
    client.Underlying.SetReceiveTimeout(5000);
    var reader = new Http2FrameReader(new HttpBufferedReader(client, 65536u));
    var preface = new byte[24u];
    if (reader.ReadAllHttp2Bytes(preface, 24u) != 24u)
    {
        client.Close();
        return;
    }
    var opening = new Http2Buffer(64u);
    WriteHttp2Settings(opening, new List<uint>());
    WriteHttp2SettingsAck(opening);
    WriteAllHttpBytes(client, opening.Storage, 0u, opening.Length);

    // The opening SETTINGS is acknowledged too.
    nuint acksWanted = frames.Count + 1u;
    nuint acks = 0u;
    nuint requests = 0u;
    uint firstStream = 0u;
    bool firstAnswered = false;
    var decoder = new HpackDecoder(HpackDefaultTableSize, 65536u);
    while (true)
    {
        Http2ReadStatus status = reader.ReadHttp2Frame(Http2MaxAllowedFrameSize, out Http2Frame? read);
        if (status != Http2ReadStatus.Frame)
            break;
        var frame = (Http2Frame)read;
        if (frame.Type == Http2FrameType.Settings && frame.HasFlag(Http2FlagAck))
            acks++;
        if (frame.Type == Http2FrameType.Headers)
        {
            requests++;
            var fields = new List<HpackField>();
            if (requests == 2u)
                ReadHttp2TableUpdates(frame.Payload, frame.Length, record.Updates);
            HpackStatus decoded = decoder.DecodeHpackHeaderBlock(frame.Payload, 0u, frame.Length, fields);
            if (requests == 2u || decoded != HpackStatus.Decoded)
                record.Decoded = $"{decoded}";
            if (requests == 1u)
            {
                firstStream = frame.StreamId;
                var changes = new Http2Buffer(64u);
                foreach (var sizes in frames)
                {
                    var settings = new List<uint>();
                    foreach (var size in sizes)
                    {
                        settings.Add((uint)Http2Setting.HeaderTableSize);
                        settings.Add(size);
                    }
                    WriteHttp2Settings(changes, settings);
                }
                WriteAllHttpBytes(client, changes.Storage, 0u, changes.Length);
            }
            else
            {
                AnswerHttp2TableRequest(client, frame.StreamId);
            }
        }
        if (requests >= 1u && !firstAnswered && acks >= acksWanted)
        {
            AnswerHttp2TableRequest(client, firstStream);
            firstAnswered = true;
        }
        if (frame.Type == Http2FrameType.GoAway)
            break;
    }
    client.Close();
}

/// Sends one HTTP/2 GET for `uri` and gives back its status, or its error.
internal String SendHttp2TableRequest(HttpClient client, String uri)
{
    var request = new HttpRequestMessage(HttpMethod.Get, uri);
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    return sent.Ok ? Text.FromInteger((long)(int)sent.Value.StatusCode) : $"{sent.Error}";
}

/// Runs two requests on one connection against a peer that sends `frames`
/// between them, and says how the second request's header block began.
public String RunHttp2TableScenario(List<List<uint>> frames)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return "no listener";
    TcpListener listener = listening.Value;
    var record = new Http2TableRecord();
    var peer = new Thread(() => PlayHttp2TablePeer(listener, frames, record));
    var client = new HttpClient(new HttpClientHandler());
    client.Timeout = TimeSpan.FromSeconds(3);
    String uri = "http://127.0.0.1:" + Text.FromInteger((long)listener.LocalEndPoint.Port) + "/";
    String first = SendHttp2TableRequest(client, uri);
    String outcome = first == "204" ? SendHttp2TableRequest(client, uri) : "first: " + first;
    client.Dispose();
    peer.Join();
    listener.Close();
    String updates = record.Updates.IsEmpty ? "none" : ", ".Join(record.Updates.ToArray());
    return outcome + "; size updates: " + updates + "; the peer decoded it: " + record.Decoded;
}
