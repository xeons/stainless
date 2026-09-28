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

module Standard.IO.Compression;

import Standard.IO;

// What `DeflateStream`, `GZipStream` and `ZLibStream` share, which is all of
// it but the format.
class CompressionStreamCore
{
    IStream _stream;
    bool _leaveOpen;
    bool _closed;
    IOError _error;
    Inflater? _inflater;
    Deflater? _deflater;

    CompressionStreamCore(IStream stream, CompressionFormat format, CompressionMode mode,
                          CompressionLevel level, bool leaveOpen)
    {
        _stream = stream;
        _leaveOpen = leaveOpen;
        _error = IOError.None;
        if (mode == CompressionMode.Decompress)
            _inflater = new Inflater(stream, format);
        else
            _deflater = new Deflater(stream, format, level);
    }

    IStream BaseStream => _stream;

    bool CanRead => !_closed && _inflater != null && _stream.CanRead;

    bool CanWrite => !_closed && _deflater != null && _stream.CanWrite;

    IOError Error
    {
        get
        {
            if (_error != IOError.None)
                return _error;
            if (_inflater is Inflater inflater)
                return inflater.Error;
            if (_deflater is Deflater deflater)
                return deflater.Error;
            return IOError.None;
        }
    }

    CompressionError DataError
    {
        get
        {
            if (_inflater is Inflater inflater)
                return inflater.DataError;
            return CompressionError.None;
        }
    }

    nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        _error = IOError.None;
        if (_closed)
        {
            _error = IOError.Closed;
            return 0;
        }
        if (offset > buffer.Length || count > buffer.Length - offset)
        {
            _error = IOError.Invalid;
            return 0;
        }
        if (_inflater is Inflater inflater)
            return inflater.Read(buffer, offset, count);

        _error = IOError.Invalid;
        return 0;
    }

    nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        _error = IOError.None;
        if (_closed)
        {
            _error = IOError.Closed;
            return 0;
        }
        if (offset > buffer.Length || count > buffer.Length - offset)
        {
            _error = IOError.Invalid;
            return 0;
        }
        if (_deflater is Deflater deflater)
        {
            if (count > 0)
                deflater.WriteData(buffer[offset:][:count]);
            return deflater.Error == IOError.None ? count : 0;
        }

        _error = IOError.Invalid;
        return 0;
    }

    void Flush()
    {
        if (_closed)
            return;
        if (_deflater is Deflater deflater)
            deflater.FlushData();
    }

    void Close()
    {
        if (_closed)
            return;
        if (_deflater is Deflater deflater)
            deflater.Finish();
        if (!_leaveOpen)
        {
            _stream.Close();
            _error = _stream.Error;
        }
        _closed = true;
    }
}
