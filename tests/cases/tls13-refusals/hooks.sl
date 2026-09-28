// SPDX-License-Identifier: 0BSD
// A misbehaving client, built from the real one's steps: this file joins
// Standard.Net.Security so that it can run the client's handshake a step at
// a time and send a Finished that is wrong.
module Standard.Net.Security;

import Standard.Console;
import Standard.IO;

/// Runs a client handshake that sends a Finished with one bit flipped, and
/// answers how the server's reply ended it.
public TlsError RunTlsClientWithWrongFinished(IStream inner, TlsClientOptions options)
{
    var connection = new TlsConnection(inner, false, true);
    var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
    TlsError step = handshake.SendTlsClientHello();
    if (step == TlsError.None)
        step = handshake.ReadTlsServerHello();
    if (step == TlsError.None)
        step = handshake.ReadTlsEncryptedExtensions();
    if (step == TlsError.None)
        step = handshake.ReadTlsServerAuthentication();
    var schedule = handshake.Schedule;
    if (step != TlsError.None || schedule == null)
        return step;

    var writing = schedule.CreateTlsRecordCipher(connection._cipherSuite,
                                                 schedule._clientHandshakeTrafficSecret);
    if (!writing.Ok)
        return writing.Error;
    connection.InstallTlsWriteCipher(writing.Value);
    byte[] wrong = new byte[schedule.HashLength];
    wrong[0u] = 1;
    connection.QueueTlsHandshakeMessage(BuildTlsFinished(wrong));
    connection.FlushTlsHandshake();

    // The server answers with an alert, under its handshake key.
    var reply = connection.ReadTlsHandshakeMessage();
    if (reply.Ok)
        return TlsError.None;
    if (reply.Error == TlsError.AlertReceived)
        Console.WriteLine("  client heard: " + $"{connection._alertReceived}");
    return reply.Error;
}
