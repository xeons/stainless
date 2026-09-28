// SPDX-License-Identifier: 0BSD
// HPACK (RFC 7541): every example of Appendix C, encoded and decoded byte for
// byte; the Huffman code over every byte value; and what the decoder refuses.
module HpackCases;

import Standard.Net.Http;

int Main()
{
    RunHpackCases();
    return 0;
}
