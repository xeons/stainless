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

**Functions** &nbsp; [DescribeSocketError](#describesocketerror-function) &middot; [ResolveHost](#resolvehost-function) &middot; [ResolveHost](#resolvehost-function)

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
`ResolveHost`. There is no socket of no family, so opening one with `Any`
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

<sub>[stdlib/Net.sl:211](../../stdlib/Net.sl#L211)</sub>

#### Host *field*

```
String Host
```

The address or name. An empty host means every address on this machine,
which is what a server binds to.

<sub>[stdlib/Net.sl:215](../../stdlib/Net.sl#L215)</sub>

#### Port *field*

```
ushort Port
```

The port. Zero asks the system to choose one, which `LocalEndPoint`
will then say.

<sub>[stdlib/Net.sl:219](../../stdlib/Net.sl#L219)</sub>

#### Create *method*

```
static EndPoint Create(String host, ushort port)
```

An endpoint, made in one expression.

<sub>[stdlib/Net.sl:222](../../stdlib/Net.sl#L222)</sub>

#### Format *method*

```
String Format()
```

Written the way one is written.

<sub>[stdlib/Net.sl:231](../../stdlib/Net.sl#L231)</sub>

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

<sub>[stdlib/Net.sl:297](../../stdlib/Net.sl#L297)</sub>

#### Open *method*

```
static Result<Socket, SocketError> Open(AddressFamily family, SocketKind kind)
```

A socket of a given family and kind, unbound and unconnected.

**Fails with**

- [SocketError.Invalid](#invalid-case) — `AddressFamily.Any`, which is a question for a resolver rather than a family a socket can have
- [SocketError.Unknown](#unknown-case) — the platform refused a socket -- out of descriptors, among others

**See also** &nbsp; [Socket.OpenConnected](#openconnected-method)

<sub>[stdlib/Net.sl:313](../../stdlib/Net.sl#L313)</sub>

#### OpenConnected *method*

```
static Result<Socket, SocketError> OpenConnected(String host, ushort port, AddressFamily family, SocketKind kind)
```

A socket already connected to a host and port.

One step, because connecting is what decides the family: a caller with
a name does not know whether it will get IPv4 or IPv6, so it cannot
open first.

**Fails with**

- [SocketError.NoName](#noname-case) — the host did not resolve
- [SocketError.Refused](#refused-case) — nothing is listening there
- [SocketError.TimedOut](#timedout-case) — no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) — no route to any of them
- [SocketError.Unknown](#unknown-case) — the last address failed for a reason with no case of its own

**See also** &nbsp; [Socket.Connect](#connect-method)

<sub>[stdlib/Net.sl:335](../../stdlib/Net.sl#L335)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the handle is still live. False before a failed open and after
`Close`; it says nothing about whether the peer is still there, which
only a read can find out.

<sub>[stdlib/Net.sl:400](../../stdlib/Net.sl#L400)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error, or `None`. Set by every call that failed, and cleared
by the next one that did not.

<sub>[stdlib/Net.sl:404](../../stdlib/Net.sl#L404)</sub>

#### Family *property*

```
AddressFamily Family { get; }
```

Which family the socket was opened for. Fixed at open.

<sub>[stdlib/Net.sl:407](../../stdlib/Net.sl#L407)</sub>

#### Kind *property*

```
SocketKind Kind { get; }
```

Stream or datagram. Fixed at open.

<sub>[stdlib/Net.sl:410](../../stdlib/Net.sl#L410)</sub>

#### Handle *property*

```
nuint Handle { get; }
```

The handle itself, for a platform call this wrapper does not make.
A `SOCKET` on Windows and a file descriptor on everything else.

<sub>[stdlib/Net.sl:414](../../stdlib/Net.sl#L414)</sub>

#### Close *method*

```
void Close()
```

Closes the handle. Idempotent, and the destructor calls it, so a
socket that goes out of scope is not leaked.

Closing a stream socket without `Shutdown` first leaves what the peer
sees up to the platform and to what is still unread; `TcpClient.Close`
shuts both directions down first, which is what ends one politely.

<sub>[stdlib/Net.sl:422](../../stdlib/Net.sl#L422)</sub>

#### Bind *method*

```
SocketError Bind(String host, ushort port)
```

Takes the address, and the port. Port 0 asks the system to choose one,
which `LocalEndPoint` will then say.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.NoName](#noname-case) — the host did not resolve
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port, or this machine has no such address
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.Listen](#listen-method)

<sub>[stdlib/Net.sl:444](../../stdlib/Net.sl#L444)</sub>

#### BindAny *method*

```
SocketError BindAny(ushort port)
```

Binds to every address on this machine, which is what a server wants
and what an empty host means to the resolver.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.Bind](#bind-method)

<sub>[stdlib/Net.sl:463](../../stdlib/Net.sl#L463)</sub>

#### Listen *method*

```
SocketError Listen(int backlog)
```

Starts accepting connections. `backlog` is how many may wait before
the system refuses more; the platform may cap it lower than asked.

Bind first -- listening on a socket that was never bound fails.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Invalid](#invalid-case) — the socket was never bound, or is a datagram socket, which has nothing to listen for
- [SocketError.AddressInUse](#addressinuse-case) — another socket is already listening on that address
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.Bind](#bind-method) &middot; [Socket.Accept](#accept-method)

<sub>[stdlib/Net.sl:480](../../stdlib/Net.sl#L480)</sub>

#### Accept *method*

```
Socket Accept()
```

Waits for a connection. The socket that comes back is open, or is not
and says why.

<sub>[stdlib/Net.sl:492](../../stdlib/Net.sl#L492)</sub>

#### Connect *method*

```
SocketError Connect(String host, ushort port)
```

Connects a socket that is already open.

Only the first address of this socket's family is tried, because a
socket whose connect failed cannot be used for a second attempt and
this one is already made. `Socket.OpenConnected` is the form that tries
them all, and the one a client should reach for.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.NoName](#noname-case) — the host did not resolve in this socket's family
- [SocketError.WouldBlock](#wouldblock-case) — a socket that does not block, where the connection is still being made; `WaitToWrite` is how it finishes
- [SocketError.Refused](#refused-case) — nothing is listening there
- [SocketError.TimedOut](#timedout-case) — no answer from that address
- [SocketError.Unreachable](#unreachable-case) — no route to it
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.OpenConnected](#openconnected-method)

<sub>[stdlib/Net.sl:525](../../stdlib/Net.sl#L525)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

This end of the connection.

<sub>[stdlib/Net.sl:536](../../stdlib/Net.sl#L536)</sub>

#### RemoteEndPoint *property*

```
EndPoint RemoteEndPoint { get; }
```

The other end.

<sub>[stdlib/Net.sl:539](../../stdlib/Net.sl#L539)</sub>

#### Send *method*

```
nuint Send(byte[] buffer, nuint offset, nuint count)
```

Sends up to `count` bytes and reports how many went.

Fewer than asked for is normal on a stream: the kernel took what fitted
in its buffer. A loop over what is left is the caller's job, or
`SendAll` is.

**Parameters**

- `buffer` — where the bytes come from
- `offset` — where in it to start
- `count` — how many to send from there

**See also** &nbsp; [Socket.SendAll](#sendall-method) &middot; [Socket.Receive](#receive-method)

<sub>[stdlib/Net.sl:554](../../stdlib/Net.sl#L554)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] buffer)
```

Sends all of it, or says why it could not.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) — the socket has no peer to send to
- [SocketError.Reset](#reset-case) — the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) — a send timeout ran out
- [SocketError.WouldBlock](#wouldblock-case) — a socket that does not block, with no room left for the rest
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.Send](#send-method)

<sub>[stdlib/Net.sl:587](../../stdlib/Net.sl#L587)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) — the socket has no peer to send to
- [SocketError.Reset](#reset-case) — the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) — a send timeout ran out
- [SocketError.WouldBlock](#wouldblock-case) — a socket that does not block, with no room left for the rest
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.SendAll](#sendall-method)

<sub>[stdlib/Net.sl:613](../../stdlib/Net.sl#L613)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes and reports how many arrived. Zero is the
peer having finished, which is an ending rather than an error -- ask
`Error` to tell the two apart.

**Parameters**

- `buffer` — where the bytes go
- `offset` — where in it to start writing them
- `count` — how many to make room for

**See also** &nbsp; [Socket.Send](#send-method)

<sub>[stdlib/Net.sl:642](../../stdlib/Net.sl#L642)</sub>

#### SendTo *method*

```
nuint SendTo(byte[] buffer, EndPoint target)
```

Sends one datagram. It arrives whole or not at all.

**See also** &nbsp; [Socket.ReceiveFrom](#receivefrom-method)

<sub>[stdlib/Net.sl:668](../../stdlib/Net.sl#L668)</sub>

#### ReceiveFrom *method*

```
nuint ReceiveFrom(byte[] buffer, ref EndPoint from)
```

Reads one datagram, and says where it came from.

A datagram longer than the buffer is truncated and the rest is gone,
which is what a datagram is: there is no second read to get the rest of
one. The count is what fitted, and it is not an error.

When the read fails, `from` is an empty host and port 0.

**Parameters**

- `buffer` — where the datagram goes, from its first byte
- `from` — filled in with where it came from

**See also** &nbsp; [Socket.SendTo](#sendto-method)

<sub>[stdlib/Net.sl:695](../../stdlib/Net.sl#L695)</sub>

#### SetBlocking *method*

```
SocketError SetBlocking(bool blocking)
```

Whether a call waits. A socket that does not block answers
`WouldBlock` instead of waiting, which is not a failure.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the change

<sub>[stdlib/Net.sl:724](../../stdlib/Net.sl#L724)</sub>

#### SetNoDelay *method*

```
SocketError SetNoDelay(bool on)
```

Turns off Nagle's algorithm, so a small write goes out now rather than
waiting to be joined by the next one.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option -- a datagram socket has no Nagle to turn off

<sub>[stdlib/Net.sl:735](../../stdlib/Net.sl#L735)</sub>

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

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

<sub>[stdlib/Net.sl:750](../../stdlib/Net.sl#L750)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets a datagram socket send to a broadcast address. Off by default,
and meaningless on a stream socket.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option, which is what a stream socket does with it

<sub>[stdlib/Net.sl:761](../../stdlib/Net.sl#L761)</sub>

#### SetKeepAlive *method*

```
SocketError SetKeepAlive(bool on)
```

Asks the system to probe an idle connection, so a peer that vanished
without closing is eventually noticed. The interval is the platform's
and is measured in hours by default, so this detects a dead peer rather
than a slow one.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

<sub>[stdlib/Net.sl:773](../../stdlib/Net.sl#L773)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long a read waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

**See also** &nbsp; [Socket.SetSendTimeout](#setsendtimeout-method)

<sub>[stdlib/Net.sl:783](../../stdlib/Net.sl#L783)</sub>

#### SetSendTimeout *method*

```
SocketError SetSendTimeout(int milliseconds)
```

How long a send waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

**See also** &nbsp; [Socket.SetReceiveTimeout](#setreceivetimeout-method)

<sub>[stdlib/Net.sl:793](../../stdlib/Net.sl#L793)</sub>

#### Shutdown *method*

```
SocketError Shutdown(SocketShutdown how)
```

Finishes one direction, or both. The other end sees an ending rather
than a reset, which is the difference between this and closing.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.NotConnected](#notconnected-case) — there is no connection to finish
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [Socket.Close](#close-method)

<sub>[stdlib/Net.sl:806](../../stdlib/Net.sl#L806)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits until there is something to read, the time runs out, or it fails.
A negative wait is forever.

<sub>[stdlib/Net.sl:820](../../stdlib/Net.sl#L820)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits until there is room to write. On a socket that is connecting
without blocking, this is also how the connection finishing is seen:
a connect that failed answers false, and `Error` says why.

<sub>[stdlib/Net.sl:825](../../stdlib/Net.sl#L825)</sub>

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
`SocketErrorCode` has the exact one, and the two are there together because a
generic reader wants the first and code that knows it is a socket wants the
second.

<sub>[stdlib/Net.sl:1054](../../stdlib/Net.sl#L1054)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port)
```

Connects to a host and port.

**Fails with**

- [SocketError.NoName](#noname-case) — the host did not resolve
- [SocketError.Refused](#refused-case) — nothing is listening there
- [SocketError.TimedOut](#timedout-case) — no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) — no route to any of them
- [SocketError.Unknown](#unknown-case) — the last address failed for a reason with no case of its own

**See also** &nbsp; [TcpListener.Accept](#accept-method)

<sub>[stdlib/Net.sl:1069](../../stdlib/Net.sl#L1069)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port, AddressFamily family)
```

Connects, naming the family rather than letting the resolver choose.

Blocks until the connection is made or refused; there is no timeout
here, and the system's own is measured in tens of seconds.

**Parameters**

- `host` — the name or address to reach
- `port` — the port to reach it on
- `family` — which family to resolve the name in

**Fails with**

- [SocketError.NoName](#noname-case) — the host did not resolve in that family
- [SocketError.Refused](#refused-case) — nothing is listening there
- [SocketError.TimedOut](#timedout-case) — no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) — no route to any of them
- [SocketError.Unknown](#unknown-case) — the last address failed for a reason with no case of its own

<sub>[stdlib/Net.sl:1090](../../stdlib/Net.sl#L1090)</sub>

#### IsConnected *property*

```
bool IsConnected { get; }
```

Whether the connection is there. False after the peer finished, after
`Close`, and if connecting never worked.

<sub>[stdlib/Net.sl:1110](../../stdlib/Net.sl#L1110)</sub>

#### SocketErrorCode *property*

```
SocketError SocketErrorCode { get; }
```

The exact reason, which `Error` rounds off to fit an `IStream`.

<sub>[stdlib/Net.sl:1119](../../stdlib/Net.sl#L1119)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

This end of the connection -- the address and the port the system
chose for it.

<sub>[stdlib/Net.sl:1123](../../stdlib/Net.sl#L1123)</sub>

#### RemoteEndPoint *property*

```
EndPoint RemoteEndPoint { get; }
```

The other end: who is connected. What an accepted connection is asked
to find out where it came from.

<sub>[stdlib/Net.sl:1127](../../stdlib/Net.sl#L1127)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose. Closing it
closes the connection.

<sub>[stdlib/Net.sl:1131](../../stdlib/Net.sl#L1131)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends all of `text`, looping until it has gone.

**Fails with**

- [SocketError.Closed](#closed-case) — the connection was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) — the connection was never made
- [SocketError.Reset](#reset-case) — the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) — a send timeout ran out
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [TcpClient.SendAll](#sendall-method)

<sub>[stdlib/Net.sl:1144](../../stdlib/Net.sl#L1144)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] data)
```

Sends all of `data`.

**Fails with**

- [SocketError.Closed](#closed-case) — the connection was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) — the connection was never made
- [SocketError.Reset](#reset-case) — the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) — a send timeout ran out
- [SocketError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [TcpClient.SendText](#sendtext-method)

<sub>[stdlib/Net.sl:1157](../../stdlib/Net.sl#L1157)</sub>

#### ReceiveAll *method*

```
byte[] ReceiveAll()
```

Reads until the peer finishes, and gives back what arrived.

For a protocol that ends by closing -- HTTP/1.0, or anything behind
`shutdown` -- this is the whole body. For one that does not, it never
returns, which is the caller's to know.

<sub>[stdlib/Net.sl:1164](../../stdlib/Net.sl#L1164)</sub>

#### ReceiveText *method*

```
String ReceiveText()
```

The same, read as UTF-8. Anything malformed becomes U+FFFD, because the
result is a `String` and a `String` is valid UTF-8 by invariant.

<sub>[stdlib/Net.sl:1190](../../stdlib/Net.sl#L1190)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for something to read, answering whether
there is. A peer that closed counts as readable -- the read that
follows returns zero, which is how the ending is seen.

<sub>[stdlib/Net.sl:1201](../../stdlib/Net.sl#L1201)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits up to `milliseconds` for room to write, answering whether there
is. Only interesting once a send has filled the kernel's buffer.

<sub>[stdlib/Net.sl:1205](../../stdlib/Net.sl#L1205)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while the connection is open and the peer has not finished.

<sub>[stdlib/Net.sl:1210](../../stdlib/Net.sl#L1210)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while the connection is open. A peer that finished sending can
still be written to, until it closes for real.

<sub>[stdlib/Net.sl:1214](../../stdlib/Net.sl#L1214)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

A connection has no position to move to.

<sub>[stdlib/Net.sl:1217](../../stdlib/Net.sl#L1217)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many arrived.

Fewer than asked for is normal and not an error: a stream delivers what
has arrived. Zero means the peer finished, and `Error` distinguishes
that from a failure.

<sub>[stdlib/Net.sl:1225](../../stdlib/Net.sl#L1225)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes up to `count` bytes from `buffer` at `offset`, answering how
many went. A short write is normal; `SendAll` is the one that loops.

<sub>[stdlib/Net.sl:1238](../../stdlib/Net.sl#L1238)</sub>

#### Position *property*

```
long Position { get; }
```

Not a position, and not pretended to be one.

<sub>[stdlib/Net.sl:1244](../../stdlib/Net.sl#L1244)</sub>

#### Length *property*

```
long Length { get; }
```

Not a length either. A connection does not know how much is coming.

<sub>[stdlib/Net.sl:1246](../../stdlib/Net.sl#L1246)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false. There is nowhere to seek to on a connection.

<sub>[stdlib/Net.sl:1249](../../stdlib/Net.sl#L1249)</sub>

#### Flush *method*

```
void Flush()
```

Nothing is buffered here; the kernel decides when bytes leave.

<sub>[stdlib/Net.sl:1252](../../stdlib/Net.sl#L1252)</sub>

#### Close *method*

```
void Close()
```

Ends the connection politely: shuts both directions down first, so the
peer sees an ending rather than a reset, then closes. Idempotent, and
the destructor calls it.

<sub>[stdlib/Net.sl:1257](../../stdlib/Net.sl#L1257)</sub>

#### Error *property*

```
IOError Error { get; }
```

The socket error as the nearest `IOError`, so that a reader which knows
nothing about sockets still gets something it can act on.

<sub>[stdlib/Net.sl:1267](../../stdlib/Net.sl#L1267)</sub>

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
    while (client.IsConnected) { ... }

<sub>[stdlib/Net.sl:921](../../stdlib/Net.sl#L921)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(ushort port)
```

Listens on every address this machine has.

**Fails with**

- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net.sl:933](../../stdlib/Net.sl#L933)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port)
```

Listens on one address. `"127.0.0.1"` is the useful one: a service that
only its own machine should reach says so here rather than in a
firewall.

**Fails with**

- [SocketError.NoName](#noname-case) — the host did not resolve, or is not an address this machine has
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net.sl:949](../../stdlib/Net.sl#L949)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port, AddressFamily family, int backlog)
```

Listens with everything named: the address, the port, the family and
how many connections may queue.

The other two overloads are this one with IPv4 and a backlog of 16.

**Parameters**

- `host` — which address to take, empty for every one of them
- `port` — which port to take, 0 to be given one
- `family` — which family to listen in
- `backlog` — how many connections may queue before the system refuses more

**Fails with**

- [SocketError.Invalid](#invalid-case) — `AddressFamily.Any`, which no socket can be opened in
- [SocketError.NoName](#noname-case) — the host did not resolve in that family
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net.sl:973](../../stdlib/Net.sl#L973)</sub>

#### IsListening *property*

```
bool IsListening { get; }
```

Whether it bound and listened. False means the constructor gave up
part-way, and `Error` says where.

<sub>[stdlib/Net.sl:1004](../../stdlib/Net.sl#L1004)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net.sl:1007](../../stdlib/Net.sl#L1007)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

Where it is listening. With port 0 this is how the port the system
chose is found out.

<sub>[stdlib/Net.sl:1011](../../stdlib/Net.sl#L1011)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net.sl:1014](../../stdlib/Net.sl#L1014)</sub>

#### Accept *method*

```
TcpClient Accept()
```

Waits for a connection. The client that comes back is connected, or is
not and says why.

<sub>[stdlib/Net.sl:1018](../../stdlib/Net.sl#L1018)</sub>

#### Pending *method*

```
bool Pending(int milliseconds)
```

Whether a connection is waiting, without blocking to find out.

<sub>[stdlib/Net.sl:1024](../../stdlib/Net.sl#L1024)</sub>

#### Close *method*

```
void Close()
```

Stops listening and closes the socket. Connections already accepted
are their own sockets and are unaffected.

<sub>[stdlib/Net.sl:1031](../../stdlib/Net.sl#L1031)</sub>

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
    var from = EndPoint.Create("", 0u);
    var buffer = new byte[1500];
    nuint got = socket.Receive(buffer, ref from);

<sub>[stdlib/Net.sl:1300](../../stdlib/Net.sl#L1300)</sub>

#### Create *method*

```
static Result<UdpSocket, SocketError> Create()
```

A socket that can send and not receive, because nothing bound it.

**Fails with**

- [SocketError.Unknown](#unknown-case) — the platform refused a socket -- out of descriptors, among others

**See also** &nbsp; [UdpSocket.Bind](#bind-method)

<sub>[stdlib/Net.sl:1310](../../stdlib/Net.sl#L1310)</sub>

#### Create *method*

```
static Result<UdpSocket, SocketError> Create(AddressFamily family)
```

The same, in a named family.

**Fails with**

- [SocketError.Invalid](#invalid-case) — `AddressFamily.Any`, which no socket can be opened in
- [SocketError.Unknown](#unknown-case) — the platform refused a socket

<sub>[stdlib/Net.sl:1320](../../stdlib/Net.sl#L1320)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(ushort port)
```

A socket bound to a port, so it can receive. Port 0 asks the system to
choose one, which `LocalEndPoint` will say.

**Fails with**

- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open or the bind failed for a reason with no case of its own

**See also** &nbsp; [UdpSocket.Create](#create-method)

<sub>[stdlib/Net.sl:1336](../../stdlib/Net.sl#L1336)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(String host, ushort port)
```

The same, on one address rather than all of them.

**Fails with**

- [SocketError.NoName](#noname-case) — the host did not resolve, or is not an address this machine has
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open or the bind failed for a reason with no case of its own

<sub>[stdlib/Net.sl:1349](../../stdlib/Net.sl#L1349)</sub>

#### Bind *method*

```
static Result<UdpSocket, SocketError> Bind(String host, ushort port, AddressFamily family)
```

Binds with everything named: the address, the port and the family.

**Parameters**

- `host` — which address to take, empty for every one of them
- `port` — which port to take, 0 to be given one
- `family` — which family to bind in

**Fails with**

- [SocketError.Invalid](#invalid-case) — `AddressFamily.Any`, which no socket can be opened in
- [SocketError.NoName](#noname-case) — the host did not resolve in that family
- [SocketError.AddressInUse](#addressinuse-case) — something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) — a port this process may not take
- [SocketError.Unknown](#unknown-case) — the open or the bind failed for a reason with no case of its own

<sub>[stdlib/Net.sl:1367](../../stdlib/Net.sl#L1367)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the socket is usable. False after `Close`, and after an open
that did not work.

<sub>[stdlib/Net.sl:1392](../../stdlib/Net.sl#L1392)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net.sl:1395](../../stdlib/Net.sl#L1395)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

Where it is bound. With port 0 this is how the port the system chose is
found out; an unbound socket answers with nothing useful.

<sub>[stdlib/Net.sl:1399](../../stdlib/Net.sl#L1399)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net.sl:1402](../../stdlib/Net.sl#L1402)</sub>

#### Send *method*

```
nuint Send(byte[] data, String host, ushort port)
```

Sends one datagram. The count back is how many bytes went, which for a
datagram is all of them or none.

<sub>[stdlib/Net.sl:1406](../../stdlib/Net.sl#L1406)</sub>

#### SendText *method*

```
nuint SendText(String text, String host, ushort port)
```

Sends one datagram of UTF-8. The encoded length is what goes on the
wire, so a string of multi-byte characters is longer than its character
count -- which matters against the roughly 1500-byte practical limit.

<sub>[stdlib/Net.sl:1414](../../stdlib/Net.sl#L1414)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, ref EndPoint from)
```

Reads one datagram and says where it came from. A datagram longer than
the buffer is truncated, and the rest is gone -- there is no second
read to collect it.

<sub>[stdlib/Net.sl:1422](../../stdlib/Net.sl#L1422)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for a datagram to arrive, answering whether
one has. The way to poll without blocking forever on an empty socket.

<sub>[stdlib/Net.sl:1429](../../stdlib/Net.sl#L1429)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets this socket send to a broadcast address.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

<sub>[stdlib/Net.sl:1435](../../stdlib/Net.sl#L1435)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long `Receive` waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) — the socket was closed before the call
- [SocketError.Unknown](#unknown-case) — the platform refused the option

<sub>[stdlib/Net.sl:1441](../../stdlib/Net.sl#L1441)</sub>

#### Close *method*

```
void Close()
```

Closes the socket. Idempotent, and the destructor calls it.

<sub>[stdlib/Net.sl:1447](../../stdlib/Net.sl#L1447)</sub>

## Functions

### DescribeSocketError *function*

```
String DescribeSocketError(SocketError error)
```

What went wrong, in words.

**See also** &nbsp; [SocketError](#socketerror-enum)

<sub>[stdlib/Net.sl:176](../../stdlib/Net.sl#L176)</sub>

### ResolveHost *function*

```
Result<String, SocketError> ResolveHost(String host)
```

The first address a name resolves to, as text.

One address rather than the list: a list is only useful to something that
will try each in turn, and that is what connecting already does inside the
runtime, where it can try each socket as well as each address.

**Fails with**

- [SocketError.NoName](#noname-case) — the name did not resolve, or resolved to an address the platform would not write out
- [SocketError.Unknown](#unknown-case) — the platform's networking could not be started

<sub>[stdlib/Net.sl:252](../../stdlib/Net.sl#L252)</sub>

### ResolveHost *function*

```
Result<String, SocketError> ResolveHost(String host, AddressFamily family)
```

The first address a name resolves to in one family, as text.

`AddressFamily.Any` takes whichever the resolver prefers. Name it when the
socket that will use the address is already one family or the other, since
an IPv6 address cannot be connected to from an IPv4 socket.

**Parameters**

- `host` — the name or literal address to look up
- `family` — which family to take an address from

**Fails with**

- [SocketError.NoName](#noname-case) — the name did not resolve in that family, or resolved to an address the platform would not write out
- [SocketError.Unknown](#unknown-case) — the platform's networking could not be started

<sub>[stdlib/Net.sl:269](../../stdlib/Net.sl#L269)</sub>

