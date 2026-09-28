// SPDX-License-Identifier: 0BSD
// A scripted HTTP/1.1 server for the http-* cases, over the loopback.
//
// Each connection has a thread of its own, so that one the client keeps alive
// never stops another from being served. A route decides each reply from the
// request, and a reply is a script of steps: bytes to send, a pause, a wait
// for the case to say go, a close. The server writes nothing itself; what it
// saw is kept for the case to print once it has stopped.
module HttpTestServer;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Text;
import Standard.Threading;

/// Decides the reply to one request.
public closure HttpTestReply HttpTestRoute(HttpTestRequest request);

/// A request as the server read it.
public sealed class HttpTestRequest
{
    public String Method = "";
    public String Target = "";
    public String Version = "";
    public List<String> Fields = new List<String>();
    public byte[] Body = new byte[0u];
    public bool Chunked = false;
    public List<String> Trailers = new List<String>();

    /// Which connection it came on, counting from 1.
    public int Connection = 0;

    /// Which request it is on that connection, counting from 1.
    public int Sequence = 0;

    /// The first value of the field `name`, or empty.
    public String GetField(String name)
    {
        String wanted = name.ToLowerAscii() + ":";
        foreach (var line in Fields)
        {
            if (line.ToLowerAscii().StartsWith(wanted))
                return line.Substring(wanted.ByteLength()).Trim();
        }
        return "";
    }

    public bool HasField(String name)
    {
        String wanted = name.ToLowerAscii() + ":";
        foreach (var line in Fields)
        {
            if (line.ToLowerAscii().StartsWith(wanted))
                return true;
        }
        return false;
    }

    public String BodyText => Body.Length == 0u ? "" : Text.FromBytes(&Body[0u], Body.Length);
}

/// What the server does in answer: bytes, pauses, and perhaps a close.
public sealed class HttpTestReply
{
    internal List<HttpTestStep> Steps = new List<HttpTestStep>();

    public HttpTestReply() { }

    /// A reply of exactly `raw`.
    public static HttpTestReply CreateRaw(String raw) => new HttpTestReply().SendText(raw);

    /// A complete response with a `Content-Length`.
    public static HttpTestReply CreateText(int status, String reason, String extraFields, String body)
    {
        String head = "HTTP/1.1 " + Text.FromInteger((long)status) + " " + reason + "\r\n" + extraFields +
                      "Content-Length: " + Text.FromInteger((long)body.ByteLength()) + "\r\n\r\n";
        return new HttpTestReply().SendText(head + body);
    }

    public HttpTestReply SendText(String text)
    {
        Steps.Add(new HttpTestStep(text.ToBytes(), 0, false));
        return this;
    }

    public HttpTestReply SendBytes(byte[] bytes)
    {
        Steps.Add(new HttpTestStep(bytes, 0, false));
        return this;
    }

    public HttpTestReply Pause(int milliseconds)
    {
        Steps.Add(new HttpTestStep(new byte[0u], milliseconds, false));
        return this;
    }

    public HttpTestReply CloseConnection()
    {
        Steps.Add(new HttpTestStep(new byte[0u], 0, true));
        return this;
    }

    /// Waits until `condition` holds, or `limit` milliseconds have passed.
    public HttpTestReply WaitUntil(HttpTestCondition condition, int limit)
    {
        var step = new HttpTestStep(new byte[0u], limit, false);
        step.Condition = condition;
        step.HasCondition = true;
        Steps.Add(step);
        return this;
    }
}

/// Something a reply waits for.
public closure bool HttpTestCondition();

internal sealed class HttpTestStep
{
    internal byte[] Bytes;
    internal int Pause;
    internal bool Close;
    internal bool HasCondition = false;
    internal HttpTestCondition Condition = () => true;

    internal HttpTestStep(byte[] bytes, int pause, bool close)
    {
        Bytes = bytes;
        Pause = pause;
        Close = close;
    }
}

/// One connection the server holds, and what it has read and not used.
internal sealed class HttpTestConnection
{
    internal TcpClient Client;
    internal IStream Stream;
    internal int Number;
    internal int Served = 0;
    internal byte[] Pending = new byte[0u];

    internal HttpTestConnection(TcpClient client, IStream stream, int number)
    {
        Client = client;
        Stream = stream;
        Number = number;
    }

    internal void SendToClient(byte[] bytes)
    {
        nuint at = 0u;
        while (at < bytes.Length)
        {
            nuint wrote = Stream.Write(bytes, at, bytes.Length - at);
            if (wrote == 0u)
                return;
            at += wrote;
        }
    }

    internal void CloseToClient()
    {
        Stream.Close();
        Client.Close();
    }

    /// Reads more from the client onto `Pending`. False at its end.
    internal bool ReadMoreFromClient()
    {
        var block = new byte[16384u];
        nuint got = Stream.Read(block, 0u, block.Length);
        if (got == 0u)
            return false;
        var joined = new byte[Pending.Length + got];
        for (nuint i = 0u; i < Pending.Length; i++)
            joined[i] = Pending[i];
        for (nuint i = 0u; i < got; i++)
            joined[Pending.Length + i] = block[i];
        Pending = joined;
        return true;
    }

    /// Takes `count` bytes off the front of `Pending`.
    internal byte[] TakePending(nuint count)
    {
        var taken = new byte[count];
        for (nuint i = 0u; i < count; i++)
            taken[i] = Pending[i];
        var rest = new byte[Pending.Length - count];
        for (nuint i = 0u; i < rest.Length; i++)
            rest[i] = Pending[count + i];
        Pending = rest;
        return taken;
    }

    /// The next line, CRLF taken off, or null at the end.
    internal String? ReadLineFromClient()
    {
        while (true)
        {
            for (nuint i = 0u; i + 1u < Pending.Length; i++)
            {
                if (Pending[i] == (byte)'\r' && Pending[i + 1u] == (byte)'\n')
                {
                    byte[] line = TakePending(i + 2u);
                    return i == 0u ? "" : Text.FromBytes(&line[0u], i);
                }
            }
            if (!ReadMoreFromClient())
                return null;
        }
    }

    internal bool ReadBytesFromClient(nuint count, out byte[] bytes)
    {
        bytes = new byte[0u];
        while (Pending.Length < count)
        {
            if (!ReadMoreFromClient())
                return false;
        }
        bytes = TakePending(count);
        return true;
    }
}

/// The server: a listener on the loopback, a thread that accepts, and a
/// thread per connection that serves it.
///
/// A thread per connection rather than one polling them all, because a TLS
/// connection can hold a request its stream has already read from the socket,
/// and the socket then has nothing to say that there is one.
public sealed class HttpTestServer
{
    private TcpListener _listener;
    private HttpTestRoute _route;
    private TlsServerOptions? _tls;
    private AtomicBool _stopping = new AtomicBool(false);
    private AtomicInt _accepts = new AtomicInt(0);
    private Mutex<int> _lock = new Mutex<int>(0);
    private List<HttpTestConnection> _open = new List<HttpTestConnection>();
    private List<Thread> _workers = new List<Thread>();
    private Thread? _acceptor;

    /// Each request seen, as `METHOD target`, in order, and each TLS
    /// handshake. Read it once the server has stopped.
    public List<String> Log = new List<String>();

    /// Each request seen, whole. Read it once the server has stopped.
    public List<HttpTestRequest> Requests = new List<HttpTestRequest>();

    private HttpTestServer(TcpListener listener, HttpTestRoute route, TlsServerOptions? tls)
    {
        _listener = listener;
        _route = route;
        _tls = tls;
    }

    /// A server on a port the system chooses, already serving, or null when
    /// it could not listen.
    public static HttpTestServer? StartServing(HttpTestRoute route) => StartServing(route, null);

    /// The same, speaking TLS with `tls` when it is not null.
    public static HttpTestServer? StartServing(HttpTestRoute route, TlsServerOptions? tls)
    {
        var listening = TcpListener.Listen("127.0.0.1", 0u);
        if (!listening.Ok)
            return null;
        var server = new HttpTestServer(listening.Value, route, tls);
        server._acceptor = new Thread(() => server.AcceptTestConnections());
        return server;
    }

    public ushort Port => _listener.LocalEndPoint.Port;

    /// `http://127.0.0.1:port`, or `https://` for TLS, with no slash after it.
    public String Origin => (_tls == null ? "http" : "https") + "://127.0.0.1:" + Text.FromInteger((long)Port);

    /// How many connections have been accepted.
    public int Accepts => _accepts.Read();

    /// Stops serving: ends every connection, which ends the read its thread
    /// is waiting in, and waits for every thread to finish.
    public void StopServing()
    {
        _stopping.Write(true);
        if (_acceptor is Thread acceptor)
            acceptor.Join();
        {
            var held = _lock.Enter();
            foreach (var connection in _open)
                connection.Client.Underlying.Shutdown(SocketShutdown.Both);
        }
        foreach (var worker in _workers)
            worker.Join();
        _listener.Close();
    }

    private void AcceptTestConnections()
    {
        int accepted = 0;
        while (!this._stopping.Read())
        {
            if (!this._listener.Pending(10))
                continue;
            TcpClient client = this._listener.Accept();
            accepted++;
            this._accepts.Increment();
            client.Underlying.SetReceiveTimeout(5000);
            int number = accepted;
            this._workers.Add(new Thread(() => this.ServeTestConnection(client, number)));
        }
    }

    private void ServeTestConnection(TcpClient client, int number)
    {
        HttpTestConnection? started = this.StartTestConnection(client, number);
        if (started == null)
            return;
        HttpTestConnection connection = started;
        {
            var held = this._lock.Enter();
            this._open.Add(connection);
        }
        while (!this._stopping.Read() && this.ServeOneRequest(connection))
        {
        }
        connection.CloseToClient();
    }

    private void NoteTestEvent(String line, HttpTestRequest? request)
    {
        var held = this._lock.Enter();
        this.Log.Add(line);
        if (request != null)
            this.Requests.Add(request);
    }

    /// The connection, after TLS when this server speaks it, or null when the
    /// handshake failed.
    private HttpTestConnection? StartTestConnection(TcpClient client, int number)
    {
        TlsServerOptions? options = this._tls;
        if (options == null)
            return new HttpTestConnection(client, client, number);
        var secured = TlsStream.AuthenticateAsServer(client, options);
        if (!secured.Ok)
        {
            this.NoteTestEvent("TLS handshake failed: " + DescribeTlsError(secured.Error), null);
            client.Close();
            return null;
        }
        TlsStream tls = secured.Value;
        String? protocol = tls.NegotiatedApplicationProtocol;
        this.NoteTestEvent("TLS, ALPN " + (protocol == null ? "none" : protocol), null);
        return new HttpTestConnection(client, tls, number);
    }

    /// Reads a request and plays its reply. False when the connection is
    /// over.
    private bool ServeOneRequest(HttpTestConnection connection)
    {
        String? line = connection.ReadLineFromClient();
        if (line == null)
            return false;
        var request = new HttpTestRequest();
        String[] parts = line.Split(' ');
        if (parts.Length == 3u)
        {
            request.Method = parts[0u];
            request.Target = parts[1u];
            request.Version = parts[2u];
        }
        while (true)
        {
            String? field = connection.ReadLineFromClient();
            if (field == null)
                return false;
            if (field.IsEmpty)
                break;
            request.Fields.Add(field);
        }

        if (request.GetField("Transfer-Encoding").ToLowerAscii() == "chunked")
        {
            request.Chunked = true;
            var body = new List<byte>();
            while (true)
            {
                String? size = connection.ReadLineFromClient();
                if (size == null)
                    return false;
                nuint length = ParseTestHexadecimal(size);
                if (length == 0u)
                    break;
                if (!connection.ReadBytesFromClient(length + 2u, out byte[] data))
                    return false;
                for (nuint i = 0u; i < length; i++)
                    body.Add(data[i]);
            }
            while (true)
            {
                String? trailer = connection.ReadLineFromClient();
                if (trailer == null)
                    return false;
                if (trailer.IsEmpty)
                    break;
                request.Trailers.Add(trailer);
            }
            request.Body = body.ToArray();
        }
        else
        {
            String declared = request.GetField("Content-Length");
            nuint length = declared.IsEmpty ? 0u : ParseTestDecimal(declared);
            bool expectsContinue = request.GetField("Expect").ToLowerAscii() == "100-continue";
            if (length > 0u && expectsContinue)
                connection.SendToClient("HTTP/1.1 100 Continue\r\n\r\n".ToBytes());
            if (length > 0u)
            {
                if (!connection.ReadBytesFromClient(length, out byte[] data))
                    return false;
                request.Body = data;
            }
        }

        connection.Served++;
        request.Connection = connection.Number;
        request.Sequence = connection.Served;
        this.NoteTestEvent(request.Method + " " + request.Target, request);

        HttpTestReply reply = this._route(request);
        foreach (var step in reply.Steps)
        {
            if (step.HasCondition)
            {
                for (int waited = 0; waited < step.Pause && !step.Condition(); waited += 5)
                    Sleep(5u);
            }
            else if (step.Pause > 0)
            {
                Sleep((ulong)step.Pause);
            }
            if (step.Bytes.Length > 0u)
                connection.SendToClient(step.Bytes);
            if (step.Close)
                return false;
        }
        return true;
    }
}

internal nuint ParseTestHexadecimal(String text)
{
    nuint value = 0u;
    for (nuint i = 0u; i < text.ByteLength(); i++)
    {
        byte c = text.GetByteAt(i);
        if (c >= (byte)'0' && c <= (byte)'9')
            value = value * 16u + (nuint)(c - (byte)'0');
        else if (c >= (byte)'a' && c <= (byte)'f')
            value = value * 16u + (nuint)(c - (byte)'a' + 10);
        else if (c >= (byte)'A' && c <= (byte)'F')
            value = value * 16u + (nuint)(c - (byte)'A' + 10);
        else
            break;
    }
    return value;
}

public nuint ParseTestDecimal(String text)
{
    nuint value = 0u;
    for (nuint i = 0u; i < text.ByteLength(); i++)
    {
        byte c = text.GetByteAt(i);
        if (c < (byte)'0' || c > (byte)'9')
            break;
        value = value * 10u + (nuint)(c - (byte)'0');
    }
    return value;
}
