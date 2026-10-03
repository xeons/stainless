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

import Standard.Text;

/// What every decoder does except decide where a character was cut.
///
/// The held bytes and the new ones are joined, everything complete is handed
/// to the encoding it belongs to, and the remainder is kept. Only
/// `CountIncompleteTail` differs between encodings, and it is the one thing that
/// needs to know how the encoding is shaped.
abstract class TailDecoder : IDecoder
{
    IEncoding _encoding;

    /// Four bytes is the longest unfinished character any encoding here has:
    /// three of a UTF-8 sequence, or an odd byte and a high surrogate.
    byte[] _held;
    nuint _heldCount;

    protected TailDecoder(IEncoding encoding)
    {
        _encoding = encoding;
        _held = new byte[4];
        _heldCount = 0u;
    }

    /// How many bytes at the end begin a character that is not finished.
    protected abstract nuint CountIncompleteTail(byte[] data, nuint length);

    public String GetString(byte[] bytes, nuint index, nuint count, bool flush)
    {
        nuint total = _heldCount + count;
        if (total == 0u)
            return "";

        var joined = new byte[total];
        _held[:_heldCount].CopyTo(joined);
        bytes[index:index + count].CopyTo(joined[_heldCount:]);

        // Nothing is held back on a flush: what is unfinished then is never
        // going to be finished, and the encoding turns it into U+FFFD.
        nuint tail = flush ? 0u : this.CountIncompleteTail(joined, total);
        if (tail > 4u)
            tail = 4u;

        nuint usable = total - tail;

        _heldCount = tail;
        joined[usable:].CopyTo(_held);

        if (usable == 0u)
            return "";

        return _encoding.GetString(joined[:usable].ToArray());
    }

    public void Reset()
    {
        _heldCount = 0u;
    }
}
