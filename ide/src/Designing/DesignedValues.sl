// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// The values a form file writes as Stainless expressions: a colour, a font,
// and a list of strings. Each is read from the spelling the file holds, so the
// designer shows what will run, and spelled back the way a person would write
// it, so the generated half copies it unchanged.
module Ide.Designing;

import Standard.Collections;
import Standard.Convert;
import Standard.Reflection;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
import Ide.Designer;

/// The type a colour property is, by its reflected name.
public const String DesignedColorType = "Forms.Drawing.Color";

/// The type a font property is.
public const String DesignedFontType = "Forms.Drawing.Font";

/// The type a picture property is.
public const String DesignedBitmapType = "Forms.Drawing.Bitmap";

/// The module the generated half needs for either.
public const String DesignedDrawingModule = "Forms.Drawing";

/// The type a shortcut property is.
public const String DesignedShortcutType = "Forms.Platform.Shortcut";

/// The module the generated half needs for a shortcut's `Key` and modifiers.
public const String DesignedPlatformModule = "Forms.Platform";

/// The type a command property is, which names a command of the form's.
public const String DesignedCommandType = "Forms.Command";

// ------------------------------------------------------------ shortcuts

/// A shortcut as the generated half writes it:
/// `Shortcut.FromKey(Key.S, ModifierKeys.Control | ModifierKeys.Shift)`, or
/// `Shortcut.Empty`.
public String SpellDesignedShortcut(Shortcut shortcut)
{
    if (shortcut.IsEmpty)
        return "Shortcut.Empty";
    var held = new List<String>();
    if (shortcut.Modifiers.HasFlag(ModifierKeys.Control))
        held.Add("ModifierKeys.Control");
    if (shortcut.Modifiers.HasFlag(ModifierKeys.Shift))
        held.Add("ModifierKeys.Shift");
    if (shortcut.Modifiers.HasFlag(ModifierKeys.Alt))
        held.Add("ModifierKeys.Alt");
    String modifiers = held.IsEmpty ? "ModifierKeys.None" : " | ".Join(held.ToArray());
    return "Shortcut.FromKey(Key." + FindKeyMemberName(shortcut.Key) + ", " + modifiers + ")";
}

/// A shortcut from what the file says, or from what a person typed into the
/// Properties grid: `Shortcut.FromKey(...)`, `Shortcut.Empty`, `Ctrl+S`, or
/// nothing at all for none.
public Result<Shortcut, String> ReadDesignedShortcut(String item)
{
    String text = item.Trim();
    if (text == "" || text == "Shortcut.Empty")
        return Ok(Shortcut.Empty);
    if (!text.StartsWith("Shortcut.FromKey(") || !text.EndsWith(")"))
    {
        var typed = Shortcut.Parse(text);
        if (typed.Some)
            return Ok(typed.Value);
        return Fail("'" + text + "' is not a shortcut; write it as Ctrl+Shift+S");
    }

    String inside = text.Substring(17u, text.ByteLength() - 18u);
    String keyPart = inside.SubstringBefore(",").Trim();
    String modifierPart = inside.SubstringAfter(",").Trim();
    if (!keyPart.StartsWith("Key."))
        return Fail("'" + keyPart + "' is not a key");
    var keyType = FindType("Forms.Platform.Key");
    long key = -1;
    for (nuint i = 0u; i < keyType.EnumMemberCount; i++)
    {
        if (keyType.GetEnumMemberName(i) == keyPart.Substring(4u))
            key = keyType.GetEnumMemberValue(i);
    }
    if (key < 0)
        return Fail("'" + keyPart + "' is not a key");

    var modifiers = ModifierKeys.None;
    foreach (var part in modifierPart.Split("|"))
    {
        switch (part.Trim())
        {
            case "ModifierKeys.None": break;
            case "ModifierKeys.Control": modifiers = modifiers | ModifierKeys.Control; break;
            case "ModifierKeys.Shift": modifiers = modifiers | ModifierKeys.Shift; break;
            case "ModifierKeys.Alt": modifiers = modifiers | ModifierKeys.Alt; break;
            default: return Fail("'" + part.Trim() + "' is not a modifier");
        }
    }
    return Ok(Shortcut.FromKey((Key)(int)key, modifiers));
}

/// A key's member name in `Key`, which is what the generated half writes.
String FindKeyMemberName(Key key)
{
    var keyType = FindType("Forms.Platform.Key");
    for (nuint i = 0u; i < keyType.EnumMemberCount; i++)
    {
        if (keyType.GetEnumMemberValue(i) == (long)(int)key)
            return keyType.GetEnumMemberName(i);
    }
    return "None";
}

// ------------------------------------------------------------ colours

/// `Colors`' members, in its order, which is the order a name is preferred in.
String[] ListColourNames() =>
    ["Transparent", "Black", "White", "Red", "Green", "Blue", "Yellow", "Gray", "LightGray",
     "DarkGray", "Navy", "Maroon", "Olive", "Purple", "Teal", "Silver"];

/// A member of `Colors` by name, or false for a name it does not have.
bool FindNamedColour(String name, out Color colour)
{
    colour = Colors.Black;
    switch (name)
    {
        case "Transparent": colour = Colors.Transparent; return true;
        case "Black": colour = Colors.Black; return true;
        case "White": colour = Colors.White; return true;
        case "Red": colour = Colors.Red; return true;
        case "Green": colour = Colors.Green; return true;
        case "Blue": colour = Colors.Blue; return true;
        case "Yellow": colour = Colors.Yellow; return true;
        case "Gray": colour = Colors.Gray; return true;
        case "LightGray": colour = Colors.LightGray; return true;
        case "DarkGray": colour = Colors.DarkGray; return true;
        case "Navy": colour = Colors.Navy; return true;
        case "Maroon": colour = Colors.Maroon; return true;
        case "Olive": colour = Colors.Olive; return true;
        case "Purple": colour = Colors.Purple; return true;
        case "Teal": colour = Colors.Teal; return true;
        case "Silver": colour = Colors.Silver; return true;
        default: return false;
    }
}

/// A member of `SystemColors` by name: a colour the theme decides, which is
/// read now and stays a name in the file.
bool FindSystemColour(String name, out Color colour)
{
    colour = Colors.Black;
    switch (name)
    {
        case "Control": colour = SystemColors.Control; return true;
        case "ControlText": colour = SystemColors.ControlText; return true;
        case "Window": colour = SystemColors.Window; return true;
        case "WindowText": colour = SystemColors.WindowText; return true;
        case "Highlight": colour = SystemColors.Highlight; return true;
        case "HighlightText": colour = SystemColors.HighlightText; return true;
        case "GrayText": colour = SystemColors.GrayText; return true;
        case "ControlDark": colour = SystemColors.ControlDark; return true;
        case "ControlLight": colour = SystemColors.ControlLight; return true;
        default: return false;
    }
}

/// A colour as the file or a person writes it: `Colors.Red` or `Red`,
/// `SystemColors.Window`, `Color.FromRgb(255, 128, 0)`,
/// `Color.FromArgb(128, 255, 128, 0)`, or the bare `255, 128, 0`.
public Result<Color, String> ReadDesignedColour(String item)
{
    String text = item.Trim();
    Color colour;
    if (text.StartsWith("Colors.") && FindNamedColour(text.Substring(7u), out colour))
        return Ok(colour);
    if (text.StartsWith("SystemColors.") && FindSystemColour(text.Substring(13u), out colour))
        return Ok(colour);
    if (FindNamedColour(text, out colour))
        return Ok(colour);

    String arguments = text;
    bool alpha = false;
    if (text.StartsWith("Color.FromRgb(") && text.EndsWith(")"))
        arguments = text.Substring(14u, text.ByteLength() - 15u);
    else if (text.StartsWith("Color.FromArgb(") && text.EndsWith(")"))
    {
        arguments = text.Substring(15u, text.ByteLength() - 16u);
        alpha = true;
    }

    var parts = SplitDesignedArguments(arguments);
    if (parts.Count == 4u)
        alpha = true;
    if (parts.Count != (alpha ? 4u : 3u))
        return Fail("'" + text + "' is not a colour: write a name, or red, green and blue from 0 to 255");

    var channels = new List<byte>();
    foreach (var part in parts)
    {
        var read = Convert.ToInt(part.Trim());
        if (!read.Ok || read.Value < 0 || read.Value > 255)
            return Fail("'" + part.Trim() + "' is not a channel from 0 to 255");
        channels.Add((byte)read.Value);
    }
    return Ok(alpha
        ? Color.FromArgb(channels[0u], channels[1u], channels[2u], channels[3u])
        : Color.FromRgb(channels[0u], channels[1u], channels[2u]));
}

/// How the file writes a colour: by its name in `Colors` when it has one, and
/// as its channels otherwise.
public String SpellDesignedColour(Color colour)
{
    foreach (var name in ListColourNames())
    {
        Color named;
        if (FindNamedColour(name, out named) && named.Equals(colour))
            return "Colors." + name;
    }
    if (colour.A == 255)
        return "Color.FromRgb(" + Text.FromInteger(colour.R) + ", " + Text.FromInteger(colour.G) + ", "
               + Text.FromInteger(colour.B) + ")";
    return "Color.FromArgb(" + Text.FromInteger(colour.A) + ", " + Text.FromInteger(colour.R) + ", "
           + Text.FromInteger(colour.G) + ", " + Text.FromInteger(colour.B) + ")";
}

// ------------------------------------------------------------ fonts

/// A font as the file writes it, `new Font("Segoe UI", 9, FontStyle.Bold)`,
/// or as a person types it, `Segoe UI, 9, Bold`.
public Result<Font, String> ReadDesignedFont(String item)
{
    String text = item.Trim();
    String arguments = text;
    bool written = text.StartsWith("new Font(") && text.EndsWith(")");
    if (written)
        arguments = text.Substring(9u, text.ByteLength() - 10u);

    var parts = SplitDesignedArguments(arguments);
    if (parts.Count < 2u || parts.Count > 3u)
        return Fail("'" + text + "' is not a font: write a family, a size in points, and any styles");

    String family = parts[0u].Trim();
    if (written || family.StartsWith("\""))
        family = UnquoteFormText(family);
    if (family == "")
        return Fail("a font needs a family");

    var size = Convert.ToInt(parts[1u].Trim());
    if (!size.Ok || size.Value <= 0)
        return Fail("'" + parts[1u].Trim() + "' is not a size in points");

    FontStyle style = FontStyle.Regular;
    if (parts.Count == 3u)
    {
        foreach (var each in parts[2u].Split("|"))
        {
            String name = each.Trim();
            if (name.StartsWith("FontStyle."))
                name = name.Substring(10u);
            switch (name)
            {
                case "Regular": break;
                case "Bold": style = style | FontStyle.Bold; break;
                case "Italic": style = style | FontStyle.Italic; break;
                case "Underline": style = style | FontStyle.Underline; break;
                case "Strikeout": style = style | FontStyle.Strikeout; break;
                default: return Fail("'" + name + "' is not a font style");
            }
        }
    }
    return Ok(new Font(family, size.Value, style));
}

/// How the file writes a font.
public String SpellDesignedFont(Font font)
{
    String spelled = "new Font(" + QuoteFormText(font.Family) + ", " + Text.FromInteger(font.Size);
    String styles = DescribeFontStyles(font.Style, "FontStyle.");
    if (styles != "")
        spelled = spelled + ", " + styles;
    return spelled + ")";
}

/// How the grid shows a font: `Segoe UI, 9, Bold | Italic`.
public String DescribeDesignedFont(Font font)
{
    String shown = font.Family + ", " + Text.FromInteger(font.Size);
    String styles = DescribeFontStyles(font.Style, "");
    return styles == "" ? shown : shown + ", " + styles;
}

String DescribeFontStyles(FontStyle style, String prefix)
{
    var names = new List<String>();
    if (style.HasFlag(FontStyle.Bold))
        names.Add(prefix + "Bold");
    if (style.HasFlag(FontStyle.Italic))
        names.Add(prefix + "Italic");
    if (style.HasFlag(FontStyle.Underline))
        names.Add(prefix + "Underline");
    if (style.HasFlag(FontStyle.Strikeout))
        names.Add(prefix + "Strikeout");
    return " | ".Join(names.ToArray());
}

// ------------------------------------------------------------ lists

/// A list of strings as the file writes it, `["One", "Two"]`.
public Result<String[], String> ReadDesignedTextArray(String item)
{
    String text = item.Trim();
    if (!text.StartsWith("[") || !text.EndsWith("]"))
        return Fail("'" + text + "' is not a list: write it as [\"One\", \"Two\"]");

    var lines = new List<String>();
    foreach (var part in SplitDesignedArguments(text.Substring(1u, text.ByteLength() - 2u)))
    {
        String quoted = part.Trim();
        if (!quoted.StartsWith("\""))
            return Fail("'" + quoted + "' is not a string");
        lines.Add(UnquoteFormText(quoted));
    }
    return Ok(lines.ToArray());
}

/// How the file writes a list of strings.
public String SpellDesignedTextArray(String[] lines)
{
    var quoted = new List<String>();
    foreach (var line in lines)
        quoted.Add(QuoteFormText(line));
    return "[" + ", ".Join(quoted.ToArray()) + "]";
}

// ------------------------------------------------------------ pictures

/// The path in a picture as the file writes it, `Embed("art/logo.png")`:
/// relative to the form file, and embedded in the program by the generated
/// half.
public Result<String, String> ReadDesignedPicturePath(String item)
{
    String text = item.Trim();
    if (!text.StartsWith("Embed(") || !text.EndsWith(")"))
        return Fail("'" + text + "' is not a picture: write it as Embed(\"art/logo.png\")");
    var parts = SplitDesignedArguments(text.Substring(6u, text.ByteLength() - 7u));
    if (parts.Count != 1u || !parts[0u].Trim().StartsWith("\""))
        return Fail("a picture names one file, as a string");
    return Ok(UnquoteFormText(parts[0u].Trim()));
}

/// How the file writes a picture. `/` separates the parts on every platform,
/// so a form file reads the same wherever it is checked out.
public String SpellDesignedPicture(String path) => "Embed(" + QuoteFormText(path.Replace("\\", "/")) + ")";

/// Where a picture the file names is, from the form file's directory.
public String FindDesignedPicture(String baseDirectory, String path) =>
    Standard.Path.IsPathRooted(path) ? path : Standard.Path.Join(baseDirectory, path);

// ------------------------------------------------------------ arguments

/// What is between the parentheses of a call or the brackets of an array,
/// split at its own commas: one inside a string or a nested call is not one.
/// Nothing at all is no arguments.
public List<String> SplitDesignedArguments(String text)
{
    var parts = new List<String>();
    if (text.Trim() == "")
        return parts;

    nuint size = text.ByteLength();
    nuint start = 0u;
    int depth = 0;
    bool quoted = false;
    for (nuint i = 0u; i < size; i++)
    {
        byte c = text.GetByteAt(i);
        if (quoted)
        {
            if (c == (byte)'\\')
                i++;
            else if (c == (byte)'"')
                quoted = false;
            continue;
        }
        switch (c)
        {
            case (byte)'"':
                quoted = true;
                break;
            case (byte)'(':
            case (byte)'[':
                depth++;
                break;
            case (byte)')':
            case (byte)']':
                depth--;
                break;
            case (byte)',':
                if (depth == 0)
                {
                    parts.Add(text.Substring(start, i - start));
                    start = i + 1u;
                }
                break;
            default:
                break;
        }
    }
    parts.Add(text.Substring(start, size - start));
    return parts;
}
