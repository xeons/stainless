// SPDX-License-Identifier: 0BSD
//
// What Standard.Net promises the same on every platform, where the platforms
// themselves disagree: a name whose first address refuses, a UDP socket after
// a send drew a port unreachable, the blocking mode of an accepted socket, a
// connected datagram receive into a short buffer, and a failure that must not
// look like the peer finishing.
module NetSocketBehaviour;

import Standard.Console;
import Standard.Net;
import Standard.Text;

void Report(String label, nuint count, SocketError error)
{
    Console.WriteLine($"{label} {count} {Net.DescribeSocketError(error)}");
}

// localhost is ::1 first on Windows. A listener on 127.0.0.1 only is reached
// by trying the next address, with a limit or without.
void CheckEveryAddressIsTried()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    if (!opened.Ok)
    {
        Console.WriteLine("listen failed");
        return;
    }
    var server = opened.Value;
    ushort port = server.LocalEndPoint.Port;

    var unbounded = TcpClient.Connect("localhost", port);
    Console.WriteLine($"localhost, no limit: {unbounded.Ok}");

    var bounded = TcpClient.Connect("localhost", port, AddressFamily.Any, 10000);
    Console.WriteLine($"localhost, within 10 s: {bounded.Ok}");
    if (bounded.Ok)
    {
        // The connection that comes back blocks: a read waits out its timeout
        // rather than answering WouldBlock.
        var client = bounded.Value;
        client.Underlying.SetReceiveTimeout(100);
        nuint got = client.Read(new byte[4], 0u, 4u);
        Report("  read with nothing sent", got, client.SocketErrorCode);
    }

    var expired = TcpClient.Connect("127.0.0.1", port, AddressFamily.Any, 0);
    Console.WriteLine($"within 0 ms: {expired.Ok} " +
                      (expired.Ok ? "" : Net.DescribeSocketError(expired.Error)));
}

// A send to a closed port draws an ICMP port unreachable. It MUST NOT fail
// the socket's next receive, or one vanished client stops a server.
void CheckUnreachableDoesNotResetUdp()
{
    var boundServer = UdpClient.Bind("127.0.0.1", 0u);
    var boundClient = UdpClient.Bind("127.0.0.1", 0u);
    var boundGone = UdpClient.Bind("127.0.0.1", 0u);
    if (!boundServer.Ok || !boundClient.Ok || !boundGone.Ok)
    {
        Console.WriteLine("udp bind failed");
        return;
    }
    var server = boundServer.Value;
    var client = boundClient.Value;
    var gone = boundGone.Value;
    ushort gonePort = gone.LocalEndPoint.Port;
    gone.Close();

    server.SendText("to nobody", "127.0.0.1", gonePort);
    client.SendText("hello", "127.0.0.1", server.LocalEndPoint.Port);

    server.SetReceiveTimeout(2000);
    var from = EndPoint.Create("", 0u);
    nuint got = server.Receive(new byte[64], ref from);
    Report("udp after unreachable", got, server.Error);
}

// A listener that does not block, polled with Pending, hands out connections
// that do.
void CheckAcceptedSocketBlocks()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    if (!opened.Ok)
    {
        Console.WriteLine("listen failed");
        return;
    }
    var server = opened.Value;
    server.Underlying.SetBlocking(false);

    var dialled = TcpClient.Connect("127.0.0.1", server.LocalEndPoint.Port);
    if (!dialled.Ok)
    {
        Console.WriteLine("connect failed");
        return;
    }
    var client = dialled.Value;

    server.Pending(2000);
    var accepted = server.Accept();
    Console.WriteLine($"accepted from a polled listener: {accepted.IsConnected}");

    accepted.Underlying.SetReceiveTimeout(100);
    nuint got = accepted.Read(new byte[16], 0u, 16u);
    Report("  read with nothing sent", got, accepted.SocketErrorCode);
    Console.WriteLine($"  still readable: {accepted.CanRead}");
    client.Close();
}

// A connected datagram socket truncates as an unconnected one does.
void CheckConnectedDatagramTruncates()
{
    var boundSender = UdpClient.Bind("127.0.0.1", 0u);
    var openedReceiver = Socket.Open(AddressFamily.IPv4, SocketType.Datagram);
    if (!boundSender.Ok || !openedReceiver.Ok)
    {
        Console.WriteLine("udp open failed");
        return;
    }
    var sender = boundSender.Value;
    var receiver = openedReceiver.Value;
    receiver.Bind("127.0.0.1", 0u);
    receiver.Connect("127.0.0.1", sender.LocalEndPoint.Port);
    receiver.SetReceiveTimeout(2000);

    sender.Send(new byte[10], "127.0.0.1", receiver.LocalEndPoint.Port);
    nuint got = receiver.Receive(new byte[4], 0u, 4u, out SocketError error);
    Report("connected datagram into 4", got, error);
}

// Each call's own error, and a read to the end that says when it was not.
void CheckErrorsTravelWithTheCall()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    if (!opened.Ok)
    {
        Console.WriteLine("listen failed");
        return;
    }
    var server = opened.Value;
    var dialled = TcpClient.Connect("127.0.0.1", server.LocalEndPoint.Port);
    if (!dialled.Ok)
    {
        Console.WriteLine("connect failed");
        return;
    }
    var client = dialled.Value;
    var accepted = server.Accept();

    client.Underlying.SetReceiveTimeout(100);
    nuint got = client.Underlying.Receive(new byte[4], 0u, 4u, out SocketError timedOut);
    Report("receive, own error", got, timedOut);
    nuint sent = client.Underlying.Send(new byte[1], 0u, 1u, out SocketError sendError);
    Report("send, own error", sent, sendError);
    Report("  last error now", 0u, client.SocketErrorCode);

    var partial = client.ReceiveToEnd();
    Console.WriteLine("to the end, peer silent: " +
                      (partial.Ok ? "ok" : Net.DescribeSocketError(partial.Error)));
    Console.WriteLine($"  still readable: {client.CanRead}");

    accepted.SendText("whole");
    accepted.Underlying.Shutdown(SocketShutdown.Send);
    var whole = client.ReceiveToEnd();
    Console.WriteLine("to the end, peer finished: " +
                      (whole.Ok ? $"{whole.Value.Length} bytes" : Net.DescribeSocketError(whole.Error)));
    Console.WriteLine($"  still readable: {client.CanRead}");
}

int Main()
{
    CheckEveryAddressIsTried();
    CheckUnreachableDoesNotResetUdp();
    CheckAcceptedSocketBlocks();
    CheckConnectedDatagramTruncates();
    CheckErrorsTravelWithTheCall();
    return 0;
}
