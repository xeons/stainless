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

module Standard.Threading;

/// A callback registered with a token, withdrawn by `Dispose`.
public sealed threadsafe class CancellationTokenRegistration : IDisposable
{
    weak CancellationTokenSource? _source;
    long _id;

    internal CancellationTokenRegistration(CancellationTokenSource? source, long id)
    {
        _source = source;
        _id = id;
    }

    /// Withdraws the callback, if it has not run. A second call does nothing.
    public void Dispose()
    {
        CancellationTokenSource? source = _source;
        if (source != null && _id != 0)
            source.UnregisterCancellation(_id);
        _id = 0;
    }
}
