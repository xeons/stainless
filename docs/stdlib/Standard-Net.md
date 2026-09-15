# Standard.Net

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Sockets, the same on every platform.

Winsock and BSD sockets are the same design that disagrees about every
detail -- a handle that is pointer-sized on one and a file descriptor on the
other, errors through WSAGetLastError or errno, closesocket or close, and a
startup call one of them will not work without. All of that is in
runtime/socket.c, for the reason every other platform difference is: a
Stainless enum crosses the boundary as itself and an errno does not.

Four types, and the choice between them is what the program is doing rather
than what the platform offers:

  TcpListener   accepts connections
  TcpClient     one connection, and an `IStream`, so everything that already
                reads a stream reads a socket
  UdpSocket     datagrams, which are not a stream and are not pretended to be
  Socket        the one underneath, for anything the three do not cover

`TcpClient` being an `IStream` is the point of the design. A reader written
against a file works over a connection with nothing changed, because there
was never anything file-shaped in it.

## Contents

**Types** &nbsp; [AddressFamily](#addressfamily-enum) &middot; [EndPoint](#endpoint-struct) &middot; [Socket](#socket-class) &middot; [SocketError](#socketerror-enum) &middot; [SocketKind](#socketkind-enum) &middot; [SocketShutdown](#socketshutdown-enum) &middot; [TcpClient](#tcpclient-class) &middot; [TcpListener](#tcplistener-class) &middot; [UdpSocket](#udpsocket-class)

**Functions** &nbsp; [Describe](#describe-function) &middot; [Resolve](#resolve-function) &middot; [Resolve](#resolve-function)

## Types

### AddressFamily *enum*

```
enum AddressFamily
```

Which internet protocol.

<sub>[stdlib/Net.sl:136](../../stdlib/Net.sl#L136)</sub>

#### Any *case*

```
Any = 0
```

Whichever the name resolves to.

Only meaningful where a name is being resolved: connecting to one, or
`Resolve`. There is no socket of no family, so opening one with `Any`
is `SocketError.Invalid` -- which is what Linux says and Windows
quietly does not, handing back an IPv4 socket instead.

<sub>[stdlib/Net.sl:144](../../stdlib/Net.sl#L144)</sub>

#### IPv4 *case*

```
IPv4 = 4
```

IPv4 only.

<sub>[stdlib/Net.sl:146](../../stdlib/Net.sl#L146)</sub>

#### IPv6 *case*

```
IPv6 = 6
```

IPv6 only. Whether it also accepts IPv4 is the platform's default,
not something set here.

<sub>[stdlib/Net.sl:149](../../stdlib/Net.sl#L149)</sub>

### EndPoint *struct*

```
struct EndPoint
```

A host and a port, together, because they always travel together.

A struct rather than a class: it holds a `String`, so copying it retains --
which is fine, and is why it cannot cross `extern "C"` (§7.6). Nothing here
needs it to.

<sub>[stdlib/Net.sl:209](../../stdlib/Net.sl#L209)</sub>

#### Host *field*

```
String Host
```

The address or name. An empty host means every address on this machine,
which is what a server binds to.

<sub>[stdlib/Net.sl:213](../../stdlib/Net.sl#L213)</sub>

#### Port *field*

```
ushort Port
```

The port. Zero asks the system to choose one, which `LocalEndPoint`
will then say.

<sub>[stdlib/Net.sl:217](../../stdlib/Net.sl#L217)</sub>

#### At *method*

```
static EndPoint At(String host, ushort port)
```

An endpoint, made in one expression.

<sub>[stdlib/Net.sl:220](../../stdlib/Net.sl#L220)</sub>

#### Format *method*

```
String Format()
```

Written the way one is written.

<sub>[stdlib/Net.sl:229](../../stdlib/Net.sl#L229)</sub>

### Socket *class*

```
class Socket
```

One socket, and nothing above it.

`TcpListener`, `TcpClient` and `UdpSocket` are what a program should reach
for; this is what they are made of, and what is left when none of the three
is the shape of the problem.

Made through `Socket.Open`, which returns a `Result`. A constructor has to
return its own type, so it cannot say why an open failed -- the best it
could do is hand back a socket holding nothing, and nothing then forces the
check that would have caught it.

Closing is the destructor's job, so a socket that goes out of scope gives
its handle back whether or not `Close` was called.

<sub>[stdlib/Net.sl:284](../../stdlib/Net.sl#L284)</sub>

#### Open *method*

```
static Result<Socket, SocketError> Open(AddressFamily family, SocketKind kind)
```

A socket of a given family and kind, unbound and unconnected.

<sub>[stdlib/Net.sl:293](../../stdlib/Net.sl#L293)</sub>

#### OpenConnected *method*

```
static Result<Socket, SocketError> OpenConnected(String host, ushort port, AddressFamily family, SocketKind kind)
```

A socket already connected to a host and port.

One step, because connecting is what decides the family: a caller with
a name does not know whether it will get IPv4 or IPv6, so it cannot
open first.

<sub>[stdlib/Net.sl:306](../../stdlib/Net.sl#L306)</sub>

#### IsOpen *method*

```
bool IsOpen()
```

Whether the handle is still live. False before a failed open and after
`Close`; it says nothing about whether the peer is still there, which
only a read can find out.

<sub>[stdlib/Net.sl:371](../../stdlib/Net.sl#L371)</sub>

#### Error *method*

```
SocketError Error()
```

The last error, or `None`. Set by every call that failed, and cleared
by the next one that did not.

<sub>[stdlib/Net.sl:375](../../stdlib/Net.sl#L375)</sub>

#### Family *method*

```
AddressFamily Family()
```

Which family the socket was opened for. Fixed at open.

<sub>[stdlib/Net.sl:378](../../stdlib/Net.sl#L378)</sub>

#### Kind *method*

```
SocketKind Kind()
```

Stream or datagram. Fixed at open.

<sub>[stdlib/Net.sl:381](../../stdlib/Net.sl#L381)</sub>

#### Handle *method*

```
nuint Handle()
```

The handle itself, for a platform call this wrapper does not make.
A `SOCKET` on Windows and a file descriptor on everything else.

<sub>[stdlib/Net.sl:385](../../stdlib/Net.sl#L385)</sub>

#### Close *method*

```
void Close()
```

Closes the handle. Idempotent, and the destructor calls it, so a
socket that goes out of scope is not leaked.

Closing a stream socket without `Shutdown` first leaves what the peer
sees up to the platform and to what is still unread; `TcpClient.Close`
shuts both directions down first, which is what ends one politely.

<sub>[stdlib/Net.sl:393](../../stdlib/Net.sl#L393)</sub>

#### Bind *method*

```
SocketError Bind(String host, ushort port)
```

Takes the address, and the port. Port 0 asks the system to choose one,
which `LocalEndPoint` will then say.

<sub>[stdlib/Net.sl:406](../../stdlib/Net.sl#L406)</sub>

#### BindAny *method*

```
SocketError BindAny(ushort port)
```

Binds to every address on this machine, which is what a server wants
and what an empty host means to the resolver.

<sub>[stdlib/Net.sl:418](../../stdlib/Net.sl#L418)</sub>

#### Listen *method*

```
SocketError Listen(int backlog)
```

Starts accepting connections. `backlog` is how many may wait before
the system refuses more; the platform may cap it lower than asked.

Bind first -- listening on a socket that was never bound fails.

<sub>[stdlib/Net.sl:424](../../stdlib/Net.sl#L424)</sub>

#### Accept *method*

```
Socket Accept()
```

Waits for a connection. The socket that comes back is open, or is not
and says why.

<sub>[stdlib/Net.sl:436](../../stdlib/Net.sl#L436)</sub>

#### Connect *method*

```
SocketError Connect(String host, ushort port)
```

Connects a socket that is already open.

Only the first address of this socket's family is tried, because a
socket whose connect failed cannot be used for a second attempt and
this one is already made. `new Socket(host, port, family, kind)` is the
form that tries them all, and the one a client should reach for.

<sub>[stdlib/Net.sl:456](../../stdlib/Net.sl#L456)</sub>

#### LocalEndPoint *method*

```
EndPoint LocalEndPoint()
```

This end of the connection.

<sub>[stdlib/Net.sl:467](../../stdlib/Net.sl#L467)</sub>

#### RemoteEndPoint *method*

```
EndPoint RemoteEndPoint()
```

The other end.

<sub>[stdlib/Net.sl:470](../../stdlib/Net.sl#L470)</sub>

#### Send *method*

```
nuint Send(byte[] buffer, nuint offset, nuint count)
```

Sends up to `count` bytes and reports how many went.

Fewer than asked for is normal on a stream: the kernel took what fitted
in its buffer. A loop over what is left is the caller's job, or
`SendAll` is.

<sub>[stdlib/Net.sl:479](../../stdlib/Net.sl#L479)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] buffer)
```

Sends all of it, or says why it could not.

<sub>[stdlib/Net.sl:501](../../stdlib/Net.sl#L501)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

<sub>[stdlib/Net.sl:516](../../stdlib/Net.sl#L516)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes and reports how many arrived. Zero is the
peer having finished, which is an ending rather than an error -- ask
`Error()` to tell the two apart.

<sub>[stdlib/Net.sl:540](../../stdlib/Net.sl#L540)</sub>

#### SendTo *method*

```
nuint SendTo(byte[] buffer, EndPoint target)
```

Sends one datagram. It arrives whole or not at all.

<sub>[stdlib/Net.sl:564](../../stdlib/Net.sl#L564)</sub>

#### ReceiveFrom *method*

```
nuint ReceiveFrom(byte[] buffer, ref EndPoint from)
```

Reads one datagram, and says where it came from.

A datagram longer than the buffer is truncated and the rest is gone,
which is what a datagram is: there is no second read to get the rest of
one.

<sub>[stdlib/Net.sl:585](../../stdlib/Net.sl#L585)</sub>

#### SetBlocking *method*

```
SocketError SetBlocking(bool blocking)
```

Whether a call waits. A socket that does not block answers
`WouldBlock` instead of waiting, which is not a failure.

<sub>[stdlib/Net.sl:610](../../stdlib/Net.sl#L610)</sub>

#### SetNoDelay *method*

```
SocketError SetNoDelay(bool on)
```

Turns off Nagle's algorithm, so a small write goes out now rather than
waiting to be joined by the next one.

<sub>[stdlib/Net.sl:617](../../stdlib/Net.sl#L617)</sub>

#### SetReuseAddress *method*

```
SocketError SetReuseAddress(bool on)
```

Lets a listener take a port that connections in TIME_WAIT still hold,
which is what a server restarting wants.

A no-op on Windows, deliberately: SO_REUSEADDR there lets a second
process steal a port another is actively listening on, which is a
different and much worse thing to ask for. Windows already allows the
TIME_WAIT case without being asked.

<sub>[stdlib/Net.sl:629](../../stdlib/Net.sl#L629)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets a datagram socket send to a broadcast address. Off by default,
and meaningless on a stream socket.

<sub>[stdlib/Net.sl:636](../../stdlib/Net.sl#L636)</sub>

#### SetKeepAlive *method*

```
SocketError SetKeepAlive(bool on)
```

Asks the system to probe an idle connection, so a peer that vanished
without closing is eventually noticed. The interval is the platform's
and is measured in hours by default, so this detects a dead peer rather
than a slow one.

<sub>[stdlib/Net.sl:645](../../stdlib/Net.sl#L645)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long a read waits before giving up. Zero is forever.

<sub>[stdlib/Net.sl:651](../../stdlib/Net.sl#L651)</sub>

#### SetSendTimeout *method*

```
SocketError SetSendTimeout(int milliseconds)
```

How long a send waits before giving up. Zero is forever.

<sub>[stdlib/Net.sl:657](../../stdlib/Net.sl#L657)</sub>

#### Shutdown *method*

```
SocketError Shutdown(SocketShutdown how)
```

Finishes one direction, or both. The other end sees an ending rather
than a reset, which is the difference between this and closing.

<sub>[stdlib/Net.sl:664](../../stdlib/Net.sl#L664)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits until there is something to read, the time runs out, or it fails.
A negative wait is forever.

<sub>[stdlib/Net.sl:678](../../stdlib/Net.sl#L678)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits until there is room to write. On a socket that is connecting
without blocking, this is also how the connection finishing is seen.

<sub>[stdlib/Net.sl:682](../../stdlib/Net.sl#L682)</sub>

### SocketError *enum*

```
enum SocketError
```

Why an operation did not work. `None` is success.

These are the distinctions a program can act on rather than the platform's
whole list, for the reason `IOError` gives: the values are the same
everywhere, and neither `errno` nor a WSA code is.

<sub>[stdlib/Net.sl:91](../../stdlib/Net.sl#L91)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/Net.sl:94](../../stdlib/Net.sl#L94)</sub>

#### WouldBlock *case*

```
WouldBlock = 1
```

Nothing to read, or no room to write, on a socket that is not blocking.
Not a failure -- it is what a non-blocking socket says instead of
waiting.

<sub>[stdlib/Net.sl:99](../../stdlib/Net.sl#L99)</sub>

#### Refused *case*

```
Refused = 2
```

Nothing is listening there.

<sub>[stdlib/Net.sl:102](../../stdlib/Net.sl#L102)</sub>

#### TimedOut *case*

```
TimedOut = 3
```

A timeout set on the socket ran out before the call finished.

<sub>[stdlib/Net.sl:105](../../stdlib/Net.sl#L105)</sub>

#### Unreachable *case*

```
Unreachable = 4
```

No route to that address.

<sub>[stdlib/Net.sl:107](../../stdlib/Net.sl#L107)</sub>

#### AddressInUse *case*

```
AddressInUse = 5
```

Something else already has that port.

<sub>[stdlib/Net.sl:110](../../stdlib/Net.sl#L110)</sub>

#### NotConnected *case*

```
NotConnected = 6
```

An operation that needs a connection, on a socket that has none.

<sub>[stdlib/Net.sl:113](../../stdlib/Net.sl#L113)</sub>

#### Reset *case*

```
Reset = 7
```

The peer went away without closing: a reset rather than an ending.

<sub>[stdlib/Net.sl:116](../../stdlib/Net.sl#L116)</sub>

#### Closed *case*

```
Closed = 8
```

The socket was closed before the call.

<sub>[stdlib/Net.sl:119](../../stdlib/Net.sl#L119)</sub>

#### Interrupted *case*

```
Interrupted = 9
```

A signal arrived mid-call. Retrying is usually right.

<sub>[stdlib/Net.sl:121](../../stdlib/Net.sl#L121)</sub>

#### AccessDenied *case*

```
AccessDenied = 10
```

Not permitted -- a low port without the privilege for it, or a
broadcast send on a socket that was not asked to allow one.

<sub>[stdlib/Net.sl:124](../../stdlib/Net.sl#L124)</sub>

#### NoName *case*

```
NoName = 11
```

The name did not resolve.

<sub>[stdlib/Net.sl:127](../../stdlib/Net.sl#L127)</sub>

#### Invalid *case*

```
Invalid = 12
```

The request made no sense for this socket in this state.

<sub>[stdlib/Net.sl:130](../../stdlib/Net.sl#L130)</sub>

#### Unknown *case*

```
Unknown = 13
```

The platform said something this enum has no name for.

<sub>[stdlib/Net.sl:132](../../stdlib/Net.sl#L132)</sub>

### SocketKind *enum*

```
enum SocketKind
```

Which of the two shapes a socket has.

<sub>[stdlib/Net.sl:153](../../stdlib/Net.sl#L153)</sub>

#### Stream *case*

```
Stream = 1
```

TCP: a stream, ordered and reliable, with no message boundaries.

<sub>[stdlib/Net.sl:156](../../stdlib/Net.sl#L156)</sub>

#### Datagram *case*

```
Datagram = 2
```

UDP: datagrams, each whole or absent, in no particular order.

<sub>[stdlib/Net.sl:159](../../stdlib/Net.sl#L159)</sub>

### SocketShutdown *enum*

```
enum SocketShutdown
```

Which half of a connection to finish.

<sub>[stdlib/Net.sl:163](../../stdlib/Net.sl#L163)</sub>

#### Receive *case*

```
Receive = 0
```

Stop receiving. The peer can still be written to.

<sub>[stdlib/Net.sl:166](../../stdlib/Net.sl#L166)</sub>

#### Send *case*

```
Send = 1
```

Stop sending, which is what tells the peer there is no more coming.

<sub>[stdlib/Net.sl:168](../../stdlib/Net.sl#L168)</sub>

#### Both *case*

```
Both = 2
```

Stop both, which is what `Close` does first.

<sub>[stdlib/Net.sl:170](../../stdlib/Net.sl#L170)</sub>

### TcpClient *class*

```
class TcpClient : IStream
```

One TCP connection, and an `IStream`.

Being a stream is the point: a reader written against a file works over a
connection with nothing changed. `CanSeek` is false and `Seek` fails,
because a connection has no position to move to -- which is the honest
answer and the one an `IStream` is built to give.

    var client = try TcpClient.Connect("example.com", 80u);
    client.SendText("GET / HTTP/1.0\r\n\r\n");

The `IOError` an `IStream` reports is the nearest one to the socket error;
`SocketError()` has the exact one, and the two are there together because a
generic reader wants the first and code that knows it is a socket wants the
second.

<sub>[stdlib/Net.sl:866](../../stdlib/Net.sl#L866)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port)
```

Connects to a host and port.

<sub>[stdlib/Net.sl:872](../../stdlib/Net.sl#L872)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port, AddressFamily family)
```

Connects, naming the family rather than letting the resolver choose.

Blocks until the connection is made or refused; there is no timeout
here, and the system's own is measured in tens of seconds.

<sub>[stdlib/Net.sl:881](../../stdlib/Net.sl#L881)</sub>

#### IsConnected *method*

```
bool IsConnected()
```

Whether the connection is there. False after the peer finished, after
`Close`, and if connecting never worked.

<sub>[stdlib/Net.sl:901](../../stdlib/Net.sl#L901)</sub>

#### SocketError *method*

```
SocketError SocketError()
```

The exact reason, which `Error()` rounds off to fit an `IStream`.

<sub>[stdlib/Net.sl:907](../../stdlib/Net.sl#L907)</sub>

#### LocalEndPoint *method*

```
EndPoint LocalEndPoint()
```

This end of the connection -- the address and the port the system
chose for it.

<sub>[stdlib/Net.sl:911](../../stdlib/Net.sl#L911)</sub>

#### RemoteEndPoint *method*

```
EndPoint RemoteEndPoint()
```

The other end: who is connected. What an accepted connection is asked
to find out where it came from.

<sub>[stdlib/Net.sl:915](../../stdlib/Net.sl#L915)</sub>

#### Underlying *method*

```
Socket Underlying()
```

The socket underneath, for an option this does not expose. Closing it
closes the connection.

<sub>[stdlib/Net.sl:919](../../stdlib/Net.sl#L919)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends all of `text`, looping until it has gone.

<sub>[stdlib/Net.sl:922](../../stdlib/Net.sl#L922)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] data)
```

Sends all of `data`.

<sub>[stdlib/Net.sl:925](../../stdlib/Net.sl#L925)</sub>

#### ReceiveAll *method*

```
byte[] ReceiveAll()
```

Reads until the peer finishes, and gives back what arrived.

For a protocol that ends by closing -- HTTP/1.0, or anything behind
`shutdown` -- this is the whole body. For one that does not, it never
returns, which is the caller's to know.

<sub>[stdlib/Net.sl:932](../../stdlib/Net.sl#L932)</sub>

#### ReceiveText *method*

```
String ReceiveText()
```

The same, read as UTF-8. Anything malformed becomes U+FFFD, because the
result is a `String` and a `String` is valid UTF-8 by invariant.

<sub>[stdlib/Net.sl:958](../../stdlib/Net.sl#L958)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for something to read, answering whether
there is. A peer that closed counts as readable -- the read that
follows returns zero, which is how the ending is seen.

<sub>[stdlib/Net.sl:969](../../stdlib/Net.sl#L969)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits up to `milliseconds` for room to write, answering whether there
is. Only interesting once a send has filled the kernel's buffer.

<sub>[stdlib/Net.sl:973](../../stdlib/Net.sl#L973)</sub>

#### CanRead *method*

```
bool CanRead()
```

True while the connection is open and the peer has not finished.

<sub>[stdlib/Net.sl:978](../../stdlib/Net.sl#L978)</sub>

#### CanWrite *method*

```
bool CanWrite()
```

True while the connection is open. A peer that finished sending can
still be written to, until it closes for real.

<sub>[stdlib/Net.sl:982](../../stdlib/Net.sl#L982)</sub>

#### CanSeek *method*

```
bool CanSeek()
```

A connection has no position to move to.

<sub>[stdlib/Net.sl:985](../../stdlib/Net.sl#L985)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many arrived.

Fewer than asked for is normal and not an error: a stream delivers what
has arrived. Zero means the peer finished, and `Error` distinguishes
that from a failure.

<sub>[stdlib/Net.sl:993](../../stdlib/Net.sl#L993)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes up to `count` bytes from `buffer` at `offset`, answering how
many went. A short write is normal; `SendAll` is the one that loops.

<sub>[stdlib/Net.sl:1003](../../stdlib/Net.sl#L1003)</sub>

#### Position *method*

```
long Position()
```

Not a position, and not pretended to be one.

<sub>[stdlib/Net.sl:1009](../../stdlib/Net.sl#L1009)</sub>

#### Length *method*

```
long Length()
```

Not a length either. A connection does not know how much is coming.

<sub>[stdlib/Net.sl:1011](../../stdlib/Net.sl#L1011)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false. There is nowhere to seek to on a connection.

<sub>[stdlib/Net.sl:1014](../../stdlib/Net.sl#L1014)</sub>

#### Flush *method*

```
void Flush()
```

Nothing is buffered here; the kernel decides when bytes leave.

<sub>[stdlib/Net.sl:1017](../../stdlib/Net.sl#L1017)</sub>

#### Close *method*

```
void Close()
```

Ends the connection politely: shuts both directions down first, so the
peer sees an ending rather than a reset, then closes. Idempotent, and
the destructor calls it.

<sub>[stdlib/Net.sl:1022](../../stdlib/Net.sl#L1022)</sub>

#### Error *method*

```
IOError Error()
```

The socket error as the nearest `IOError`, so that a reader which knows
nothing about sockets still gets something it can act on.

<sub>[stdlib/Net.sl:1032](../../stdlib/Net.sl#L1032)</sub>

### TcpListener *class*

```
class TcpListener
```

A socket that accepts connections, and does nothing else.

Opening, binding and listening are one step, because there is no useful
state between them: a listener that exists and is not listening is a thing
to check for and never a thing to want. So the step is `Listen`, and it
says which of the three failed.

    var server = try TcpListener.Listen(8080u);

    var client = server.Accept();
    while (client.IsConnected()) { ... }

<sub>[stdlib/Net.sl:762](../../stdlib/Net.sl#L762)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(ushort port)
```

Listens on every address this machine has.

<sub>[stdlib/Net.sl:768](../../stdlib/Net.sl#L768)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port)
```

Listens on one address. `"127.0.0.1"` is the useful one: a service that
only its own machine should reach says so here rather than in a
firewall.

<sub>[stdlib/Net.sl:776](../../stdlib/Net.sl#L776)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port, AddressFamily family, int backlog)
```

Listens with everything named: the address, the port, the family and
how many connections may queue.

The other two overloads are this one with IPv4 and a backlog of 16.

<sub>[stdlib/Net.sl:785](../../stdlib/Net.sl#L785)</sub>

#### IsListening *method*

```
bool IsListening()
```

Whether it bound and listened. False means the constructor gave up
part-way, and `Error` says where.

<sub>[stdlib/Net.sl:816](../../stdlib/Net.sl#L816)</sub>

#### Error *method*

```
SocketError Error()
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net.sl:819](../../stdlib/Net.sl#L819)</sub>

#### LocalEndPoint *method*

```
EndPoint LocalEndPoint()
```

Where it is listening. With port 0 this is how the port the system
chose is found out.

<sub>[stdlib/Net.sl:823](../../stdlib/Net.sl#L823)</sub>

#### Underlying *method*

```
Socket Underlying()
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net.sl:826](../../stdlib/Net.sl#L826)</sub>

#### Accept *method*

```
TcpClient Accept()
```

Waits for a connection. The client that comes back is connected, or is
not and says why.

<sub>[stdlib/Net.sl:830](../../stdlib/Net.sl#L830)</sub>

#### Pending *method*

```
bool Pending(int milliseconds)
```

Whether a connection is waiting, without blocking to find out.

<sub>[stdlib/Net.sl:836](../../stdlib/Net.sl#L836)</sub>

#### Close *method*

```
void Close()
```

Stops listening and closes the socket. Connections already accepted
are their own sockets and are unaffected.

<sub>[stdlib/Net.sl:843](../../stdlib/Net.sl#L843)</sub>

### UdpSocket *class*

```
class UdpSocket
```

Datagrams.

Not an `IStream`, and that is deliberate. A datagram arrives whole or not
at all, in no particular order, possibly twice; a stream is ordered,
reliable and has no message boundaries at all. Pretending the first is the
second is how a program comes to assume things about UDP that are not true.

    var socket = try UdpSocket.Bind(9000u);
    var from = EndPoint.At("", 0u);
    var buffer = new byte[1500];
    nuint got = socket.Receive(buffer, ref from);

<sub>[stdlib/Net.sl:1062](../../stdlib/Net.sl#L1062)</sub>

#### Datagram *method*

```
static Result<UdpSocket, SocketError> Datagram()
```

A socket that can send and not receive, because nothing bound it.

<sub>[stdlib/Net.sl:1068](../../stdlib/Net.sl#L1068)</sub>

#### Datagram *method*

```
static Result<UdpSocket, SocketError> Datagram(AddressFamily family)
```

The same, in a named family.

<sub>[stdlib/Net.sl:1074](../../stdlib/Net.sl#L1074)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(ushort port)
```

A socket bound to a port, so it can receive. Port 0 asks the system to
choose one, which `LocalEndPoint` will say.

<sub>[stdlib/Net.sl:1084](../../stdlib/Net.sl#L1084)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(String host, ushort port)
```

The same, on one address rather than all of them.

<sub>[stdlib/Net.sl:1090](../../stdlib/Net.sl#L1090)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(String host, ushort port, AddressFamily family)
```

Binds with everything named: the address, the port and the family.

<sub>[stdlib/Net.sl:1096](../../stdlib/Net.sl#L1096)</sub>

#### IsOpen *method*

```
bool IsOpen()
```

Whether the socket is usable. False after `Close`, and after an open
that did not work.

<sub>[stdlib/Net.sl:1121](../../stdlib/Net.sl#L1121)</sub>

#### Error *method*

```
SocketError Error()
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net.sl:1124](../../stdlib/Net.sl#L1124)</sub>

#### LocalEndPoint *method*

```
EndPoint LocalEndPoint()
```

Where it is bound. With port 0 this is how the port the system chose is
found out; an unbound socket answers with nothing useful.

<sub>[stdlib/Net.sl:1128](../../stdlib/Net.sl#L1128)</sub>

#### Underlying *method*

```
Socket Underlying()
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net.sl:1131](../../stdlib/Net.sl#L1131)</sub>

#### Send *method*

```
nuint Send(byte[] data, String host, ushort port)
```

Sends one datagram. The count back is how many bytes went, which for a
datagram is all of them or none.

<sub>[stdlib/Net.sl:1135](../../stdlib/Net.sl#L1135)</sub>

#### SendText *method*

```
nuint SendText(String text, String host, ushort port)
```

Sends one datagram of UTF-8. The encoded length is what goes on the
wire, so a string of multi-byte characters is longer than its character
count -- which matters against the roughly 1500-byte practical limit.

<sub>[stdlib/Net.sl:1143](../../stdlib/Net.sl#L1143)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, ref EndPoint from)
```

Reads one datagram and says where it came from. A datagram longer than
the buffer is truncated, and the rest is gone -- there is no second
read to collect it.

<sub>[stdlib/Net.sl:1151](../../stdlib/Net.sl#L1151)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for a datagram to arrive, answering whether
one has. The way to poll without blocking forever on an empty socket.

<sub>[stdlib/Net.sl:1158](../../stdlib/Net.sl#L1158)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets this socket send to a broadcast address.

<sub>[stdlib/Net.sl:1161](../../stdlib/Net.sl#L1161)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long `Receive` waits before giving up. Zero is forever.

<sub>[stdlib/Net.sl:1164](../../stdlib/Net.sl#L1164)</sub>

#### Close *method*

```
void Close()
```

Closes the socket. Idempotent, and the destructor calls it.

<sub>[stdlib/Net.sl:1170](../../stdlib/Net.sl#L1170)</sub>

## Functions

### Describe *function*

```
String Describe(SocketError error)
```

What went wrong, in words.

<sub>[stdlib/Net.sl:174](../../stdlib/Net.sl#L174)</sub>

### Resolve *function*

```
Result<String, SocketError> Resolve(String host)
```

The first address a name resolves to, as text.

One address rather than the list: a list is only useful to something that
will try each in turn, and that is what connecting already does inside the
runtime, where it can try each socket as well as each address.

<sub>[stdlib/Net.sl:246](../../stdlib/Net.sl#L246)</sub>

### Resolve *function*

```
Result<String, SocketError> Resolve(String host, AddressFamily family)
```

The first address a name resolves to in one family, as text.

`AddressFamily.Any` takes whichever the resolver prefers. Name it when the
socket that will use the address is already one family or the other, since
an IPv6 address cannot be connected to from an IPv4 socket.

<sub>[stdlib/Net.sl:256](../../stdlib/Net.sl#L256)</sub>

