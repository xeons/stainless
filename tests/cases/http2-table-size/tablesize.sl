// SPDX-License-Identifier: 0BSD
// When the peer changes SETTINGS_HEADER_TABLE_SIZE more than once before
// the next header block, the block begins with the smallest size since the
// last one and then the final size (RFC 7541 section 4.2), so the peer's
// decoder evicts what the smaller size did. The peer is scripted, over the
// loopback in h2c with prior knowledge.
module Http2TableSize;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;

List<uint> CreateSizes(uint first, uint second, bool both)
{
    var sizes = new List<uint>();
    sizes.Add(first);
    if (both)
        sizes.Add(second);
    return sizes;
}

int Main()
{
    var unchanged = new List<List<uint>>();
    unchanged.Add(new List<uint>());
    Console.WriteLine("no change: " + RunHttp2TableScenario(unchanged));

    var zero = new List<List<uint>>();
    zero.Add(CreateSizes(0u, 0u, false));
    Console.WriteLine("0: " + RunHttp2TableScenario(zero));

    var oneFrame = new List<List<uint>>();
    oneFrame.Add(CreateSizes(0u, 4096u, true));
    Console.WriteLine("0 then 4096 in one frame: " + RunHttp2TableScenario(oneFrame));

    var twoFrames = new List<List<uint>>();
    twoFrames.Add(CreateSizes(1024u, 0u, false));
    twoFrames.Add(CreateSizes(256u, 2048u, true));
    Console.WriteLine("1024, then 256 then 2048: " + RunHttp2TableScenario(twoFrames));
    return 0;
}
