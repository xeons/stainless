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

/// One endpoint: a speaker, a headset, a microphone.
[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
com interface IMMDevice
{
    int Activate(Guid* interfaceId, uint context, byte* parameters, byte** result);
    int OpenPropertyStore(uint access, byte** store);
    int GetId(char16** id);
    int GetState(uint* state);
}

#endif
