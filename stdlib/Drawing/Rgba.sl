// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Drawing;

import Standard.Collections;
import Standard.Text;
import Standard.File;
import Standard.IO;

// ============================================================== the colour

/// A colour, as the eight-bit channels an image actually stores.
///
/// **Named for the layout rather than called `Color`**, and deliberately:
/// `Forms.Drawing` already declares a `Color`, and a program that loaded a PNG
/// to put it on a form would have to qualify every mention of either. `Rgba`
/// also says the one thing a caller has to know, which is that the alpha is
/// eight bits and 255 is opaque.
///
/// Packed as `0xAARRGGBB`, which is what GDI+ calls an ARGB and what the
/// libgd backend converts to and from -- libgd's alpha is seven bits and
/// inverted, and that is the only place it shows.
public struct Rgba
{
    public byte R;
    public byte G;
    public byte B;
    public byte A;

    /// An opaque colour.
    ///
    /// @param red    0 to 255
    /// @param green  0 to 255
    /// @param blue   0 to 255
    /// @see Rgba.FromArgb
    public static Rgba FromRgb(byte red, byte green, byte blue)
    {
        Rgba colour;
        colour.R = red;
        colour.G = green;
        colour.B = blue;
        colour.A = (byte)255;
        return colour;
    }

    /// A colour with an alpha, where 0 is invisible and 255 is opaque.
    ///
    /// @param alpha  0 to 255, and it comes first
    /// @param red    0 to 255
    /// @param green  0 to 255
    /// @param blue   0 to 255
    /// @see Rgba.FromRgb
    public static Rgba FromArgb(byte alpha, byte red, byte green, byte blue)
    {
        Rgba colour;
        colour.R = red;
        colour.G = green;
        colour.B = blue;
        colour.A = alpha;
        return colour;
    }

    /// From `0xAARRGGBB`, which is what `Packed` answers and what a colour
    /// written as a hex literal in a program usually is.
    ///
    /// @see Rgba.Packed
    public static Rgba FromPacked(uint packed)
    {
        return Rgba.FromArgb((byte)((packed >> 24) & 0xFFu), (byte)((packed >> 16) & 0xFFu),
                         (byte)((packed >> 8) & 0xFFu), (byte)(packed & 0xFFu));
    }

    /// `0xAARRGGBB`.
    public uint Packed =>
        ((uint)A << 24) | ((uint)R << 16) | ((uint)G << 8) | (uint)B;

    /// Whether anything of this would be drawn at all.
    public bool IsInvisible => A == (byte)0;

    public bool Equals(Rgba other) => Packed == other.Packed;

    /// **Properties rather than `static readonly` fields**, which is not a
    /// style choice. A static needs an entry point to be initialized from and a
    /// `--shared` library has none (SL0380) -- and this module is compiled into
    /// every program, including every shared library anybody builds. A property
    /// is a function, so there is nothing to initialize and nothing to go
    /// wrong; the six of them fold to four bytes each.
    public static Rgba Transparent => Rgba.FromArgb((byte)0, (byte)0, (byte)0, (byte)0);
    public static Rgba Black       => Rgba.FromRgb((byte)0, (byte)0, (byte)0);
    public static Rgba White       => Rgba.FromRgb((byte)255, (byte)255, (byte)255);
    public static Rgba Red         => Rgba.FromRgb((byte)255, (byte)0, (byte)0);
    public static Rgba Green       => Rgba.FromRgb((byte)0, (byte)128, (byte)0);
    public static Rgba Blue        => Rgba.FromRgb((byte)0, (byte)0, (byte)255);
}
