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

#if MACOS

/// One open queue. Each flag is 1 while AudioQueue has handed its buffer back
/// -- played, so free to fill; or recorded, so holding sound -- and 0 while
/// the queue has it. A callback stores 1 and nothing else, from AudioQueue's
/// own thread; everything else happens on the thread that opened the queue.
struct QueueState
{
    public void* Queue;
    public bool Started;
    public uint FrameSize;
    public uint BufferBytes;
    public int Next;
    public uint ReadAt;
    public QueueBuffer* First;
    public QueueBuffer* Second;
    public QueueBuffer* Third;
    public int FirstBack;
    public int SecondBack;
    public int ThirdBack;
}

#endif
