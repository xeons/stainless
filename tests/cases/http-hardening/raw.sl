// SPDX-License-Identifier: 0BSD
// A loopback server that hands each connection to a handler as it is, so
// that a case can send exactly the bytes it wants, when it wants, and see
// exactly the bytes the client sent.
module HttpRawServer;

import Standard.Collections;
import Standard.Net;
import Standard.Text;
import Standard.Threading;

/// Serves one connection, the `index`th accepted.
public closure void RawHandler(TcpClient connection, int index);

/// Lines written by the handlers, read once the server has stopped, so that
/// what they saw prints in one place and in one order.
public sealed class RawLog
{
    private Mutex<int> _lock = new Mutex<int>(0);
    private List<String> _lines = new List<String>();

    public RawLog() { }

    public void AddLine(String line)
    {
        var held = _lock.Enter();
        _lines.Add(line);
    }

    public List<String> CopyLines()
    {
        var held = _lock.Enter();
        var copy = new List<String>();
        foreach (var line in _lines)
            copy.Add(line);
        return copy;
    }
}

public sealed class RawServer
{
    private TcpListener _listener;
    private RawHandler _handler;
    private AtomicBool _stopping = new AtomicBool(false);
    private List<Thread> _workers = new List<Thread>();
    private Thread? _acceptor;

    private RawServer(TcpListener listener, RawHandler handler)
    {
        _listener = listener;
        _handler = handler;
    }

    /// A server already accepting, or null when it could not listen.
    public static RawServer? StartRawServer(RawHandler handler)
    {
        if (TcpListener.Listen("127.0.0.1", 0u) is not Ok listening)
            return null;
        var server = new RawServer(listening.Value, handler);
        server._acceptor = new Thread(() => server.AcceptRawConnections());
        return server;
    }

    public ushort Port => _listener.LocalEndPoint.Port;

    public String Origin => "http://127.0.0.1:" + Text.FromInteger((long)Port);

    private void AcceptRawConnections()
    {
        int accepted = 0;
        while (!this._stopping.Read())
        {
            if (!this._listener.Pending(10))
                continue;
            TcpClient client = this._listener.Accept();
            accepted++;
            int number = accepted;
            client.Underlying.SetReceiveTimeout(10000);
            this._workers.Add(new Thread(() => this._handler(client, number)));
        }
    }

    /// Stops accepting and waits for every handler to return.
    public void StopRawServer()
    {
        _stopping.Write(true);
        if (_acceptor is Thread acceptor)
            acceptor.Join();
        foreach (var worker in _workers)
            worker.Join();
        _listener.Close();
    }
}

/// A request head up to and including its empty line, or what came before
/// the end.
public String ReadRawHead(TcpClient connection)
{
    var bytes = new List<byte>();
    var one = new byte[1u];
    while (true)
    {
        if (connection.Read(one, 0u, 1u) == 0u)
            break;
        bytes.Add(one[0u]);
        nuint n = bytes.Count;
        if (n >= 4u && bytes[n - 4u] == (byte)'\r' && bytes[n - 3u] == (byte)'\n' &&
            bytes[n - 2u] == (byte)'\r' && bytes[n - 1u] == (byte)'\n')
            break;
    }
    return ConvertRawBytesToText(bytes);
}

/// Up to `limit` bytes, or fewer when the peer stops.
public String ReadRawBytes(TcpClient connection, nuint limit)
{
    var bytes = new List<byte>();
    var block = new byte[4096u];
    while (bytes.Count < limit)
    {
        nuint wanted = limit - bytes.Count;
        if (wanted > block.Length)
            wanted = block.Length;
        nuint got = connection.Read(block, 0u, wanted);
        if (got == 0u)
            break;
        for (nuint i = 0u; i < got; i++)
            bytes.Add(block[i]);
    }
    return ConvertRawBytesToText(bytes);
}

/// The value of the field `name` in a head, or "(none)".
public String FindRawField(String head, String name)
{
    foreach (var line in head.Split('\n'))
    {
        String trimmed = line.Trim();
        long colon = trimmed.IndexOf(':');
        if (colon > 0 && trimmed.Substring(0u, (nuint)colon).ToLowerAscii() == name.ToLowerAscii())
            return trimmed.Substring((nuint)colon + 1u).Trim();
    }
    return "(none)";
}

/// The request line of a head.
public String FindRawRequestLine(String head) => head.SubstringBefore("\r\n");

/// The digits at the start of `text` as a number.
public nuint ParseRawDecimal(String text)
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

internal String ConvertRawBytesToText(List<byte> bytes)
{
    if (bytes.Count == 0u)
        return "";
    byte[] all = bytes.ToArray();
    return Text.FromBytes(&all[0u], all.Length);
}
