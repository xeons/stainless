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

/// Objective-C's runtime, for a program built for macOS.
///
/// The compiler declares `AnyObject`, `Selector` and `Class`, because a
/// declaration of Objective-C's own types names them; this module adds what a
/// program does with them. Everything here is macOS's alone, so a page
/// generated on another host lists none of it.
module Standard.ObjC;

#if MACOS
extern "C"
{
    byte* objc_autoreleasePoolPush();
    void objc_autoreleasePoolPop(byte* pool);
    byte* sel_registerName(byte* name);
    byte* sel_getName(byte* selector);
    byte* class_getName(byte* type);
}

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

/// Objective-C's `Class`: the object a class message is sent to.
public struct Class
{
    /// What the runtime calls the class.
    public String Name => FromCString(class_getName(_handle));
}

/// Runs `body` inside an autorelease pool of its own, which drains when it
/// returns.
///
/// An object a message hands back at +0 lives until the pool holding it
/// drains. Every thread and the program as a whole run inside one already;
/// this is for a loop that makes many such objects and wants them gone each
/// time round rather than at the end.
public void WithAutoreleasePool(Action body)
{
    byte* pool = objc_autoreleasePoolPush();
    body();
    objc_autoreleasePoolPop(pool);
}

/// A C string the runtime owns, as a `String` of its own.
String FromCString(byte* text)
{
    nuint length = 0u;
    while (text[length] != 0u)
        length++;
    return Standard.Text.FromBytes(text, length);
}
#endif
