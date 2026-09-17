// SPDX-License-Identifier: 0BSD
//
// The consumer never sees the file: the bytes are in the library's image, and
// what crosses is a function that reads them.
module App;

import Standard.Console;
import Library.Banner;

int Main()
{
    Console.WriteLine($"{BannerLength()} bytes");
    Console.WriteLine(Banner());
    return 0;
}
