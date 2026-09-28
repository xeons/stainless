// SPDX-License-Identifier: 0BSD
//
// A static carrying an `[Embed]`, in a library built --shared. The static is
// born holding the object's address, so there is no code to run.
module Library.Banner;

import Standard.Text;

static class Held
{
    [Embed("banner.txt")]
    public static readonly byte[] Banner;
}

/// The bytes, as text. The array lives in the library's image and is immortal,
/// so the String made from it is an ordinary one crossing the boundary.
public String Banner() => Text.FromBytes(&Held.Banner[0], Held.Banner.Length);

public nuint BannerLength() => Held.Banner.Length;
