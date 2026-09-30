// SPDX-License-Identifier: 0BSD
// What an HTTP/2 client does when the peer stops reading: every write is
// bounded by the request's deadline, a request waiting to write gives up on
// its own deadline, and control frames the peer provokes meanwhile are
// capped. The peer is scripted, over the loopback in h2c with prior
// knowledge.
module Http2Backpressure;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;

int Main()
{
    var scenarios = new List<String>();
    scenarios.Add("stalled");
    scenarios.Add("second");
    scenarios.Add("flood");
    foreach (var scenario in scenarios)
        Console.WriteLine(scenario + ": " + RunHttp2StallScenario(scenario));
    return 0;
}
