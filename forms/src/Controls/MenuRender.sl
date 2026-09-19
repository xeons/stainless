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

// How a menu is drawn, chosen by the program rather than by the widget set.
//
// **WinForms' `ToolStripRenderer`, not a themed widget set.** The difference
// matters: a themed widget set restyles everything a program has, and is the
// direction `forms/README.md` rules out because it means a second renderer for
// every control type ever added. A renderer is asked for by the one menu that
// wants it, and a program that asks for nothing keeps the platform's own
// drawing -- which on a GTK desktop is the only right answer anyway.
//
// The seam underneath is `IMenuItemPeer.SetOwnerDrawn`, which answers whether
// the platform will hand an item over. Windows will; GTK says no and draws its
// own menus through the desktop theme. So a renderer is asked, is told no, and
// nothing else happens -- rather than a program having to know which platform
// it is on before it can ask.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

/// What draws a menu's items.
///
/// A class rather than a set of closures, because the two questions are asked
/// at different times about the same item and want the same state between
/// them: how big is this, and later, draw it there.
public abstract class MenuRenderer
{
    /// Whether this renderer wants the items handed to it.
    ///
    /// False leaves the platform drawing its own menus, which is what
    /// `SystemMenuRenderer` is: turning owner drawing off is a thing a program
    /// must be able to do, and a renderer that is asked for and then draws
    /// nothing would be a menu of empty rectangles.
    public abstract bool OwnerDrawn { get; }

    /// How much room the item wants.
    public abstract Size Measure(Graphics surface, MenuItem item);

    /// Draw it, background included: nothing is drawn underneath an
    /// owner-drawn item.
    public abstract void Draw(Graphics surface, MenuItem item,
                              Rectangle bounds, MenuItemState state);
}

/// The platform's own drawing, which is what a menu has unless asked
/// otherwise.
///
/// `Measure` and `Draw` are never called: `OwnerDrawn` is false, so nothing is
/// ever handed over. They are here because the base class declares them and an
/// abstract method with no body is not a thing.
public sealed class SystemMenuRenderer : MenuRenderer
{
    public override bool OwnerDrawn => false;

    public override Size Measure(Graphics surface, MenuItem item) => Size.Of(0, 0);

    public override void Draw(Graphics surface, MenuItem item,
                              Rectangle bounds, MenuItemState state)
    {
    }
}

/// Office XP: a gradient gutter down the left, and a flat outlined rectangle
/// where the pointer is.
///
/// **Flat, which is the whole of what made it look new in 2001.** Windows drew
/// a raised bevel round a hot menu item and a sunken one round a pressed
/// button; Office XP drew a one-pixel outline and a wash of the highlight
/// colour, and everything since has copied it. There is no bevel anywhere
/// here, deliberately.
///
/// The colours come from the system rather than from a table of Office's own,
/// so a machine with a different scheme gets a menu that belongs to it. That
/// is a departure from what Office actually did -- it shipped its colours --
/// and it is the right one for a library: a program that wants Office's exact
/// blue can set the properties.
public class OfficeXpRenderer : MenuRenderer
{
    /// How wide the gutter is: the strip down the left where a tick or an icon
    /// goes.
    public int GutterWidth { get; set; }

    /// Room above and below the text.
    public int Padding { get; set; }

    public OfficeXpRenderer()
    {
        GutterWidth = 24;
        Padding = 4;
    }

    public override bool OwnerDrawn => true;

    /// The colour a hot item is washed with: the highlight, mostly faded out.
    ///
    /// Office XP used about a fifth of the selection colour over white, which
    /// is light enough to read black text on -- and reading black text on it is
    /// the point, because the other way round means the text colour changing
    /// as the pointer moves.
    public virtual Color HotFill => Blend(SystemColors.Highlight, SystemColors.Window, 20);

    /// And the line round it, which is the selection colour itself.
    public virtual Color HotBorder => SystemColors.Highlight;

    /// The gutter, which fades across rather than down: a vertical gradient in
    /// a strip this narrow reads as a mistake, and Office's ran left to right.
    ///
    /// **It starts darker than the control colour on purpose.** Ramping from
    /// `Control` to `Window` is the obvious reading of what Office did, and on
    /// a modern light scheme those two are #F0F0F0 and #FFFFFF -- a gradient
    /// nobody can see, which is a gutter that is not there. A quarter of the
    /// shadow colour mixed in gives it an edge that reads on every scheme
    /// without naming a colour of its own.
    public virtual Color GutterFrom => Blend(SystemColors.ControlDark, SystemColors.Control, 25);
    public virtual Color GutterTo => SystemColors.Control;

    public virtual Color Background => SystemColors.Window;

    /// What a menu bar sits on, which is the window's own furniture colour and
    /// not the white a dropdown uses.
    public virtual Color BarBackground => SystemColors.Control;
    public virtual Color TextColor => SystemColors.WindowText;
    public virtual Color DisabledText => SystemColors.GrayText;

    /// The font a menu is drawn in.
    ///
    /// The widget set's default rather than a `Graphics` property, because a
    /// device context has no font in this library -- text is drawn with one
    /// that is passed in, which is what keeps a `Graphics` from carrying state
    /// between calls. A program wanting another one sets this.
    public virtual Font Font => WidgetSet.Current.DefaultFont();

    public override Size Measure(Graphics surface, MenuItem item)
    {
        if (item.IsSeparator)
            return Size.Of(GutterWidth + 32, 3 + Padding);

        var text = surface.MeasureString(Spoken(item.Text), Font);

        // A word on the bar, and **nothing added to it**.
        //
        // Windows puts its own margin round a bar item -- measured at fourteen
        // pixels on this scheme -- and adds it to whatever a `WM_MEASUREITEM`
        // reports. Padding here as well is padding twice: `File` came out
        // forty-eight pixels wide where the platform's own is thirty-two, and
        // the bar read as airy for no reason a reader of this code could see.
        // Reporting the text alone lands on exactly the platform's number.
        //
        // The height is reported and ignored: a bar is `SM_CYMENU` tall
        // whatever an item asks for, which is why `File` came back nineteen
        // when this asked for twenty-three.
        if (item.OnMenuBar)
            return Size.Of(text.Width, text.Height);

        // Room for the caption, the gutter it sits beside, and a margin on the
        // right for the arrow.
        //
        // **The arrow is ours to draw and ours to leave room for.** Windows
        // draws the little triangle on an item that opens a submenu -- until
        // the item is owner-drawn, at which point it draws nothing at all and
        // the program has to.
        //
        // The margin is smaller than it looks because Windows adds its own
        // check-mark column to what is reported here, the same way it adds a
        // margin to a bar item. That cannot be measured from a menu nobody has
        // opened, so unlike the bar above this is proportioned by eye.
        return Size.Of(GutterWidth + text.Width + 18, text.Height + Padding * 2);
    }

    public override void Draw(Graphics surface, MenuItem item,
                              Rectangle bounds, MenuItemState state)
    {
        bool disabled = state.HasFlag(MenuItemState.Disabled);
        bool selected = state.HasFlag(MenuItemState.Selected) && !disabled;

        if (item.OnMenuBar)
        {
            DrawOnBar(surface, item, bounds, disabled, selected);
            return;
        }

        surface.FillRectangle(new Brush(Background), bounds);

        var gutter = Rectangle.Of(bounds.X, bounds.Y, GutterWidth, bounds.Height);
        surface.FillRectangle(new Brush(GutterFrom, GutterTo,
                                        BrushStyle.HorizontalGradient), gutter);

        if (item.IsSeparator)
        {
            // Across the text area only, as Office's did -- a rule that also
            // crossed the gutter would cut the strip in half.
            int y = bounds.Y + bounds.Height / 2;
            surface.DrawLine(new Pen(SystemColors.ControlDark),
                             bounds.X + GutterWidth + 2, y, bounds.Right - 2, y);
            return;
        }

        if (selected)
        {
            // Over the gutter as well, which is what makes a hot item read as
            // one strip rather than as two rectangles side by side.
            surface.FillRectangle(new Brush(HotFill), bounds);
            surface.DrawRectangle(new Pen(HotBorder),
                                  Rectangle.Of(bounds.X, bounds.Y,
                                               bounds.Width - 1, bounds.Height - 1));
        }

        if (state.HasFlag(MenuItemState.Checked))
            DrawTick(surface, gutter, disabled);

        var text = Rectangle.Of(bounds.X + GutterWidth + 8, bounds.Y,
                                bounds.Width - GutterWidth - 16, bounds.Height);

        TextFormat format;
        format.Horizontal = HorizontalAlignment.Left;
        format.Vertical = VerticalAlignment.Middle;
        format.Wrap = false;

        surface.DrawString(item.Text, Font,
                           disabled ? DisabledText : TextColor, text, format);

        if (item.HasItems)
            DrawArrow(surface, bounds, disabled);
    }

    /// The triangle on an item that opens a submenu.
    ///
    /// Drawn as a stack of shortening lines rather than as a glyph, for the
    /// reason the tick is: the character a font has for this is not the same
    /// character in every font, and a menu cannot afford to find that out on
    /// somebody else's machine.
    void DrawArrow(Graphics surface, Rectangle bounds, bool disabled)
    {
        var ink = new Pen(disabled ? DisabledText : TextColor, 1, PenStyle.Solid);
        int x = bounds.Right - 12;
        int middle = bounds.Y + bounds.Height / 2;

        for (int step = 0; step < 4; step++)
        {
            surface.DrawLine(ink, x + step, middle - 3 + step, x + step, middle + 4 - step);
        }
    }

    /// One word on the bar: flat, on the window's own colour, with an outline
    /// round it when it is hot or when its menu is open.
    ///
    /// **The same outline for hot and for open**, which is what Office XP did
    /// and what makes the bar read as one row of words rather than as buttons.
    /// Windows reports an open heading as selected, so both arrive here the
    /// same way and neither needs telling apart.
    void DrawOnBar(Graphics surface, MenuItem item, Rectangle bounds,
                   bool disabled, bool selected)
    {
        surface.FillRectangle(new Brush(BarBackground), bounds);

        if (selected)
        {
            surface.FillRectangle(new Brush(HotFill), bounds);
            surface.DrawRectangle(new Pen(HotBorder),
                                  Rectangle.Of(bounds.X, bounds.Y,
                                               bounds.Width - 1, bounds.Height - 1));
        }

        TextFormat format;
        format.Horizontal = HorizontalAlignment.Center;
        format.Vertical = VerticalAlignment.Middle;
        format.Wrap = false;

        surface.DrawString(item.Text, Font,
                           disabled ? DisabledText : TextColor, bounds, format);
    }

    /// A tick, drawn as two strokes rather than as a character: the glyph
    /// fonts disagree about is the one thing a menu cannot afford to get
    /// wrong, and two lines look the same everywhere.
    void DrawTick(Graphics surface, Rectangle gutter, bool disabled)
    {
        var ink = new Pen(disabled ? DisabledText : TextColor, 2, PenStyle.Solid);
        int x = gutter.X + gutter.Width / 2 - 3;
        int y = gutter.Y + gutter.Height / 2;

        surface.DrawLine(ink, x - 2, y, x, y + 3);
        surface.DrawLine(ink, x, y + 3, x + 5, y - 4);
    }

    /// A caption with its accelerator markers taken out, which is the string
    /// that actually reaches the screen.
    ///
    /// **Measuring `&File` and drawing `File` is how a menu bar ends up
    /// airy.** The two calls underneath disagree on purpose: measuring goes
    /// through `GetTextExtentPoint32W`, which counts every character it is
    /// given, and drawing goes through `DrawTextW` without `DT_NOPREFIX`,
    /// which eats the ampersand and underlines what follows. So every caption
    /// measured one glyph wider than it drew, the item was padded to that
    /// width, and the text sat centred in a gap the size of an ampersand --
    /// twice over between any two items.
    ///
    /// `&&` is a literal ampersand and stays one, which is the same rule
    /// `DrawTextW` follows.
    static String Spoken(String caption)
    {
        if (!caption.Contains("&"))
            return caption;

        var plain = new StringBuilder();
        nuint at = 0u;
        nuint length = caption.ByteLength();

        while (at < length)
        {
            byte here = caption.ByteAt(at);
            if (here != (byte)38)                    // '&'
            {
                plain.AppendByte(here);
                at++;
                continue;
            }

            // A doubled one is a real ampersand; a single one marks the letter
            // after it and is not drawn.
            at++;
            if (at < length && caption.ByteAt(at) == (byte)38)
            {
                plain.AppendByte((byte)38);
                at++;
            }
        }
        return plain.ToText();
    }

    /// `percent` of `a` over `b`.
    ///
    /// Here rather than on `Color`, which has no blending and does not need
    /// any: one renderer wanting a wash of the selection colour is not a
    /// reason for every program to gain a colour arithmetic.
    ///
    /// Module level rather than a static member: a static is not reached
    /// through an object, so `protected` has nothing to say about one
    /// (SL0575), and a subclass wanting it can call it by name like anything
    /// else in this module.
    static Color Blend(Color a, Color b, int percent)
    {
        int rest = 100 - percent;
        return Color.FromRgb(
            (byte)(((int)a.R * percent + (int)b.R * rest) / 100),
            (byte)(((int)a.G * percent + (int)b.G * rest) / 100),
            (byte)(((int)a.B * percent + (int)b.B * rest) / 100));
    }
}
