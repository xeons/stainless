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

// ---------------------------------------------------------------- inflate

// Where the decoder is between calls. Decoding stops only at a symbol
// boundary, so nothing else has to survive a return.
enum InflateStage
{
    Header = 0,
    BlockHeader = 1,
    Stored = 2,
    Huffman = 3,
    Trailer = 4,
    Done = 5,
    Failed = 6,
}

// RFC 1951 decoding, pulled: bits are read from the source only when a
// symbol needs them, and output goes into a ring the caller drains.
//
// The ring is twice the 32 KiB a distance can reach, so up to 32 KiB of
// output can wait to be read while a full window of history stays behind
// it. Reading from the source is in blocks of `InputSize`, so up to that many
// bytes past the end of the compressed data may be taken from it.
class Inflater
{
    const nuint RingSize = 65536;
    const nuint RingMask = 65535;
    const nuint MaxDistance = 32768;
    const nuint MaxMatch = 258;
    const nuint InputSize = 16384;

    // Enough for the longest length code with its extra bits and the longest
    // distance code with its: 15 + 5 + 15 + 13.
    const int SymbolBits = 48;

    IStream _source;
    CompressionFormat _format;
    InflateStage _stage;
    CompressionError _dataError;
    IOError _ioError;

    byte[] _input;
    nuint _inputAt;
    nuint _inputEnd;
    bool _sourceEnded;
    ulong _bits;
    int _bitCount;

    byte[] _ring;
    nuint _writeAt;
    nuint _pending;
    nuint _unchecked;
    ulong _total;

    bool _started;
    bool _lastBlock;
    nuint _storedLeft;
    HuffmanDecoder _literals;
    HuffmanDecoder _distances;
    HuffmanDecoder _codeLengths;
    byte[] _lengths;
    byte[] _order;
    bool _fixedLoaded;

    Crc32 _crc;
    Adler32 _adler;

    Inflater(IStream source, CompressionFormat format)
    {
        _source = source;
        _format = format;
        _stage = InflateStage.Header;
        _dataError = CompressionError.None;
        _ioError = IOError.None;
        _input = new byte[InputSize];
        _ring = new byte[RingSize];
        _literals = new HuffmanDecoder(288);
        _distances = new HuffmanDecoder(32);
        _codeLengths = new HuffmanDecoder(19);
        _lengths = new byte[320];
        _order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        _crc = new Crc32();
        _adler = new Adler32();
    }

    bool IsFailed => _stage == InflateStage.Failed;

    IOError Error => _ioError;

    CompressionError DataError => _dataError;

    // Up to `count` decoded bytes into `buffer` at `offset`. Zero at the end
    // of the data and on failure, which `Error` tells apart.
    nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (count == 0)
            return 0;
        if (_pending == 0)
            Decode();
        if (_stage == InflateStage.Failed || _pending == 0)
            return 0;

        nuint taking = count < _pending ? count : _pending;
        nuint from = (_writeAt - _pending) & RingMask;
        nuint first = RingSize - from;
        if (first > taking)
            first = taking;

        memcpy(&buffer[offset], &_ring[from], first);
        if (taking > first)
            memcpy(&buffer[offset + first], &_ring[0], taking - first);

        _pending -= taking;
        return taking;
    }

    // Decodes until there is output to hand over, the data ends, or it
    // fails. Returns early with output pending rather than wait on a source
    // that has nothing buffered.
    void Decode()
    {
        while (_pending == 0 || !IsWaitingOnSource)
        {
            switch (_stage)
            {
                case InflateStage.Header:
                    // No bytes at all is an empty stream, as .NET reads one.
                    if (!_started && PeekByte() < 0 && _ioError == IOError.None)
                    {
                        _stage = InflateStage.Done;
                        return;
                    }
                    _started = true;
                    if (!ReadHeader())
                        return;
                    _lastBlock = false;
                    _stage = InflateStage.BlockHeader;
                    break;

                case InflateStage.BlockHeader:
                    if (_lastBlock)
                    {
                        _stage = InflateStage.Trailer;
                        break;
                    }
                    if (!ReadBlockHeader())
                        return;
                    break;

                case InflateStage.Stored:
                    CopyStored();
                    break;

                case InflateStage.Huffman:
                    DecodeHuffman();
                    break;

                case InflateStage.Trailer:
                    UpdateChecksum();
                    if (!ReadTrailer())
                        return;
                    break;

                default:
                    UpdateChecksum();
                    return;
            }

            if (RingSize - _pending < MaxMatch)
                break;
        }

        UpdateChecksum();
    }

    // Whether the next bit would have to come from the source.
    bool IsWaitingOnSource => _inputAt == _inputEnd && _bitCount < SymbolBits;

    // ---------------------------------------------------------- bits in

    void FailDecoding(CompressionError why)
    {
        _stage = InflateStage.Failed;
        _dataError = why;
        if (_ioError == IOError.None)
            _ioError = IOError.InvalidData;
    }

    // Reads the next block of the source into `_input`, answering whether
    // anything came.
    bool FillInput()
    {
        if (_sourceEnded)
            return false;

        nuint got = _source.Read(_input, 0, InputSize);
        if (got == 0)
        {
            _sourceEnded = true;
            IOError failure = _source.Error;
            if (failure != IOError.None)
                _ioError = failure;
            return false;
        }

        _inputAt = 0;
        _inputEnd = got;
        return true;
    }

    // Tops the bit buffer up from `_input` without touching the source.
    void RefillBits()
    {
        while (_bitCount <= 56 && _inputAt < _inputEnd)
        {
            _bits |= (ulong)_input[_inputAt] << _bitCount;
            _inputAt++;
            _bitCount += 8;
        }
    }

    // Makes `count` bits available, reading the source if it must. Fails the
    // stream as truncated when the source ends first.
    bool Need(int count)
    {
        while (_bitCount < count)
        {
            if (_inputAt == _inputEnd && !FillInput())
            {
                FailDecoding(CompressionError.Truncated);
                return false;
            }
            RefillBits();
        }
        return true;
    }

    uint TakeBits(int count)
    {
        uint value = (uint)(_bits & (((ulong)1 << count) - 1u));
        _bits >>= count;
        _bitCount -= count;
        return value;
    }

    void AlignToByte()
    {
        TakeBits(_bitCount & 7);
    }

    // The next whole byte, or -1 at the end of the source. The bit buffer
    // MUST be byte-aligned.
    int PeekByte()
    {
        if (_bitCount == 0 && _inputAt == _inputEnd && !FillInput())
            return -1;
        if (_bitCount == 0)
            RefillBits();
        return (int)(_bits & 0xFFu);
    }

    // ---------------------------------------------------- headers, trailers

    bool ReadHeader()
    {
        switch (_format)
        {
            case CompressionFormat.ZLib: return ReadZLibHeader();
            case CompressionFormat.GZip: return ReadGZipHeader();
            default:                     return true;
        }
    }

    bool ReadZLibHeader()
    {
        if (!Need(16))
            return false;

        uint method = TakeBits(8);
        uint flags = TakeBits(8);
        if ((method & 15u) != 8u || (method >> 4) > 7u || ((method << 8) | flags) % 31u != 0u)
        {
            FailDecoding(CompressionError.InvalidHeader);
            return false;
        }
        if ((flags & 0x20u) != 0u)
        {
            FailDecoding(CompressionError.DictionaryRequired);
            return false;
        }

        _adler.Reset();
        return true;
    }

    // One header byte, added to the header's own CRC for FHCRC.
    bool TakeHeaderByte(Crc32 headerCrc, out uint value)
    {
        value = 0;
        if (!Need(8))
            return false;
        value = TakeBits(8);
        headerCrc.AppendByte((byte)value);
        return true;
    }

    bool SkipHeaderBytes(Crc32 headerCrc, nuint count)
    {
        for (nuint i = 0; i < count; i++)
        {
            if (!TakeHeaderByte(headerCrc, out uint ignored))
                return false;
        }
        return true;
    }

    // Through the zero that ends FNAME or FCOMMENT.
    bool SkipHeaderText(Crc32 headerCrc)
    {
        for (;;)
        {
            if (!TakeHeaderByte(headerCrc, out uint value))
                return false;
            if (value == 0u)
                return true;
        }
    }

    bool ReadGZipHeader()
    {
        var headerCrc = new Crc32();
        uint first = 0;
        uint second = 0;
        uint method = 0;
        uint flags = 0;
        if (!TakeHeaderByte(headerCrc, out first) || !TakeHeaderByte(headerCrc, out second) ||
            !TakeHeaderByte(headerCrc, out method) || !TakeHeaderByte(headerCrc, out flags))
        {
            return false;
        }
        if (first != 0x1Fu || second != 0x8Bu || method != 8u || (flags & 0xE0u) != 0u)
        {
            FailDecoding(CompressionError.InvalidHeader);
            return false;
        }

        // MTIME, XFL and OS say nothing a decoder needs.
        if (!SkipHeaderBytes(headerCrc, 6))
            return false;

        if ((flags & 0x04u) != 0u)
        {
            if (!TakeHeaderByte(headerCrc, out uint low) ||
                !TakeHeaderByte(headerCrc, out uint high))
            {
                return false;
            }
            if (!SkipHeaderBytes(headerCrc, (nuint)(low | (high << 8))))
                return false;
        }
        if ((flags & 0x08u) != 0u && !SkipHeaderText(headerCrc))
            return false;
        if ((flags & 0x10u) != 0u && !SkipHeaderText(headerCrc))
            return false;

        if ((flags & 0x02u) != 0u)
        {
            uint expected = headerCrc.Value & 0xFFFFu;
            if (!Need(16))
                return false;
            if (TakeBits(16) != expected)
            {
                FailDecoding(CompressionError.InvalidHeader);
                return false;
            }
        }

        _crc.Reset();
        _total = 0;
        return true;
    }

    bool ReadTrailer()
    {
        AlignToByte();
        switch (_format)
        {
            case CompressionFormat.ZLib:
            {
                if (!Need(32))
                    return false;
                uint stored = TakeBits(8) << 24;
                stored |= TakeBits(8) << 16;
                stored |= TakeBits(8) << 8;
                stored |= TakeBits(8);
                if (stored != _adler.Value)
                {
                    FailDecoding(CompressionError.ChecksumMismatch);
                    return false;
                }
                _stage = InflateStage.Done;
                return true;
            }

            case CompressionFormat.GZip:
            {
                if (!Need(32))
                    return false;
                uint crc = TakeBits(32);
                if (!Need(32))
                    return false;
                uint size = TakeBits(32);
                if (crc != _crc.Value)
                {
                    FailDecoding(CompressionError.ChecksumMismatch);
                    return false;
                }
                if (size != (uint)(_total & 0xFFFFFFFFu))
                {
                    FailDecoding(CompressionError.LengthMismatch);
                    return false;
                }

                // Another member follows when the next byte starts one, as
                // `gzip -d` reads them; anything else after is left unread.
                _stage = PeekByte() == 0x1F ? InflateStage.Header : InflateStage.Done;
                return true;
            }

            default:
                _stage = InflateStage.Done;
                return true;
        }
    }

    void UpdateChecksum()
    {
        if (_unchecked == 0 || _format == CompressionFormat.Raw)
        {
            _unchecked = 0;
            return;
        }

        nuint from = (_writeAt - _unchecked) & RingMask;
        nuint first = RingSize - from;
        if (first > _unchecked)
            first = _unchecked;

        AppendChecksum(from, first);
        if (_unchecked > first)
            AppendChecksum(0, _unchecked - first);
        _unchecked = 0;
    }

    void AppendChecksum(nuint from, nuint count)
    {
        if (_format == CompressionFormat.GZip)
            _crc.Append(_ring[from:][:count]);
        else
            _adler.Append(_ring[from:][:count]);
    }

    // ------------------------------------------------------------- blocks

    bool ReadBlockHeader()
    {
        if (!Need(3))
            return false;

        _lastBlock = TakeBits(1) == 1u;
        switch (TakeBits(2))
        {
            case 0u:
            {
                AlignToByte();
                if (!Need(32))
                    return false;
                uint length = TakeBits(16);
                uint complement = TakeBits(16);
                if ((length ^ 0xFFFFu) != complement)
                {
                    FailDecoding(CompressionError.StoredLengthMismatch);
                    return false;
                }
                _storedLeft = (nuint)length;
                _stage = InflateStage.Stored;
                return true;
            }

            case 1u:
                LoadFixedTables();
                _stage = InflateStage.Huffman;
                return true;

            case 2u:
                if (!ReadDynamicTables())
                    return false;
                _fixedLoaded = false;
                _stage = InflateStage.Huffman;
                return true;

            default:
                FailDecoding(CompressionError.InvalidBlockType);
                return false;
        }
    }

    void LoadFixedTables()
    {
        if (_fixedLoaded)
            return;

        for (nuint i = 0; i < 144u; i++)
            _lengths[i] = 8;
        for (nuint i = 144; i < 256u; i++)
            _lengths[i] = 9;
        for (nuint i = 256; i < 280u; i++)
            _lengths[i] = 7;
        for (nuint i = 280; i < 288u; i++)
            _lengths[i] = 8;
        _literals.Build(_lengths, 0, 288, false);

        // Codes 30 and 31 take part in the code and never in the data.
        for (nuint i = 0; i < 32u; i++)
            _lengths[i] = 5;
        _distances.Build(_lengths, 0, 32, false);
        _fixedLoaded = true;
    }

    bool ReadDynamicTables()
    {
        if (!Need(14))
            return false;

        nuint literalCount = (nuint)TakeBits(5) + 257;
        nuint distanceCount = (nuint)TakeBits(5) + 1;
        nuint codeLengthCount = (nuint)TakeBits(4) + 4;
        if (literalCount > 286u || distanceCount > 30u)
        {
            FailDecoding(CompressionError.InvalidCodeLengths);
            return false;
        }

        for (nuint i = 0; i < 19u; i++)
            _lengths[i] = 0;
        for (nuint i = 0; i < codeLengthCount; i++)
        {
            if (!Need(3))
                return false;
            _lengths[_order[i]] = (byte)TakeBits(3);
        }
        if (!_codeLengths.Build(_lengths, 0, 19, false))
        {
            FailDecoding(CompressionError.InvalidCodeLengths);
            return false;
        }

        nuint total = literalCount + distanceCount;
        nuint at = 0;
        while (at < total)
        {
            // Seven bits is the longest code-length code, and seven extra
            // bits the longest repeat.
            if (!NeedForSymbol(14))
                return false;

            int symbol = _codeLengths.DecodeSymbol(_bits, out int length);
            if (!AcceptSymbol(symbol, length))
                return false;
            TakeBits(length);

            if (symbol < 16)
            {
                _lengths[at] = (byte)symbol;
                at++;
                continue;
            }

            byte repeated = 0;
            nuint times = 0;
            switch (symbol)
            {
                case 16:
                    if (at == 0)
                    {
                        FailDecoding(CompressionError.InvalidCodeLengths);
                        return false;
                    }
                    if (!Need(2))
                        return false;
                    repeated = _lengths[at - 1];
                    times = 3 + (nuint)TakeBits(2);
                    break;

                case 17:
                    if (!Need(3))
                        return false;
                    times = 3 + (nuint)TakeBits(3);
                    break;

                default:
                    if (!Need(7))
                        return false;
                    times = 11 + (nuint)TakeBits(7);
                    break;
            }

            if (times > total - at)
            {
                FailDecoding(CompressionError.InvalidCodeLengths);
                return false;
            }
            for (nuint i = 0; i < times; i++)
                _lengths[at + i] = repeated;
            at += times;
        }

        if (_lengths[256] == 0 ||
            !_literals.Build(_lengths, 0, literalCount, true) ||
            !_distances.Build(_lengths, literalCount, distanceCount, true))
        {
            FailDecoding(CompressionError.InvalidCodeLengths);
            return false;
        }
        return true;
    }

    // Tops the bit buffer up to `count` bits where the source has them, and
    // to fewer at its end: a short code near the end needs fewer bits than
    // the longest, and `AcceptSymbol` checks what was actually used.
    bool NeedForSymbol(int count)
    {
        RefillBits();
        while (_bitCount < count)
        {
            if (!FillInput())
            {
                if (_ioError != IOError.None)
                {
                    FailDecoding(CompressionError.Truncated);
                    return false;
                }
                return true;
            }
            RefillBits();
        }
        return true;
    }

    // Whether a decoded symbol is real: a code that fits in the bits there
    // are. A pattern no code stands for is invalid unless the data ran out
    // under it, which is truncation.
    bool AcceptSymbol(int symbol, int length)
    {
        if (symbol >= 0 && length <= _bitCount)
            return true;
        if (_sourceEnded && (symbol >= 0 || _bitCount < 15))
            FailDecoding(CompressionError.Truncated);
        else
            FailDecoding(CompressionError.InvalidCode);
        return false;
    }

    void CopyStored()
    {
        // Whole bytes still in the bit buffer come first.
        while (_storedLeft > 0 && _bitCount >= 8 && _pending < RingSize)
        {
            _ring[_writeAt] = (byte)TakeBits(8);
            Produce(1);
            _storedLeft--;
        }

        while (_storedLeft > 0 && _pending < RingSize)
        {
            if (_inputAt == _inputEnd)
            {
                if (_pending > 0)
                    return;
                if (!FillInput())
                {
                    FailDecoding(CompressionError.Truncated);
                    return;
                }
            }

            nuint taking = _storedLeft;
            nuint available = _inputEnd - _inputAt;
            nuint room = RingSize - _pending;
            nuint untilWrap = RingSize - _writeAt;
            if (taking > available)
                taking = available;
            if (taking > room)
                taking = room;
            if (taking > untilWrap)
                taking = untilWrap;

            memcpy(&_ring[_writeAt], &_input[_inputAt], taking);
            _inputAt += taking;
            _storedLeft -= taking;
            Produce(taking);
        }

        if (_storedLeft == 0)
            _stage = InflateStage.BlockHeader;
    }

    // Counts `count` bytes just written at `_writeAt` as output.
    void Produce(nuint count)
    {
        _writeAt = (_writeAt + count) & RingMask;
        _pending += count;
        _unchecked += count;
        _total += (ulong)count;
    }

    void DecodeHuffman()
    {
        byte[] ring = _ring;
        HuffmanDecoder literals = _literals;
        HuffmanDecoder distances = _distances;

        for (;;)
        {
            if (RingSize - _pending < MaxMatch)
                return;

            if (_bitCount < SymbolBits)
            {
                RefillBits();
                if (_bitCount < SymbolBits && _inputAt == _inputEnd)
                {
                    if (_pending > 0)
                        return;
                    if (!NeedForSymbol(SymbolBits))
                        return;
                }
            }

            int symbol = literals.DecodeSymbol(_bits, out int length);
            if (!AcceptSymbol(symbol, length))
                return;
            TakeBits(length);

            if (symbol < 256)
            {
                ring[_writeAt] = (byte)symbol;
                Produce(1);
                continue;
            }
            if (symbol == 256)
            {
                _stage = InflateStage.BlockHeader;
                return;
            }

            int lengthCode = symbol - 257;
            if (lengthCode >= 29)
            {
                FailDecoding(CompressionError.InvalidCode);
                return;
            }

            nuint matchLength = 258;
            if (lengthCode < 8)
            {
                matchLength = (nuint)lengthCode + 3;
            }
            else if (lengthCode < 28)
            {
                int extra = (lengthCode >> 2) - 1;
                if (!Need(extra))
                    return;
                matchLength = ((nuint)(4 + (lengthCode & 3)) << extra) + 3 + (nuint)TakeBits(extra);
            }

            int distanceSymbol = distances.DecodeSymbol(_bits, out int distanceLength);
            if (!AcceptSymbol(distanceSymbol, distanceLength))
                return;
            TakeBits(distanceLength);
            if (distanceSymbol >= 30)
            {
                FailDecoding(CompressionError.InvalidCode);
                return;
            }

            nuint distance = (nuint)distanceSymbol + 1;
            if (distanceSymbol >= 4)
            {
                int extra = (distanceSymbol >> 1) - 1;
                if (!Need(extra))
                    return;
                distance = ((nuint)(2 + (distanceSymbol & 1)) << extra) + 1 +
                           (nuint)TakeBits(extra);
            }
            if ((ulong)distance > _total)
            {
                FailDecoding(CompressionError.InvalidDistance);
                return;
            }

            nuint to = _writeAt;
            nuint from = (to - distance) & RingMask;
            if (from + matchLength <= RingSize && to + matchLength <= RingSize)
            {
                // Forwards, a byte at a time: a distance shorter than the
                // length repeats what this copy has just written.
                for (nuint i = 0; i < matchLength; i++)
                    ring[to + i] = ring[from + i];
            }
            else
            {
                for (nuint i = 0; i < matchLength; i++)
                    ring[(to + i) & RingMask] = ring[(from + i) & RingMask];
            }
            Produce(matchLength);
        }
    }
}
