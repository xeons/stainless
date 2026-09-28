// SPDX-License-Identifier: 0BSD
// RFC 8448 §3, the simple 1-RTT handshake, replayed against this library.
//
// Four parts. The key schedule is fed the trace's shared secret and
// transcript and must produce every secret the trace prints. The record
// cipher must seal and open the trace's records byte for byte. The client,
// given the trace's ClientHello and X25519 key, reads the trace's server
// records from a scripted stream, and must accept them — the RSA-PSS
// CertificateVerify included — and write exactly the trace's Finished,
// application data and close_notify records. The server, given the trace's
// random and X25519 key and the trace's ClientHello, must write exactly the
// trace's ServerHello, and a flight the trace's handshake keys open, holding
// the trace's Certificate and a CertificateVerify and Finished that check.
module Tls13Rfc8448;

import Standard.Collections;
import Standard.Console;
import Standard.Convert;
import Standard.IO;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Text;

/// A stream that hands out a fixed script and keeps what is written.
class ScriptedStream : IStream
{
    private byte[] _script;
    private nuint _at;
    private List<byte> _written;

    public ScriptedStream(byte[] script)
    {
        _script = script;
        _at = 0u;
        _written = new List<byte>();
    }

    public byte[] Written
    {
        get
        {
            var all = new byte[_written.Count];
            for (nuint i = 0u; i < all.Length; i++)
                all[i] = _written[i];
            return all;
        }
    }

    public void ForgetWritten() => _written.Clear();

    public bool CanRead => true;
    public bool CanWrite => true;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        nuint taking = _script.Length - _at;
        if (taking > count)
            taking = count;
        for (nuint i = 0u; i < taking; i++)
            buffer[offset + i] = _script[_at + i];
        _at += taking;
        return taking;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        for (nuint i = 0u; i < count; i++)
            _written.Add(buffer[offset + i]);
        return count;
    }

    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => IOError.None;
}

byte[] Hex(String text) =>
    Convert.FromHexString(text.Replace("\n", "")).GetValueOrDefault(new byte[0u]);

byte[] JoinBytes(byte[] first, byte[] second)
{
    var joined = new byte[first.Length + second.Length];
    for (nuint i = 0u; i < first.Length; i++)
        joined[i] = first[i];
    for (nuint i = 0u; i < second.Length; i++)
        joined[first.Length + i] = second[i];
    return joined;
}

byte[] SliceBytes(byte[] data, nuint start, nuint length)
{
    var part = new byte[length];
    for (nuint i = 0u; i < length; i++)
        part[i] = data[start + i];
    return part;
}

bool AreSame(byte[] left, byte[] right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

void Check(String name, byte[] actual, String expected)
{
    if (AreSame(actual, Hex(expected)))
        Console.WriteLine(name + ": ok");
    else
        Console.WriteLine(name + ": MISMATCH " + Convert.ToHexString(actual, false));
}

void Say(String name, bool value) => Console.WriteLine(name + ": " + (value ? "yes" : "no"));

// ------------------------------------------------------------ key schedule

void CheckKeySchedule()
{
    var shared = X25519.DeriveSharedSecret(Hex(ClientPrivateKey), Hex(ServerPublicKey));
    Check("x25519 shared secret", shared.GetValueOrDefault(new byte[0u]), SharedSecret);

    var schedule = new TlsTestKeySchedule();
    Check("early secret", schedule.EarlySecret, EarlySecret);

    byte[] hello = JoinBytes(Hex(ClientHello), Hex(ServerHello));
    Check("hash through ServerHello", schedule.HashTranscript(hello), HelloHash);
    schedule.DeriveHandshake(Hex(SharedSecret), Hex(HelloHash));
    Check("handshake secret", schedule.HandshakeSecret, HandshakeSecret);
    Check("c hs traffic", schedule.ClientHandshakeTraffic, ClientHandshakeTraffic);
    Check("s hs traffic", schedule.ServerHandshakeTraffic, ServerHandshakeTraffic);
    Check("server handshake key", schedule.ExpandLabel(schedule.ServerHandshakeTraffic, "key", 16u),
          ServerHandshakeKey);
    Check("server handshake iv", schedule.ExpandLabel(schedule.ServerHandshakeTraffic, "iv", 12u),
          ServerHandshakeIv);
    Check("client handshake key", schedule.ExpandLabel(schedule.ClientHandshakeTraffic, "key", 16u),
          ClientHandshakeKey);
    Check("client handshake iv", schedule.ExpandLabel(schedule.ClientHandshakeTraffic, "iv", 12u),
          ClientHandshakeIv);

    byte[] throughVerify = JoinBytes(JoinBytes(JoinBytes(hello, Hex(EncryptedExtensions)),
                                               Hex(Certificate)), Hex(CertificateVerify));
    Check("server finished", schedule.ComputeFinished(schedule.ServerHandshakeTraffic,
                                                      schedule.HashTranscript(throughVerify)),
          ServerFinishedData);

    byte[] throughServerFinished = JoinBytes(throughVerify, Hex(ServerFinished));
    Check("hash through server Finished", schedule.HashTranscript(throughServerFinished),
          ServerFinishedHash);
    schedule.DeriveApplication(Hex(ServerFinishedHash));
    Check("master secret", schedule.MasterSecret, MasterSecret);
    Check("c ap traffic", schedule.ClientApplicationTraffic, ClientApplicationTraffic);
    Check("s ap traffic", schedule.ServerApplicationTraffic, ServerApplicationTraffic);
    Check("exp master", schedule.ExporterMaster, ExporterMaster);
    Check("server application key", schedule.ExpandLabel(schedule.ServerApplicationTraffic, "key", 16u),
          ServerApplicationKey);
    Check("server application iv", schedule.ExpandLabel(schedule.ServerApplicationTraffic, "iv", 12u),
          ServerApplicationIv);
    Check("client application key", schedule.ExpandLabel(schedule.ClientApplicationTraffic, "key", 16u),
          ClientApplicationKey);
    Check("client application iv", schedule.ExpandLabel(schedule.ClientApplicationTraffic, "iv", 12u),
          ClientApplicationIv);

    Check("client finished", schedule.ComputeFinished(schedule.ClientHandshakeTraffic,
                                                      schedule.HashTranscript(throughServerFinished)),
          ClientFinishedData);
    byte[] throughClientFinished = JoinBytes(throughServerFinished, Hex(ClientFinished));
    Check("hash through client Finished", schedule.HashTranscript(throughClientFinished),
          ClientFinishedHash);
    schedule.DeriveResumption(Hex(ClientFinishedHash));
    Check("res master", schedule.ResumptionMaster, ResumptionMaster);
    Check("resumption key", schedule.DeriveResumptionKey(Hex("0000")), ResumptionKey);
}

// ----------------------------------------------------------------- records

void CheckRecords()
{
    byte[] opened = OpenTlsTestRecord(Hex(ServerHandshakeTraffic), Hex(ServerFlightRecord));
    Check("open server flight", opened, ServerFlight + "16");
    Check("seal server flight", SealTlsTestRecord(Hex(ServerHandshakeTraffic), 0x16, Hex(ServerFlight)),
          ServerFlightRecord);
    Check("seal client Finished", SealTlsTestRecord(Hex(ClientHandshakeTraffic), 0x16, Hex(ClientFinished)),
          ClientFinishedRecord);
    Check("seal ticket", SealTlsTestRecord(Hex(ServerApplicationTraffic), 0x16, Hex(NewSessionTicket)),
          NewSessionTicketRecord);
}

// ------------------------------------------------------------------ client

TlsError AcceptTheTraceCertificate(List<byte[]> chain, String targetHost)
{
    Console.WriteLine("validator: " + Text.FromInteger((long)chain.Count) + " certificate of " +
                      Text.FromInteger((long)chain[0u].Length) + " bytes for '" + targetHost + "'");
    return TlsError.None;
}

void ReportTicket(TlsSessionTicket ticket)
{
    Console.WriteLine("ticket: lifetime " + Text.FromInteger((long)ticket.Lifetime) + ", " +
                      Text.FromInteger((long)ticket.Ticket.Length) + " bytes, early data " +
                      Text.FromInteger((long)ticket.MaxEarlyDataSize));
    Check("ticket nonce", ticket.Nonce, "0000");
    Check("ticket resumption key", ticket.ResumptionKey, ResumptionKey);
}

void CheckClient()
{
    byte[] script = JoinBytes(JoinBytes(JoinBytes(JoinBytes(Hex(ServerHelloRecord), Hex(ServerFlightRecord)),
                                                  Hex(NewSessionTicketRecord)),
                                        Hex(ServerApplicationRecord)),
                              Hex(ServerAlertRecord));
    var stream = new ScriptedStream(script);

    var options = new TlsClientOptions();
    options.TargetHost = "server";
    options.CertificateValidator = AcceptTheTraceCertificate;
    options.SessionTicketReceived = ReportTicket;
    options.LeaveInnerStreamOpen = true;
    FixTlsTestClientHello(options, Hex(ClientHello), Hex(ClientPrivateKey));

    var connected = TlsStream.AuthenticateAsClient(stream, options);
    if (!connected.Ok)
    {
        Console.WriteLine("client handshake: " + DescribeTlsError(connected.Error));
        return;
    }
    TlsStream tls = connected.Value;
    Console.WriteLine($"client: {tls.CipherSuite} {tls.KeyExchangeGroup} {tls.SignatureScheme}");
    Check("client wrote ClientHello and Finished", stream.Written,
          ClientHelloRecord + ClientFinishedRecord);
    stream.ForgetWritten();

    byte[] payload = Hex(ApplicationPayload);
    tls.Write(payload, 0u, payload.Length);
    Check("client application record", stream.Written, ClientApplicationRecord);
    stream.ForgetWritten();

    var received = new byte[100u];
    nuint got = tls.Read(received, 0u, received.Length);
    Check("server application data", SliceBytes(received, 0u, got), ApplicationPayload);
    nuint after = tls.Read(received, 0u, received.Length);
    Console.WriteLine("after close_notify: " + Text.FromInteger((long)after) + " bytes, " +
                      DescribeTlsError(tls.TlsErrorCode));

    tls.Close();
    Check("client close_notify", stream.Written, ClientAlertRecord);
}

// ------------------------------------------------------------------ server

void CheckServer()
{
    var parameters = new RsaParameters();
    parameters.Modulus = Hex(RsaModulus);
    parameters.Exponent = Hex(RsaExponent);
    parameters.D = Hex(RsaD);
    parameters.P = Hex(RsaP);
    parameters.Q = Hex(RsaQ);
    parameters.DP = Hex(RsaDp);
    parameters.DQ = Hex(RsaDq);
    parameters.InverseQ = Hex(RsaInverseQ);
    var rsa = Rsa.Create(parameters);
    if (!rsa.Ok)
    {
        Console.WriteLine("server key: " + $"{rsa.Error}");
        return;
    }
    var key = TlsSigningKey.FromRsa(rsa.Value);
    if (!key.Ok)
        return;

    // The certificate's DER is the first entry of the trace's Certificate:
    // after the header, the empty context and two three-byte lengths.
    byte[] certificateMessage = Hex(Certificate);
    nuint derLength = ((nuint)certificateMessage[8u] << 16) | ((nuint)certificateMessage[9u] << 8) |
                      (nuint)certificateMessage[10u];
    byte[] der = SliceBytes(certificateMessage, 11u, derLength);

    var options = new TlsServerOptions();
    options.CertificateChain.Add(der);
    options.PrivateKey = key.Value;
    options.LeaveInnerStreamOpen = true;
    // The trace's server preferred AES-128-GCM; this one's default is
    // ChaCha20, so it is told.
    options.CipherSuites.Clear();
    options.CipherSuites.Add(TlsCipherSuite.TlsAes128GcmSha256);
    FixTlsTestServerRandom(options, SliceBytes(Hex(ServerHello), 6u, 32u), Hex(ServerPrivateKey));

    // Only the ClientHello: the server writes its whole flight, then finds
    // the stream ended where the client's Finished should be.
    var stream = new ScriptedStream(Hex(ClientHelloRecord));
    var accepted = TlsStream.AuthenticateAsServer(stream, options);
    Console.WriteLine("server handshake: " + (accepted.Ok ? "done" : DescribeTlsError(accepted.Error)));

    byte[] written = stream.Written;
    byte[] serverHelloRecord = Hex(ServerHelloRecord);
    Check("server ServerHello", SliceBytes(written, 0u, serverHelloRecord.Length), ServerHelloRecord);

    byte[] rest = SliceBytes(written, serverHelloRecord.Length, written.Length - serverHelloRecord.Length);
    byte[] flight = OpenTlsTestRecord(Hex(ServerHandshakeTraffic), rest);
    Say("server flight opens under the trace's key", flight.Length > 0u);
    if (flight.Length == 0u)
        return;

    nuint extensionsLength = 4u + (((nuint)flight[2u] << 8) | (nuint)flight[3u]);
    byte[] extensions = SliceBytes(flight, 0u, extensionsLength);
    Check("server EncryptedExtensions", extensions, "080000060004" + "00000000");
    byte[] certificate = SliceBytes(flight, extensionsLength, certificateMessage.Length);
    Check("server Certificate", certificate, Certificate);

    nuint verifyAt = extensionsLength + certificateMessage.Length;
    nuint verifyLength = 4u + (((nuint)flight[verifyAt + 2u] << 8) | (nuint)flight[verifyAt + 3u]);
    byte[] verify = SliceBytes(flight, verifyAt, verifyLength);
    Say("server CertificateVerify is rsa_pss_rsae_sha256", verify[4u] == 0x08 && verify[5u] == 0x04);

    var schedule = new TlsTestKeySchedule();
    byte[] throughCertificate = JoinBytes(JoinBytes(JoinBytes(Hex(ClientHello), Hex(ServerHello)), extensions),
                                          certificate);
    byte[] content = new byte[64u];
    for (nuint i = 0u; i < 64u; i++)
        content[i] = 0x20;
    content = JoinBytes(JoinBytes(content, "TLS 1.3, server CertificateVerify"u8.ToArray()), new byte[1u]);
    content = JoinBytes(content, schedule.HashTranscript(throughCertificate));
    var peer = Rsa.ImportRsaPublicKey(rsa.Value.ExportRsaPublicKey());
    Say("server signature verifies",
        peer.Ok && peer.Value.VerifyData(content, SliceBytes(verify, 8u, verify.Length - 8u),
                                         HashAlgorithmName.Sha256, RsaSignaturePadding.Pss));

    byte[] finished = SliceBytes(flight, verifyAt + verifyLength, flight.Length - verifyAt - verifyLength);
    byte[] expected = schedule.ComputeFinished(Hex(ServerHandshakeTraffic),
                                               schedule.HashTranscript(JoinBytes(throughCertificate, verify)));
    Check("server Finished", finished, "14000020" + Convert.ToHexString(expected, false) + "16");
}

int Main()
{
    CheckKeySchedule();
    CheckRecords();
    CheckClient();
    CheckServer();
    return 0;
}
