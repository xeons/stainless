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

module Standard.Xml;

class Cursor
{
    public String Source;
    public nuint At;
    public nuint Depth;
    public XmlError Failure;

    public Cursor(String source)
    {
        Source = source;
        At = 0u;
        Depth = 0u;
        Failure = XmlError.None;
    }

    public bool Failed => Failure != XmlError.None;

    public void RecordFailure(XmlError why)
    {
        if (Failure == XmlError.None)
            Failure = why;
    }

    public bool AtEnd => At >= Source.ByteLength();

    public byte Peek()
    {
        if (AtEnd)
            return (byte)0;
        return Source.GetByteAt(At);
    }

    public byte PeekAt(nuint ahead)
    {
        if (At + ahead >= Source.ByteLength())
            return (byte)0;
        return Source.GetByteAt(At + ahead);
    }

    public void Skip() => At = At + 1u;

    /// Consumes `word` when it is next, and answers whether it was.
    public bool TryConsume(String word)
    {
        if (At + word.ByteLength() > Source.ByteLength())
            return false;

        for (nuint i = 0u; i < word.ByteLength(); i++)
        {
            if (Source.GetByteAt(At + i) != word.GetByteAt(i))
                return false;
        }

        At = At + word.ByteLength();
        return true;
    }

    /// Moves past `word`, or to the end when it is not there.
    public bool SkipPast(String word)
    {
        while (!AtEnd)
        {
            if (TryConsume(word))
                return true;
            Skip();
        }
        return false;
    }
}
