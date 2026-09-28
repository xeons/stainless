# Standard.Net.Http

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

An HTTP/1.1 and HTTP/2 client, over TCP or TLS, as `System.Net.Http`.

```csharp
var client = new HttpClient();
client.Timeout = TimeSpan.FromSeconds(10);
String page = try client.GetString("https://example.com/");

var response = try client.Post("https://example.com/api",
                               new StringContent("{}", Encoding.CreateUtf8(),
                                                 "application/json"));
try response.EnsureSuccessStatusCode();
```

**The shape is .NET's, without the `Async`.** Every call blocks, so
`SendAsync` is `Send` and `GetStringAsync` is `GetString`. Where .NET
throws `HttpRequestException`, a call here returns
`Result<…, HttpError>`; the overloads taking `out HttpFailure` say more —
the socket error, the TLS error, the status a proxy refused with.

**What is implemented** is HTTP/1.1 (RFC 9112) and HTTP/2 (RFC 9113) over
TCP and TLS: keep-alive with a pool of connections per server, request
bodies of known length or chunked, responses framed by length, by chunks
(with trailers) or by the connection closing, `Expect: 100-continue`,
redirects, cookies (RFC 6265), gzip and deflate, proxies over HTTP with
`CONNECT` tunnels, and one timeout that covers the whole of a request.

**What is not:** HTTP/3, server push, authentication other than Basic to
a proxy, a proxy spoken to over TLS, and a timeout on name resolution,
which the platform's resolver does not offer.

**HTTP/2 is used as .NET uses it: when the request asks.**
`HttpRequestMessage.Version` is 1.1 and `VersionPolicy` is
`RequestVersionOrLower` unless set, which is HTTP/1.1; ask for 2.0, or
set `HttpClient.DefaultRequestVersion`, and TLS offers ALPN `h2` then
`http/1.1` and the connection is whichever the server chose. Plain http
speaks HTTP/2 only when the policy allows nothing else, with prior
knowledge. `HttpVersionPolicy` has the whole table.

**An HTTP/2 connection carries every request to its server at once**, a
stream each, up to the server's limit, with a reader thread of its own
that ends when the connection does. Flow control holds a body read slowly
to its window without holding up the others; a timeout, or a body closed
early, resets only its stream. A request the server never processed — a
GOAWAY below its stream, or REFUSED_STREAM — is sent again on a new
connection whatever its method.

**Responses are parsed strictly.** A status line that is not
`HTTP/1.x NNN reason`, a folded header, a header line or block over its
limit, a chunk size that is not hexadecimal or does not fit, two
disagreeing `Content-Length`s, and a `Content-Length` beside a
`Transfer-Encoding` are all refused as `HttpError.InvalidResponse`, since
each is how one message is smuggled inside another. In HTTP/2 a field
with upper-case letters or one that belongs to a single connection, a
missing `:status` and a body unlike its `content-length` reset the stream
and are `InvalidResponse`; a peer that breaks the framing is sent GOAWAY
and every stream on it fails with `ProtocolError`.

**Certificates are judged by the TLS module's validator** unless
`HttpClientHandler.ServerCertificateCustomValidationCallback` is set, in
which case it decides, and is told what the default would have answered.

**One client MAY be used by several threads at once.** The pool is under
a lock; a request and its response belong to the thread that sent it.

## Contents

**Types** &nbsp; [ByteArrayContent](#bytearraycontent-class) &middot; [Cookie](#cookie-class) &middot; [CookieContainer](#cookiecontainer-class) &middot; [DecompressionMethods](#decompressionmethods-enum) &middot; [FormUrlEncodedContent](#formurlencodedcontent-class) &middot; [HttpClient](#httpclient-class) &middot; [HttpClientHandler](#httpclienthandler-class) &middot; [HttpCompletionOption](#httpcompletionoption-enum) &middot; [HttpContent](#httpcontent-class) &middot; [HttpContentHeaders](#httpcontentheaders-class) &middot; [HttpEnvironmentProxy](#httpenvironmentproxy-class) &middot; [HttpEnvironmentVariableReader](#httpenvironmentvariablereader-closure) &middot; [HttpError](#httperror-enum) &middot; [HttpFailure](#httpfailure-class) &middot; [HttpHeaders](#httpheaders-class) &middot; [HttpMethod](#httpmethod-class) &middot; [HttpRequestHeaders](#httprequestheaders-class) &middot; [HttpRequestMessage](#httprequestmessage-class) &middot; [HttpResponseHeaders](#httpresponseheaders-class) &middot; [HttpResponseMessage](#httpresponsemessage-class) &middot; [HttpServerCertificateValidator](#httpservercertificatevalidator-closure) &middot; [HttpStatusCode](#httpstatuscode-enum) &middot; [HttpVersion](#httpversion-class) &middot; [HttpVersionPolicy](#httpversionpolicy-enum) &middot; [IWebProxy](#iwebproxy-interface) &middot; [MediaTypeHeaderValue](#mediatypeheadervalue-class) &middot; [MultipartContent](#multipartcontent-class) &middot; [MultipartFormDataContent](#multipartformdatacontent-class) &middot; [NetworkCredential](#networkcredential-class) &middot; [StreamContent](#streamcontent-class) &middot; [StringContent](#stringcontent-class) &middot; [WebProxy](#webproxy-class)

**Functions** &nbsp; [DescribeHttpError](#describehttperror-function)

## Types

### ByteArrayContent *class*

```
class ByteArrayContent : HttpContent
```

A body held in memory: bytes, sent as they are.

Knows its length, so it is sent with `Content-Length`, and can be sent
again, so a redirect that keeps the body keeps it.

<sub>[stdlib/Net/Http/ByteArrayContent.sl:30](../../stdlib/Net/Http/ByteArrayContent.sl#L30)</sub>

### Cookie *class*

```
sealed class Cookie
```

One cookie: a name, a value, and where and until when it is sent.

.NET's `System.Net.Cookie`, kept here beside the container that is its
only user. `Expires` is none for a session cookie, which lives as long as
its container.

<sub>[stdlib/Net/Http/Cookie.sl:31](../../stdlib/Net/Http/Cookie.sl#L31)</sub>

#### Name *property*

```
String Name { get; set; }
```

*No documentation.*

<sub>[stdlib/Net/Http/Cookie.sl:60](../../stdlib/Net/Http/Cookie.sl#L60)</sub>

#### Value *property*

```
String Value { get; set; }
```

*No documentation.*

<sub>[stdlib/Net/Http/Cookie.sl:62](../../stdlib/Net/Http/Cookie.sl#L62)</sub>

#### Path *property*

```
String Path { get; set; }
```

The path it is sent under: `/` and everything below, for `/`.

<sub>[stdlib/Net/Http/Cookie.sl:65](../../stdlib/Net/Http/Cookie.sl#L65)</sub>

#### Domain *property*

```
String Domain { get; set; }
```

The host it came from, when `IsHostOnly`, and otherwise the domain
whose every host it is sent to. Lower case, with no leading dot.

<sub>[stdlib/Net/Http/Cookie.sl:69](../../stdlib/Net/Http/Cookie.sl#L69)</sub>

#### Secure *property*

```
bool Secure { get; set; }
```

Whether it is sent only over https.

<sub>[stdlib/Net/Http/Cookie.sl:72](../../stdlib/Net/Http/Cookie.sl#L72)</sub>

#### HttpOnly *property*

```
bool HttpOnly { get; set; }
```

Whether the server asked that script not see it. Stored, and sent
like any other: there is no script here.

<sub>[stdlib/Net/Http/Cookie.sl:76](../../stdlib/Net/Http/Cookie.sl#L76)</sub>

#### SameSite *property*

```
String SameSite { get; set; }
```

The `SameSite` the server asked for — `Strict`, `Lax` or `None` — or
empty. Stored and not enforced: a client with no notion of a site
has nothing to enforce it against.

<sub>[stdlib/Net/Http/Cookie.sl:81](../../stdlib/Net/Http/Cookie.sl#L81)</sub>

#### Expires *property*

```
Optional<DateTimeOffset> Expires { get; set; }
```

When it expires, or none for a session cookie.

<sub>[stdlib/Net/Http/Cookie.sl:84](../../stdlib/Net/Http/Cookie.sl#L84)</sub>

#### IsHostOnly *property*

```
bool IsHostOnly { get; set; }
```

Whether it is sent to exactly the host it came from, rather than to a
domain and every host below it.

<sub>[stdlib/Net/Http/Cookie.sl:88](../../stdlib/Net/Http/Cookie.sl#L88)</sub>

#### TimeStamp *property*

```
DateTimeOffset TimeStamp { get; set; }
```

When it was first stored.

<sub>[stdlib/Net/Http/Cookie.sl:91](../../stdlib/Net/Http/Cookie.sl#L91)</sub>

#### HasExpiredAt *method*

```
bool HasExpiredAt(DateTimeOffset now)
```

Whether it had expired at `now`.

<sub>[stdlib/Net/Http/Cookie.sl:94](../../stdlib/Net/Http/Cookie.sl#L94)</sub>

#### ToString *method*

```
String ToString()
```

`name=value`, as a `Cookie` field sends it.

<sub>[stdlib/Net/Http/Cookie.sl:102](../../stdlib/Net/Http/Cookie.sl#L102)</sub>

### CookieContainer *class*

```
sealed class CookieContainer
```

The cookies a client has been given, and the rules for which it sends
where: RFC 6265.

    var cookies = new CookieContainer();
    cookies.SetCookies(uri, "id=a3fWa; Path=/; Secure; Max-Age=3600");
    String header = cookies.GetCookieHeader(uri);        // id=a3fWa

**A cookie belongs to a host, or to a domain.** Without `Domain` it is
sent back only to the host that set it; with one it is sent to that domain
and every host below it, and a host may only name a domain it is itself
in. A domain that is a public suffix — one under which unrelated parties
register names, as `com` or `co.uk` — is refused, so that one site cannot
set a cookie for all of them. **The list of public suffixes here is
short**: every single-label name, and a few dozen well-known multi-label
ones. It is not the Public Suffix List, and a cookie for a suffix it lacks
is accepted.

**`Path` limits a cookie to part of a site**, `Secure` to https,
and `Expires` or `Max-Age` to a time. A cookie set from http cannot be
`Secure`. `HttpOnly` and `SameSite` are kept and not acted on.

One container MAY be shared by several clients and threads.

<sub>[stdlib/Net/Http/CookieContainer.sl:51](../../stdlib/Net/Http/CookieContainer.sl#L51)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many cookies it holds, expired ones included until next looked at.

<sub>[stdlib/Net/Http/CookieContainer.sl:60](../../stdlib/Net/Http/CookieContainer.sl#L60)</sub>

#### MaxCookieSize *property*

```
nuint MaxCookieSize { get; set; }
```

The most bytes a cookie's name and value may take together.

<sub>[stdlib/Net/Http/CookieContainer.sl:70](../../stdlib/Net/Http/CookieContainer.sl#L70)</sub>

#### Add *method*

```
bool Add(Cookie cookie)
```

Stores `cookie`, which MUST name its `Domain`, replacing one of the
same name, domain and path. False when it names no domain or no name,
or has already expired.

<sub>[stdlib/Net/Http/CookieContainer.sl:75](../../stdlib/Net/Http/CookieContainer.sl#L75)</sub>

#### Add *method*

```
bool Add(Uri uri, Cookie cookie)
```

Stores `cookie` as though `uri` had set it: its domain, if it names
one, MUST contain `uri`'s host, and it defaults to that host and to the
directory of `uri`'s path. False when it is refused.

<sub>[stdlib/Net/Http/CookieContainer.sl:91](../../stdlib/Net/Http/CookieContainer.sl#L91)</sub>

#### GetCookies *method*

```
List<Cookie> GetCookies(Uri uri)
```

The cookies that would be sent to `uri`, longest path first.

<sub>[stdlib/Net/Http/CookieContainer.sl:99](../../stdlib/Net/Http/CookieContainer.sl#L99)</sub>

#### GetAllCookies *method*

```
List<Cookie> GetAllCookies()
```

Every cookie held that has not expired.

<sub>[stdlib/Net/Http/CookieContainer.sl:102](../../stdlib/Net/Http/CookieContainer.sl#L102)</sub>

#### GetCookieHeader *method*

```
String GetCookieHeader(Uri uri)
```

What a request to `uri` sends as its `Cookie` field: `a=1; b=2`, or
empty when nothing applies.

<sub>[stdlib/Net/Http/CookieContainer.sl:115](../../stdlib/Net/Http/CookieContainer.sl#L115)</sub>

#### SetCookies *method*

```
nuint SetCookies(Uri uri, String cookieHeader)
```

Stores the cookies in `cookieHeader` as `uri` set them: one
`Set-Cookie` value, or several separated by commas, as .NET's takes
them. A comma inside an `Expires` date does not separate. Answers how
many are held afterwards: a malformed or refused one is skipped, and an
expired one only removes what it names.

<sub>[stdlib/Net/Http/CookieContainer.sl:134](../../stdlib/Net/Http/CookieContainer.sl#L134)</sub>

### DecompressionMethods *enum*

```
enum DecompressionMethods
```

Which content codings `HttpClientHandler` asks for and undoes.

**See also** &nbsp; [HttpClientHandler.AutomaticDecompression](#automaticdecompression-property)

<sub>[stdlib/Net/Http/DecompressionMethods.sl:27](../../stdlib/Net/Http/DecompressionMethods.sl#L27)</sub>

#### None *case*

```
None = 0
```

None: the body arrives as the server sent it.

<sub>[stdlib/Net/Http/DecompressionMethods.sl:31](../../stdlib/Net/Http/DecompressionMethods.sl#L31)</sub>

#### GZip *case*

```
GZip = 1
```

gzip, RFC 1952.

<sub>[stdlib/Net/Http/DecompressionMethods.sl:34](../../stdlib/Net/Http/DecompressionMethods.sl#L34)</sub>

#### Deflate *case*

```
Deflate = 2
```

deflate: RFC 1950's zlib format, or RFC 1951's raw deflate, which
some servers send under the same name and every browser accepts.

<sub>[stdlib/Net/Http/DecompressionMethods.sl:38](../../stdlib/Net/Http/DecompressionMethods.sl#L38)</sub>

#### All *case*

```
All = 3
```

Every coding this module can undo.

<sub>[stdlib/Net/Http/DecompressionMethods.sl:41](../../stdlib/Net/Http/DecompressionMethods.sl#L41)</sub>

### FormUrlEncodedContent *class*

```
class FormUrlEncodedContent : ByteArrayContent
```

Names and values as `application/x-www-form-urlencoded`: what an HTML
form posts.

    var form = new FormUrlEncodedContent([
        new KeyValuePair<String, String>("user", "ann"),
        new KeyValuePair<String, String>("note", "a & b"),
    ]);                                   // user=ann&note=a+%26+b

<sub>[stdlib/Net/Http/FormUrlEncodedContent.sl:34](../../stdlib/Net/Http/FormUrlEncodedContent.sl#L34)</sub>

### HttpClient *class*

```
class HttpClient
```

Sends requests and receives responses: .NET's `HttpClient`, blocking.

    var client = new HttpClient();
    client.BaseAddress = new Uri("https://api.example.com/");
    client.DefaultRequestHeaders.Accept = "application/json";
    var response = try client.Get("items/42");
    String body = try response.Content.ReadAsString();

One client is meant to be made once and used for many requests, so that
its handler's connections are reused. `Timeout` covers each request whole
— connecting, TLS, sending, redirects, and reading the body unless the
body is streamed.

<sub>[stdlib/Net/Http/HttpClient.sl:40](../../stdlib/Net/Http/HttpClient.sl#L40)</sub>

#### DefaultProxy *property*

```
static IWebProxy DefaultProxy { get; set; }
```

The proxy a handler uses when its own `Proxy` is null: the one the
environment names (see `HttpEnvironmentProxy`), read the first time it
is asked for, or one that sends everything direct.

<sub>[stdlib/Net/Http/HttpClient.sl:68](../../stdlib/Net/Http/HttpClient.sl#L68)</sub>

#### BaseAddress *property*

```
Uri? BaseAddress { get; set; }
```

The URI a relative request URI is resolved against.

<sub>[stdlib/Net/Http/HttpClient.sl:90](../../stdlib/Net/Http/HttpClient.sl#L90)</sub>

#### DefaultRequestHeaders *property*

```
HttpRequestHeaders DefaultRequestHeaders { get; }
```

Fields sent with every request, where the request does not name them
itself.

<sub>[stdlib/Net/Http/HttpClient.sl:94](../../stdlib/Net/Http/HttpClient.sl#L94)</sub>

#### Timeout *property*

```
TimeSpan Timeout { get; set; }
```

How long a request may take, 100 seconds unless set. Zero or negative
is no limit.

<sub>[stdlib/Net/Http/HttpClient.sl:98](../../stdlib/Net/Http/HttpClient.sl#L98)</sub>

#### MaxResponseContentBufferSize *property*

```
long MaxResponseContentBufferSize { get; set; }
```

The longest body read into memory, 2 GiB unless set.

<sub>[stdlib/Net/Http/HttpClient.sl:101](../../stdlib/Net/Http/HttpClient.sl#L101)</sub>

#### Handler *property*

```
HttpClientHandler Handler { get; }
```

The handler requests go through.

<sub>[stdlib/Net/Http/HttpClient.sl:104](../../stdlib/Net/Http/HttpClient.sl#L104)</sub>

#### DefaultRequestVersion *property*

```
Version DefaultRequestVersion { get; set; }
```

The version the methods that make their own request ask for — `Get`,
`Post`, `GetString` and the rest. HTTP/1.1 unless set, as .NET's is;
a request made by the caller keeps its own.

<sub>[stdlib/Net/Http/HttpClient.sl:109](../../stdlib/Net/Http/HttpClient.sl#L109)</sub>

#### DefaultVersionPolicy *property*

```
HttpVersionPolicy DefaultVersionPolicy { get; set; }
```

The policy those requests are made with.

<sub>[stdlib/Net/Http/HttpClient.sl:112](../../stdlib/Net/Http/HttpClient.sl#L112)</sub>

#### Send *method*

```
Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request)
```

Sends `request` and reads the whole response.

**Fails with**

- [HttpError.Timeout](#timeout-case) — `Timeout` ran out
- [HttpError.ConnectFailure](#connectfailure-case) — no connection could be made
- [HttpError.InvalidResponse](#invalidresponse-case) — the response was malformed
- [HttpError.InvalidRequest](#invalidrequest-case) — the request has no absolute URI and there is no `BaseAddress`

<sub>[stdlib/Net/Http/HttpClient.sl:123](../../stdlib/Net/Http/HttpClient.sl#L123)</sub>

#### Send *method*

```
Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request, HttpCompletionOption completionOption)
```

Sends `request`, returning when `completionOption` says.

**Fails with**

- [HttpError.Timeout](#timeout-case) — `Timeout` ran out

<sub>[stdlib/Net/Http/HttpClient.sl:129](../../stdlib/Net/Http/HttpClient.sl#L129)</sub>

#### Send *method*

```
Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request, HttpCompletionOption completionOption, out HttpFailure failure)
```

Sends `request`, returning when `completionOption` says, and says what
went wrong in `failure` when it fails.

**Parameters**

- `request` — what to send; a followed redirect changes it
- `completionOption` — whether to read the body before returning
- `failure` — the detail of a failure, or `None`

**Fails with**

- [HttpError.Timeout](#timeout-case) — `Timeout` ran out
- [HttpError.TlsFailure](#tlsfailure-case) — the TLS handshake failed
- [HttpError.TooManyRedirects](#toomanyredirects-case) — more than the handler allows
- [HttpError.ResponseTooLarge](#responsetoolarge-case) — past `MaxResponseContentBufferSize`

<sub>[stdlib/Net/Http/HttpClient.sl:143](../../stdlib/Net/Http/HttpClient.sl#L143)</sub>

#### Get *method*

```
Result<HttpResponseMessage, HttpError> Get(String requestUri)
```

`GET` of `requestUri`, with the whole body read.

<sub>[stdlib/Net/Http/HttpClient.sl:183](../../stdlib/Net/Http/HttpClient.sl#L183)</sub>

#### Get *method*

```
Result<HttpResponseMessage, HttpError> Get(Uri requestUri)
```

`GET` of `requestUri`, with the whole body read.

<sub>[stdlib/Net/Http/HttpClient.sl:187](../../stdlib/Net/Http/HttpClient.sl#L187)</sub>

#### Get *method*

```
Result<HttpResponseMessage, HttpError> Get(String requestUri, HttpCompletionOption completionOption)
```

`GET` of `requestUri`, returning when `completionOption` says.

<sub>[stdlib/Net/Http/HttpClient.sl:191](../../stdlib/Net/Http/HttpClient.sl#L191)</sub>

#### Get *method*

```
Result<HttpResponseMessage, HttpError> Get(Uri requestUri, HttpCompletionOption completionOption)
```

`GET` of `requestUri`, returning when `completionOption` says.

<sub>[stdlib/Net/Http/HttpClient.sl:195](../../stdlib/Net/Http/HttpClient.sl#L195)</sub>

#### GetString *method*

```
Result<String, HttpError> GetString(String requestUri)
```

The body of a `GET` as text.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:201](../../stdlib/Net/Http/HttpClient.sl#L201)</sub>

#### GetString *method*

```
Result<String, HttpError> GetString(Uri requestUri)
```

The body of a `GET` as text.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:207](../../stdlib/Net/Http/HttpClient.sl#L207)</sub>

#### GetByteArray *method*

```
Result<byte[], HttpError> GetByteArray(String requestUri)
```

The body of a `GET` as bytes.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:213](../../stdlib/Net/Http/HttpClient.sl#L213)</sub>

#### GetByteArray *method*

```
Result<byte[], HttpError> GetByteArray(Uri requestUri)
```

The body of a `GET` as bytes.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:219](../../stdlib/Net/Http/HttpClient.sl#L219)</sub>

#### GetStream *method*

```
Result<IStream, HttpError> GetStream(String requestUri)
```

The body of a `GET` as a stream, read from the connection as it
arrives.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:226](../../stdlib/Net/Http/HttpClient.sl#L226)</sub>

#### GetStream *method*

```
Result<IStream, HttpError> GetStream(Uri requestUri)
```

The body of a `GET` as a stream, read from the connection as it
arrives.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status was not 2xx

<sub>[stdlib/Net/Http/HttpClient.sl:233](../../stdlib/Net/Http/HttpClient.sl#L233)</sub>

#### Post *method*

```
Result<HttpResponseMessage, HttpError> Post(String requestUri, HttpContent? content)
```

`POST` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:237](../../stdlib/Net/Http/HttpClient.sl#L237)</sub>

#### Post *method*

```
Result<HttpResponseMessage, HttpError> Post(Uri requestUri, HttpContent? content)
```

`POST` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:241](../../stdlib/Net/Http/HttpClient.sl#L241)</sub>

#### Put *method*

```
Result<HttpResponseMessage, HttpError> Put(String requestUri, HttpContent? content)
```

`PUT` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:245](../../stdlib/Net/Http/HttpClient.sl#L245)</sub>

#### Put *method*

```
Result<HttpResponseMessage, HttpError> Put(Uri requestUri, HttpContent? content)
```

`PUT` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:249](../../stdlib/Net/Http/HttpClient.sl#L249)</sub>

#### Patch *method*

```
Result<HttpResponseMessage, HttpError> Patch(String requestUri, HttpContent? content)
```

`PATCH` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:253](../../stdlib/Net/Http/HttpClient.sl#L253)</sub>

#### Patch *method*

```
Result<HttpResponseMessage, HttpError> Patch(Uri requestUri, HttpContent? content)
```

`PATCH` of `content` to `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:257](../../stdlib/Net/Http/HttpClient.sl#L257)</sub>

#### Delete *method*

```
Result<HttpResponseMessage, HttpError> Delete(String requestUri)
```

`DELETE` of `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:261](../../stdlib/Net/Http/HttpClient.sl#L261)</sub>

#### Delete *method*

```
Result<HttpResponseMessage, HttpError> Delete(Uri requestUri)
```

`DELETE` of `requestUri`.

<sub>[stdlib/Net/Http/HttpClient.sl:265](../../stdlib/Net/Http/HttpClient.sl#L265)</sub>

#### Dispose *method*

```
void Dispose()
```

Refuses further requests, and disposes the handler unless it was made
to be shared.

<sub>[stdlib/Net/Http/HttpClient.sl:270](../../stdlib/Net/Http/HttpClient.sl#L270)</sub>

### HttpClientHandler *class*

```
class HttpClientHandler
```

What a client does between a request and the wire: connections and their
pool, proxies, TLS, redirects, cookies and decompression.

    var handler = new HttpClientHandler();
    handler.AutomaticDecompression = DecompressionMethods.All;
    handler.MaxConnectionsPerServer = 4;
    var client = new HttpClient(handler);

.NET's `HttpClientHandler`, and its defaults. Its settings are read when
a request is sent; the pool is made with the ones in force at the first
request and keeps them.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:44](../../stdlib/Net/Http/HttpClientHandler.sl#L44)</sub>

#### AllowAutoRedirect *property*

```
bool AllowAutoRedirect { get; set; }
```

Whether a `3xx` with a `Location` is followed.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:60](../../stdlib/Net/Http/HttpClientHandler.sl#L60)</sub>

#### MaxAutomaticRedirections *property*

```
int MaxAutomaticRedirections { get; set; }
```

How many redirects one request may follow before it fails with
`TooManyRedirects`.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:64](../../stdlib/Net/Http/HttpClientHandler.sl#L64)</sub>

#### AutomaticDecompression *property*

```
DecompressionMethods AutomaticDecompression { get; set; }
```

Which codings are asked for with `Accept-Encoding` and undone.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:67](../../stdlib/Net/Http/HttpClientHandler.sl#L67)</sub>

#### UseCookies *property*

```
bool UseCookies { get; set; }
```

Whether `CookieContainer` is sent and filled.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:70](../../stdlib/Net/Http/HttpClientHandler.sl#L70)</sub>

#### CookieContainer *property*

```
CookieContainer CookieContainer { get; set; }
```

The cookies sent and received.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:73](../../stdlib/Net/Http/HttpClientHandler.sl#L73)</sub>

#### UseProxy *property*

```
bool UseProxy { get; set; }
```

Whether a proxy is used at all.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:76](../../stdlib/Net/Http/HttpClientHandler.sl#L76)</sub>

#### Proxy *property*

```
IWebProxy? Proxy { get; set; }
```

The proxy, or null for `HttpClient.DefaultProxy`.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:79](../../stdlib/Net/Http/HttpClientHandler.sl#L79)</sub>

#### ServerCertificateCustomValidationCallback *property*

```
HttpServerCertificateValidator ServerCertificateCustomValidationCallback { get; set; }
```

Decides whether to trust a server's certificate, in place of the TLS
module's validator, which it is told the answer of.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:83](../../stdlib/Net/Http/HttpClientHandler.sl#L83)</sub>

#### DangerousAcceptAnyServerCertificateValidator *property*

```
static HttpServerCertificateValidator DangerousAcceptAnyServerCertificateValidator { get; }
```

A callback that trusts every certificate. For a test against a server
with a throwaway certificate, and nothing else: it makes TLS encryption
without authentication, which a machine in the middle defeats.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:96](../../stdlib/Net/Http/HttpClientHandler.sl#L96)</sub>

#### ClientCertificates *property*

```
List<byte[]> ClientCertificates { get; set; }
```

The client's certificates, DER, leaf first, sent when a server asks.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:100](../../stdlib/Net/Http/HttpClientHandler.sl#L100)</sub>

#### ClientCertificateKey *property*

```
TlsSigningKey? ClientCertificateKey { get; set; }
```

The key of the client's leaf certificate.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:103](../../stdlib/Net/Http/HttpClientHandler.sl#L103)</sub>

#### MaxConnectionsPerServer *property*

```
int MaxConnectionsPerServer { get; set; }
```

The most connections open to one server at once. A request past it
waits, within its timeout, for one to be free.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:107](../../stdlib/Net/Http/HttpClientHandler.sl#L107)</sub>

#### PooledConnectionIdleTimeout *property*

```
TimeSpan PooledConnectionIdleTimeout { get; set; }
```

How long a connection may sit idle in the pool and still be reused.
Zero pools nothing; negative keeps connections for ever.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:111](../../stdlib/Net/Http/HttpClientHandler.sl#L111)</sub>

#### MaxResponseHeadersLength *property*

```
int MaxResponseHeadersLength { get; set; }
```

The most a response head may take, in KiB. HTTP/2 advertises it as
`SETTINGS_MAX_HEADER_LIST_SIZE`.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:115](../../stdlib/Net/Http/HttpClientHandler.sl#L115)</sub>

#### InitialHttp2StreamWindowSize *property*

```
int InitialHttp2StreamWindowSize { get; set; }
```

How much of a response body each HTTP/2 stream lets the server send
before the reader has read it, in bytes: the flow-control window,
between 65 535 and 2^31 − 1. .NET's starts at 65 535 and grows it as
it measures the connection; this one is fixed, so its default is a
window wide enough for a fast link, 1 MiB.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:122](../../stdlib/Net/Http/HttpClientHandler.sl#L122)</sub>

#### EnableMultipleHttp2Connections *property*

```
bool EnableMultipleHttp2Connections { get; set; }
```

Whether a second HTTP/2 connection to a server is opened when every
stream the first allows is busy. When false, as by default, a request
waits for a stream to end.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:127](../../stdlib/Net/Http/HttpClientHandler.sl#L127)</sub>

#### Dispose *method*

```
void Dispose()
```

Closes every idle connection. A response still being read keeps its
connection until it is done with it, and that one is then closed too.

<sub>[stdlib/Net/Http/HttpClientHandler.sl:131](../../stdlib/Net/Http/HttpClientHandler.sl#L131)</sub>

### HttpCompletionOption *enum*

```
enum HttpCompletionOption
```

When `Send` returns: once the whole response has been read, or as soon as
its head has.

<sub>[stdlib/Net/Http/HttpCompletionOption.sl:26](../../stdlib/Net/Http/HttpCompletionOption.sl#L26)</sub>

#### ResponseContentRead *case*

```
ResponseContentRead = 0
```

The body is read into memory before `Send` returns, within
`HttpClient.Timeout` and `MaxResponseContentBufferSize`, and the
connection goes back to the pool at once.

<sub>[stdlib/Net/Http/HttpCompletionOption.sl:31](../../stdlib/Net/Http/HttpCompletionOption.sl#L31)</sub>

#### ResponseHeadersRead *case*

```
ResponseHeadersRead = 1
```

`Send` returns once the head is read, and the body is read from
`Content.ReadAsStream()` as it arrives. The connection goes back to the
pool when the body has been read to its end; a response disposed
before then closes it. `HttpClient.Timeout` does not cover the body.

<sub>[stdlib/Net/Http/HttpCompletionOption.sl:37](../../stdlib/Net/Http/HttpCompletionOption.sl#L37)</sub>

### HttpContent *class*

```
abstract class HttpContent
```

A body and the fields that describe it.

    String text = try response.Content.ReadAsString();
    IStream body = try response.Content.ReadAsStream();

.NET's `HttpContent`. A derived class says how to write itself with
`SerializeToStream` and whether it knows its length with
`TryComputeLength`; everything else is built on those two.

**A response's content reads once** unless it was buffered, which it is
unless the request asked for `ResponseHeadersRead`. `LoadIntoBuffer` reads
the rest of it into memory, after which every read starts again from the
beginning.

<sub>[stdlib/Net/Http/HttpContent.sl:42](../../stdlib/Net/Http/HttpContent.sl#L42)</sub>

#### Headers *property*

```
HttpContentHeaders Headers { get; }
```

The fields describing this body.

<sub>[stdlib/Net/Http/HttpContent.sl:51](../../stdlib/Net/Http/HttpContent.sl#L51)</sub>

#### ReadAsByteArray *method*

```
Result<byte[], HttpError> ReadAsByteArray()
```

The whole body.

**Fails with**

- [HttpError.ConnectionClosed](#connectionclosed-case) — the connection ended mid-body
- [HttpError.Timeout](#timeout-case) — the request's timeout ran out
- [HttpError.ContentFailure](#contentfailure-case) — the body could not be read

<sub>[stdlib/Net/Http/HttpContent.sl:73](../../stdlib/Net/Http/HttpContent.sl#L73)</sub>

#### ReadAsString *method*

```
Result<String, HttpError> ReadAsString()
```

The whole body as text, decoded by the `charset` of `Content-Type`
when this module knows it, by a byte order mark when there is one,
and as UTF-8 otherwise. Malformed input becomes U+FFFD.

**Fails with**

- [HttpError.ConnectionClosed](#connectionclosed-case) — the connection ended mid-body
- [HttpError.Timeout](#timeout-case) — the request's timeout ran out

<sub>[stdlib/Net/Http/HttpContent.sl:87](../../stdlib/Net/Http/HttpContent.sl#L87)</sub>

#### ReadAsStream *method*

```
Result<IStream, HttpError> ReadAsStream()
```

A stream to read the body from. For a response that was not buffered
this is the connection itself, and reads once.

**Fails with**

- [HttpError.ContentFailure](#contentfailure-case) — the body could not be buffered

<sub>[stdlib/Net/Http/HttpContent.sl:116](../../stdlib/Net/Http/HttpContent.sl#L116)</sub>

#### CopyTo *method*

```
HttpError CopyTo(IStream destination)
```

Writes the body to `destination`.

**Fails with**

- [HttpError.ContentFailure](#contentfailure-case) — `destination` would not take it, or the body could not be read

<sub>[stdlib/Net/Http/HttpContent.sl:133](../../stdlib/Net/Http/HttpContent.sl#L133)</sub>

#### LoadIntoBuffer *method*

```
HttpError LoadIntoBuffer()
```

Reads the whole body into memory, so that it can be read again.

**Fails with**

- [HttpError.ContentFailure](#contentfailure-case) — the body could not be read

<sub>[stdlib/Net/Http/HttpContent.sl:147](../../stdlib/Net/Http/HttpContent.sl#L147)</sub>

#### LoadIntoBuffer *method*

```
HttpError LoadIntoBuffer(long maxBufferSize)
```

Reads the whole body into memory, refusing one over `maxBufferSize`.

**Parameters**

- `maxBufferSize` — the most bytes to hold

**Fails with**

- [HttpError.ResponseTooLarge](#responsetoolarge-case) — the body is longer than that

<sub>[stdlib/Net/Http/HttpContent.sl:153](../../stdlib/Net/Http/HttpContent.sl#L153)</sub>

#### Dispose *method*

```
virtual void Dispose()
```

Releases what the body holds: a response's connection, which is
closed rather than pooled if the body was not read to its end.

<sub>[stdlib/Net/Http/HttpContent.sl:170](../../stdlib/Net/Http/HttpContent.sl#L170)</sub>

### HttpContentHeaders *class*

```
sealed class HttpContentHeaders : HttpHeaders
```

The fields that describe a body: its type, its length, its coding.

`ContentLength` answers the content's own length when no field was set,
as .NET's does, so a `ByteArrayContent` knows its length without being
told.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:32](../../stdlib/Net/Http/HttpContentHeaders.sl#L32)</sub>

#### ContentDisposition *property*

```
String? ContentDisposition { get; set; }
```

`Content-Disposition`, as written: `form-data; name="file"`.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:39](../../stdlib/Net/Http/HttpContentHeaders.sl#L39)</sub>

#### ContentEncoding *property*

```
String[] ContentEncoding { get; }
```

The codings of `Content-Encoding`, outermost last. A body that
`AutomaticDecompression` undid has none left.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:47](../../stdlib/Net/Http/HttpContentHeaders.sl#L47)</sub>

#### ContentLanguage *property*

```
String? ContentLanguage { get; set; }
```

`Content-Language`.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:59](../../stdlib/Net/Http/HttpContentHeaders.sl#L59)</sub>

#### ContentLength *property*

```
Optional<long> ContentLength { get; set; }
```

`Content-Length`: the field when it is set, and otherwise the
content's own length when it knows one.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:67](../../stdlib/Net/Http/HttpContentHeaders.sl#L67)</sub>

#### ContentType *property*

```
MediaTypeHeaderValue? ContentType { get; set; }
```

`Content-Type`, parsed; null when it is absent or malformed.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:93](../../stdlib/Net/Http/HttpContentHeaders.sl#L93)</sub>

#### Expires *property*

```
Optional<DateTimeOffset> Expires { get; }
```

`Expires`, when it is an HTTP-date.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:114](../../stdlib/Net/Http/HttpContentHeaders.sl#L114)</sub>

#### LastModified *property*

```
Optional<DateTimeOffset> LastModified { get; set; }
```

`Last-Modified`, when it is an HTTP-date.

<sub>[stdlib/Net/Http/HttpContentHeaders.sl:117](../../stdlib/Net/Http/HttpContentHeaders.sl#L117)</sub>

### HttpEnvironmentProxy *class*

```
sealed class HttpEnvironmentProxy : IWebProxy
```

The proxy the environment names, as curl reads it.

    http_proxy=http://proxy.example:3128
    https_proxy=http://user:secret@proxy.example:3128
    no_proxy=localhost,.internal.example,10.0.0.0/8,example.com:8080

**Each variable is read in lower case first and upper case second**, as
curl reads them: `http_proxy` for http requests, `https_proxy` for https,
`all_proxy` for either when its own is unset, and `no_proxy` for the
exceptions. Upper-case `HTTP_PROXY` is ignored when `REQUEST_METHOD` is
set, because a CGI program finds a request's `Proxy` header there
("httpoxy"). A value without a scheme is taken as `http://`; one naming any
other scheme is ignored, since only HTTP proxies are spoken to.

**`no_proxy`** is a comma-separated list: `*` for everything; a domain,
which matches itself and every name below it, with or without a leading
`.` or `*.`; an IP address, matched exactly, or an IPv4 range as
`10.0.0.0/8`; any of them with `:port` to match that port alone.

**A loopback destination always goes direct** — `localhost`, 127/8, `::1`
— since no proxy elsewhere can reach this machine's loopback.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:52](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L52)</sub>

#### FromEnvironment *method*

```
static IWebProxy? FromEnvironment()
```

The proxy this process's environment names, or null when it names
none.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:63](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L63)</sub>

#### FromEnvironment *method*

```
static IWebProxy? FromEnvironment(HttpEnvironmentVariableReader read)
```

The proxy the variables `read` answers name, or null when they name
none.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:68](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L68)</sub>

#### HttpProxy *property*

```
Uri? HttpProxy { get; }
```

The proxy for http requests, or null.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:88](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L88)</sub>

#### HttpsProxy *property*

```
Uri? HttpsProxy { get; }
```

The proxy for https requests, or null.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:91](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L91)</sub>

#### Credentials *property*

```
NetworkCredential? Credentials { get; set; }
```

The credentials in the proxy URI's user information, when it had any.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:94](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L94)</sub>

#### GetProxy *method*

```
Uri? GetProxy(Uri destination)
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:96](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L96)</sub>

#### IsBypassed *method*

```
bool IsBypassed(Uri host)
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:103](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L103)</sub>

### HttpEnvironmentVariableReader *closure*

```
closure String? HttpEnvironmentVariableReader(String name)
```

Reads an environment variable: its value, or null when it is not set.

<sub>[stdlib/Net/Http/HttpEnvironmentProxy.sl:29](../../stdlib/Net/Http/HttpEnvironmentProxy.sl#L29)</sub>

### HttpError *enum*

```
enum HttpError
```

Why a request failed. `None` is success.

.NET's `HttpRequestError`, as the case a `Result` fails with rather than a
property of an exception. `HttpFailure` carries the detail beneath it: the
socket error, the TLS error, the status a proxy refused with.

**See also** &nbsp; [HttpFailure](#httpfailure-class)

<sub>[stdlib/Net/Http/HttpError.sl:31](../../stdlib/Net/Http/HttpError.sl#L31)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/Net/Http/HttpError.sl:34](../../stdlib/Net/Http/HttpError.sl#L34)</sub>

#### NameResolutionFailure *case*

```
NameResolutionFailure
```

The host name did not resolve.

<sub>[stdlib/Net/Http/HttpError.sl:37](../../stdlib/Net/Http/HttpError.sl#L37)</sub>

#### ConnectFailure *case*

```
ConnectFailure
```

No connection could be made: refused, unreachable, or reset while it
was being made.

<sub>[stdlib/Net/Http/HttpError.sl:41](../../stdlib/Net/Http/HttpError.sl#L41)</sub>

#### ConnectionClosed *case*

```
ConnectionClosed
```

The connection ended before the response did, or before it began.

<sub>[stdlib/Net/Http/HttpError.sl:44](../../stdlib/Net/Http/HttpError.sl#L44)</sub>

#### Timeout *case*

```
Timeout
```

`HttpClient.Timeout` ran out: connecting, in TLS, sending, or reading.

<sub>[stdlib/Net/Http/HttpError.sl:47](../../stdlib/Net/Http/HttpError.sl#L47)</sub>

#### TlsFailure *case*

```
TlsFailure
```

The TLS handshake failed, or a record did; `HttpFailure.TlsErrorCode`
says which.

<sub>[stdlib/Net/Http/HttpError.sl:51](../../stdlib/Net/Http/HttpError.sl#L51)</sub>

#### InvalidResponse *case*

```
InvalidResponse
```

The response was malformed: HTTP/1.1's syntax or framing broken, or an
HTTP/2 head or body its stream was reset for.

<sub>[stdlib/Net/Http/HttpError.sl:55](../../stdlib/Net/Http/HttpError.sl#L55)</sub>

#### ResponseTooLarge *case*

```
ResponseTooLarge
```

The response head or body was over its limit.

<sub>[stdlib/Net/Http/HttpError.sl:58](../../stdlib/Net/Http/HttpError.sl#L58)</sub>

#### TooManyRedirects *case*

```
TooManyRedirects
```

More redirects than `HttpClientHandler.MaxAutomaticRedirections`.

<sub>[stdlib/Net/Http/HttpError.sl:61](../../stdlib/Net/Http/HttpError.sl#L61)</sub>

#### ProxyFailure *case*

```
ProxyFailure
```

The proxy could not be reached, refused the tunnel, or asked for
credentials it was not given; `HttpFailure.StatusCode` says which.

<sub>[stdlib/Net/Http/HttpError.sl:65](../../stdlib/Net/Http/HttpError.sl#L65)</sub>

#### DecompressionFailed *case*

```
DecompressionFailed
```

A gzip or deflate body was corrupt.

<sub>[stdlib/Net/Http/HttpError.sl:68](../../stdlib/Net/Http/HttpError.sl#L68)</sub>

#### InvalidRequest *case*

```
InvalidRequest
```

The request cannot be sent as it is: a relative URI with no
`BaseAddress`, a scheme other than http or https, a header value with
a line break in it.

<sub>[stdlib/Net/Http/HttpError.sl:73](../../stdlib/Net/Http/HttpError.sl#L73)</sub>

#### UnsuccessfulStatusCode *case*

```
UnsuccessfulStatusCode
```

`EnsureSuccessStatusCode` found a status outside 200–299.

<sub>[stdlib/Net/Http/HttpError.sl:76](../../stdlib/Net/Http/HttpError.sl#L76)</sub>

#### ContentFailure *case*

```
ContentFailure
```

The request content could not be read, or the response content could
not be written where it was asked to go.

<sub>[stdlib/Net/Http/HttpError.sl:80](../../stdlib/Net/Http/HttpError.sl#L80)</sub>

#### Disposed *case*

```
Disposed
```

The client or its handler has been disposed.

<sub>[stdlib/Net/Http/HttpError.sl:83](../../stdlib/Net/Http/HttpError.sl#L83)</sub>

#### ProtocolError *case*

```
ProtocolError
```

The HTTP/2 server broke the protocol, ending the connection, or reset
the stream; `HttpFailure.ProtocolErrorCode` says with which code.

<sub>[stdlib/Net/Http/HttpError.sl:87](../../stdlib/Net/Http/HttpError.sl#L87)</sub>

#### VersionNegotiationFailure *case*

```
VersionNegotiationFailure
```

The request's `VersionPolicy` ruled out every version the server or
the route would speak: HTTP/2 required and refused in ALPN, or asked
of a plain proxy.

<sub>[stdlib/Net/Http/HttpError.sl:92](../../stdlib/Net/Http/HttpError.sl#L92)</sub>

### HttpFailure *class*

```
sealed class HttpFailure
```

What went wrong with a request, in more detail than its `HttpError`.

    var response = client.Send(request, HttpCompletionOption.ResponseContentRead,
                               out HttpFailure failure);
    if (!response.Ok)
        Console.WriteLine(failure.Message);

.NET's `HttpRequestException`, handed back through `out` rather than
thrown. A request that succeeded leaves `Error` as `None`.

<sub>[stdlib/Net/Http/HttpFailure.sl:37](../../stdlib/Net/Http/HttpFailure.sl#L37)</sub>

#### Error *property*

```
HttpError Error { get; set; }
```

The case the request failed with.

<sub>[stdlib/Net/Http/HttpFailure.sl:43](../../stdlib/Net/Http/HttpFailure.sl#L43)</sub>

#### Message *property*

```
String Message { get; set; }
```

A sentence saying what happened.

<sub>[stdlib/Net/Http/HttpFailure.sl:46](../../stdlib/Net/Http/HttpFailure.sl#L46)</sub>

#### StatusCode *property*

```
Optional<HttpStatusCode> StatusCode { get; set; }
```

The status that caused the failure: a proxy's refusal, or what
`EnsureSuccessStatusCode` found.

<sub>[stdlib/Net/Http/HttpFailure.sl:50](../../stdlib/Net/Http/HttpFailure.sl#L50)</sub>

#### SocketErrorCode *property*

```
SocketError SocketErrorCode { get; set; }
```

The socket's own error, when a connection failed.

<sub>[stdlib/Net/Http/HttpFailure.sl:53](../../stdlib/Net/Http/HttpFailure.sl#L53)</sub>

#### TlsErrorCode *property*

```
TlsError TlsErrorCode { get; set; }
```

The TLS error, when `Error` is `TlsFailure`.

<sub>[stdlib/Net/Http/HttpFailure.sl:56](../../stdlib/Net/Http/HttpFailure.sl#L56)</sub>

#### TlsAlert *property*

```
TlsAlertDescription TlsAlert { get; set; }
```

The alert the server sent, when `TlsErrorCode` is `AlertReceived`.

<sub>[stdlib/Net/Http/HttpFailure.sl:59](../../stdlib/Net/Http/HttpFailure.sl#L59)</sub>

#### CompressionErrorCode *property*

```
CompressionError CompressionErrorCode { get; set; }
```

The decompressor's error, when `Error` is `DecompressionFailed`.

<sub>[stdlib/Net/Http/HttpFailure.sl:62](../../stdlib/Net/Http/HttpFailure.sl#L62)</sub>

#### ProtocolErrorCode *property*

```
long ProtocolErrorCode { get; set; }
```

The HTTP/2 error code the stream was reset with, or the connection
ended with, when `Error` is `ProtocolError`; zero, NO_ERROR, otherwise.

<sub>[stdlib/Net/Http/HttpFailure.sl:66](../../stdlib/Net/Http/HttpFailure.sl#L66)</sub>

#### RequestUri *property*

```
Uri? RequestUri { get; set; }
```

The URI of the request that failed.

<sub>[stdlib/Net/Http/HttpFailure.sl:69](../../stdlib/Net/Http/HttpFailure.sl#L69)</sub>

#### ToString *method*

```
String ToString()
```

The failure in words: the message, or the case described when there
is none.

<sub>[stdlib/Net/Http/HttpFailure.sl:93](../../stdlib/Net/Http/HttpFailure.sl#L93)</sub>

### HttpHeaders *class*

```
class HttpHeaders
```

The fields of a message head, by name, each with every value it was
given.

    request.Headers.Add("Accept", "text/html");
    request.Headers.Add("Accept", "application/xhtml+xml");
    String[] accepted = request.Headers.GetValues("accept");   // both

Names compare without regard to ASCII case and keep the spelling they were
first added with. A field given several values is written as several lines,
so a `Set-Cookie` is never joined with a comma.

.NET's `HttpHeaders`, with `GetValues` answering an empty array where .NET
throws. `Add` validates what it is given; `TryAddWithoutValidation` checks
only the name, and a value with a line break in it is refused when the
request is sent rather than written.

<sub>[stdlib/Net/Http/HttpHeaders.sl:42](../../stdlib/Net/Http/HttpHeaders.sl#L42)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many distinct names are present.

<sub>[stdlib/Net/Http/HttpHeaders.sl:49](../../stdlib/Net/Http/HttpHeaders.sl#L49)</sub>

#### Add *method*

```
bool Add(String name, String value)
```

Adds `value` to the field `name`, after its existing values.

**Parameters**

- `name` — the field name, which MUST be a token
- `value` — the value, which MUST NOT hold a control character but HTAB

**Returns** &nbsp; false when either is malformed, or `name` belongs to another collection — a `Content-Type` belongs on the content

<sub>[stdlib/Net/Http/HttpHeaders.sl:58](../../stdlib/Net/Http/HttpHeaders.sl#L58)</sub>

#### Add *method*

```
bool Add(String name, ReadOnlySpan<String> values)
```

Adds each of `values` to the field `name`. Nothing is added when any
of them is malformed.

<sub>[stdlib/Net/Http/HttpHeaders.sl:70](../../stdlib/Net/Http/HttpHeaders.sl#L70)</sub>

#### TryAddWithoutValidation *method*

```
bool TryAddWithoutValidation(String name, String value)
```

Adds `value` as it is, checking only that `name` is a token that
belongs here.

<sub>[stdlib/Net/Http/HttpHeaders.sl:86](../../stdlib/Net/Http/HttpHeaders.sl#L86)</sub>

#### Contains *method*

```
bool Contains(String name)
```

Whether the field `name` is present.

<sub>[stdlib/Net/Http/HttpHeaders.sl:95](../../stdlib/Net/Http/HttpHeaders.sl#L95)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes the field `name` and every value it had. False when it was not
present.

<sub>[stdlib/Net/Http/HttpHeaders.sl:99](../../stdlib/Net/Http/HttpHeaders.sl#L99)</sub>

#### Clear *method*

```
void Clear()
```

Removes every field.

<sub>[stdlib/Net/Http/HttpHeaders.sl:114](../../stdlib/Net/Http/HttpHeaders.sl#L114)</sub>

#### GetValues *method*

```
String[] GetValues(String name)
```

Every value of the field `name`, in the order added; empty when it is
not present.

<sub>[stdlib/Net/Http/HttpHeaders.sl:118](../../stdlib/Net/Http/HttpHeaders.sl#L118)</sub>

#### TryGetValues *method*

```
Optional<String[]> TryGetValues(String name)
```

Every value of the field `name`, or none when it is not present.

<sub>[stdlib/Net/Http/HttpHeaders.sl:127](../../stdlib/Net/Http/HttpHeaders.sl#L127)</sub>

#### GetEnumerator *method*

```
IEnumerator<KeyValuePair<String, String[]>> GetEnumerator()
```

Each field's name and values, in the order the names were first added.

<sub>[stdlib/Net/Http/HttpHeaders.sl:136](../../stdlib/Net/Http/HttpHeaders.sl#L136)</sub>

#### ToString *method*

```
String ToString()
```

The fields as a head writes them: a line per name, its values joined by
`, `, each line ending in CRLF.

<sub>[stdlib/Net/Http/HttpHeaders.sl:146](../../stdlib/Net/Http/HttpHeaders.sl#L146)</sub>

### HttpMethod *class*

```
threadsafe sealed class HttpMethod : IEquatable<HttpMethod>
```

An HTTP method: one of the standard nine, or any other token.

    var request = new HttpRequestMessage(HttpMethod.Put, uri);
    var custom = new HttpMethod("PROPFIND");

Methods compare by name, and the name is case-sensitive, as RFC 9110 says.
The standard ones are made afresh each time they are asked for rather than
kept in statics, which would be alive at exit in every program that
imports this module.

<sub>[stdlib/Net/Http/HttpMethod.sl:35](../../stdlib/Net/Http/HttpMethod.sl#L35)</sub>

#### Get *property*

```
static HttpMethod Get { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:43](../../stdlib/Net/Http/HttpMethod.sl#L43)</sub>

#### Post *property*

```
static HttpMethod Post { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:45](../../stdlib/Net/Http/HttpMethod.sl#L45)</sub>

#### Put *property*

```
static HttpMethod Put { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:47](../../stdlib/Net/Http/HttpMethod.sl#L47)</sub>

#### Delete *property*

```
static HttpMethod Delete { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:49](../../stdlib/Net/Http/HttpMethod.sl#L49)</sub>

#### Head *property*

```
static HttpMethod Head { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:51](../../stdlib/Net/Http/HttpMethod.sl#L51)</sub>

#### Options *property*

```
static HttpMethod Options { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:53](../../stdlib/Net/Http/HttpMethod.sl#L53)</sub>

#### Patch *property*

```
static HttpMethod Patch { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:55](../../stdlib/Net/Http/HttpMethod.sl#L55)</sub>

#### Trace *property*

```
static HttpMethod Trace { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:57](../../stdlib/Net/Http/HttpMethod.sl#L57)</sub>

#### Connect *property*

```
static HttpMethod Connect { get; }
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:59](../../stdlib/Net/Http/HttpMethod.sl#L59)</sub>

#### Method *property*

```
String Method { get; }
```

The name, as it goes on the request line.

<sub>[stdlib/Net/Http/HttpMethod.sl:62](../../stdlib/Net/Http/HttpMethod.sl#L62)</sub>

#### Equals *method*

```
bool Equals(HttpMethod other)
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:84](../../stdlib/Net/Http/HttpMethod.sl#L84)</sub>

#### operator == *operator*

```
static bool operator ==(HttpMethod left, HttpMethod right)
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:86](../../stdlib/Net/Http/HttpMethod.sl#L86)</sub>

#### operator != *operator*

```
static bool operator !=(HttpMethod left, HttpMethod right)
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:88](../../stdlib/Net/Http/HttpMethod.sl#L88)</sub>

#### ToString *method*

```
String ToString()
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpMethod.sl:90](../../stdlib/Net/Http/HttpMethod.sl#L90)</sub>

### HttpRequestHeaders *class*

```
sealed class HttpRequestHeaders : HttpHeaders
```

The fields of a request head.

A content field — `Content-Type`, `Content-Length` and the rest — is
refused here; it belongs on `HttpContent.Headers`. The typed properties
read and write the fields of the same name, so setting `UserAgent` is
`Remove("User-Agent")` and an `Add`, and a null removes it.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:30](../../stdlib/Net/Http/HttpRequestHeaders.sl#L30)</sub>

#### Accept *property*

```
String? Accept { get; set; }
```

`Accept`: the media types wanted.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:35](../../stdlib/Net/Http/HttpRequestHeaders.sl#L35)</sub>

#### AcceptEncoding *property*

```
String? AcceptEncoding { get; set; }
```

`Accept-Encoding`. `HttpClientHandler.AutomaticDecompression` sets it
when the request does not.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:43](../../stdlib/Net/Http/HttpRequestHeaders.sl#L43)</sub>

#### AcceptLanguage *property*

```
String? AcceptLanguage { get; set; }
```

`Accept-Language`.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:50](../../stdlib/Net/Http/HttpRequestHeaders.sl#L50)</sub>

#### Authorization *property*

```
String? Authorization { get; set; }
```

`Authorization`: a scheme and its credentials, as `Bearer abc`. Sent
to the request's origin and dropped by a redirect to another.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:58](../../stdlib/Net/Http/HttpRequestHeaders.sl#L58)</sub>

#### Connection *property*

```
String? Connection { get; set; }
```

`Connection`, as written.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:65](../../stdlib/Net/Http/HttpRequestHeaders.sl#L65)</sub>

#### ConnectionClose *property*

```
bool ConnectionClose { get; set; }
```

Whether `Connection` holds `close`, which ends the connection after
this exchange instead of pooling it.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:73](../../stdlib/Net/Http/HttpRequestHeaders.sl#L73)</sub>

#### ExpectContinue *property*

```
bool ExpectContinue { get; set; }
```

Whether `Expect` holds `100-continue`: the body waits for the server's
`100 Continue`, or for a second, whichever comes first.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:81](../../stdlib/Net/Http/HttpRequestHeaders.sl#L81)</sub>

#### Host *property*

```
String? Host { get; set; }
```

`Host`, when it should differ from the request URI's authority.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:88](../../stdlib/Net/Http/HttpRequestHeaders.sl#L88)</sub>

#### Referrer *property*

```
String? Referrer { get; set; }
```

`Referer`, as the field is spelt.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:95](../../stdlib/Net/Http/HttpRequestHeaders.sl#L95)</sub>

#### TransferEncodingChunked *property*

```
bool TransferEncodingChunked { get; set; }
```

Whether the body is sent chunked even when its length is known.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:102](../../stdlib/Net/Http/HttpRequestHeaders.sl#L102)</sub>

#### UserAgent *property*

```
String? UserAgent { get; set; }
```

`User-Agent`.

<sub>[stdlib/Net/Http/HttpRequestHeaders.sl:109](../../stdlib/Net/Http/HttpRequestHeaders.sl#L109)</sub>

### HttpRequestMessage *class*

```
class HttpRequestMessage
```

A request: a method, a URI, fields and perhaps a body.

    var request = new HttpRequestMessage(HttpMethod.Post, "https://example.com/items");
    request.Headers.Accept = "application/json";
    request.Content = new StringContent(json, null, "application/json");
    var response = try client.Send(request);

A redirect that is followed changes `RequestUri`, and a `303` changes
`Method` to `GET` and drops `Content`, as .NET does; afterwards the
message describes the request that was answered last.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:36](../../stdlib/Net/Http/HttpRequestMessage.sl#L36)</sub>

#### Method *property*

```
HttpMethod Method { get; set; }
```

The method.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:61](../../stdlib/Net/Http/HttpRequestMessage.sl#L61)</sub>

#### RequestUri *property*

```
Uri? RequestUri { get; set; }
```

Where the request goes, or null to take `HttpClient.BaseAddress`.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:64](../../stdlib/Net/Http/HttpRequestMessage.sl#L64)</sub>

#### Headers *property*

```
HttpRequestHeaders Headers { get; }
```

The request's own fields. `HttpClient.DefaultRequestHeaders` are
added to them when sent, where these do not already name the field.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:68](../../stdlib/Net/Http/HttpRequestMessage.sl#L68)</sub>

#### Content *property*

```
HttpContent? Content { get; set; }
```

The body, or null for none.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:71](../../stdlib/Net/Http/HttpRequestMessage.sl#L71)</sub>

#### Version *property*

```
Version Version { get; set; }
```

The version asked for, HTTP/1.1 unless set, as .NET's is.
`VersionPolicy` says how strictly it is kept to.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:75](../../stdlib/Net/Http/HttpRequestMessage.sl#L75)</sub>

#### VersionPolicy *property*

```
HttpVersionPolicy VersionPolicy { get; set; }
```

Whether a lower or a higher version than `Version` may be used.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:78](../../stdlib/Net/Http/HttpRequestMessage.sl#L78)</sub>

#### Dispose *method*

```
void Dispose()
```

Disposes the content.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:81](../../stdlib/Net/Http/HttpRequestMessage.sl#L81)</sub>

#### ToString *method*

```
String ToString()
```

The method and the URI.

<sub>[stdlib/Net/Http/HttpRequestMessage.sl:89](../../stdlib/Net/Http/HttpRequestMessage.sl#L89)</sub>

### HttpResponseHeaders *class*

```
sealed class HttpResponseHeaders : HttpHeaders
```

The fields of a response head, or of the trailer that follows a chunked
body.

A content field is kept on `HttpContent.Headers` instead, as .NET keeps
it. The typed properties read the fields of the same name.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:31](../../stdlib/Net/Http/HttpResponseHeaders.sl#L31)</sub>

#### Age *property*

```
Optional<long> Age { get; }
```

`Age`, in seconds, or none.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:36](../../stdlib/Net/Http/HttpResponseHeaders.sl#L36)</sub>

#### Connection *property*

```
String? Connection { get; set; }
```

`Connection`, as written.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:48](../../stdlib/Net/Http/HttpResponseHeaders.sl#L48)</sub>

#### ConnectionClose *property*

```
bool ConnectionClose { get; set; }
```

Whether `Connection` holds `close`: the server will close the
connection after this response.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:56](../../stdlib/Net/Http/HttpResponseHeaders.sl#L56)</sub>

#### Date *property*

```
Optional<DateTimeOffset> Date { get; }
```

`Date`, when it is an HTTP-date.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:63](../../stdlib/Net/Http/HttpResponseHeaders.sl#L63)</sub>

#### ETag *property*

```
String? ETag { get; set; }
```

`ETag`, quotes and all.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:77](../../stdlib/Net/Http/HttpResponseHeaders.sl#L77)</sub>

#### Location *property*

```
Uri? Location { get; }
```

`Location`: where a redirect points, or what a `201 Created` made.
Relative when the server wrote it relative; resolve it against the
request URI.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:86](../../stdlib/Net/Http/HttpResponseHeaders.sl#L86)</sub>

#### ProxyAuthenticate *property*

```
String? ProxyAuthenticate { get; }
```

`Proxy-Authenticate`: the challenge a proxy answered `407` with.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:100](../../stdlib/Net/Http/HttpResponseHeaders.sl#L100)</sub>

#### Server *property*

```
String? Server { get; set; }
```

`Server`.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:103](../../stdlib/Net/Http/HttpResponseHeaders.sl#L103)</sub>

#### TransferEncodingChunked *property*

```
bool TransferEncodingChunked { get; set; }
```

Whether `Transfer-Encoding` ends in `chunked`.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:110](../../stdlib/Net/Http/HttpResponseHeaders.sl#L110)</sub>

#### WwwAuthenticate *property*

```
String? WwwAuthenticate { get; }
```

`WWW-Authenticate`: the challenge a `401` came with.

<sub>[stdlib/Net/Http/HttpResponseHeaders.sl:117](../../stdlib/Net/Http/HttpResponseHeaders.sl#L117)</sub>

### HttpResponseMessage *class*

```
class HttpResponseMessage
```

A response: a status, fields, a body, and the request it answered.

    var response = try client.Get("https://example.com/");
    if (response.IsSuccessStatusCode)
        Console.WriteLine(try response.Content.ReadAsString());

A response holds its connection until its body has been read to the end,
and closes it when disposed or released before then.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:35](../../stdlib/Net/Http/HttpResponseMessage.sl#L35)</sub>

#### StatusCode *property*

```
HttpStatusCode StatusCode { get; set; }
```

The status.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:48](../../stdlib/Net/Http/HttpResponseMessage.sl#L48)</sub>

#### ReasonPhrase *property*

```
String ReasonPhrase { get; set; }
```

The reason phrase the server sent, or RFC 9110's for the status when
none was set.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:52](../../stdlib/Net/Http/HttpResponseMessage.sl#L52)</sub>

#### Headers *property*

```
HttpResponseHeaders Headers { get; }
```

The response's fields, less the content's.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:63](../../stdlib/Net/Http/HttpResponseMessage.sl#L63)</sub>

#### TrailingHeaders *property*

```
HttpResponseHeaders TrailingHeaders { get; }
```

The trailer of a chunked body. Filled in once the body has been read
to its end, and empty until then.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:67](../../stdlib/Net/Http/HttpResponseMessage.sl#L67)</sub>

#### Content *property*

```
HttpContent Content { get; set; }
```

The body. A response with none has empty content rather than null.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:70](../../stdlib/Net/Http/HttpResponseMessage.sl#L70)</sub>

#### Version *property*

```
Version Version { get; set; }
```

The version the server answered in.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:73](../../stdlib/Net/Http/HttpResponseMessage.sl#L73)</sub>

#### RequestMessage *property*

```
HttpRequestMessage? RequestMessage { get; set; }
```

The request this answered: after redirects, the last one sent.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:76](../../stdlib/Net/Http/HttpResponseMessage.sl#L76)</sub>

#### IsSuccessStatusCode *property*

```
bool IsSuccessStatusCode { get; }
```

Whether the status is in 200–299.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:79](../../stdlib/Net/Http/HttpResponseMessage.sl#L79)</sub>

#### EnsureSuccessStatusCode *method*

```
Result<HttpResponseMessage, HttpError> EnsureSuccessStatusCode()
```

This response when `IsSuccessStatusCode`, and a failure otherwise.

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status is outside 200–299

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:84](../../stdlib/Net/Http/HttpResponseMessage.sl#L84)</sub>

#### EnsureSuccessStatusCode *method*

```
Result<HttpResponseMessage, HttpError> EnsureSuccessStatusCode(out HttpFailure failure)
```

The same, saying which status it was.

**Parameters**

- `failure` — the status and a message when it fails

**Fails with**

- [HttpError.UnsuccessfulStatusCode](#unsuccessfulstatuscode-case) — the status is outside 200–299

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:91](../../stdlib/Net/Http/HttpResponseMessage.sl#L91)</sub>

#### Dispose *method*

```
void Dispose()
```

Releases the body, closing the connection if it was not read to its
end.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:106](../../stdlib/Net/Http/HttpResponseMessage.sl#L106)</sub>

#### ToString *method*

```
String ToString()
```

The status line.

<sub>[stdlib/Net/Http/HttpResponseMessage.sl:109](../../stdlib/Net/Http/HttpResponseMessage.sl#L109)</sub>

### HttpServerCertificateValidator *closure*

```
closure bool HttpServerCertificateValidator(HttpRequestMessage request, X509Certificate2? certificate, List<byte[]> chain, TlsError defaultVerdict)
```

Decides whether to trust a server's certificate chain for a request.

`certificate` is the leaf, parsed, or null when it could not be; `chain`
is every certificate as the server sent it, DER, leaf first. `defaultVerdict`
is what the TLS module's own validator answered — `None` when it would
have trusted the chain — as .NET hands over its `SslPolicyErrors`. The
answer is whether to go on.

**See also** &nbsp; [HttpClientHandler.ServerCertificateCustomValidationCallback](#servercertificatecustomvalidationcallback-property)

<sub>[stdlib/Net/Http/HttpServerCertificateValidator.sl:37](../../stdlib/Net/Http/HttpServerCertificateValidator.sl#L37)</sub>

### HttpStatusCode *enum*

```
enum HttpStatusCode
```

The status codes RFC 9110 and its companions register, by .NET's names.

A response may carry a code with no name here; it is still a value of
this type, cast from its number, and prints as that number.

<sub>[stdlib/Net/Http/HttpStatusCode.sl:28](../../stdlib/Net/Http/HttpStatusCode.sl#L28)</sub>

#### Continue *case*

```
Continue = 100
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:30](../../stdlib/Net/Http/HttpStatusCode.sl#L30)</sub>

#### SwitchingProtocols *case*

```
SwitchingProtocols = 101
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:31](../../stdlib/Net/Http/HttpStatusCode.sl#L31)</sub>

#### Processing *case*

```
Processing = 102
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:32](../../stdlib/Net/Http/HttpStatusCode.sl#L32)</sub>

#### EarlyHints *case*

```
EarlyHints = 103
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:33](../../stdlib/Net/Http/HttpStatusCode.sl#L33)</sub>

#### OK *case*

```
OK = 200
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:35](../../stdlib/Net/Http/HttpStatusCode.sl#L35)</sub>

#### Created *case*

```
Created = 201
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:36](../../stdlib/Net/Http/HttpStatusCode.sl#L36)</sub>

#### Accepted *case*

```
Accepted = 202
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:37](../../stdlib/Net/Http/HttpStatusCode.sl#L37)</sub>

#### NonAuthoritativeInformation *case*

```
NonAuthoritativeInformation = 203
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:38](../../stdlib/Net/Http/HttpStatusCode.sl#L38)</sub>

#### NoContent *case*

```
NoContent = 204
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:39](../../stdlib/Net/Http/HttpStatusCode.sl#L39)</sub>

#### ResetContent *case*

```
ResetContent = 205
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:40](../../stdlib/Net/Http/HttpStatusCode.sl#L40)</sub>

#### PartialContent *case*

```
PartialContent = 206
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:41](../../stdlib/Net/Http/HttpStatusCode.sl#L41)</sub>

#### MultiStatus *case*

```
MultiStatus = 207
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:42](../../stdlib/Net/Http/HttpStatusCode.sl#L42)</sub>

#### AlreadyReported *case*

```
AlreadyReported = 208
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:43](../../stdlib/Net/Http/HttpStatusCode.sl#L43)</sub>

#### IMUsed *case*

```
IMUsed = 226
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:44](../../stdlib/Net/Http/HttpStatusCode.sl#L44)</sub>

#### MultipleChoices *case*

```
MultipleChoices = 300
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:46](../../stdlib/Net/Http/HttpStatusCode.sl#L46)</sub>

#### MovedPermanently *case*

```
MovedPermanently = 301
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:47](../../stdlib/Net/Http/HttpStatusCode.sl#L47)</sub>

#### Found *case*

```
Found = 302
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:48](../../stdlib/Net/Http/HttpStatusCode.sl#L48)</sub>

#### SeeOther *case*

```
SeeOther = 303
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:49](../../stdlib/Net/Http/HttpStatusCode.sl#L49)</sub>

#### NotModified *case*

```
NotModified = 304
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:50](../../stdlib/Net/Http/HttpStatusCode.sl#L50)</sub>

#### UseProxy *case*

```
UseProxy = 305
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:51](../../stdlib/Net/Http/HttpStatusCode.sl#L51)</sub>

#### Unused *case*

```
Unused = 306
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:52](../../stdlib/Net/Http/HttpStatusCode.sl#L52)</sub>

#### TemporaryRedirect *case*

```
TemporaryRedirect = 307
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:53](../../stdlib/Net/Http/HttpStatusCode.sl#L53)</sub>

#### PermanentRedirect *case*

```
PermanentRedirect = 308
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:54](../../stdlib/Net/Http/HttpStatusCode.sl#L54)</sub>

#### BadRequest *case*

```
BadRequest = 400
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:56](../../stdlib/Net/Http/HttpStatusCode.sl#L56)</sub>

#### Unauthorized *case*

```
Unauthorized = 401
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:57](../../stdlib/Net/Http/HttpStatusCode.sl#L57)</sub>

#### PaymentRequired *case*

```
PaymentRequired = 402
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:58](../../stdlib/Net/Http/HttpStatusCode.sl#L58)</sub>

#### Forbidden *case*

```
Forbidden = 403
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:59](../../stdlib/Net/Http/HttpStatusCode.sl#L59)</sub>

#### NotFound *case*

```
NotFound = 404
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:60](../../stdlib/Net/Http/HttpStatusCode.sl#L60)</sub>

#### MethodNotAllowed *case*

```
MethodNotAllowed = 405
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:61](../../stdlib/Net/Http/HttpStatusCode.sl#L61)</sub>

#### NotAcceptable *case*

```
NotAcceptable = 406
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:62](../../stdlib/Net/Http/HttpStatusCode.sl#L62)</sub>

#### ProxyAuthenticationRequired *case*

```
ProxyAuthenticationRequired = 407
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:63](../../stdlib/Net/Http/HttpStatusCode.sl#L63)</sub>

#### RequestTimeout *case*

```
RequestTimeout = 408
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:64](../../stdlib/Net/Http/HttpStatusCode.sl#L64)</sub>

#### Conflict *case*

```
Conflict = 409
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:65](../../stdlib/Net/Http/HttpStatusCode.sl#L65)</sub>

#### Gone *case*

```
Gone = 410
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:66](../../stdlib/Net/Http/HttpStatusCode.sl#L66)</sub>

#### LengthRequired *case*

```
LengthRequired = 411
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:67](../../stdlib/Net/Http/HttpStatusCode.sl#L67)</sub>

#### PreconditionFailed *case*

```
PreconditionFailed = 412
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:68](../../stdlib/Net/Http/HttpStatusCode.sl#L68)</sub>

#### RequestEntityTooLarge *case*

```
RequestEntityTooLarge = 413
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:69](../../stdlib/Net/Http/HttpStatusCode.sl#L69)</sub>

#### RequestUriTooLong *case*

```
RequestUriTooLong = 414
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:70](../../stdlib/Net/Http/HttpStatusCode.sl#L70)</sub>

#### UnsupportedMediaType *case*

```
UnsupportedMediaType = 415
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:71](../../stdlib/Net/Http/HttpStatusCode.sl#L71)</sub>

#### RequestedRangeNotSatisfiable *case*

```
RequestedRangeNotSatisfiable = 416
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:72](../../stdlib/Net/Http/HttpStatusCode.sl#L72)</sub>

#### ExpectationFailed *case*

```
ExpectationFailed = 417
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:73](../../stdlib/Net/Http/HttpStatusCode.sl#L73)</sub>

#### MisdirectedRequest *case*

```
MisdirectedRequest = 421
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:74](../../stdlib/Net/Http/HttpStatusCode.sl#L74)</sub>

#### UnprocessableContent *case*

```
UnprocessableContent = 422
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:75](../../stdlib/Net/Http/HttpStatusCode.sl#L75)</sub>

#### Locked *case*

```
Locked = 423
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:76](../../stdlib/Net/Http/HttpStatusCode.sl#L76)</sub>

#### FailedDependency *case*

```
FailedDependency = 424
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:77](../../stdlib/Net/Http/HttpStatusCode.sl#L77)</sub>

#### UpgradeRequired *case*

```
UpgradeRequired = 426
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:78](../../stdlib/Net/Http/HttpStatusCode.sl#L78)</sub>

#### PreconditionRequired *case*

```
PreconditionRequired = 428
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:79](../../stdlib/Net/Http/HttpStatusCode.sl#L79)</sub>

#### TooManyRequests *case*

```
TooManyRequests = 429
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:80](../../stdlib/Net/Http/HttpStatusCode.sl#L80)</sub>

#### RequestHeaderFieldsTooLarge *case*

```
RequestHeaderFieldsTooLarge = 431
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:81](../../stdlib/Net/Http/HttpStatusCode.sl#L81)</sub>

#### UnavailableForLegalReasons *case*

```
UnavailableForLegalReasons = 451
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:82](../../stdlib/Net/Http/HttpStatusCode.sl#L82)</sub>

#### InternalServerError *case*

```
InternalServerError = 500
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:84](../../stdlib/Net/Http/HttpStatusCode.sl#L84)</sub>

#### NotImplemented *case*

```
NotImplemented = 501
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:85](../../stdlib/Net/Http/HttpStatusCode.sl#L85)</sub>

#### BadGateway *case*

```
BadGateway = 502
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:86](../../stdlib/Net/Http/HttpStatusCode.sl#L86)</sub>

#### ServiceUnavailable *case*

```
ServiceUnavailable = 503
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:87](../../stdlib/Net/Http/HttpStatusCode.sl#L87)</sub>

#### GatewayTimeout *case*

```
GatewayTimeout = 504
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:88](../../stdlib/Net/Http/HttpStatusCode.sl#L88)</sub>

#### HttpVersionNotSupported *case*

```
HttpVersionNotSupported = 505
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:89](../../stdlib/Net/Http/HttpStatusCode.sl#L89)</sub>

#### VariantAlsoNegotiates *case*

```
VariantAlsoNegotiates = 506
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:90](../../stdlib/Net/Http/HttpStatusCode.sl#L90)</sub>

#### InsufficientStorage *case*

```
InsufficientStorage = 507
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:91](../../stdlib/Net/Http/HttpStatusCode.sl#L91)</sub>

#### LoopDetected *case*

```
LoopDetected = 508
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:92](../../stdlib/Net/Http/HttpStatusCode.sl#L92)</sub>

#### NotExtended *case*

```
NotExtended = 510
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:93](../../stdlib/Net/Http/HttpStatusCode.sl#L93)</sub>

#### NetworkAuthenticationRequired *case*

```
NetworkAuthenticationRequired = 511
```

*No documentation.*

<sub>[stdlib/Net/Http/HttpStatusCode.sl:94](../../stdlib/Net/Http/HttpStatusCode.sl#L94)</sub>

### HttpVersion *class*

```
class HttpVersion
```

The protocol versions a message can name.

<sub>[stdlib/Net/Http/HttpVersion.sl:25](../../stdlib/Net/Http/HttpVersion.sl#L25)</sub>

### HttpVersionPolicy *enum*

```
enum HttpVersionPolicy
```

How strictly `HttpRequestMessage.Version` is kept to: .NET's
`HttpVersionPolicy`.

| Version | Policy | https | http |
|---|---|---|---|
| 1.1 | `RequestVersionOrLower` | HTTP/1.1 | HTTP/1.1 |
| 1.1 | `RequestVersionOrHigher` | h2 if ALPN agrees, else 1.1 | HTTP/1.1 |
| 1.1 | `RequestVersionExact` | HTTP/1.1 | HTTP/1.1 |
| 2.0 | `RequestVersionOrLower` | h2 if ALPN agrees, else 1.1 | HTTP/1.1 |
| 2.0 | `RequestVersionOrHigher` | h2, or a failure | h2 with prior knowledge |
| 2.0 | `RequestVersionExact` | h2, or a failure | h2 with prior knowledge |

Plain http never upgrades: HTTP/2 is used there only when the request
will take nothing else, and then it is spoken from the first byte. A
request through a plain proxy is always HTTP/1.1, since the proxy is
spoken to in absolute form; through a `CONNECT` tunnel it is https as
above. A version this module does not speak — 3.0 — is taken as 2.0 when
the policy lets it be lower, and refused otherwise.

<sub>[stdlib/Net/Http/HttpVersionPolicy.sl:42](../../stdlib/Net/Http/HttpVersionPolicy.sl#L42)</sub>

#### RequestVersionOrLower *case*

```
RequestVersionOrLower
```

The version asked for, or a lower one the server prefers. The default.

<sub>[stdlib/Net/Http/HttpVersionPolicy.sl:45](../../stdlib/Net/Http/HttpVersionPolicy.sl#L45)</sub>

#### RequestVersionOrHigher *case*

```
RequestVersionOrHigher
```

The version asked for, or a higher one the server offers.

<sub>[stdlib/Net/Http/HttpVersionPolicy.sl:48](../../stdlib/Net/Http/HttpVersionPolicy.sl#L48)</sub>

#### RequestVersionExact *case*

```
RequestVersionExact
```

The version asked for and no other.

<sub>[stdlib/Net/Http/HttpVersionPolicy.sl:51](../../stdlib/Net/Http/HttpVersionPolicy.sl#L51)</sub>

### IWebProxy *interface*

```
interface IWebProxy
```

Decides which proxy, if any, a request goes through.

.NET's `System.Net.IWebProxy`. `HttpClientHandler` asks `IsBypassed`
first and then `GetProxy`; an answer of null, or of the destination
itself, goes direct.

**See also** &nbsp; [WebProxy](#webproxy-class) &middot; [HttpEnvironmentProxy](#httpenvironmentproxy-class)

<sub>[stdlib/Net/Http/IWebProxy.sl:32](../../stdlib/Net/Http/IWebProxy.sl#L32)</sub>

#### Credentials *property*

```
NetworkCredential? Credentials { get; set; }
```

Sent to the proxy as Basic `Proxy-Authorization`, when not null.

<sub>[stdlib/Net/Http/IWebProxy.sl:35](../../stdlib/Net/Http/IWebProxy.sl#L35)</sub>

#### GetProxy *method*

```
Uri? GetProxy(Uri destination)
```

The proxy for `destination`: an `http:` URI, or null to go direct.

<sub>[stdlib/Net/Http/IWebProxy.sl:38](../../stdlib/Net/Http/IWebProxy.sl#L38)</sub>

#### IsBypassed *method*

```
bool IsBypassed(Uri host)
```

Whether `host` goes direct.

<sub>[stdlib/Net/Http/IWebProxy.sl:41](../../stdlib/Net/Http/IWebProxy.sl#L41)</sub>

### MediaTypeHeaderValue *class*

```
sealed class MediaTypeHeaderValue
```

A media type and its parameters: the value of `Content-Type`.

    var type = new MediaTypeHeaderValue("text/plain", "utf-8");
    type.ToString();                     // text/plain; charset=utf-8

Parameter names compare without regard to case. A value that is not a
token is written as a quoted string.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:34](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L34)</sub>

#### MediaType *property*

```
String MediaType { get; set; }
```

`type/subtype`, without parameters.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:51](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L51)</sub>

#### CharSet *property*

```
String? CharSet { get; set; }
```

The `charset` parameter, or null.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:58](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L58)</sub>

#### Parameters *property*

```
List<KeyValuePair<String, String>> Parameters { get; }
```

The parameters, in order, names as written.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:65](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L65)</sub>

#### GetParameter *method*

```
String? GetParameter(String name)
```

The parameter `name`, or null.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:68](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L68)</sub>

#### SetParameter *method*

```
void SetParameter(String name, String? value)
```

Replaces the parameter `name`, or removes it for null.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:79](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L79)</sub>

#### Parse *method*

```
static Result<MediaTypeHeaderValue, ParseError> Parse(String text)
```

`text` read as `type/subtype *( ; name=value )`, a value either a token
or a quoted string.

**Fails with**

- [ParseError.Empty](Standard.md#empty-case) — there is nothing but whitespace
- [ParseError.Malformed](Standard.md#malformed-case) — it is not that shape

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:98](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L98)</sub>

#### ToString *method*

```
String ToString()
```

The value as a field writes it.

<sub>[stdlib/Net/Http/MediaTypeHeaderValue.sl:176](../../stdlib/Net/Http/MediaTypeHeaderValue.sl#L176)</sub>

### MultipartContent *class*

```
class MultipartContent : HttpContent
```

Several bodies in one, each with its own fields, between boundaries:
RFC 2046's `multipart`.

    var parts = new MultipartContent("mixed");
    parts.Add(new StringContent("first"));
    parts.Add(new ByteArrayContent(image));

The length is known when every part's is, and the whole can be sent again
when every part can.

<sub>[stdlib/Net/Http/MultipartContent.sl:37](../../stdlib/Net/Http/MultipartContent.sl#L37)</sub>

#### Boundary *property*

```
String Boundary { get; }
```

The boundary between parts.

<sub>[stdlib/Net/Http/MultipartContent.sl:59](../../stdlib/Net/Http/MultipartContent.sl#L59)</sub>

#### Parts *property*

```
List<HttpContent> Parts { get; }
```

The parts, in order.

<sub>[stdlib/Net/Http/MultipartContent.sl:62](../../stdlib/Net/Http/MultipartContent.sl#L62)</sub>

#### Add *method*

```
void Add(HttpContent content)
```

Adds a part after the others.

<sub>[stdlib/Net/Http/MultipartContent.sl:65](../../stdlib/Net/Http/MultipartContent.sl#L65)</sub>

#### Dispose *method*

```
override void Dispose()
```

Disposes every part.

<sub>[stdlib/Net/Http/MultipartContent.sl:125](../../stdlib/Net/Http/MultipartContent.sl#L125)</sub>

### MultipartFormDataContent *class*

```
class MultipartFormDataContent : MultipartContent
```

`multipart/form-data`: named fields and files, as an HTML form with a file
input posts them (RFC 7578).

    var form = new MultipartFormDataContent();
    form.Add(new StringContent("ann"), "user");
    form.Add(new ByteArrayContent(photo), "photo", "photo.jpg");

<sub>[stdlib/Net/Http/MultipartFormDataContent.sl:30](../../stdlib/Net/Http/MultipartFormDataContent.sl#L30)</sub>

#### Add *method*

```
void Add(HttpContent content, String name)
```

Adds `content` as the field `name`.

<sub>[stdlib/Net/Http/MultipartFormDataContent.sl:39](../../stdlib/Net/Http/MultipartFormDataContent.sl#L39)</sub>

#### Add *method*

```
void Add(HttpContent content, String name, String fileName)
```

Adds `content` as the file `fileName` in the field `name`.

<sub>[stdlib/Net/Http/MultipartFormDataContent.sl:46](../../stdlib/Net/Http/MultipartFormDataContent.sl#L46)</sub>

### NetworkCredential *class*

```
sealed class NetworkCredential
```

A user name and a password, for a proxy that asks for Basic credentials.

.NET's `System.Net.NetworkCredential`, kept here beside the client that is
its only user.

<sub>[stdlib/Net/Http/NetworkCredential.sl:28](../../stdlib/Net/Http/NetworkCredential.sl#L28)</sub>

#### UserName *property*

```
String UserName { get; set; }
```

*No documentation.*

<sub>[stdlib/Net/Http/NetworkCredential.sl:48](../../stdlib/Net/Http/NetworkCredential.sl#L48)</sub>

#### Password *property*

```
String Password { get; set; }
```

*No documentation.*

<sub>[stdlib/Net/Http/NetworkCredential.sl:50](../../stdlib/Net/Http/NetworkCredential.sl#L50)</sub>

#### Domain *property*

```
String Domain { get; set; }
```

*No documentation.*

<sub>[stdlib/Net/Http/NetworkCredential.sl:52](../../stdlib/Net/Http/NetworkCredential.sl#L52)</sub>

### StreamContent *class*

```
class StreamContent : HttpContent
```

A body read from a stream as it is sent.

A seekable stream knows its length, from where it stood when the content
was made to its end, and is sent with `Content-Length`; any other stream
is sent chunked. Only a seekable stream can be sent twice, so only its
body survives a `307` or `308`, or a retry.

<sub>[stdlib/Net/Http/StreamContent.sl:32](../../stdlib/Net/Http/StreamContent.sl#L32)</sub>

#### Dispose *method*

```
override void Dispose()
```

Closes the stream.

<sub>[stdlib/Net/Http/StreamContent.sl:91](../../stdlib/Net/Http/StreamContent.sl#L91)</sub>

### StringContent *class*

```
class StringContent : ByteArrayContent
```

A body of text, encoded when it is made.

    new StringContent("hello")                          // text/plain; charset=utf-8
    new StringContent(json, Encoding.CreateUtf8(), "application/json")

`Content-Type` names the media type and the encoding's charset.

<sub>[stdlib/Net/Http/StringContent.sl:32](../../stdlib/Net/Http/StringContent.sl#L32)</sub>

### WebProxy *class*

```
class WebProxy : IWebProxy
```

One HTTP proxy, and the hosts that go around it.

    var handler = new HttpClientHandler();
    handler.Proxy = new WebProxy("http://proxy.example:3128", true,
                                 ["*.internal.example", "10.*"]);

.NET's `System.Net.WebProxy`, with one difference: a `BypassList` entry is
a pattern in which `*` stands for any run of characters, matched against
the host without regard to case — or against `host:port` when it names a
port — rather than a regular expression.

<sub>[stdlib/Net/Http/WebProxy.sl:36](../../stdlib/Net/Http/WebProxy.sl#L36)</sub>

#### Address *property*

```
Uri? Address { get; set; }
```

Where the proxy is, or null for none.

<sub>[stdlib/Net/Http/WebProxy.sl:63](../../stdlib/Net/Http/WebProxy.sl#L63)</sub>

#### BypassProxyOnLocal *property*

```
bool BypassProxyOnLocal { get; set; }
```

Whether a host with no dot in its name, or a loopback address, goes
direct.

<sub>[stdlib/Net/Http/WebProxy.sl:67](../../stdlib/Net/Http/WebProxy.sl#L67)</sub>

#### BypassList *property*

```
String[] BypassList { get; set; }
```

Patterns of hosts that go direct.

<sub>[stdlib/Net/Http/WebProxy.sl:70](../../stdlib/Net/Http/WebProxy.sl#L70)</sub>

#### Credentials *property*

```
NetworkCredential? Credentials { get; set; }
```

Sent to the proxy as Basic credentials, when not null.

<sub>[stdlib/Net/Http/WebProxy.sl:73](../../stdlib/Net/Http/WebProxy.sl#L73)</sub>

#### GetProxy *method*

```
Uri? GetProxy(Uri destination)
```

`Address`, or `destination` itself when it goes direct.

<sub>[stdlib/Net/Http/WebProxy.sl:76](../../stdlib/Net/Http/WebProxy.sl#L76)</sub>

#### IsBypassed *method*

```
bool IsBypassed(Uri host)
```

Whether `host` goes direct: there is no proxy, it is local and local
hosts go direct, or a pattern matches it.

<sub>[stdlib/Net/Http/WebProxy.sl:87](../../stdlib/Net/Http/WebProxy.sl#L87)</sub>

## Functions

### DescribeHttpError *function*

```
String DescribeHttpError(HttpError error)
```

A sentence describing an HTTP error, for a message a person will read.

**See also** &nbsp; [HttpError](#httperror-enum)

<sub>[stdlib/Net/Http/Http.sl:120](../../stdlib/Net/Http/Http.sl#L120)</sub>

