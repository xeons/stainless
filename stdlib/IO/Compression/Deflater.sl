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
import Standard.Bits;

// ---------------------------------------------------------------- deflate

// RFC 1951 encoding, zlib's design: a window of two 32 KiB halves slid down
// when the upper fills, hash chains over three-byte prefixes, and lazy
// matching, which takes a match only when the next position does not start a
// longer one. Each block is written in whichever of stored, fixed or dynamic
// Huffman is smallest.
//
// Positions are `int` because sliding the window moves the ones it keeps
// below zero until they are forgotten.
class Deflater
{
    const int WindowSize = 32768;
    const int WindowMask = 32767;
    const int MinMatch = 3;
    const int MaxMatch = 258;
    const int MinLookahead = 262;
    const int MaxDistance = 32506;
    const int TooFar = 4096;
    const nuint HashSize = 32768;
    const nuint SymbolCapacity = 16383;
    const nuint OutputSize = 65536;
    const nuint MaxStored = 65535;

    IStream _sink;
    CompressionFormat _format;
    CompressionLevel _level;
    IOError _error;
    bool _headerWritten;
    bool _finished;

    int _goodLength;
    int _lazyLength;
    int _niceLength;
    int _maxChain;
    bool _greedy;

    byte[] _window;
    int[] _head;
    int[] _prev;
    int _stringStart;
    int _lookahead;
    int _blockStart;
    int _matchLength;
    int _matchStart;
    int _previousLength;
    int _previousMatch;
    bool _matchAvailable;

    ushort[] _symbolLengths;
    ushort[] _symbolDistances;
    nuint _symbolCount;
    uint[] _literalFrequencies;
    uint[] _distanceFrequencies;
    uint[] _codeLengthFrequencies;

    byte[] _literalLengths;
    ushort[] _literalCodes;
    byte[] _distanceLengths;
    ushort[] _distanceCodes;
    byte[] _codeLengthLengths;
    ushort[] _codeLengthCodes;
    byte[] _fixedLiteralLengths;
    ushort[] _fixedLiteralCodes;
    byte[] _fixedDistanceLengths;
    ushort[] _fixedDistanceCodes;

    byte[] _runSymbols;
    byte[] _runExtras;
    nuint _runCount;
    byte[] _order;

    uint[] _sortKeys;
    uint[] _depths;
    int[] _lengthCounts;
    ushort[] _nextCode;

    byte[] _output;
    nuint _outputAt;
    ulong _bitBuffer;
    int _bitCount;

    Crc32 _crc;
    Adler32 _adler;
    ulong _total;

    Deflater(IStream sink, CompressionFormat format, CompressionLevel level)
    {
        _sink = sink;
        _format = format;
        _level = level;
        _error = IOError.None;

        switch (level)
        {
            case CompressionLevel.Fastest:
                SetEffort(4, 4, 8, 4, true);
                break;
            case CompressionLevel.SmallestSize:
                SetEffort(32, 258, 258, 4096, false);
                break;
            default:
                SetEffort(8, 16, 128, 128, false);
                break;
        }

        // The slack past two windows is what a match compared at the very
        // end may read; nothing past the data is ever taken into one.
        _window = new byte[(nuint)(2 * WindowSize + MaxMatch + 8)];
        _head = new int[HashSize];
        _prev = new int[(nuint)WindowSize];
        for (nuint i = 0; i < HashSize; i++)
            _head[i] = -1;

        _matchLength = MinMatch - 1;
        _previousLength = MinMatch - 1;

        _symbolLengths = new ushort[SymbolCapacity];
        _symbolDistances = new ushort[SymbolCapacity];
        _literalFrequencies = new uint[286];
        _distanceFrequencies = new uint[30];
        _codeLengthFrequencies = new uint[19];

        _literalLengths = new byte[288];
        _literalCodes = new ushort[288];
        _distanceLengths = new byte[32];
        _distanceCodes = new ushort[32];
        _codeLengthLengths = new byte[19];
        _codeLengthCodes = new ushort[19];
        _fixedLiteralLengths = new byte[288];
        _fixedLiteralCodes = new ushort[288];
        _fixedDistanceLengths = new byte[32];
        _fixedDistanceCodes = new ushort[32];

        _runSymbols = new byte[320];
        _runExtras = new byte[320];
        _order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

        _sortKeys = new uint[288];
        _depths = new uint[288];
        _lengthCounts = new int[290];
        _nextCode = new ushort[16];

        _output = new byte[OutputSize];
        _crc = new Crc32();
        _adler = new Adler32();

        for (nuint i = 0; i < 288u; i++)
        {
            byte length = 8;
            if (i >= 144u && i < 256u)
                length = 9;
            else if (i >= 256u && i < 280u)
                length = 7;
            _fixedLiteralLengths[i] = length;
        }
        for (nuint i = 0; i < 32u; i++)
            _fixedDistanceLengths[i] = 5;
        AssignCodes(_fixedLiteralLengths, 288, _fixedLiteralCodes);
        AssignCodes(_fixedDistanceLengths, 32, _fixedDistanceCodes);
    }

    IOError Error => _error;

    void SetEffort(int good, int lazy, int nice, int chain, bool greedy)
    {
        _goodLength = good;
        _lazyLength = lazy;
        _niceLength = nice;
        _maxChain = chain;
        _greedy = greedy;
    }

    // ---------------------------------------------------------- input

    // Compresses `data`, writing output onward as it fills.
    void WriteData(ReadOnlySpan<byte> data)
    {
        if (_finished || _error != IOError.None)
            return;
        WriteHeader();

        if (_format == CompressionFormat.GZip)
            _crc.Append(data);
        else if (_format == CompressionFormat.ZLib)
            _adler.Append(data);
        _total += (ulong)data.Length;

        nuint at = 0;
        while (at < data.Length && _error == IOError.None)
        {
            if (_level == CompressionLevel.NoCompression)
            {
                nuint room = MaxStored - (nuint)_lookahead;
                nuint taking = data.Length - at;
                if (taking > room)
                    taking = room;
                CopyIntoWindow(data, at, taking, (nuint)_lookahead);
                _lookahead += (int)taking;
                at += taking;
                if ((nuint)_lookahead == MaxStored)
                {
                    WriteStoredBlock(0, MaxStored, false);
                    _lookahead = 0;
                }
                continue;
            }

            if (_stringStart >= WindowSize + MaxDistance)
                SlideWindow();

            nuint end = (nuint)(_stringStart + _lookahead);
            nuint space = (nuint)(2 * WindowSize) - end;
            nuint count = data.Length - at;
            if (count > space)
                count = space;
            CopyIntoWindow(data, at, count, end);
            _lookahead += (int)count;
            at += count;

            Compress(false);
        }
    }

    void CopyIntoWindow(ReadOnlySpan<byte> data, nuint from, nuint count, nuint to)
    {
        data[from:from + count].CopyTo(_window[to:]);
    }

    // Moves the upper window down over the lower, and forgets every position
    // that falls off the bottom. A block whose bytes would go with them is
    // written first, so a stored block is always possible.
    void SlideWindow()
    {
        if (_blockStart < WindowSize && BlockEnd > _blockStart)
            FlushBlock(false);

        memmove(&_window[0], &_window[(nuint)WindowSize], (nuint)(WindowSize + MaxMatch + 8));
        _stringStart -= WindowSize;
        _matchStart -= WindowSize;
        _previousMatch -= WindowSize;
        _blockStart -= WindowSize;

        for (nuint i = 0; i < HashSize; i++)
        {
            int position = _head[i];
            _head[i] = position >= WindowSize ? position - WindowSize : -1;
        }
        for (nuint i = 0; i < (nuint)WindowSize; i++)
        {
            int position = _prev[i];
            _prev[i] = position >= WindowSize ? position - WindowSize : -1;
        }
    }

    // Pushes everything written so far out as complete bytes, ending on an
    // empty stored block as zlib's sync flush does, so a reader can decode
    // all of it without waiting for more.
    void FlushData()
    {
        if (_finished || _error != IOError.None)
            return;
        WriteHeader();

        if (_level == CompressionLevel.NoCompression)
        {
            if (_lookahead > 0)
                WriteStoredBlock(0, (nuint)_lookahead, false);
            _lookahead = 0;
        }
        else
        {
            Compress(true);
            FinishMatching();
            FlushBlock(false);
        }

        WriteStoredBlock(0, 0, false);
        FlushOutput();
        if (_error == IOError.None)
            _sink.Flush();
    }

    // Writes the final block and the trailer. Nothing may be written after.
    void Finish()
    {
        if (_finished)
            return;
        _finished = true;
        if (_error != IOError.None)
            return;
        WriteHeader();

        if (_level == CompressionLevel.NoCompression)
        {
            WriteStoredBlock(0, (nuint)_lookahead, true);
            _lookahead = 0;
        }
        else
        {
            Compress(true);
            FinishMatching();
            FlushBlock(true);
        }
        AlignToByte();

        switch (_format)
        {
            case CompressionFormat.ZLib:
            {
                uint check = _adler.Value;
                PutByte((byte)(check >> 24));
                PutByte((byte)(check >> 16));
                PutByte((byte)(check >> 8));
                PutByte((byte)check);
                break;
            }

            case CompressionFormat.GZip:
            {
                PutWord(_crc.Value);
                PutWord((uint)(_total & 0xFFFFFFFFu));
                break;
            }

            default:
                break;
        }
        FlushOutput();
    }

    void WriteHeader()
    {
        if (_headerWritten)
            return;
        _headerWritten = true;

        switch (_format)
        {
            case CompressionFormat.ZLib:
            {
                // CINFO 7 is the 32 KiB window; FLEVEL is advisory.
                uint method = 0x78;
                uint level = 2;
                switch (_level)
                {
                    case CompressionLevel.NoCompression: level = 0; break;
                    case CompressionLevel.Fastest:       level = 0; break;
                    case CompressionLevel.SmallestSize:  level = 3; break;
                    default:                             level = 2; break;
                }
                uint flags = level << 6;
                flags += 31u - ((method << 8) | flags) % 31u;
                PutByte((byte)method);
                PutByte((byte)flags);
                break;
            }

            case CompressionFormat.GZip:
            {
                // No name, no time, and an operating system of "unknown".
                byte extra = 0;
                if (_level == CompressionLevel.SmallestSize)
                    extra = 2;
                else if (_level == CompressionLevel.Fastest)
                    extra = 4;
                PutByte(0x1F);
                PutByte(0x8B);
                PutByte(8);
                PutByte(0);
                PutWord(0);
                PutByte(extra);
                PutByte(255);
                break;
            }

            default:
                break;
        }
    }

    // ------------------------------------------------------------ matching

    int InsertString(int position)
    {
        uint key = ((uint)_window[position] << 16) | ((uint)_window[position + 1] << 8) |
                   (uint)_window[position + 2];
        nuint hash = (nuint)((key * 0x9E3779B1u) >> 17);
        int previous = _head[hash];
        _prev[position & WindowMask] = previous;
        _head[hash] = position;
        return previous;
    }

    // The longest match for `_stringStart` along the chain from `candidate`
    // that beats `best`, with its start in `_matchStart`.
    int FindLongestMatch(int candidate, int best)
    {
        int scan = _stringStart;
        int chain = _maxChain;
        if (best >= _goodLength)
            chain >>= 2;

        int limit = scan - MaxDistance;
        int longest = MaxMatch < _lookahead ? MaxMatch : _lookahead;
        int nice = _niceLength < longest ? _niceLength : longest;
        if (best >= longest)
            return best;

        while (candidate >= 0 && candidate > limit && candidate < scan)
        {
            if (_window[candidate + best] == _window[scan + best] &&
                _window[candidate + best - 1] == _window[scan + best - 1] &&
                _window[candidate] == _window[scan] &&
                _window[candidate + 1] == _window[scan + 1])
            {
                int length = 2;
                while (length < longest && _window[candidate + length] == _window[scan + length])
                    length++;

                if (length > best)
                {
                    _matchStart = candidate;
                    best = length;
                    if (length >= nice)
                        break;
                }
            }

            chain--;
            if (chain == 0)
                break;
            candidate = _prev[candidate & WindowMask];
        }

        return best;
    }

    // Consumes the window down to `MinLookahead`, or to nothing when
    // `flush`, recording literals and matches and emitting blocks as the
    // symbol buffer fills.
    void Compress(bool flush)
    {
        if (_greedy)
            CompressGreedily(flush);
        else
            CompressLazily(flush);
    }

    void CompressGreedily(bool flush)
    {
        while (_error == IOError.None)
        {
            if (_lookahead < MinLookahead && !flush)
                return;
            if (_lookahead == 0)
                return;

            int head = -1;
            if (_lookahead >= MinMatch)
                head = InsertString(_stringStart);

            _matchLength = MinMatch - 1;
            if (head >= 0 && _stringStart - head <= MaxDistance)
                _matchLength = FindLongestMatch(head, MinMatch - 1);

            if (_matchLength >= MinMatch)
            {
                RecordMatch(_stringStart - _matchStart, _matchLength);
                _lookahead -= _matchLength;

                // Inserting every position of a long match costs more than
                // the matches it would find.
                if (_matchLength <= _lazyLength && _lookahead >= MinMatch)
                {
                    for (int i = 1; i < _matchLength; i++)
                        InsertString(_stringStart + i);
                }
                _stringStart += _matchLength;
            }
            else
            {
                RecordLiteral(_window[_stringStart]);
                _lookahead--;
                _stringStart++;
            }

            if (_symbolCount == SymbolCapacity)
                FlushBlock(false);
        }
    }

    void CompressLazily(bool flush)
    {
        while (_error == IOError.None)
        {
            if (_lookahead < MinLookahead && !flush)
                return;
            if (_lookahead == 0)
                return;

            int head = -1;
            if (_lookahead >= MinMatch)
                head = InsertString(_stringStart);

            _previousLength = _matchLength;
            _previousMatch = _matchStart;
            _matchLength = MinMatch - 1;

            if (head >= 0 && _previousLength < _lazyLength && _stringStart - head <= MaxDistance)
            {
                _matchLength = FindLongestMatch(head, _previousLength);

                // A three-byte match a long way back costs more than three
                // literals.
                if (_matchLength == MinMatch && _stringStart - _matchStart > TooFar)
                    _matchLength = MinMatch - 1;
            }

            if (_previousLength >= MinMatch && _matchLength <= _previousLength)
            {
                int lastInsert = _stringStart + _lookahead - MinMatch;
                RecordMatch(_stringStart - 1 - _previousMatch, _previousLength);

                // The match began at the previous position, whose string is
                // inserted already, as is this one.
                _lookahead -= _previousLength - 1;
                for (int i = 1; i < _previousLength - 1; i++)
                {
                    if (_stringStart + i <= lastInsert)
                        InsertString(_stringStart + i);
                }
                _stringStart += _previousLength - 1;
                _matchAvailable = false;
                _matchLength = MinMatch - 1;

                if (_symbolCount == SymbolCapacity)
                    FlushBlock(false);
            }
            else if (_matchAvailable)
            {
                RecordLiteral(_window[_stringStart - 1]);
                _stringStart++;
                _lookahead--;
                if (_symbolCount == SymbolCapacity)
                    FlushBlock(false);
            }
            else
            {
                _matchAvailable = true;
                _stringStart++;
                _lookahead--;
            }
        }
    }

    // The byte lazy matching held back waiting to see what followed it.
    void FinishMatching()
    {
        if (_matchAvailable)
        {
            RecordLiteral(_window[_stringStart - 1]);
            _matchAvailable = false;
        }
        _matchLength = MinMatch - 1;
        _previousLength = MinMatch - 1;
    }

    void RecordLiteral(byte value)
    {
        _symbolLengths[_symbolCount] = (ushort)value;
        _symbolDistances[_symbolCount] = 0;
        _symbolCount++;
        _literalFrequencies[value]++;
    }

    void RecordMatch(int distance, int length)
    {
        _symbolLengths[_symbolCount] = (ushort)length;
        _symbolDistances[_symbolCount] = (ushort)distance;
        _symbolCount++;
        _literalFrequencies[257 + LengthCode(length)]++;
        _distanceFrequencies[DistanceCode(distance)]++;
    }

    // ------------------------------------------------------------- blocks

    // Where the recorded symbols end: the byte lazy matching is holding back
    // is not yet among them.
    int BlockEnd => _matchAvailable ? _stringStart - 1 : _stringStart;

    // Writes the symbols recorded since the last block as one block, in
    // whichever encoding is smallest.
    void FlushBlock(bool last)
    {
        _literalFrequencies[256] = 1;
        BuildLengths(_literalFrequencies, 286, 15, _literalLengths);
        BuildLengths(_distanceFrequencies, 30, 15, _distanceLengths);

        nuint literalCount = 286;
        while (literalCount > 257u && _literalLengths[literalCount - 1] == 0)
            literalCount--;
        nuint distanceCount = 30;
        while (distanceCount > 1u && _distanceLengths[distanceCount - 1] == 0)
            distanceCount--;

        EncodeRuns(literalCount, distanceCount);
        BuildLengths(_codeLengthFrequencies, 19, 7, _codeLengthLengths);
        nuint codeLengthCount = 19;
        while (codeLengthCount > 4u && _codeLengthLengths[_order[codeLengthCount - 1]] == 0)
            codeLengthCount--;

        ulong dynamicBits = 17 + 3 * (ulong)codeLengthCount;
        for (nuint i = 0; i < 19u; i++)
            dynamicBits += (ulong)_codeLengthFrequencies[i] * (ulong)_codeLengthLengths[i];
        dynamicBits += 2 * (ulong)_codeLengthFrequencies[16] +
                       3 * (ulong)_codeLengthFrequencies[17] +
                       7 * (ulong)_codeLengthFrequencies[18];

        ulong fixedBits = 3;
        ulong extraBits = 0;
        for (nuint i = 0; i < 286u; i++)
        {
            ulong frequency = (ulong)_literalFrequencies[i];
            dynamicBits += frequency * (ulong)_literalLengths[i];
            fixedBits += frequency * (ulong)_fixedLiteralLengths[i];
            if (i >= 257u)
                extraBits += frequency * (ulong)LengthExtraBits((int)i - 257);
        }
        for (nuint i = 0; i < 30u; i++)
        {
            ulong frequency = (ulong)_distanceFrequencies[i];
            dynamicBits += frequency * (ulong)_distanceLengths[i];
            fixedBits += frequency * 5;
            extraBits += frequency * (ulong)DistanceExtraBits((int)i);
        }
        dynamicBits += extraBits;
        fixedBits += extraBits;

        int end = BlockEnd;
        nuint bytes = (nuint)(end - _blockStart);
        nuint blocks = (bytes + MaxStored - 1) / MaxStored;
        if (blocks == 0)
            blocks = 1;
        ulong storedBits = (ulong)blocks * 40 + 8 * (ulong)bytes + 7;

        if (storedBits <= fixedBits && storedBits <= dynamicBits)
        {
            WriteStoredBlock((nuint)_blockStart, bytes, last);
        }
        else if (fixedBits <= dynamicBits)
        {
            PutBits(last ? 3u : 2u, 3);
            WriteSymbols(_fixedLiteralLengths, _fixedLiteralCodes,
                         _fixedDistanceLengths, _fixedDistanceCodes);
        }
        else
        {
            AssignCodes(_literalLengths, 286, _literalCodes);
            AssignCodes(_distanceLengths, 30, _distanceCodes);
            AssignCodes(_codeLengthLengths, 19, _codeLengthCodes);

            PutBits(last ? 5u : 4u, 3);
            PutBits((uint)(literalCount - 257), 5);
            PutBits((uint)(distanceCount - 1), 5);
            PutBits((uint)(codeLengthCount - 4), 4);
            for (nuint i = 0; i < codeLengthCount; i++)
                PutBits((uint)_codeLengthLengths[_order[i]], 3);

            for (nuint i = 0; i < _runCount; i++)
            {
                byte symbol = _runSymbols[i];
                PutBits((uint)_codeLengthCodes[symbol], (int)_codeLengthLengths[symbol]);
                switch (symbol)
                {
                    case 16: PutBits((uint)_runExtras[i], 2); break;
                    case 17: PutBits((uint)_runExtras[i], 3); break;
                    case 18: PutBits((uint)_runExtras[i], 7); break;
                    default: break;
                }
            }

            WriteSymbols(_literalLengths, _literalCodes, _distanceLengths, _distanceCodes);
        }

        _symbolCount = 0;
        for (nuint i = 0; i < 286u; i++)
            _literalFrequencies[i] = 0;
        for (nuint i = 0; i < 30u; i++)
            _distanceFrequencies[i] = 0;
        _blockStart = end;
    }

    void WriteSymbols(byte[] literalLengths, ushort[] literalCodes,
                      byte[] distanceLengths, ushort[] distanceCodes)
    {
        for (nuint i = 0; i < _symbolCount; i++)
        {
            int value = (int)_symbolLengths[i];
            int distance = (int)_symbolDistances[i];
            if (distance == 0)
            {
                PutBits((uint)literalCodes[value], (int)literalLengths[value]);
                continue;
            }

            int code = LengthCode(value);
            PutBits((uint)literalCodes[257 + code], (int)literalLengths[257 + code]);
            int extra = LengthExtraBits(code);
            if (extra > 0)
                PutBits((uint)(value - LengthBase(code)), extra);

            code = DistanceCode(distance);
            PutBits((uint)distanceCodes[code], (int)distanceLengths[code]);
            extra = DistanceExtraBits(code);
            if (extra > 0)
                PutBits((uint)(distance - DistanceBase(code)), extra);
        }

        PutBits((uint)literalCodes[256], (int)literalLengths[256]);
    }

    // Stored blocks for `count` bytes of the window from `from`, split at
    // the 65535 a block holds; only the last carries `last`.
    void WriteStoredBlock(nuint from, nuint count, bool last)
    {
        do
        {
            nuint taking = count < MaxStored ? count : MaxStored;
            bool final = last && taking == count;
            PutBits(final ? 1u : 0u, 3);
            AlignToByte();
            PutByte((byte)taking);
            PutByte((byte)(taking >> 8));
            PutByte((byte)~taking);
            PutByte((byte)(~taking >> 8));
            PutBytes(from, taking);
            from += taking;
            count -= taking;
        }
        while (count > 0);
    }

    // The code-length sequence for the two tables, run-length coded with
    // 16, 17 and 18, and how often each of the nineteen symbols is used.
    void EncodeRuns(nuint literalCount, nuint distanceCount)
    {
        for (nuint i = 0; i < 19u; i++)
            _codeLengthFrequencies[i] = 0;
        _runCount = 0;

        nuint total = literalCount + distanceCount;
        nuint at = 0;
        while (at < total)
        {
            byte current = LengthAt(at, literalCount);
            nuint run = 1;
            while (at + run < total && LengthAt(at + run, literalCount) == current)
                run++;
            at += run;

            if (current == 0)
            {
                while (run >= 11u)
                {
                    nuint taking = run < 138u ? run : 138;
                    AddRun(18, (byte)(taking - 11));
                    run -= taking;
                }
                if (run >= 3u)
                {
                    AddRun(17, (byte)(run - 3));
                    run = 0;
                }
            }
            else
            {
                AddRun(current, 0);
                run--;
                while (run >= 3u)
                {
                    nuint taking = run < 6u ? run : 6;
                    AddRun(16, (byte)(taking - 3));
                    run -= taking;
                }
            }

            while (run > 0)
            {
                AddRun(current, 0);
                run--;
            }
        }
    }

    byte LengthAt(nuint index, nuint literalCount)
    {
        if (index < literalCount)
            return _literalLengths[index];
        return _distanceLengths[index - literalCount];
    }

    void AddRun(byte symbol, byte extra)
    {
        _runSymbols[_runCount] = symbol;
        _runExtras[_runCount] = extra;
        _runCount++;
        _codeLengthFrequencies[symbol]++;
    }

    // ---------------------------------------------------------- Huffman

    // Code lengths for `count` symbols from their frequencies, none longer
    // than `limit`. The lengths are Moffat and Katajainen's in-place
    // minimum-redundancy code; an over-long one is shortened by moving codes
    // down the tree, as miniz does, which keeps the set complete.
    void BuildLengths(uint[] frequencies, nuint count, int limit, byte[] lengths)
    {
        nuint used = 0;
        for (nuint i = 0; i < count; i++)
        {
            lengths[i] = 0;
            if (frequencies[i] != 0u)
            {
                _sortKeys[used] = (frequencies[i] << 16) | (uint)i;
                used++;
            }
        }

        // RFC 1951 decoders want at least two codes, and a code of one
        // symbol would need zero bits, which the format cannot say.
        for (nuint i = 0; used < 2u; i++)
        {
            if (frequencies[i] == 0u)
            {
                _sortKeys[used] = (1u << 16) | (uint)i;
                used++;
            }
        }

        for (nuint i = 1; i < used; i++)
        {
            uint key = _sortKeys[i];
            nuint j = i;
            while (j > 0 && _sortKeys[j - 1] > key)
            {
                _sortKeys[j] = _sortKeys[j - 1];
                j--;
            }
            _sortKeys[j] = key;
        }

        for (nuint i = 0; i < used; i++)
            _depths[i] = _sortKeys[i] >> 16;
        ComputeMinimumRedundancy(_depths, (int)used);

        for (nuint i = 0; i < 290u; i++)
            _lengthCounts[i] = 0;
        for (nuint i = 0; i < used; i++)
            _lengthCounts[_depths[i]]++;

        for (int i = limit + 1; i < 290; i++)
        {
            _lengthCounts[limit] += _lengthCounts[i];
            _lengthCounts[i] = 0;
        }

        uint kraft = 0;
        for (int i = limit; i > 0; i--)
            kraft += (uint)_lengthCounts[i] << (limit - i);
        while (kraft != 1u << limit)
        {
            _lengthCounts[limit]--;
            for (int i = limit - 1; i > 0; i--)
            {
                if (_lengthCounts[i] != 0)
                {
                    _lengthCounts[i]--;
                    _lengthCounts[i + 1] += 2;
                    break;
                }
            }
            kraft--;
        }

        // The rarest symbols take the longest codes.
        nuint next = used;
        for (int length = 1; length <= limit; length++)
        {
            for (int n = _lengthCounts[length]; n > 0; n--)
            {
                next--;
                lengths[(nuint)(_sortKeys[next] & 0xFFFFu)] = (byte)length;
            }
        }
    }

    // Moffat and Katajainen, "In-Place Calculation of Minimum-Redundancy
    // Codes": `a` holds `n` ascending weights and leaves holding each one's
    // code length.
    void ComputeMinimumRedundancy(uint[] a, int n)
    {
        if (n == 1)
        {
            a[0] = 1;
            return;
        }

        a[0] += a[1];
        int root = 0;
        int leaf = 2;
        for (int next = 1; next < n - 1; next++)
        {
            if (leaf >= n || a[root] < a[leaf])
            {
                a[next] = a[root];
                a[root] = (uint)next;
                root++;
            }
            else
            {
                a[next] = a[leaf];
                leaf++;
            }

            if (leaf >= n || (root < next && a[root] < a[leaf]))
            {
                a[next] += a[root];
                a[root] = (uint)next;
                root++;
            }
            else
            {
                a[next] += a[leaf];
                leaf++;
            }
        }

        a[n - 2] = 0;
        for (int next = n - 3; next >= 0; next--)
            a[next] = a[a[next]] + 1u;

        int available = 1;
        int usedAtDepth = 0;
        uint depth = 0;
        root = n - 2;
        int slot = n - 1;
        while (available > 0)
        {
            while (root >= 0 && a[root] == depth)
            {
                usedAtDepth++;
                root--;
            }
            while (available > usedAtDepth)
            {
                a[slot] = depth;
                slot--;
                available--;
            }
            available = 2 * usedAtDepth;
            depth++;
            usedAtDepth = 0;
        }
    }

    // Canonical codes for `lengths`, bit-reversed for writing.
    void AssignCodes(byte[] lengths, nuint count, ushort[] codes)
    {
        for (nuint i = 0; i < 16u; i++)
            _lengthCounts[i] = 0;
        for (nuint i = 0; i < count; i++)
            _lengthCounts[lengths[i]]++;
        _lengthCounts[0] = 0;

        int code = 0;
        for (nuint bits = 1; bits < 16u; bits++)
        {
            code = (code + _lengthCounts[bits - 1]) << 1;
            _nextCode[bits] = (ushort)code;
        }

        for (nuint i = 0; i < count; i++)
        {
            int length = (int)lengths[i];
            if (length == 0)
                continue;
            codes[i] = (ushort)ReverseBits((uint)_nextCode[length], length);
            _nextCode[length]++;
        }
    }

    // ------------------------------------------------------------ bits out

    void PutBits(uint value, int count)
    {
        _bitBuffer |= (ulong)value << _bitCount;
        _bitCount += count;
        if (_bitCount >= 32)
        {
            if (_outputAt + 4 > OutputSize)
                FlushOutput();
            _output[_outputAt] = (byte)_bitBuffer;
            _output[_outputAt + 1] = (byte)(_bitBuffer >> 8);
            _output[_outputAt + 2] = (byte)(_bitBuffer >> 16);
            _output[_outputAt + 3] = (byte)(_bitBuffer >> 24);
            _outputAt += 4;
            _bitBuffer >>= 32;
            _bitCount -= 32;
        }
    }

    // Pads the last partial byte with zeros and moves every whole byte out
    // of the bit buffer.
    void AlignToByte()
    {
        while (_bitCount > 0)
        {
            if (_outputAt == OutputSize)
                FlushOutput();
            _output[_outputAt] = (byte)_bitBuffer;
            _outputAt++;
            _bitBuffer >>= 8;
            _bitCount = _bitCount > 8 ? _bitCount - 8 : 0;
        }
        _bitBuffer = 0;
    }

    // A byte at a byte boundary. The bit buffer MUST be empty.
    void PutByte(byte value)
    {
        if (_outputAt == OutputSize)
            FlushOutput();
        _output[_outputAt] = value;
        _outputAt++;
    }

    void PutWord(uint value)
    {
        PutByte((byte)value);
        PutByte((byte)(value >> 8));
        PutByte((byte)(value >> 16));
        PutByte((byte)(value >> 24));
    }

    // `count` bytes of the window from `from`, at a byte boundary.
    void PutBytes(nuint from, nuint count)
    {
        while (count > 0)
        {
            if (_outputAt == OutputSize)
                FlushOutput();
            nuint room = OutputSize - _outputAt;
            nuint taking = count < room ? count : room;
            memcpy(&_output[_outputAt], &_window[from], taking);
            _outputAt += taking;
            from += taking;
            count -= taking;
        }
    }

    void FlushOutput()
    {
        nuint at = 0;
        while (at < _outputAt && _error == IOError.None)
        {
            nuint wrote = _sink.Write(_output, at, _outputAt - at);
            if (wrote == 0)
            {
                IOError failure = _sink.Error;
                _error = failure != IOError.None ? failure : IOError.Unknown;
            }
            at += wrote;
        }
        _outputAt = 0;
    }
}

// ------------------------------------------------- length and distance codes

// Which of the 29 length codes covers a match length of 3 to 258.
int LengthCode(int length)
{
    int offset = length - 3;
    if (offset < 8)
        return offset;
    if (offset == 255)
        return 28;
    int top = Bits.Log2((uint)offset);
    return 4 * (top - 1) + ((offset >> (top - 2)) & 3);
}

int LengthExtraBits(int code)
{
    if (code < 8 || code == 28)
        return 0;
    return (code >> 2) - 1;
}

int LengthBase(int code)
{
    if (code < 8)
        return code + 3;
    if (code == 28)
        return 258;
    return ((4 + (code & 3)) << ((code >> 2) - 1)) + 3;
}

// Which of the 30 distance codes covers a distance of 1 to 32768.
int DistanceCode(int distance)
{
    int offset = distance - 1;
    if (offset < 4)
        return offset;
    int top = Bits.Log2((uint)offset);
    return 2 * top + ((offset >> (top - 1)) & 1);
}

int DistanceExtraBits(int code)
{
    if (code < 4)
        return 0;
    return (code >> 1) - 1;
}

int DistanceBase(int code)
{
    if (code < 4)
        return code + 1;
    return ((2 + (code & 1)) << ((code >> 1) - 1)) + 1;
}
