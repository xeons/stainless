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
  UdpClient     datagrams, which are not a stream and are not pretended to be
  Socket        the one underneath, for anything the three do not cover

`TcpClient` being an `IStream` is the point of the design. A reader written
against a file works over a connection with nothing changed, because there
was never anything file-shaped in it.

## Contents

**Types** &nbsp; [AddressFamily](#addressfamily-enum) &middot; [EndPoint](#endpoint-struct) &middot; [Socket](#socket-class) &middot; [SocketError](#socketerror-enum) &middot; [SocketShutdown](#socketshutdown-enum) &middot; [SocketType](#sockettype-enum) &middot; [TcpClient](#tcpclient-class) &middot; [TcpListener](#tcplistener-class) &middot; [UdpClient](#udpclient-class)

**Functions** &nbsp; [DescribeSocketError](#describesocketerror-function) &middot; [ResolveHost](#resolvehost-function) &middot; [ResolveHost](#resolvehost-function)

## Types

### AddressFamily *enum*

```
enum AddressFamily
```

Which internet protocol.

<sub>[stdlib/Net/AddressFamily.sl:29](../../stdlib/Net/AddressFamily.sl#L29)</sub>

#### Any *case*

```
Any = 0
```

Whichever the name resolves to.

Only meaningful where a name is being resolved: connecting to one, or
`ResolveHost`. There is no socket of no family, so opening one with `Any`
is `SocketError.Invalid` -- which is what Linux says and Windows
quietly does not, handing back an IPv4 socket instead.

<sub>[stdlib/Net/AddressFamily.sl:37](../../stdlib/Net/AddressFamily.sl#L37)</sub>

#### IPv4 *case*

```
IPv4 = 4
```

IPv4 only.

<sub>[stdlib/Net/AddressFamily.sl:39](../../stdlib/Net/AddressFamily.sl#L39)</sub>

#### IPv6 *case*

```
IPv6 = 6
```

IPv6 only. Whether it also accepts IPv4 is the platform's default,
not something set here.

<sub>[stdlib/Net/AddressFamily.sl:42](../../stdlib/Net/AddressFamily.sl#L42)</sub>

### EndPoint *struct*

```
struct EndPoint
```

A host and a port, together, because they always travel together.

A struct rather than a class: it holds a `String`, so copying it retains --
which is fine, and is why it cannot cross `extern "C"` (§7.6). Nothing here
needs it to.

<sub>[stdlib/Net/EndPoint.sl:35](../../stdlib/Net/EndPoint.sl#L35)</sub>

#### Host *field*

```
String Host
```

The address or name. An empty host means every address on this machine,
which is what a server binds to.

<sub>[stdlib/Net/EndPoint.sl:39](../../stdlib/Net/EndPoint.sl#L39)</sub>

#### Port *field*

```
ushort Port
```

The port. Zero asks the system to choose one, which `LocalEndPoint`
will then say.

<sub>[stdlib/Net/EndPoint.sl:43](../../stdlib/Net/EndPoint.sl#L43)</sub>

#### Create *method*

```
static EndPoint Create(String host, ushort port)
```

An endpoint, made in one expression.

<sub>[stdlib/Net/EndPoint.sl:46](../../stdlib/Net/EndPoint.sl#L46)</sub>

#### Format *method*

```
String Format()
```

Written the way one is written.

<sub>[stdlib/Net/EndPoint.sl:55](../../stdlib/Net/EndPoint.sl#L55)</sub>

### Socket *class*

```
class Socket
```

One socket, and nothing above it.

`TcpListener`, `TcpClient` and `UdpClient` are what a program should reach
for; this is what they are made of, and what is left when none of the three
is the shape of the problem.

Made through `Socket.Open`, which returns a `Result`. A constructor has to
return its own type, so it cannot say why an open failed -- the best it
could do is hand back a socket holding nothing, and nothing then forces the
check that would have caught it.

Closing is the destructor's job, so a socket that goes out of scope gives
its handle back whether or not `Close` was called.

<sub>[stdlib/Net/Socket.sl:43](../../stdlib/Net/Socket.sl#L43)</sub>

#### Open *method*

```
static Result<Socket, SocketError> Open(AddressFamily family, SocketType kind)
```

A socket of a given family and kind, unbound and unconnected.

**Fails with**

- [SocketError.Invalid](#invalid-case) -- `AddressFamily.Any`, which is a question for a resolver rather than a family a socket can have
- [SocketError.Unknown](#unknown-case) -- the platform refused a socket -- out of descriptors, among others

**See also** &nbsp; [Socket.OpenConnected](#openconnected-method)

<sub>[stdlib/Net/Socket.sl:59](../../stdlib/Net/Socket.sl#L59)</sub>

#### OpenConnected *method*

```
static Result<Socket, SocketError> OpenConnected(String host, ushort port, AddressFamily family, SocketType kind)
```

A socket already connected to a host and port.

One step, because connecting is what decides the family: a caller with
a name does not know whether it will get IPv4 or IPv6, so it cannot
open first.

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve
- [SocketError.TryAgain](#tryagain-case) -- the resolver could not answer for now
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) -- no route to any of them
- [SocketError.Unknown](#unknown-case) -- the last address failed for a reason with no case of its own

**See also** &nbsp; [Socket.Connect](#connect-method)

<sub>[stdlib/Net/Socket.sl:82](../../stdlib/Net/Socket.sl#L82)</sub>

#### OpenConnected *method*

```
static Result<Socket, SocketError> OpenConnected(String host, ushort port, AddressFamily family, SocketType kind, int timeoutMilliseconds)
```

A socket already connected to a host and port, within a time limit.

Every address the name resolved to is tried in turn until one
connects, and all of them together get `timeoutMilliseconds`. Each
attempt is given an equal share of what is left, so an address that
never answers cannot spend the time the next one needed. The socket
that comes back blocks.

Resolving the name is not bounded: the platform's resolver cannot be.

**Parameters**

- `host` -- the name or address to reach
- `port` -- the port to reach it on
- `family` -- which family to resolve the name in
- `kind` -- stream or datagram
- `timeoutMilliseconds` -- the limit for every attempt together; negative is none

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve
- [SocketError.TryAgain](#tryagain-case) -- the resolver could not answer for now
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- the time ran out, or no answer from any address
- [SocketError.Unreachable](#unreachable-case) -- no route to any of them
- [SocketError.Unknown](#unknown-case) -- the last address failed for a reason with no case of its own

<sub>[stdlib/Net/Socket.sl:112](../../stdlib/Net/Socket.sl#L112)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the handle is still live. False before a failed open and after
`Close`; it says nothing about whether the peer is still there, which
only a read can find out.

<sub>[stdlib/Net/Socket.sl:179](../../stdlib/Net/Socket.sl#L179)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error, or `None`. Set by every call that failed, and cleared
by the next one that did not.

It is the last call's on any thread. A socket used from two threads
at once, one sending while the other receives, MUST take each call's
error from the `Send` and `Receive` forms that hand it back.

<sub>[stdlib/Net/Socket.sl:187](../../stdlib/Net/Socket.sl#L187)</sub>

#### Family *property*

```
AddressFamily Family { get; }
```

Which family the socket was opened for. Fixed at open.

<sub>[stdlib/Net/Socket.sl:190](../../stdlib/Net/Socket.sl#L190)</sub>

#### Kind *property*

```
SocketType Kind { get; }
```

Stream or datagram. Fixed at open.

<sub>[stdlib/Net/Socket.sl:193](../../stdlib/Net/Socket.sl#L193)</sub>

#### Handle *property*

```
nuint Handle { get; }
```

The handle itself, for a platform call this wrapper does not make.
A `SOCKET` on Windows and a file descriptor on everything else.

<sub>[stdlib/Net/Socket.sl:197](../../stdlib/Net/Socket.sl#L197)</sub>

#### Close *method*

```
void Close()
```

Closes the handle. Idempotent, and the destructor calls it, so a
socket that goes out of scope is not leaked.

Closing a stream socket without `Shutdown` first leaves what the peer
sees up to the platform and to what is still unread; `TcpClient.Close`
shuts both directions down first, which is what ends one politely.

<sub>[stdlib/Net/Socket.sl:205](../../stdlib/Net/Socket.sl#L205)</sub>

#### Bind *method*

```
SocketError Bind(String host, ushort port)
```

Takes the address, and the port. Port 0 asks the system to choose one,
which `LocalEndPoint` will then say.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.NoName](#noname-case) -- the host did not resolve
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port, or this machine has no such address
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.Listen](#listen-method)

<sub>[stdlib/Net/Socket.sl:227](../../stdlib/Net/Socket.sl#L227)</sub>

#### BindAny *method*

```
SocketError BindAny(ushort port)
```

Binds to every address on this machine, which is what a server wants
and what an empty host means to the resolver.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.Bind](#bind-method)

<sub>[stdlib/Net/Socket.sl:246](../../stdlib/Net/Socket.sl#L246)</sub>

#### Listen *method*

```
SocketError Listen(int backlog)
```

Starts accepting connections. `backlog` is how many may wait before
the system refuses more; the platform may cap it lower than asked.

Bind first -- listening on a socket that was never bound fails.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Invalid](#invalid-case) -- the socket was never bound, or is a datagram socket, which has nothing to listen for
- [SocketError.AddressInUse](#addressinuse-case) -- another socket is already listening on that address
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.Bind](#bind-method) &middot; [Socket.Accept](#accept-method)

<sub>[stdlib/Net/Socket.sl:263](../../stdlib/Net/Socket.sl#L263)</sub>

#### Accept *method*

```
Socket Accept()
```

Waits for a connection. The socket that comes back is open, or is not
and says why.

The accepted socket blocks, whether or not this one does, and no child
process inherits it.

<sub>[stdlib/Net/Socket.sl:278](../../stdlib/Net/Socket.sl#L278)</sub>

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

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.NoName](#noname-case) -- the host did not resolve in this socket's family
- [SocketError.WouldBlock](#wouldblock-case) -- a socket that does not block, where the connection is still being made; `WaitToWrite` is how it finishes
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- no answer from that address
- [SocketError.Unreachable](#unreachable-case) -- no route to it
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.OpenConnected](#openconnected-method)

<sub>[stdlib/Net/Socket.sl:311](../../stdlib/Net/Socket.sl#L311)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

This end of the connection.

<sub>[stdlib/Net/Socket.sl:322](../../stdlib/Net/Socket.sl#L322)</sub>

#### RemoteEndPoint *property*

```
EndPoint RemoteEndPoint { get; }
```

The other end.

<sub>[stdlib/Net/Socket.sl:325](../../stdlib/Net/Socket.sl#L325)</sub>

#### Send *method*

```
nuint Send(byte[] buffer, nuint offset, nuint count)
```

Sends up to `count` bytes and reports how many went.

Fewer than asked for is normal on a stream: the kernel took what fitted
in its buffer. A loop over what is left is the caller's job, or
`SendAll` is.

**Parameters**

- `buffer` -- where the bytes come from
- `offset` -- where in it to start
- `count` -- how many to send from there

**See also** &nbsp; [Socket.SendAll](#sendall-method) &middot; [Socket.Receive](#receive-method)

<sub>[stdlib/Net/Socket.sl:340](../../stdlib/Net/Socket.sl#L340)</sub>

#### Send *method*

```
nuint Send(byte[] buffer, nuint offset, nuint count, out SocketError error)
```

Sends up to `count` bytes, and hands back this call's own error beside
the count.

`Error` is the last error of any call on the socket, so a thread
sending while another receives MUST read this one instead.

**Parameters**

- `buffer` -- where the bytes come from
- `offset` -- where in it to start
- `count` -- how many to send from there
- `error` -- this call's error, or `None`

<sub>[stdlib/Net/Socket.sl:355](../../stdlib/Net/Socket.sl#L355)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] buffer)
```

Sends all of it, or says why it could not.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) -- the socket has no peer to send to
- [SocketError.Reset](#reset-case) -- the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) -- a send timeout ran out
- [SocketError.WouldBlock](#wouldblock-case) -- a socket that does not block, with no room left for the rest
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.Send](#send-method)

<sub>[stdlib/Net/Socket.sl:389](../../stdlib/Net/Socket.sl#L389)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) -- the socket has no peer to send to
- [SocketError.Reset](#reset-case) -- the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) -- a send timeout ran out
- [SocketError.WouldBlock](#wouldblock-case) -- a socket that does not block, with no room left for the rest
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.SendAll](#sendall-method)

<sub>[stdlib/Net/Socket.sl:415](../../stdlib/Net/Socket.sl#L415)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes and reports how many arrived. Zero is the
peer having finished, which is an ending rather than an error -- ask
`Error` to tell the two apart.

**Parameters**

- `buffer` -- where the bytes go
- `offset` -- where in it to start writing them
- `count` -- how many to make room for

**See also** &nbsp; [Socket.Send](#send-method)

<sub>[stdlib/Net/Socket.sl:444](../../stdlib/Net/Socket.sl#L444)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, nuint offset, nuint count, out SocketError error)
```

Reads up to `count` bytes, and hands back this call's own error beside
the count. Zero with `None` is the peer having finished.

`Error` is the last error of any call on the socket, so a thread
receiving while another sends MUST read this one instead: a send that
succeeded in between clears `Error`, and a read that failed would look
like an ending.

**Parameters**

- `buffer` -- where the bytes go
- `offset` -- where in it to start writing them
- `count` -- how many to make room for
- `error` -- this call's error, or `None`

<sub>[stdlib/Net/Socket.sl:461](../../stdlib/Net/Socket.sl#L461)</sub>

#### SendTo *method*

```
nuint SendTo(byte[] buffer, EndPoint target)
```

Sends one datagram. It arrives whole or not at all.

**See also** &nbsp; [Socket.ReceiveFrom](#receivefrom-method)

<sub>[stdlib/Net/Socket.sl:488](../../stdlib/Net/Socket.sl#L488)</sub>

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

- `buffer` -- where the datagram goes, from its first byte
- `from` -- filled in with where it came from

**See also** &nbsp; [Socket.SendTo](#sendto-method)

<sub>[stdlib/Net/Socket.sl:515](../../stdlib/Net/Socket.sl#L515)</sub>

#### SetBlocking *method*

```
SocketError SetBlocking(bool blocking)
```

Whether a call waits. A socket that does not block answers
`WouldBlock` instead of waiting, which is not a failure.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the change

<sub>[stdlib/Net/Socket.sl:544](../../stdlib/Net/Socket.sl#L544)</sub>

#### SetNoDelay *method*

```
SocketError SetNoDelay(bool on)
```

Turns off Nagle's algorithm, so a small write goes out now rather than
waiting to be joined by the next one.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option -- a datagram socket has no Nagle to turn off

<sub>[stdlib/Net/Socket.sl:555](../../stdlib/Net/Socket.sl#L555)</sub>

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

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

<sub>[stdlib/Net/Socket.sl:570](../../stdlib/Net/Socket.sl#L570)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets a datagram socket send to a broadcast address. Off by default,
and meaningless on a stream socket.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option, which is what a stream socket does with it

<sub>[stdlib/Net/Socket.sl:581](../../stdlib/Net/Socket.sl#L581)</sub>

#### SetKeepAlive *method*

```
SocketError SetKeepAlive(bool on)
```

Asks the system to probe an idle connection, so a peer that vanished
without closing is eventually noticed. The interval is the platform's
and is measured in hours by default, so this detects a dead peer rather
than a slow one.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

<sub>[stdlib/Net/Socket.sl:593](../../stdlib/Net/Socket.sl#L593)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long a read waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

**See also** &nbsp; [Socket.SetSendTimeout](#setsendtimeout-method)

<sub>[stdlib/Net/Socket.sl:603](../../stdlib/Net/Socket.sl#L603)</sub>

#### SetSendTimeout *method*

```
SocketError SetSendTimeout(int milliseconds)
```

How long a send waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

**See also** &nbsp; [Socket.SetReceiveTimeout](#setreceivetimeout-method)

<sub>[stdlib/Net/Socket.sl:613](../../stdlib/Net/Socket.sl#L613)</sub>

#### Shutdown *method*

```
SocketError Shutdown(SocketShutdown how)
```

Finishes one direction, or both. The other end sees an ending rather
than a reset, which is the difference between this and closing.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.NotConnected](#notconnected-case) -- there is no connection to finish
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [Socket.Close](#close-method)

<sub>[stdlib/Net/Socket.sl:626](../../stdlib/Net/Socket.sl#L626)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits until there is something to read, the time runs out, or it fails.
A negative wait is forever.

<sub>[stdlib/Net/Socket.sl:640](../../stdlib/Net/Socket.sl#L640)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits until there is room to write. On a socket that is connecting
without blocking, this is also how the connection finishing is seen:
a connect that failed answers false, and `Error` says why.

<sub>[stdlib/Net/Socket.sl:645](../../stdlib/Net/Socket.sl#L645)</sub>

### SocketError *enum*

```
enum SocketError
```

Why an operation did not work. `None` is success.

These are the distinctions a program can act on rather than the platform's
whole list, for the reason `IOError` gives: the values are the same
everywhere, and neither `errno` nor a WSA code is.

<sub>[stdlib/Net/SocketError.sl:35](../../stdlib/Net/SocketError.sl#L35)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/Net/SocketError.sl:38](../../stdlib/Net/SocketError.sl#L38)</sub>

#### WouldBlock *case*

```
WouldBlock = 1
```

Nothing to read, or no room to write, on a socket that is not blocking.
Not a failure -- it is what a non-blocking socket says instead of
waiting.

<sub>[stdlib/Net/SocketError.sl:43](../../stdlib/Net/SocketError.sl#L43)</sub>

#### Refused *case*

```
Refused = 2
```

Nothing is listening there.

<sub>[stdlib/Net/SocketError.sl:46](../../stdlib/Net/SocketError.sl#L46)</sub>

#### TimedOut *case*

```
TimedOut = 3
```

A timeout set on the socket ran out before the call finished.

<sub>[stdlib/Net/SocketError.sl:49](../../stdlib/Net/SocketError.sl#L49)</sub>

#### Unreachable *case*

```
Unreachable = 4
```

No route to that address.

<sub>[stdlib/Net/SocketError.sl:51](../../stdlib/Net/SocketError.sl#L51)</sub>

#### AddressInUse *case*

```
AddressInUse = 5
```

Something else already has that port.

<sub>[stdlib/Net/SocketError.sl:54](../../stdlib/Net/SocketError.sl#L54)</sub>

#### NotConnected *case*

```
NotConnected = 6
```

An operation that needs a connection, on a socket that has none.

<sub>[stdlib/Net/SocketError.sl:57](../../stdlib/Net/SocketError.sl#L57)</sub>

#### Reset *case*

```
Reset = 7
```

The peer went away without closing: a reset rather than an ending.

<sub>[stdlib/Net/SocketError.sl:60](../../stdlib/Net/SocketError.sl#L60)</sub>

#### Closed *case*

```
Closed = 8
```

The socket was closed before the call.

<sub>[stdlib/Net/SocketError.sl:63](../../stdlib/Net/SocketError.sl#L63)</sub>

#### Interrupted *case*

```
Interrupted = 9
```

A signal arrived mid-call. Retrying is usually right.

<sub>[stdlib/Net/SocketError.sl:65](../../stdlib/Net/SocketError.sl#L65)</sub>

#### AccessDenied *case*

```
AccessDenied = 10
```

Not permitted -- a low port without the privilege for it, or a
broadcast send on a socket that was not asked to allow one.

<sub>[stdlib/Net/SocketError.sl:68](../../stdlib/Net/SocketError.sl#L68)</sub>

#### NoName *case*

```
NoName = 11
```

The name did not resolve.

<sub>[stdlib/Net/SocketError.sl:71](../../stdlib/Net/SocketError.sl#L71)</sub>

#### Invalid *case*

```
Invalid = 12
```

The request made no sense for this socket in this state.

<sub>[stdlib/Net/SocketError.sl:74](../../stdlib/Net/SocketError.sl#L74)</sub>

#### Unknown *case*

```
Unknown = 13
```

The platform said something this enum has no name for.

<sub>[stdlib/Net/SocketError.sl:76](../../stdlib/Net/SocketError.sl#L76)</sub>

#### TryAgain *case*

```
TryAgain = 14
```

The resolver could not answer for now: a DNS server that timed out or
failed temporarily. Unlike `NoName`, retrying MAY work.

<sub>[stdlib/Net/SocketError.sl:80](../../stdlib/Net/SocketError.sl#L80)</sub>

### SocketShutdown *enum*

```
enum SocketShutdown
```

Which half of a connection to finish.

<sub>[stdlib/Net/SocketShutdown.sl:29](../../stdlib/Net/SocketShutdown.sl#L29)</sub>

#### Receive *case*

```
Receive = 0
```

Stop receiving. The peer can still be written to.

<sub>[stdlib/Net/SocketShutdown.sl:32](../../stdlib/Net/SocketShutdown.sl#L32)</sub>

#### Send *case*

```
Send = 1
```

Stop sending, which is what tells the peer there is no more coming.

<sub>[stdlib/Net/SocketShutdown.sl:34](../../stdlib/Net/SocketShutdown.sl#L34)</sub>

#### Both *case*

```
Both = 2
```

Stop both, which is what `Close` does first.

<sub>[stdlib/Net/SocketShutdown.sl:36](../../stdlib/Net/SocketShutdown.sl#L36)</sub>

### SocketType *enum*

```
enum SocketType
```

Which of the two shapes a socket has.

<sub>[stdlib/Net/SocketType.sl:29](../../stdlib/Net/SocketType.sl#L29)</sub>

#### Stream *case*

```
Stream = 1
```

TCP: a stream, ordered and reliable, with no message boundaries.

<sub>[stdlib/Net/SocketType.sl:32](../../stdlib/Net/SocketType.sl#L32)</sub>

#### Datagram *case*

```
Datagram = 2
```

UDP: datagrams, each whole or absent, in no particular order.

<sub>[stdlib/Net/SocketType.sl:35](../../stdlib/Net/SocketType.sl#L35)</sub>

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

<sub>[stdlib/Net/TcpClient.sl:44](../../stdlib/Net/TcpClient.sl#L44)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port)
```

Connects to a host and port.

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) -- no route to any of them
- [SocketError.Unknown](#unknown-case) -- the last address failed for a reason with no case of its own

**See also** &nbsp; [TcpListener.Accept](#accept-method)

<sub>[stdlib/Net/TcpClient.sl:59](../../stdlib/Net/TcpClient.sl#L59)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port, AddressFamily family)
```

Connects, naming the family rather than letting the resolver choose.

Blocks until the connection is made or refused; there is no timeout
here, and the system's own is measured in tens of seconds.

**Parameters**

- `host` -- the name or address to reach
- `port` -- the port to reach it on
- `family` -- which family to resolve the name in

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve in that family
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- no answer from any address the name resolved to
- [SocketError.Unreachable](#unreachable-case) -- no route to any of them
- [SocketError.Unknown](#unknown-case) -- the last address failed for a reason with no case of its own

<sub>[stdlib/Net/TcpClient.sl:80](../../stdlib/Net/TcpClient.sl#L80)</sub>

#### Connect *method*

```
static Result<TcpClient, SocketError> Connect(String host, ushort port, AddressFamily family, int timeoutMilliseconds)
```

Connects within a time limit.

Every address the name resolved to is tried until one connects, and
all the attempts together get `timeoutMilliseconds`. Resolving the name
is not bounded.

**Parameters**

- `host` -- the name or address to reach
- `port` -- the port to reach it on
- `family` -- which family to resolve the name in
- `timeoutMilliseconds` -- the limit for every attempt together; negative is none

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve in that family
- [SocketError.TryAgain](#tryagain-case) -- the resolver could not answer for now
- [SocketError.Refused](#refused-case) -- nothing is listening there
- [SocketError.TimedOut](#timedout-case) -- the time ran out, or no answer from any address
- [SocketError.Unreachable](#unreachable-case) -- no route to any of them
- [SocketError.Unknown](#unknown-case) -- the last address failed for a reason with no case of its own

**See also** &nbsp; [Socket.OpenConnected](#openconnected-method)

<sub>[stdlib/Net/TcpClient.sl:107](../../stdlib/Net/TcpClient.sl#L107)</sub>

#### IsConnected *property*

```
bool IsConnected { get; }
```

Whether the connection is there. False after the peer finished, after
`Close`, and if connecting never worked.

<sub>[stdlib/Net/TcpClient.sl:128](../../stdlib/Net/TcpClient.sl#L128)</sub>

#### SocketErrorCode *property*

```
SocketError SocketErrorCode { get; }
```

The exact reason, which `Error` rounds off to fit an `IStream`.

<sub>[stdlib/Net/TcpClient.sl:137](../../stdlib/Net/TcpClient.sl#L137)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

This end of the connection -- the address and the port the system
chose for it.

<sub>[stdlib/Net/TcpClient.sl:141](../../stdlib/Net/TcpClient.sl#L141)</sub>

#### RemoteEndPoint *property*

```
EndPoint RemoteEndPoint { get; }
```

The other end: who is connected. What an accepted connection is asked
to find out where it came from.

<sub>[stdlib/Net/TcpClient.sl:145](../../stdlib/Net/TcpClient.sl#L145)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose. Closing it
closes the connection.

<sub>[stdlib/Net/TcpClient.sl:149](../../stdlib/Net/TcpClient.sl#L149)</sub>

#### SendText *method*

```
SocketError SendText(String text)
```

Sends all of `text`, looping until it has gone.

**Fails with**

- [SocketError.Closed](#closed-case) -- the connection was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) -- the connection was never made
- [SocketError.Reset](#reset-case) -- the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) -- a send timeout ran out
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [TcpClient.SendAll](#sendall-method)

<sub>[stdlib/Net/TcpClient.sl:162](../../stdlib/Net/TcpClient.sl#L162)</sub>

#### SendAll *method*

```
SocketError SendAll(byte[] data)
```

Sends all of `data`.

**Fails with**

- [SocketError.Closed](#closed-case) -- the connection was closed, or the peer took nothing and reported nothing
- [SocketError.NotConnected](#notconnected-case) -- the connection was never made
- [SocketError.Reset](#reset-case) -- the peer went away mid-send
- [SocketError.TimedOut](#timedout-case) -- a send timeout ran out
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [TcpClient.SendText](#sendtext-method)

<sub>[stdlib/Net/TcpClient.sl:175](../../stdlib/Net/TcpClient.sl#L175)</sub>

#### ReceiveAll *method*

```
byte[] ReceiveAll()
```

Reads until the peer finishes, and gives back what arrived.

For a protocol that ends by closing -- HTTP/1.0, or anything behind
`shutdown` -- this is the whole body. For one that does not, it never
returns, which is the caller's to know.

**A failure ends the read too**, and what arrived before it comes back
looking complete. The caller MUST check `SocketErrorCode` afterwards,
or use `ReceiveToEnd`, which says.

**See also** &nbsp; [TcpClient.ReceiveToEnd](#receivetoend-method)

<sub>[stdlib/Net/TcpClient.sl:188](../../stdlib/Net/TcpClient.sl#L188)</sub>

#### ReceiveToEnd *method*

```
Result<byte[], SocketError> ReceiveToEnd()
```

Reads until the peer finishes, and gives back what arrived, or the
error that stopped the read before the peer finished.

**Fails with**

- [SocketError.Reset](#reset-case) -- the peer went away without finishing
- [SocketError.TimedOut](#timedout-case) -- a receive timeout ran out
- [SocketError.Closed](#closed-case) -- the connection was closed
- [SocketError.NotConnected](#notconnected-case) -- the connection was never made
- [SocketError.Unknown](#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [TcpClient.ReceiveAll](#receiveall-method)

<sub>[stdlib/Net/TcpClient.sl:205](../../stdlib/Net/TcpClient.sl#L205)</sub>

#### ReceiveText *method*

```
String ReceiveText()
```

The same as `ReceiveAll`, read as UTF-8. Anything malformed becomes
U+FFFD, because the result is a `String` and a `String` is valid UTF-8
by invariant.

A failure ends the read as it does `ReceiveAll`'s, so the caller MUST
check `SocketErrorCode` afterwards.

<sub>[stdlib/Net/TcpClient.sl:220](../../stdlib/Net/TcpClient.sl#L220)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for something to read, answering whether
there is. A peer that closed counts as readable -- the read that
follows returns zero, which is how the ending is seen.

<sub>[stdlib/Net/TcpClient.sl:231](../../stdlib/Net/TcpClient.sl#L231)</sub>

#### WaitToWrite *method*

```
bool WaitToWrite(int milliseconds)
```

Waits up to `milliseconds` for room to write, answering whether there
is. Only interesting once a send has filled the kernel's buffer.

<sub>[stdlib/Net/TcpClient.sl:235](../../stdlib/Net/TcpClient.sl#L235)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while the connection is open and the peer has not finished.

<sub>[stdlib/Net/TcpClient.sl:240](../../stdlib/Net/TcpClient.sl#L240)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while the connection is open. A peer that finished sending can
still be written to, until it closes for real.

<sub>[stdlib/Net/TcpClient.sl:244](../../stdlib/Net/TcpClient.sl#L244)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

A connection has no position to move to.

<sub>[stdlib/Net/TcpClient.sl:247](../../stdlib/Net/TcpClient.sl#L247)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many arrived.

Fewer than asked for is normal and not an error: a stream delivers what
has arrived. Zero means the peer finished, and `Error` distinguishes
that from a failure.

<sub>[stdlib/Net/TcpClient.sl:255](../../stdlib/Net/TcpClient.sl#L255)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes up to `count` bytes from `buffer` at `offset`, answering how
many went. A short write is normal; `SendAll` is the one that loops.

<sub>[stdlib/Net/TcpClient.sl:268](../../stdlib/Net/TcpClient.sl#L268)</sub>

#### Position *property*

```
long Position { get; }
```

Not a position, and not pretended to be one.

<sub>[stdlib/Net/TcpClient.sl:274](../../stdlib/Net/TcpClient.sl#L274)</sub>

#### Length *property*

```
long Length { get; }
```

Not a length either. A connection does not know how much is coming.

<sub>[stdlib/Net/TcpClient.sl:276](../../stdlib/Net/TcpClient.sl#L276)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false. There is nowhere to seek to on a connection.

<sub>[stdlib/Net/TcpClient.sl:279](../../stdlib/Net/TcpClient.sl#L279)</sub>

#### Flush *method*

```
void Flush()
```

Nothing is buffered here; the kernel decides when bytes leave.

<sub>[stdlib/Net/TcpClient.sl:282](../../stdlib/Net/TcpClient.sl#L282)</sub>

#### Close *method*

```
void Close()
```

Ends the connection politely: shuts both directions down first, so the
peer sees an ending rather than a reset, then closes. Idempotent, and
the destructor calls it.

<sub>[stdlib/Net/TcpClient.sl:287](../../stdlib/Net/TcpClient.sl#L287)</sub>

#### Error *property*

```
IOError Error { get; }
```

The socket error as the nearest `IOError`, so that a reader which knows
nothing about sockets still gets something it can act on.

<sub>[stdlib/Net/TcpClient.sl:297](../../stdlib/Net/TcpClient.sl#L297)</sub>

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

<sub>[stdlib/Net/TcpListener.sl:41](../../stdlib/Net/TcpListener.sl#L41)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(ushort port)
```

Listens on every address this machine has.

**Fails with**

- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net/TcpListener.sl:53](../../stdlib/Net/TcpListener.sl#L53)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port)
```

Listens on one address. `"127.0.0.1"` is the useful one: a service that
only its own machine should reach says so here rather than in a
firewall.

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve, or is not an address this machine has
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net/TcpListener.sl:69](../../stdlib/Net/TcpListener.sl#L69)</sub>

#### Listen *method*

```
static Result<TcpListener, SocketError> Listen(String host, ushort port, AddressFamily family, int backlog)
```

Listens with everything named: the address, the port, the family and
how many connections may queue.

The other two overloads are this one with IPv4 and a backlog of 16.

**Parameters**

- `host` -- which address to take, empty for every one of them
- `port` -- which port to take, 0 to be given one
- `family` -- which family to listen in
- `backlog` -- how many connections may queue before the system refuses more

**Fails with**

- [SocketError.Invalid](#invalid-case) -- `AddressFamily.Any`, which no socket can be opened in
- [SocketError.NoName](#noname-case) -- the host did not resolve in that family
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open, the bind or the listen failed for a reason with no case of its own

<sub>[stdlib/Net/TcpListener.sl:93](../../stdlib/Net/TcpListener.sl#L93)</sub>

#### IsListening *property*

```
bool IsListening { get; }
```

Whether it bound and listened. False means the constructor gave up
part-way, and `Error` says where.

<sub>[stdlib/Net/TcpListener.sl:124](../../stdlib/Net/TcpListener.sl#L124)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net/TcpListener.sl:127](../../stdlib/Net/TcpListener.sl#L127)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

Where it is listening. With port 0 this is how the port the system
chose is found out.

<sub>[stdlib/Net/TcpListener.sl:131](../../stdlib/Net/TcpListener.sl#L131)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net/TcpListener.sl:134](../../stdlib/Net/TcpListener.sl#L134)</sub>

#### Accept *method*

```
TcpClient Accept()
```

Waits for a connection. The client that comes back is connected, or is
not and says why.

<sub>[stdlib/Net/TcpListener.sl:138](../../stdlib/Net/TcpListener.sl#L138)</sub>

#### Pending *method*

```
bool Pending(int milliseconds)
```

Whether a connection is waiting, without blocking to find out.

<sub>[stdlib/Net/TcpListener.sl:144](../../stdlib/Net/TcpListener.sl#L144)</sub>

#### Close *method*

```
void Close()
```

Stops listening and closes the socket. Connections already accepted
are their own sockets and are unaffected.

<sub>[stdlib/Net/TcpListener.sl:151](../../stdlib/Net/TcpListener.sl#L151)</sub>

### UdpClient *class*

```
class UdpClient
```

Datagrams.

Not an `IStream`, and that is deliberate. A datagram arrives whole or not
at all, in no particular order, possibly twice; a stream is ordered,
reliable and has no message boundaries at all. Pretending the first is the
second is how a program comes to assume things about UDP that are not true.

    var socket = try UdpClient.Bind(9000u);
    var from = EndPoint.Create("", 0u);
    var buffer = new byte[1500];
    nuint got = socket.Receive(buffer, ref from);

<sub>[stdlib/Net/UdpClient.sl:41](../../stdlib/Net/UdpClient.sl#L41)</sub>

#### Create *method*

```
static Result<UdpClient, SocketError> Create()
```

A socket that can send and not receive, because nothing bound it.

**Fails with**

- [SocketError.Unknown](#unknown-case) -- the platform refused a socket -- out of descriptors, among others

**See also** &nbsp; [UdpClient.Bind](#bind-method)

<sub>[stdlib/Net/UdpClient.sl:51](../../stdlib/Net/UdpClient.sl#L51)</sub>

#### Create *method*

```
static Result<UdpClient, SocketError> Create(AddressFamily family)
```

The same, in a named family.

**Fails with**

- [SocketError.Invalid](#invalid-case) -- `AddressFamily.Any`, which no socket can be opened in
- [SocketError.Unknown](#unknown-case) -- the platform refused a socket

<sub>[stdlib/Net/UdpClient.sl:61](../../stdlib/Net/UdpClient.sl#L61)</sub>

#### Bind *method*

```
static Result<UdpClient, SocketError> Bind(ushort port)
```

A socket bound to a port, so it can receive. Port 0 asks the system to
choose one, which `LocalEndPoint` will say.

**Fails with**

- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open or the bind failed for a reason with no case of its own

**See also** &nbsp; [UdpClient.Create](#create-method)

<sub>[stdlib/Net/UdpClient.sl:77](../../stdlib/Net/UdpClient.sl#L77)</sub>

#### Bind *method*

```
static Result<UdpClient, SocketError> Bind(String host, ushort port)
```

The same, on one address rather than all of them.

**Fails with**

- [SocketError.NoName](#noname-case) -- the host did not resolve, or is not an address this machine has
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open or the bind failed for a reason with no case of its own

<sub>[stdlib/Net/UdpClient.sl:90](../../stdlib/Net/UdpClient.sl#L90)</sub>

#### Bind *method*

```
static Result<UdpClient, SocketError> Bind(String host, ushort port, AddressFamily family)
```

Binds with everything named: the address, the port and the family.

**Parameters**

- `host` -- which address to take, empty for every one of them
- `port` -- which port to take, 0 to be given one
- `family` -- which family to bind in

**Fails with**

- [SocketError.Invalid](#invalid-case) -- `AddressFamily.Any`, which no socket can be opened in
- [SocketError.NoName](#noname-case) -- the host did not resolve in that family
- [SocketError.AddressInUse](#addressinuse-case) -- something else holds that port
- [SocketError.AccessDenied](#accessdenied-case) -- a port this process may not take
- [SocketError.Unknown](#unknown-case) -- the open or the bind failed for a reason with no case of its own

<sub>[stdlib/Net/UdpClient.sl:108](../../stdlib/Net/UdpClient.sl#L108)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the socket is usable. False after `Close`, and after an open
that did not work.

<sub>[stdlib/Net/UdpClient.sl:133](../../stdlib/Net/UdpClient.sl#L133)</sub>

#### Error *property*

```
SocketError Error { get; }
```

The last error from the socket underneath, or `None`.

<sub>[stdlib/Net/UdpClient.sl:136](../../stdlib/Net/UdpClient.sl#L136)</sub>

#### LocalEndPoint *property*

```
EndPoint LocalEndPoint { get; }
```

Where it is bound. With port 0 this is how the port the system chose is
found out; an unbound socket answers with nothing useful.

<sub>[stdlib/Net/UdpClient.sl:140](../../stdlib/Net/UdpClient.sl#L140)</sub>

#### Underlying *property*

```
Socket Underlying { get; }
```

The socket underneath, for an option this does not expose.

<sub>[stdlib/Net/UdpClient.sl:143](../../stdlib/Net/UdpClient.sl#L143)</sub>

#### Send *method*

```
nuint Send(byte[] data, String host, ushort port)
```

Sends one datagram. The count back is how many bytes went, which for a
datagram is all of them or none.

<sub>[stdlib/Net/UdpClient.sl:147](../../stdlib/Net/UdpClient.sl#L147)</sub>

#### SendText *method*

```
nuint SendText(String text, String host, ushort port)
```

Sends one datagram of UTF-8. The encoded length is what goes on the
wire, so a string of multi-byte characters is longer than its character
count -- which matters against the roughly 1500-byte practical limit.

<sub>[stdlib/Net/UdpClient.sl:155](../../stdlib/Net/UdpClient.sl#L155)</sub>

#### Receive *method*

```
nuint Receive(byte[] buffer, ref EndPoint from)
```

Reads one datagram and says where it came from. A datagram longer than
the buffer is truncated, and the rest is gone -- there is no second
read to collect it.

<sub>[stdlib/Net/UdpClient.sl:163](../../stdlib/Net/UdpClient.sl#L163)</sub>

#### WaitToRead *method*

```
bool WaitToRead(int milliseconds)
```

Waits up to `milliseconds` for a datagram to arrive, answering whether
one has. The way to poll without blocking forever on an empty socket.

<sub>[stdlib/Net/UdpClient.sl:170](../../stdlib/Net/UdpClient.sl#L170)</sub>

#### SetBroadcast *method*

```
SocketError SetBroadcast(bool on)
```

Lets this socket send to a broadcast address.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

<sub>[stdlib/Net/UdpClient.sl:176](../../stdlib/Net/UdpClient.sl#L176)</sub>

#### SetReceiveTimeout *method*

```
SocketError SetReceiveTimeout(int milliseconds)
```

How long `Receive` waits before giving up. Zero is forever.

**Fails with**

- [SocketError.Closed](#closed-case) -- the socket was closed before the call
- [SocketError.Unknown](#unknown-case) -- the platform refused the option

<sub>[stdlib/Net/UdpClient.sl:182](../../stdlib/Net/UdpClient.sl#L182)</sub>

#### Close *method*

```
void Close()
```

Closes the socket. Idempotent, and the destructor calls it.

<sub>[stdlib/Net/UdpClient.sl:188](../../stdlib/Net/UdpClient.sl#L188)</sub>

## Functions

### DescribeSocketError *function*

```
String DescribeSocketError(SocketError error)
```

What went wrong, in words.

**See also** &nbsp; [SocketError](#socketerror-enum)

<sub>[stdlib/Net/Net.sl:89](../../stdlib/Net/Net.sl#L89)</sub>

### ResolveHost *function*

```
Result<String, SocketError> ResolveHost(String host)
```

The first address a name resolves to, as text.

One address rather than the list: a list is only useful to something that
will try each in turn, and that is what connecting already does inside the
runtime, where it can try each socket as well as each address.

**Fails with**

- [SocketError.NoName](#noname-case) -- the name did not resolve, or resolved to an address the platform would not write out
- [SocketError.TryAgain](#tryagain-case) -- the resolver could not answer for now
- [SocketError.Unknown](#unknown-case) -- the platform's networking could not be started

<sub>[stdlib/Net/Net.sl:128](../../stdlib/Net/Net.sl#L128)</sub>

### ResolveHost *function*

```
Result<String, SocketError> ResolveHost(String host, AddressFamily family)
```

The first address a name resolves to in one family, as text.

`AddressFamily.Any` takes whichever the resolver prefers. Name it when the
socket that will use the address is already one family or the other, since
an IPv6 address cannot be connected to from an IPv4 socket.

**Parameters**

- `host` -- the name or literal address to look up
- `family` -- which family to take an address from

**Fails with**

- [SocketError.NoName](#noname-case) -- the name did not resolve in that family, or resolved to an address the platform would not write out
- [SocketError.TryAgain](#tryagain-case) -- the resolver could not answer for now
- [SocketError.Unknown](#unknown-case) -- the platform's networking could not be started

<sub>[stdlib/Net/Net.sl:146](../../stdlib/Net/Net.sl#L146)</sub>

