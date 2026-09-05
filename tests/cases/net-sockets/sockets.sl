// Sockets over the loopback, which is the only network a test may assume.
//
// Everything here runs in one thread, which is possible because of how the two
// protocols actually work. A TCP connect completes as soon as the listener's
// backlog accepts it -- `accept` is the program collecting a connection the
// kernel already made, not the thing that makes it -- so a client can connect
// before anything accepts. UDP has no handshake to wait for at all.
//
// Nothing here is platform-specific and nothing is guarded. That is the claim
// being tested: Winsock and BSD sockets disagree about the handle, the errors,
// the close and the startup, and none of that reaches this file.
module NetSockets;

import Standard.Console;
import Standard.Text;
import Standard.IO;
import Standard.Net;

void Say(String label, String value) {
    Console.WriteLine(label + " " + value);
}

void SayNumber(String label, long value) {
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

void SayBool(String label, bool value) {
    Console.WriteLine(label + " " + Text.FromBool(value));
}

int Main() {
    // ---------------------------------------------------------------- names
    var local = Net.Resolve("localhost");
    switch (local) {
        case Ok:   SayBool("resolve-localhost", true); break;
        case Fail: SayBool("resolve-localhost", false); break;
    }

    // A literal address resolves to itself, which is the property that lets
    // one code path take both a name and an address.
    var literal = Net.Resolve("127.0.0.1");
    switch (literal) {
        case Ok ok:  Say("resolve-literal", ok.Value); break;
        case Fail:   Say("resolve-literal", "failed"); break;
    }

    var nowhere = Net.Resolve("this.name.does.not.exist.invalid");
    SayBool("resolve-nowhere", nowhere.Ok);

    // ------------------------------------------------------------------ TCP
    //
    // Port 0 asks the system to choose, so two copies of this test can run at
    // once and neither has to know a port number in advance.
    var server = new TcpListener("127.0.0.1", 0u);
    SayBool("listening", server.IsListening());

    var address = server.LocalEndPoint();
    Say("bound-host", address.Host);
    SayBool("bound-port", address.Port != 0u);

    // No family named, so `Any`: the name decides. This is the shape that used
    // to open an AF_UNSPEC socket before resolving -- which Winsock accepts and
    // Linux does not, so it worked here and hung there.
    var client = new TcpClient("127.0.0.1", address.Port);
    SayBool("connected", client.IsConnected());
    SayBool("connected-family", client.Underlying().Family() == AddressFamily.Any);

    // And opening one directly with `Any` is an error rather than a guess,
    // because there is no socket of no family.
    var nofamily = new Socket(AddressFamily.Any, SocketKind.Stream);
    SayBool("any-is-not-a-socket", !nofamily.IsOpen());
    SayBool("any-says-why", nofamily.Error() == SocketError.Invalid);

    var accepted = server.Accept();
    SayBool("accepted", accepted.IsConnected());

    // The two ends agree about who is who.
    var here = client.LocalEndPoint();
    var there = client.RemoteEndPoint();
    SayBool("peer-port", there.Port == address.Port);
    SayBool("peer-host", there.Host == "127.0.0.1");
    // The text, not the number: an ephemeral port is whatever the system had
    // free, so a test that printed it would print something different tomorrow.
    SayBool("remote-formatted", Net.Format(there).StartsWith("127.0.0.1:"));

    // An IPv6 address goes in brackets, because a bare one already contains
    // colons and the port would be indistinguishable from another group.
    Say("formatted-v6", Net.Format(Net.At("::1", 80u)));

    var seen = accepted.RemoteEndPoint();
    SayBool("mirror", seen.Port == here.Port);

    // ------------------------------------------------------------- talking
    client.SendText("hello, socket");

    var buffer = new byte[64];
    nuint got = accepted.Read(buffer, 0u, buffer.Length);
    SayNumber("server-read", (long)got);
    Say("server-saw", Text.FromBytes(&buffer[0], got));

    accepted.SendText("and back");
    nuint back = client.Read(buffer, 0u, buffer.Length);
    Say("client-saw", Text.FromBytes(&buffer[0], back));

    // A `TcpClient` is an `IStream`, so anything written against one reads a
    // connection with nothing changed.
    IStream stream = accepted;
    SayBool("stream-can-read", stream.CanRead());
    SayBool("stream-can-write", stream.CanWrite());
    SayBool("stream-can-seek", stream.CanSeek());
    SayNumber("stream-length", stream.Length());
    SayBool("stream-seek", stream.Seek(0, SeekOrigin.Start));

    // ------------------------------------------------------------- endings
    //
    // Shutting down the sending half is how a protocol that ends by closing
    // says it has finished. The other end sees an ending rather than a reset.
    client.Underlying().Shutdown(SocketShutdown.Send);

    var rest = accepted.ReceiveAll();
    SayNumber("after-shutdown", (long)rest.Length);
    SayBool("finished", !accepted.CanRead());

    accepted.Close();
    client.Close();
    server.Close();

    SayBool("closed", !client.IsConnected());

    // ------------------------------------------------------------------ UDP
    //
    // No handshake, so one socket can talk to itself in a straight line.
    var listener = new UdpSocket("127.0.0.1", 0u);
    SayBool("udp-open", listener.IsOpen());

    var inbox = listener.LocalEndPoint();
    SayBool("udp-port", inbox.Port != 0u);

    var sender = new UdpSocket();
    nuint sent = sender.SendText("a datagram", "127.0.0.1", inbox.Port);
    SayNumber("udp-sent", (long)sent);

    var from = Net.At("", 0u);
    var packet = new byte[64];
    nuint received = listener.Receive(packet, ref from);
    SayNumber("udp-received", (long)received);
    Say("udp-text", Text.FromBytes(&packet[0], received));
    SayBool("udp-from", from.Host == "127.0.0.1");
    SayBool("udp-from-port", from.Port != 0u);

    listener.Close();
    sender.Close();

    // ------------------------------------------------------------- failures
    //
    // Connecting to a port nothing is listening on. Which error the platform
    // gives is its own business -- refused on a machine that answers, timed
    // out or unreachable on one that drops -- so what is checked is that it
    // failed and said something rather than which something it said.
    var refused = new TcpClient("127.0.0.1", 1u);
    SayBool("refused", !refused.IsConnected());
    SayBool("refused-said-why", refused.SocketError() != SocketError.None);

    // And the error rounds off to an IOError for a reader that has never
    // heard of a socket.
    SayBool("refused-as-io", refused.Error() != IOError.None);

    // Two listeners on one port. The second one fails to bind.
    var first = new TcpListener("127.0.0.1", 0u);
    var taken = first.LocalEndPoint().Port;
    var second = new TcpListener("127.0.0.1", taken);
    SayBool("second-listener", second.IsListening());

    first.Close();
    second.Close();

    // A socket that was never opened answers everything with Closed rather
    // than doing anything.
    var dead = new TcpListener("127.0.0.1", taken);
    dead.Close();
    SayBool("closed-listener", dead.IsListening());

    return 0;
}
