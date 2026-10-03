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

module Standard.Json;

/// Where a parser is, which is a byte offset and a reason it stopped.
///
/// A class rather than a struct so that every function below shares the one
/// cursor without `ref` at each call: a recursive descent that has to say
/// `ref` twenty times reads like plumbing rather than like the grammar it is.
class Cursor
{
    public String Text;
    public nuint At;
    public nuint Depth;
    public JsonError Failure;

    public Cursor(String text)
    {
        Text = text;
        At = 0u;
        Depth = 0u;
        Failure = JsonError.None;
    }

    public bool Failed => Failure != JsonError.None;

    /// The first reason wins: everything after a failure is noise about the
    /// same mistake, and the first one is where it was made.
    public void RecordFailure(JsonError why)
    {
        if (Failure == JsonError.None)
            Failure = why;
    }

    public bool AtEnd => At >= Text.ByteLength();

    public byte Peek()
    {
        if (AtEnd)
            return (byte)0;
        return Text.GetByteAt(At);
    }

    public void Skip() => At = At + 1u;
}
