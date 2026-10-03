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

module Standard.Encoding;

/// UTF-8, where a lead byte says how many follow it.
class Utf8Decoder : TailDecoder
{
    public Utf8Decoder(IEncoding encoding) { base(encoding); }

    protected override nuint CountIncompleteTail(byte[] data, nuint length)
    {
        // A sequence is at most four bytes, so a lead byte further back than
        // that cannot be waiting on anything here.
        nuint back = length < 4u ? length : 4u;

        for (nuint i = 1u; i <= back; i++)
        {
            byte lead = data[length - i];
            if ((lead & 0xC0) == 0x80)
                continue;

            nuint wanted = 1u;
            if ((lead & 0xE0) == 0xC0)
                wanted = 2u;
            else if ((lead & 0xF0) == 0xE0)
                wanted = 3u;
            else if ((lead & 0xF8) == 0xF0)
                wanted = 4u;

            return i < wanted ? i : 0u;
        }

        // Four continuation bytes and no lead: malformed rather than cut, and
        // the encoding says so better than holding them would.
        return 0u;
    }
}
