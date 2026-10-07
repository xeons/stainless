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

// A key with the modifiers held for it: what chooses a menu item from
// anywhere in its window.
module Forms.Platform;

import Standard.Text;

/// A key and its modifiers, as a menu item or a command names them.
///
/// ```
/// save.Shortcut = Shortcut.FromKey(Key.S, ModifierKeys.Control);
/// open.Shortcut = Shortcut.Parse("Ctrl+O") ?? Shortcut.Empty;
/// ```
///
/// **`Control` is Command on a Mac.** The backends report both keys as
/// `ModifierKeys.Control`, so Ctrl+S in a program is Cmd+S there, which is
/// what a Mac user presses.
public struct Shortcut
{
    public Key Key;
    public ModifierKeys Modifiers;

    public static Shortcut FromKey(Key key, ModifierKeys modifiers)
    {
        Shortcut made;
        made.Key = key;
        made.Modifiers = modifiers;
        return made;
    }

    /// No shortcut at all.
    public static readonly Shortcut Empty = Shortcut.FromKey(Key.None, ModifierKeys.None);

    public bool IsEmpty => Key == Key.None;

    public bool Equals(Shortcut other) => Key == other.Key && Modifiers == other.Modifiers;

    /// Whether this is the key just pressed. An empty shortcut matches nothing.
    public bool Matches(Key key, ModifierKeys modifiers)
        => !IsEmpty && Key == key && Modifiers == modifiers;

    /// How a menu shows it: "Ctrl+Shift+S", or the glyphs on a Mac.
    public String ToText()
    {
        if (IsEmpty)
            return "";
        var built = new StringBuilder();
#if MACOS
        if (Modifiers.HasFlag(ModifierKeys.Alt))
            built.Append(Text.FromChar((char32)0x2325));
        if (Modifiers.HasFlag(ModifierKeys.Shift))
            built.Append(Text.FromChar((char32)0x21E7));
        if (Modifiers.HasFlag(ModifierKeys.Control))
            built.Append(Text.FromChar((char32)0x2318));
#else
        if (Modifiers.HasFlag(ModifierKeys.Control))
            built.Append("Ctrl+");
        if (Modifiers.HasFlag(ModifierKeys.Alt))
            built.Append("Alt+");
        if (Modifiers.HasFlag(ModifierKeys.Shift))
            built.Append("Shift+");
#endif
        built.Append(FormatKeyName(Key));
        return built.ToText();
    }

    /// Reads "Ctrl+Shift+S", "Alt+F4" or "F5". `Cmd` is taken as `Ctrl` and
    /// `Option` as `Alt`, and case does not matter. None for anything else.
    public static Optional<Shortcut> Parse(String text)
    {
        var modifiers = ModifierKeys.None;
        var parts = text.Trim().Split('+');
        if (parts.Length == 0u)
            return None;
        for (nuint i = 0u; i + 1u < parts.Length; i++)
        {
            String part = parts[i].Trim().ToLowerAscii();
            switch (part)
            {
                case "ctrl":
                case "control":
                case "cmd":
                case "command":
                    modifiers = modifiers | ModifierKeys.Control;
                    break;
                case "shift":
                    modifiers = modifiers | ModifierKeys.Shift;
                    break;
                case "alt":
                case "option":
                    modifiers = modifiers | ModifierKeys.Alt;
                    break;
                default:
                    return None;
            }
        }
        Key key = ParseKeyName(parts[parts.Length - 1u].Trim());
        if (key == Key.None)
            return None;
        return Some(Shortcut.FromKey(key, modifiers));
    }
}

/// The name a shortcut shows for a key: a letter, a digit, "F5", "Del".
public String FormatKeyName(Key key)
{
    int code = (int)key;
    if (code >= (int)Key.A && code <= (int)Key.Z)
        return Text.FromChar((char32)code);
    if (code >= (int)Key.D0 && code <= (int)Key.D9)
        return Text.FromChar((char32)code);
    if (code >= (int)Key.F1 && code <= (int)Key.F12)
        return "F" + Text.FromInteger(code - (int)Key.F1 + 1);
    switch (key)
    {
        case Key.Backspace: return "Backspace";
        case Key.Tab: return "Tab";
        case Key.Enter: return "Enter";
        case Key.Pause: return "Pause";
        case Key.Escape: return "Esc";
        case Key.Space: return "Space";
        case Key.PageUp: return "PgUp";
        case Key.PageDown: return "PgDn";
        case Key.End: return "End";
        case Key.Home: return "Home";
        case Key.Left: return "Left";
        case Key.Up: return "Up";
        case Key.Right: return "Right";
        case Key.Down: return "Down";
        case Key.Insert: return "Ins";
        case Key.Delete: return "Del";
        default: return "";
    }
}

/// The key a shortcut's last part names, or `Key.None`. Takes the names
/// `FormatKeyName` writes and their long forms.
public Key ParseKeyName(String name)
{
    if (name.ByteLength() == 1u)
    {
        byte only = name.ToUpperAscii().GetByteAt(0u);
        if ((only >= (byte)'A' && only <= (byte)'Z') || (only >= (byte)'0' && only <= (byte)'9'))
            return (Key)(int)only;
        return Key.None;
    }
    String lower = name.ToLowerAscii();
    if (lower.ByteLength() <= 3u && lower.StartsWith("f"))
    {
        int number = 0;
        for (nuint i = 1u; i < lower.ByteLength(); i++)
        {
            byte digit = lower.GetByteAt(i);
            if (digit < (byte)'0' || digit > (byte)'9')
                return Key.None;
            number = number * 10 + (int)(digit - (byte)'0');
        }
        if (number < 1 || number > 12)
            return Key.None;
        return (Key)((int)Key.F1 + number - 1);
    }
    switch (lower)
    {
        case "backspace": return Key.Backspace;
        case "tab": return Key.Tab;
        case "enter":
        case "return": return Key.Enter;
        case "pause": return Key.Pause;
        case "esc":
        case "escape": return Key.Escape;
        case "space": return Key.Space;
        case "pgup":
        case "pageup": return Key.PageUp;
        case "pgdn":
        case "pagedown": return Key.PageDown;
        case "end": return Key.End;
        case "home": return Key.Home;
        case "left": return Key.Left;
        case "up": return Key.Up;
        case "right": return Key.Right;
        case "down": return Key.Down;
        case "ins":
        case "insert": return Key.Insert;
        case "del":
        case "delete": return Key.Delete;
        default: return Key.None;
    }
}
