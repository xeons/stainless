// SPDX-License-Identifier: 0BSD
// Frames the peer sends on a stream after this end reset it are dropped,
// however many streams have been reset since, and a late header block is
// still decoded so that the HPACK tables stay in step. The peer is
// scripted, over the loopback in h2c with prior knowledge.
module Http2LateFrames;

import Standard.Console;
import Standard.Net.Http;

int Main()
{
    Console.WriteLine("3 streams reset: " + RunHttp2LateScenario(3u));
    Console.WriteLine("200 streams reset: " + RunHttp2LateScenario(200u));
    return 0;
}
