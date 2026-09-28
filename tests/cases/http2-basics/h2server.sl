// SPDX-License-Identifier: 0BSD
// An HTTP/2 server for the http2-* cases, over the loopback, in TLS with
// ALPN or in the clear with prior knowledge. It joins Standard.Net.Http to
// reuse the frame reader and HPACK, which are internal there.
//
// Each connection has a reader thread, and each request a thread of its own
// that plays the reply the route chose, so that one stream held open never
// stops another. A connection whose ALPN or first bytes say HTTP/1.1 is
// answered in HTTP/1.1, so that a client falling back can be seen doing it.
// What the server saw is logged for the case to print once it has stopped.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Text;
import Standard.Threading;

/// Decides the reply to one request.
public closure Http2TestReply Http2TestRoute(Http2TestRequest request);

/// Something a reply waits for.
public closure bool Http2TestCondition();

/// What the server's SETTINGS say, and whether it pings.
public sealed class Http2TestSettings
{
    /// Zero sends no limit.
    public uint MaxConcurrentStreams = 0u;
    public uint InitialWindowSize = 65535u;
    public bool SendsPing = false;

    public Http2TestSettings() { }
}

/// A request as the server read it.
public sealed class Http2TestRequest
{
    public String Protocol = "h2";
    public String Method = "";
    public String Scheme = "";
    public String Authority = "";
    public String Path = "";
    public List<String> Fields = new List<String>();
    public List<String> Trailers = new List<String>();
    public byte[] Body = new byte[0u];
    public int Connection = 0;
    public uint Stream = 0u;

    public Http2TestRequest() { }

    /// The first value of `name`, or empty.
    public String GetField(String name)
    {
        String wanted = name.ToLowerAscii() + ": ";
        foreach (var line in Fields)
        {
            if (line.ToLowerAscii().StartsWith(wanted))
                return line.Substring(wanted.ByteLength());
        }
        return "";
    }

    /// How many fields are named `name`.
    public nuint CountField(String name)
    {
        String wanted = name.ToLowerAscii() + ": ";
        nuint count = 0u;
        foreach (var line in Fields)
        {
            if (line.ToLowerAscii().StartsWith(wanted))
                count++;
        }
        return count;
    }

    public String BodyText => Body.Length == 0u ? "" : Text.FromBytes(&Body[0u], Body.Length);
}

/// What the server does in answer.
public sealed class Http2TestReply
{
    internal int Status = 200;
    internal List<String> Fields = new List<String>();
    internal List<String> TrailerFields = new List<String>();
    internal List<int> Interim = new List<int>();
    internal byte[] Body = new byte[0u];
    internal int PauseMilliseconds = 0;
    internal bool HasCondition = false;
    internal Http2TestCondition Condition = () => true;
    internal int ConditionLimit = 0;
    internal bool Resets = false;
    internal uint ResetCode = 0u;
    internal bool GoesAway = false;
    internal uint GoAwayLastStream = 0u;
    internal bool IsSilent = false;

    public Http2TestReply() { }

    public static Http2TestReply CreateText(int status, String body)
    {
        var reply = new Http2TestReply();
        reply.Status = status;
        reply.Body = body.ToBytes();
        reply.Fields.Add("content-type");
        reply.Fields.Add("text/plain");
        return reply;
    }

    public Http2TestReply AddField(String name, String value)
    {
        Fields.Add(name);
        Fields.Add(value);
        return this;
    }

    public Http2TestReply AddTrailer(String name, String value)
    {
        TrailerFields.Add(name);
        TrailerFields.Add(value);
        return this;
    }

    public Http2TestReply AddInterim(int status)
    {
        Interim.Add(status);
        return this;
    }

    public Http2TestReply SetBody(byte[] body)
    {
        Body = body;
        return this;
    }

    public Http2TestReply Pause(int milliseconds)
    {
        PauseMilliseconds = milliseconds;
        return this;
    }

    /// Waits until `condition` holds, or `limit` milliseconds have passed.
    public Http2TestReply WaitUntil(Http2TestCondition condition, int limit)
    {
        HasCondition = true;
        Condition = condition;
        ConditionLimit = limit;
        return this;
    }

    /// RST_STREAM with `code` in place of a reply.
    public Http2TestReply ResetStream(uint code)
    {
        Resets = true;
        ResetCode = code;
        return this;
    }

    /// GOAWAY with `lastStream`, and no reply to this request.
    public Http2TestReply SendGoAway(uint lastStream)
    {
        GoesAway = true;
        GoAwayLastStream = lastStream;
        return this;
    }

    /// No reply at all, until the client resets the stream.
    public Http2TestReply StaySilent()
    {
        IsSilent = true;
        return this;
    }
}

/// What every connection reports into: the log and the counts.
internal sealed class Http2TestRecord
{
    internal Mutex<int> Lock = new Mutex<int>(0);
    internal List<String> Log = new List<String>();
    internal int OpenStreams = 0;
    internal int MostOpenStreams = 0;
    internal int WindowUpdates = 0;
    internal int StreamsSeen = 0;

    internal Http2TestRecord() { }

    internal void NoteHttp2TestEvent(String line)
    {
        var held = Lock.Enter();
        Log.Add(line);
    }

    internal void NoteHttp2StreamOpened()
    {
        var held = Lock.Enter();
        OpenStreams++;
        StreamsSeen++;
        if (OpenStreams > MostOpenStreams)
            MostOpenStreams = OpenStreams;
    }

    internal void NoteHttp2StreamClosed()
    {
        var held = Lock.Enter();
        OpenStreams--;
    }

    internal void NoteHttp2WindowUpdate()
    {
        var held = Lock.Enter();
        WindowUpdates++;
    }
}

/// One stream the server holds.
internal sealed class Http2TestStream
{
    internal Http2TestRequest Request = new Http2TestRequest();
    internal List<byte> Body = new List<byte>();
    internal long SendWindow = 0;
    internal long ReceiveWindow = 0;
    internal bool IsReset = false;
    internal bool IsClosed = false;
    internal bool HasBlocked = false;

    internal Http2TestStream() { }
}

/// One connection the server holds.
internal sealed class Http2TestPeer
{
    internal TcpClient Client;
    internal IStream Stream;
    internal int Number;
    internal Http2TestRoute Route;
    internal Http2TestSettings Settings;
    internal Http2TestRecord Record;
    internal Mutex<int> WriteLock = new Mutex<int>(0);
    internal Monitor<int> State = new Monitor<int>(0);
    internal HpackEncoder Encoder = new HpackEncoder(HpackDefaultTableSize);
    internal HpackDecoder Decoder = new HpackDecoder(HpackDefaultTableSize, 1048576u);
    internal Dictionary<uint, Http2TestStream> Streams = new Dictionary<uint, Http2TestStream>();
    internal long SendWindow = 65535;
    internal long PeerInitialWindow = 65535;
    internal bool Ended = false;
    internal List<Thread> Workers = new List<Thread>();

    internal Http2TestPeer(TcpClient client, IStream stream, int number, Http2TestRoute route,
                           Http2TestSettings settings, Http2TestRecord record)
    {
        Client = client;
        Stream = stream;
        Number = number;
        Route = route;
        Settings = settings;
        Record = record;
    }

    internal String Label => "conn " + Text.FromInteger((long)Number);

    internal bool WriteHttp2TestFrames(Http2Buffer frames)
    {
        var writing = WriteLock.Enter();
        return WriteAllHttpBytes(Stream, frames.Storage, 0u, frames.Length);
    }

    internal void EndHttp2TestPeer()
    {
        var held = State.Enter();
        Ended = true;
        held.PulseAll();
    }
}

/// The server: a listener on the loopback, a thread that accepts, and a
/// thread per connection.
public sealed class Http2TestServer
{
    private TcpListener _listener;
    private Http2TestRoute _route;
    private TlsServerOptions? _tls;
    private Http2TestSettings _settings;
    private Http2TestRecord _record = new Http2TestRecord();
    private AtomicBool _stopping = new AtomicBool(false);
    private AtomicInt _accepts = new AtomicInt(0);
    private Mutex<int> _lock = new Mutex<int>(0);
    private List<Http2TestPeer> _open = new List<Http2TestPeer>();
    private List<Thread> _workers = new List<Thread>();
    private Thread? _acceptor;

    private Http2TestServer(TcpListener listener, Http2TestRoute route, TlsServerOptions? tls,
                            Http2TestSettings settings)
    {
        _listener = listener;
        _route = route;
        _tls = tls;
        _settings = settings;
    }

    /// A server on a port the system chooses, already serving, or null.
    public static Http2TestServer? StartServing(Http2TestRoute route, TlsServerOptions? tls,
                                                Http2TestSettings settings)
    {
        var listening = TcpListener.Listen("127.0.0.1", 0u);
        if (!listening.Ok)
            return null;
        var server = new Http2TestServer(listening.Value, route, tls, settings);
        server._acceptor = new Thread(() => server.AcceptHttp2TestConnections());
        return server;
    }

    public ushort Port => _listener.LocalEndPoint.Port;

    public String Origin => (_tls == null ? "http" : "https") + "://127.0.0.1:" + Text.FromInteger((long)Port);

    public int Accepts => _accepts.Read();

    /// Streams open now.
    public int OpenStreams
    {
        get
        {
            var held = _record.Lock.Enter();
            return _record.OpenStreams;
        }
    }

    /// Streams opened in all.
    public int StreamsSeen
    {
        get
        {
            var held = _record.Lock.Enter();
            return _record.StreamsSeen;
        }
    }

    /// The most streams open at once.
    public int MostOpenStreams
    {
        get
        {
            var held = _record.Lock.Enter();
            return _record.MostOpenStreams;
        }
    }

    /// WINDOW_UPDATE frames received for a stream.
    public int WindowUpdates
    {
        get
        {
            var held = _record.Lock.Enter();
            return _record.WindowUpdates;
        }
    }

    /// Whether a log line holds `text` yet.
    public bool HasLogged(String text)
    {
        var held = _record.Lock.Enter();
        foreach (var line in _record.Log)
        {
            if (line.Contains(text))
                return true;
        }
        return false;
    }

    /// Every event, in order. Read it once the server has stopped.
    public List<String> Log => _record.Log;

    /// Stops serving: ends every connection and waits for every thread.
    public void StopServing()
    {
        _stopping.Write(true);
        if (_acceptor is Thread acceptor)
            acceptor.Join();
        {
            var held = _lock.Enter();
            foreach (var peer in _open)
            {
                peer.Client.Underlying.Shutdown(SocketShutdown.Both);
                peer.EndHttp2TestPeer();
            }
        }
        foreach (var worker in _workers)
            worker.Join();
        _listener.Close();
    }

    private void AcceptHttp2TestConnections()
    {
        int accepted = 0;
        while (!this._stopping.Read())
        {
            if (!this._listener.Pending(10))
                continue;
            TcpClient client = this._listener.Accept();
            accepted++;
            this._accepts.Increment();
            int number = accepted;
            this._workers.Add(new Thread(() => this.ServeHttp2TestConnection(client, number)));
        }
    }

    private void ServeHttp2TestConnection(TcpClient client, int number)
    {
        IStream stream = client;
        String protocol = "";
        if (this._tls is TlsServerOptions options)
        {
            var secured = TlsStream.AuthenticateAsServer(client, options);
            if (!secured.Ok)
            {
                this._record.NoteHttp2TestEvent("conn " + Text.FromInteger((long)number) + ": TLS failed");
                client.Close();
                return;
            }
            TlsStream tls = secured.Value;
            String? agreed = tls.NegotiatedApplicationProtocol;
            protocol = agreed ?? "none";
            stream = tls;
            this._record.NoteHttp2TestEvent("conn " + Text.FromInteger((long)number) + ": ALPN " + protocol);
        }
        var peer = new Http2TestPeer(client, stream, number, this._route, this._settings, this._record);
        {
            var held = this._lock.Enter();
            this._open.Add(peer);
        }
        var reader = new HttpBufferedReader(stream, 65536u);
        if (protocol == "h2")
        {
            ServeHttp2TestPeer(peer, reader);
        }
        else if (protocol.IsEmpty)
        {
            // In the clear: the preface says HTTP/2, anything else HTTP/1.1.
            var first = new byte[24u];
            nuint got = new Http2FrameReader(reader).ReadAllHttp2Bytes(first, 24u);
            if (got == 24u && Text.FromBytes(&first[0u], 24u) == s_http2ClientPreface)
            {
                this._record.NoteHttp2TestEvent(peer.Label + ": h2c");
                ServeHttp2TestFrames(peer, reader);
            }
            else if (got > 0u)
            {
                var prefix = new byte[got];
                for (nuint i = 0u; i < got; i++)
                    prefix[i] = first[i];
                var rest = new HttpPrefixedStream(prefix, new Http2TestReaderStream(reader));
                ServeHttp11TestPeer(peer, new HttpBufferedReader(rest, 65536u));
            }
        }
        else
        {
            ServeHttp11TestPeer(peer, reader);
        }
        peer.EndHttp2TestPeer();
        foreach (var worker in peer.Workers)
            worker.Join();
        stream.Close();
        client.Close();
    }
}

/// What a buffered reader has left, as a stream.
internal sealed class Http2TestReaderStream : IStream
{
    private HttpBufferedReader _reader;

    internal Http2TestReaderStream(HttpBufferedReader reader) => _reader = reader;

    public bool CanRead => true;

    public bool CanWrite => false;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => _reader.ReadHttpBytes(buffer, offset, count);

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close() { }

    public IOError Error => IOError.None;
}

// ------------------------------------------------------------ HTTP/2

internal void ServeHttp2TestPeer(Http2TestPeer peer, HttpBufferedReader reader)
{
    var first = new byte[24u];
    nuint got = new Http2FrameReader(reader).ReadAllHttp2Bytes(first, 24u);
    if (got != 24u || Text.FromBytes(&first[0u], 24u) != s_http2ClientPreface)
    {
        peer.Record.NoteHttp2TestEvent(peer.Label + ": no preface");
        return;
    }
    ServeHttp2TestFrames(peer, reader);
}

/// The reader thread's loop, after the preface.
internal void ServeHttp2TestFrames(Http2TestPeer peer, HttpBufferedReader reader)
{
    var settings = new List<uint>();
    if (peer.Settings.MaxConcurrentStreams != 0u)
    {
        settings.Add((uint)Http2Setting.MaxConcurrentStreams);
        settings.Add(peer.Settings.MaxConcurrentStreams);
    }
    if (peer.Settings.InitialWindowSize != 65535u)
    {
        settings.Add((uint)Http2Setting.InitialWindowSize);
        settings.Add(peer.Settings.InitialWindowSize);
    }
    var opening = new Http2Buffer(64u);
    WriteHttp2Settings(opening, settings);
    if (peer.Settings.SendsPing)
        WriteHttp2Ping(opening, "pingpong".ToBytes(), false);
    peer.WriteHttp2TestFrames(opening);

    var frames = new Http2FrameReader(reader);
    var block = new Http2Buffer(256u);
    uint blockStream = 0u;
    bool blockEnds = false;
    while (true)
    {
        Http2ReadStatus status = frames.ReadHttp2Frame(Http2MaxAllowedFrameSize, out Http2Frame? read);
        if (status != Http2ReadStatus.Frame)
            return;
        var frame = (Http2Frame)read;
        switch (frame.Type)
        {
            case Http2FrameType.Settings:
                if (!frame.HasFlag(Http2FlagAck))
                {
                    ApplyHttp2TestSettings(peer, frame);
                    var ack = new Http2Buffer(16u);
                    WriteHttp2SettingsAck(ack);
                    peer.WriteHttp2TestFrames(ack);
                }
                break;
            case Http2FrameType.WindowUpdate:
                ApplyHttp2TestWindowUpdate(peer, frame);
                break;
            case Http2FrameType.Headers:
            {
                nuint from = 0u;
                nuint length = frame.Length;
                if (frame.HasFlag(Http2FlagPadded))
                {
                    from = 1u;
                    length = length - 1u - (nuint)frame.Payload[0u];
                }
                if (frame.HasFlag(Http2FlagPriority))
                {
                    from += 5u;
                    length -= 5u;
                }
                block.Clear();
                block.WriteArray(frame.Payload, from, length);
                blockStream = frame.StreamId;
                blockEnds = frame.HasFlag(Http2FlagEndStream);
                if (frame.HasFlag(Http2FlagEndHeaders))
                    AcceptHttp2TestHeaders(peer, blockStream, block, blockEnds);
                break;
            }
            case Http2FrameType.Continuation:
                block.WriteArray(frame.Payload, 0u, frame.Length);
                if (frame.HasFlag(Http2FlagEndHeaders))
                    AcceptHttp2TestHeaders(peer, blockStream, block, blockEnds);
                break;
            case Http2FrameType.Data:
                AcceptHttp2TestData(peer, frame);
                break;
            case Http2FrameType.RstStream:
            {
                uint code = frame.ReadHttp2Word(0u);
                peer.Record.NoteHttp2TestEvent(peer.Label + ": RST_STREAM on stream " +
                                               Text.FromInteger((long)frame.StreamId) + ", " +
                                               DescribeHttp2ErrorCode(code));
                var held = peer.State.Enter();
                if (peer.Streams.TryGetValue(frame.StreamId) is Some found)
                    found.Value.IsReset = true;
                held.PulseAll();
                break;
            }
            case Http2FrameType.Ping:
                if (frame.HasFlag(Http2FlagAck))
                {
                    peer.Record.NoteHttp2TestEvent(peer.Label + ": PING answered with \"" +
                                                   Text.FromBytes(&frame.Payload[0u], 8u) + "\"");
                }
                break;
            case Http2FrameType.GoAway:
                peer.Record.NoteHttp2TestEvent(peer.Label + ": GOAWAY, last stream " +
                                               Text.FromInteger((long)frame.ReadHttp2Word(0u)) + ", " +
                                               DescribeHttp2ErrorCode(frame.ReadHttp2Word(4u)));
                break;
        }
    }
}

internal void ApplyHttp2TestSettings(Http2TestPeer peer, Http2Frame frame)
{
    var held = peer.State.Enter();
    for (nuint at = 0u; at + 6u <= frame.Length; at += 6u)
    {
        uint setting = ((uint)frame.Payload[at] << 8) | (uint)frame.Payload[at + 1u];
        uint value = frame.ReadHttp2Word(at + 2u);
        if (setting == (uint)Http2Setting.InitialWindowSize)
        {
            long delta = (long)value - peer.PeerInitialWindow;
            peer.PeerInitialWindow = (long)value;
            foreach (var stream in peer.Streams.GetValues())
                stream.SendWindow += delta;
        }
    }
    held.PulseAll();
}

internal void ApplyHttp2TestWindowUpdate(Http2TestPeer peer, Http2Frame frame)
{
    if (frame.StreamId != 0u)
        peer.Record.NoteHttp2WindowUpdate();
    long increment = (long)(frame.ReadHttp2Word(0u) & Http2MaxStreamId);
    var held = peer.State.Enter();
    if (frame.StreamId == 0u)
        peer.SendWindow += increment;
    else if (peer.Streams.TryGetValue(frame.StreamId) is Some found)
        found.Value.SendWindow += increment;
    held.PulseAll();
}

internal void AcceptHttp2TestHeaders(Http2TestPeer peer, uint id, Http2Buffer block, bool endStream)
{
    var fields = new List<HpackField>();
    peer.Decoder.DecodeHpackHeaderBlock(block.Storage, 0u, block.Length, fields);
    Http2TestStream? existing = null;
    {
        var held = peer.State.Enter();
        if (peer.Streams.TryGetValue(id) is Some found)
            existing = found.Value;
    }
    if (existing is Http2TestStream trailing)
    {
        foreach (var field in fields)
            trailing.Request.Trailers.Add(field.Name + ": " + field.Value);
        if (endStream)
            DispatchHttp2TestRequest(peer, trailing);
        return;
    }

    var stream = new Http2TestStream();
    Http2TestRequest request = stream.Request;
    request.Connection = peer.Number;
    request.Stream = id;
    foreach (var field in fields)
    {
        switch (field.Name)
        {
            case ":method": request.Method = field.Value; break;
            case ":scheme": request.Scheme = field.Value; break;
            case ":authority": request.Authority = field.Value; break;
            case ":path": request.Path = field.Value; break;
            default: request.Fields.Add(field.Name + ": " + field.Value); break;
        }
    }
    {
        var held = peer.State.Enter();
        stream.SendWindow = peer.PeerInitialWindow;
        stream.ReceiveWindow = (long)peer.Settings.InitialWindowSize;
        peer.Streams.SetValue(id, stream);
    }
    peer.Record.NoteHttp2StreamOpened();
    peer.Record.NoteHttp2TestEvent(peer.Label + ": stream " + Text.FromInteger((long)id) + " " +
                                   request.Method + " " + request.Path);
    if (endStream)
        DispatchHttp2TestRequest(peer, stream);
}

internal void AcceptHttp2TestData(Http2TestPeer peer, Http2Frame frame)
{
    Http2TestStream? found = null;
    bool overrun = false;
    {
        var held = peer.State.Enter();
        if (peer.Streams.TryGetValue(frame.StreamId) is Some known)
        {
            found = known.Value;
            known.Value.ReceiveWindow -= (long)frame.Length;
            overrun = known.Value.ReceiveWindow < 0;
        }
    }
    if (found is not Http2TestStream stream)
        return;
    if (overrun)
    {
        peer.Record.NoteHttp2TestEvent(peer.Label + ": stream " + Text.FromInteger((long)frame.StreamId) +
                                       " sent past its window");
    }
    nuint from = 0u;
    nuint length = frame.Length;
    if (frame.HasFlag(Http2FlagPadded))
    {
        from = 1u;
        length = length - 1u - (nuint)frame.Payload[0u];
    }
    for (nuint i = 0u; i < length; i++)
        stream.Body.Add(frame.Payload[from + i]);
    bool ends = frame.HasFlag(Http2FlagEndStream);
    if (frame.Length > 0u && !ends)
    {
        var update = new Http2Buffer(32u);
        WriteHttp2WindowUpdate(update, frame.StreamId, (uint)frame.Length);
        WriteHttp2WindowUpdate(update, 0u, (uint)frame.Length);
        {
            var held = peer.State.Enter();
            stream.ReceiveWindow += (long)frame.Length;
        }
        peer.WriteHttp2TestFrames(update);
    }
    else if (frame.Length > 0u)
    {
        var update = new Http2Buffer(16u);
        WriteHttp2WindowUpdate(update, 0u, (uint)frame.Length);
        peer.WriteHttp2TestFrames(update);
    }
    if (ends)
        DispatchHttp2TestRequest(peer, stream);
}

internal void DispatchHttp2TestRequest(Http2TestPeer peer, Http2TestStream stream)
{
    stream.Request.Body = stream.Body.ToArray();
    peer.Workers.Add(new Thread(() => RespondToHttp2TestRequest(peer, stream)));
}

/// Plays the reply the route chose, on a thread of its own.
internal void RespondToHttp2TestRequest(Http2TestPeer peer, Http2TestStream stream)
{
    Http2TestReply reply = peer.Route(stream.Request);
    uint id = stream.Request.Stream;
    if (reply.GoesAway)
    {
        var goAway = new Http2Buffer(32u);
        WriteHttp2GoAway(goAway, reply.GoAwayLastStream, 0u, "");
        peer.WriteHttp2TestFrames(goAway);
        peer.Record.NoteHttp2TestEvent(peer.Label + ": sent GOAWAY, last stream " +
                                       Text.FromInteger((long)reply.GoAwayLastStream));
        CloseHttp2TestStream(peer, stream);
        return;
    }
    if (reply.Resets)
    {
        var reset = new Http2Buffer(16u);
        WriteHttp2RstStream(reset, id, reply.ResetCode);
        peer.WriteHttp2TestFrames(reset);
        CloseHttp2TestStream(peer, stream);
        return;
    }
    if (reply.PauseMilliseconds > 0)
        Sleep((ulong)reply.PauseMilliseconds);
    if (reply.HasCondition)
    {
        for (int waited = 0; waited < reply.ConditionLimit && !reply.Condition(); waited += 5)
        {
            if (IsHttp2TestStreamGone(peer, stream))
                break;
            Sleep(5u);
        }
    }
    if (reply.IsSilent)
    {
        for (int waited = 0; waited < 10000 && !IsHttp2TestStreamGone(peer, stream); waited += 5)
            Sleep(5u);
        CloseHttp2TestStream(peer, stream);
        return;
    }

    foreach (var interim in reply.Interim)
    {
        var fields = new List<String>();
        fields.Add(":status");
        fields.Add(Text.FromInteger((long)interim));
        WriteHttp2TestHeaders(peer, id, fields, false);
    }
    var head = new List<String>();
    head.Add(":status");
    head.Add(Text.FromInteger((long)reply.Status));
    foreach (var field in reply.Fields)
        head.Add(field);
    if (reply.Body.Length > 0u)
    {
        head.Add("content-length");
        head.Add(Text.FromInteger((long)reply.Body.Length));
    }
    bool hasBody = reply.Body.Length > 0u && stream.Request.Method != "HEAD";
    bool hasTrailers = !reply.TrailerFields.IsEmpty;
    // A stream is counted closed before its last frame goes, so that the
    // client's next stream can never be counted beside it.
    if (!hasBody && !hasTrailers)
        CloseHttp2TestStream(peer, stream);
    WriteHttp2TestHeaders(peer, id, head, !hasBody && !hasTrailers);
    if (hasBody && !SendHttp2TestBody(peer, stream, reply.Body, !hasTrailers))
    {
        CloseHttp2TestStream(peer, stream);
        return;
    }
    if (hasTrailers)
    {
        CloseHttp2TestStream(peer, stream);
        WriteHttp2TestHeaders(peer, id, reply.TrailerFields, true);
    }
    CloseHttp2TestStream(peer, stream);
}

internal bool IsHttp2TestStreamGone(Http2TestPeer peer, Http2TestStream stream)
{
    var held = peer.State.Enter();
    return stream.IsReset || peer.Ended;
}

internal void CloseHttp2TestStream(Http2TestPeer peer, Http2TestStream stream)
{
    {
        var held = peer.State.Enter();
        if (stream.IsClosed)
            return;
        stream.IsClosed = true;
    }
    peer.Record.NoteHttp2StreamClosed();
}

internal void WriteHttp2TestHeaders(Http2TestPeer peer, uint id, List<String> fields, bool endStream)
{
    var writing = peer.WriteLock.Enter();
    var block = new Http2Buffer(128u);
    peer.Encoder.BeginHpackHeaderBlock(block);
    for (nuint i = 0u; i + 1u < fields.Count; i += 2u)
        peer.Encoder.EncodeHpackField(block, fields[i], fields[i + 1u]);
    var frames = new Http2Buffer(block.Length + 32u);
    WriteHttp2HeaderBlock(frames, id, block, endStream, Http2DefaultMaxFrameSize);
    WriteAllHttpBytes(peer.Stream, frames.Storage, 0u, frames.Length);
}

/// Sends `body` as DATA within the client's windows. False when the stream
/// was reset or the connection ended first.
internal bool SendHttp2TestBody(Http2TestPeer peer, Http2TestStream stream, byte[] body, bool endStream)
{
    nuint sent = 0u;
    while (sent < body.Length)
    {
        nuint part = 0u;
        {
            var held = peer.State.Enter();
            while (true)
            {
                if (stream.IsReset || peer.Ended)
                    return false;
                long window = stream.SendWindow < peer.SendWindow ? stream.SendWindow : peer.SendWindow;
                if (window > 0)
                {
                    part = body.Length - sent;
                    if ((long)part > window)
                        part = (nuint)window;
                    if (part > Http2DefaultMaxFrameSize)
                        part = Http2DefaultMaxFrameSize;
                    stream.SendWindow -= (long)part;
                    peer.SendWindow -= (long)part;
                    break;
                }
                if (!stream.HasBlocked)
                {
                    stream.HasBlocked = true;
                    peer.Record.NoteHttp2TestEvent(peer.Label + ": stream " +
                                                   Text.FromInteger((long)stream.Request.Stream) +
                                                   " waited for window after " + Text.FromInteger((long)sent) +
                                                   " bytes");
                }
                held.WaitFor(100u);
            }
        }
        var frame = new Http2Buffer(part + 16u);
        bool last = sent + part == body.Length;
        if (last && endStream)
            CloseHttp2TestStream(peer, stream);
        WriteHttp2Data(frame, stream.Request.Stream, body, sent, part, last && endStream);
        peer.WriteHttp2TestFrames(frame);
        sent += part;
    }
    return true;
}

// ------------------------------------------------------------ HTTP/1.1

/// Enough HTTP/1.1 to show a client fell back: each request is routed and
/// answered with a length, until the client closes.
internal void ServeHttp11TestPeer(Http2TestPeer peer, HttpBufferedReader reader)
{
    peer.Record.NoteHttp2TestEvent(peer.Label + ": HTTP/1.1");
    while (true)
    {
        if (reader.ReadHttpLine(HttpMaxLineLength, out String line) != HttpLineStatus.Line)
            return;
        var request = new Http2TestRequest();
        request.Protocol = "http/1.1";
        request.Connection = peer.Number;
        String[] parts = line.Split(' ');
        if (parts.Length == 3u)
        {
            request.Method = parts[0u];
            request.Path = parts[1u];
        }
        while (true)
        {
            if (reader.ReadHttpLine(HttpMaxLineLength, out String field) != HttpLineStatus.Line)
                return;
            if (field.IsEmpty)
                break;
            long colon = field.IndexOf(':');
            if (colon > 0)
            {
                request.Fields.Add(field.Substring(0u, (nuint)colon).ToLowerAscii() + ": " +
                                   TrimHttpWhitespace(field.Substring((nuint)colon + 1u)));
            }
        }
        String declared = request.GetField("content-length");
        if (!declared.IsEmpty && TryParseHttpDecimal(declared, out long length) && length > 0)
        {
            var body = new byte[(nuint)length];
            if (new Http2FrameReader(reader).ReadAllHttp2Bytes(body, (nuint)length) < (nuint)length)
                return;
            request.Body = body;
        }
        peer.Record.NoteHttp2TestEvent(peer.Label + ": " + request.Method + " " + request.Path + " in HTTP/1.1");
        Http2TestReply reply = peer.Route(request);
        var text = new StringBuilder();
        text.Append("HTTP/1.1 " + Text.FromInteger((long)reply.Status) + " OK\r\n");
        for (nuint i = 0u; i + 1u < reply.Fields.Count; i += 2u)
            text.Append(reply.Fields[i] + ": " + reply.Fields[i + 1u] + "\r\n");
        text.Append("Content-Length: " + Text.FromInteger((long)reply.Body.Length) + "\r\n\r\n");
        byte[] head = text.ToText().ToBytes();
        WriteAllHttpBytes(peer.Stream, head, 0u, head.Length);
        if (request.Method != "HEAD" && reply.Body.Length > 0u)
            WriteAllHttpBytes(peer.Stream, reply.Body, 0u, reply.Body.Length);
    }
}
