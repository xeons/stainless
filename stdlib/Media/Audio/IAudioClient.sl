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

module Standard.Media.Audio;

#if WINDOWS

// WASAPI, declared as what it is. The method order *is* the vtable, so nothing
// here may be reordered or removed -- a method that is not wanted is still
// declared, because slot 7 has to be slot 7. Every interface extends IUnknown
// whether or not it says so, so a declaration's own first method is slot 3,
// and ARC emits the AddRef and Release (section 8.5).

/// A stream on an endpoint. `Initialize` settles the format and the buffer,
/// and `GetService` hands out whichever half of it this stream is.
[Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")]
com interface IAudioClient
{
    int Initialize(int shareMode, uint streamFlags, long bufferDuration,
                   long periodicity, WaveFormatEx* format, Guid* session);
    int GetBufferSize(uint* frames);
    int GetStreamLatency(long* latency);
    int GetCurrentPadding(uint* frames);
    int IsFormatSupported(int shareMode, WaveFormatEx* format, byte** closest);
    int GetMixFormat(WaveFormatEx** format);
    int GetDevicePeriod(long* defaultPeriod, long* minimumPeriod);
    int Start();
    int Stop();
    int Reset();
    int SetEventHandle(void* signal);
    int GetService(Guid* interfaceId, byte** service);
}

#endif
