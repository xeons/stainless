// SPDX-License-Identifier: 0BSD
//
// No socket this process holds reaches a child: not a listener, not a
// connection it made, not one it accepted, not a datagram socket. A child
// holding a copy keeps the port and the peer alive after the parent closes.
//
// linux-socket-inheritance asks the same of Linux by counting /proc/self/fd;
// macOS has no /proc, so the child asks lsof what network files it has.
module MacSocketInheritance;

import Standard.Console;
import Standard.Net;
import Standard.Process;

int Main()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    var datagrams = UdpClient.Bind("127.0.0.1", 0u);
    if (!opened.Ok || !datagrams.Ok)
        return 1;
    var server = opened.Value;
    var dialled = TcpClient.Connect("127.0.0.1", server.LocalEndPoint.Port);
    var timed = TcpClient.Connect("127.0.0.1", server.LocalEndPoint.Port, AddressFamily.Any, 5000);
    if (!dialled.Ok || !timed.Ok)
        return 1;
    var accepted = server.Accept();
    Console.WriteLine($"accepted: {accepted.IsConnected}");

    var listed = RunProcess("sh", ["-c", "/usr/sbin/lsof -a -p $$ -i 2>/dev/null | grep -c -E 'TCP|UDP' || true"]);
    if (!listed.Ok)
    {
        Console.WriteLine("could not run the child");
        return 1;
    }
    Console.WriteLine("sockets the child holds: " + listed.Value.StandardOutput.Trim());
    return 0;
}
