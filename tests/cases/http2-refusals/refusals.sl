// SPDX-License-Identifier: 0BSD
// What an HTTP/2 client refuses from a peer, and how: a connection error
// ends in GOAWAY with its code, a malformed response in RST_STREAM on its
// stream, and each is the request's failure. The peer is scripted frame by
// frame, over the loopback in h2c with prior knowledge.
module Http2Refusals;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;

int Main()
{
    var scenarios = new List<String>();
    scenarios.Add("the first frame is not SETTINGS");
    scenarios.Add("SETTINGS of seven octets");
    scenarios.Add("SETTINGS with ENABLE_PUSH 1");
    scenarios.Add("a frame past SETTINGS_MAX_FRAME_SIZE");
    scenarios.Add("HEADERS interrupted before CONTINUATION");
    scenarios.Add("PUSH_PROMISE with push disabled");
    scenarios.Add("DATA on a stream already ended");
    scenarios.Add("DATA past the stream's window");
    scenarios.Add("a header block HPACK cannot decode");
    scenarios.Add("an upper-case field name");
    scenarios.Add("a connection-specific field");
    scenarios.Add("a response without :status");
    scenarios.Add("a body short of its content-length");
    scenarios.Add("a WINDOW_UPDATE of zero");
    scenarios.Add("HEADERS on a stream the server opened");
    scenarios.Add("RST_STREAM on a stream never opened");
    scenarios.Add("an unknown frame type, then a response");
    foreach (var scenario in scenarios)
        Console.WriteLine(scenario + ": " + RunHttp2RefusalScenario(scenario));
    return 0;
}
