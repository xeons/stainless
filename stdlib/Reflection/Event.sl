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

module Standard.Reflection;

/// A public event of a reflected class: its name, and the delegate a handler
/// has to match.
///
/// **Described, not raised or subscribed.** A handler is a method, and
/// methods are not described; what this is for is a tool that writes the
/// `+=` into source, such as a form designer.
///
/// @see Type.GetEventAt
public struct Event
{
    /// The class's runtime record, and which of its events this is.
    public byte* Type;
    public nuint Index;

    /// The event's name.
    public String Name => Text.FromNullTerminated(sl_type_event_name(Type, Index));

    /// The delegate's name, qualified by its module: `Forms.EventHandler`.
    public String HandlerTypeName =>
        Text.FromNullTerminated(sl_type_event_handler_type(Type, Index));
}
