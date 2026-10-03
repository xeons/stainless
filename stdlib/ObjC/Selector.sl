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

module Standard.ObjC;

#if MACOS
/// Objective-C's `SEL`: a message's name, interned by the runtime, so two
/// selectors of the same name are the same pointer.
///
///     var length = Selector.Named("length");
///
/// A member of an objc type names its own with `[Selector("...")]`; this is
/// for asking about one, as `respondsToSelector:` does.
public struct Selector
{
    /// The selector called `name`, registered with the runtime if it was not.
    public static Selector Named(String name)
    {
        Selector made;
        made._handle = sel_registerName(name.ToPointer());
        return made;
    }

    /// What the selector is called: `initWithFrame:`, colons and all.
    public String Name => FromCString(sel_getName(_handle));
}
#endif
