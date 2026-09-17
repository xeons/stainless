// SPDX-License-Identifier: 0BSD
//
// A static initialized with `embed`, in a library built --shared. A library has
// no entry point to run an initializer from (SL0380), so this compiles only
// because the static is born holding the object's address — there is no code
// to run, and nothing is refused.
module Library.Banner;

import Standard.Text;

static class Held
{
    public static readonly byte[] Banner = embed("banner.txt");
}

/// The bytes, as text. The array lives in the library's image and is immortal,
/// so the String made from it is an ordinary one crossing the boundary.
public String Banner() => Text.FromBytes(&Held.Banner[0], Held.Banner.Length);

public nuint BannerLength() => Held.Banner.Length;
