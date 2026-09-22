// SPDX-License-Identifier: 0BSD
//
// The edges of Standard.Net over the loopback: empty and oversized datagrams,
// a receive that times out, counts that do not fit, and a connect that fails
// without blocking. Every port is chosen by the system.
module EdgeSockets;

import Standard.Console;
import Standard.Limits;
import Standard.Net;

void Report(String label, nuint count, SocketError error)
{
    Console.WriteLine($"{label} {count} {Net.Describe(error)}");
}

// Leaves a stack frame full of text where the next call's locals will sit.
nuint DirtyTheStack()
{
    byte[64] scratch;
    for (nuint i = 0u; i < 64u; i++)
        scratch[i] = (byte)'x';
    return (nuint)scratch[63];
}

void CheckDatagrams()
{
    var bound = UdpSocket.Bind("127.0.0.1", 0u);
    if (!bound.Ok)
    {
        Console.WriteLine("udp bind failed");
        return;
    }

    var socket = bound.Value;
    ushort port = socket.LocalEndPoint.Port;
    var from = EndPoint.At("", 0u);

    socket.Send(new byte[0], "127.0.0.1", port);
    Report("sent empty", 0u, socket.Error);
    socket.SetReceiveTimeout(2000);
    nuint got = socket.Receive(new byte[16], ref from);
    Report("received empty", got, socket.Error);
    Console.WriteLine($"  from {from.Host}");

    var oversized = new byte[10];
    for (nuint i = 0u; i < oversized.Length; i++)
        oversized[i] = (byte)(65u + i);
    socket.Send(oversized, "127.0.0.1", port);
    var small = new byte[4];
    from = EndPoint.At("", 0u);
    got = socket.Receive(small, ref from);
    Report("truncated", got, socket.Error);
    Console.WriteLine($"  first {(char32)small[0]} last {(char32)small[3]} from {from.Host}");

    socket.Send(oversized, "127.0.0.1", port);
    got = socket.Receive(new byte[0], ref from);
    Report("into nothing", got, socket.Error);

    socket.SetReceiveTimeout(50);
    DirtyTheStack();
    from = EndPoint.At("stale", 7u);
    got = socket.Receive(new byte[16], ref from);
    Report("timed out", got, socket.Error);
    Console.WriteLine($"  from '{from.Host}' {from.Port}");
}

void CheckStream()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    if (!opened.Ok)
    {
        Console.WriteLine("listen failed");
        return;
    }

    var server = opened.Value;
    var connected = TcpClient.Connect("127.0.0.1", server.LocalEndPoint.Port);
    if (!connected.Ok)
    {
        Console.WriteLine("connect failed");
        return;
    }

    var client = connected.Value;
    var accepted = server.Accept();
    var buffer = new byte[8];

    nuint read = client.Read(buffer, 0u, 0u);
    Console.WriteLine($"read nothing {read} connected {client.IsConnected} can read {client.CanRead}");

    nuint huge = MaxNUInt;
    var raw = client.Underlying;
    Report("send past the end", raw.Send(buffer, 1u, huge), raw.Error);
    Report("receive past the end", raw.Receive(buffer, 1u, huge), raw.Error);
    Report("offset past the end", raw.Receive(buffer, 9u, 0u), raw.Error);
    Report("offset past the end with a count", raw.Receive(buffer, 9u, 1u), raw.Error);

    accepted.SendText("hi");
    read = client.Read(buffer, 0u, 8u);
    Console.WriteLine($"read {read} still connected {client.IsConnected}");
}

void CheckFailedConnect()
{
    // A port that is bound and not listening refuses a connection.
    var holder = Socket.Open(AddressFamily.IPv4, SocketKind.Stream);
    var socket = Socket.Open(AddressFamily.IPv4, SocketKind.Stream);
    if (!holder.Ok || !socket.Ok)
    {
        Console.WriteLine("open failed");
        return;
    }

    var held = holder.Value;
    held.Bind("127.0.0.1", 0u);
    ushort port = held.LocalEndPoint.Port;

    var connecting = socket.Value;
    connecting.SetBlocking(false);
    var started = connecting.Connect("127.0.0.1", port);
    Console.WriteLine($"connect started {started == SocketError.WouldBlock || started == SocketError.Refused}");

    bool writable = connecting.WaitToWrite(10000);
    Console.WriteLine($"writable {writable} {Net.Describe(connecting.Error)}");
}

public int Main()
{
    CheckDatagrams();
    CheckStream();
    CheckFailedConnect();
    return 0;
}
