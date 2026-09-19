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

// How a window's chrome -- its menus and its toolbars -- is drawn, chosen by
// the program rather than by the widget set.
//
// **One renderer for both, which is the whole reason it is not `MenuRenderer`
// any more.** A look is a palette and a set of rules, not a menu: Office XP's
// hot item and its hot toolbar button are the same wash of the same colour
// with the same one-pixel outline, and its toolbar sits on exactly the colour
// its menu bar does. Two renderers would be two copies of that palette, kept
// in step by hand, and the first divergence would be a toolbar that no longer
// matched the bar above it. So a program sets one object on both.
//
// The two halves stay recognisably separate inside it -- a menu is measured
// and drawn, a toolbar is only drawn, because comctl32 lays its own buttons
// out and is better at it than this would be.
//
// **WinForms' `ToolStripRenderer`, not a themed widget set.** The difference
// matters: a themed widget set restyles everything a program has, and is the
// direction `forms/README.md` rules out because it means a second renderer for
// every control type ever added. A renderer is asked for by the one menu that
// wants it, and a program that asks for nothing keeps the platform's own
// drawing -- which on a GTK desktop is the only right answer anyway.
//
// The seam underneath is `IMenuItemPeer.SetOwnerDrawn` and
// `IToolBarPeer.SetOwnerDrawn`, which answer whether the platform will hand
// the drawing over. Windows will; GTK says no and draws its own menus and
// toolbars through the desktop theme. So a renderer is asked, is told no, and
// nothing else happens -- rather than a program having to know which platform
// it is on before it can ask.
//
// **The two platforms say no by different mechanisms, and that is the point of
// asking.** A menu item is owner-drawn: Windows sends `WM_MEASUREITEM` and
// `WM_DRAWITEM` and the program answers both. A toolbar button is custom-drawn:
// comctl32 asks its parent, several times per paint, how much of its own
// drawing to keep. Neither of those words appears above this line.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

/// What draws a menu's items.
///
/// A class rather than a set of closures, because the two questions are asked
/// at different times about the same item and want the same state between
/// them: how big is this, and later, draw it there.
public abstract class ChromeRenderer
{
    /// Whether this renderer wants the items handed to it.
    ///
    /// False leaves the platform drawing its own menus, which is what
    /// `SystemChromeRenderer` is: turning owner drawing off is a thing a program
    /// must be able to do, and a renderer that is asked for and then draws
    /// nothing would be a menu of empty rectangles.
    public abstract bool OwnerDrawn { get; }

    /// How much room the item wants.
    public abstract Size Measure(Graphics surface, MenuItem item);

    /// Draw it, background included: nothing is drawn underneath an
    /// owner-drawn item.
    public abstract void Draw(Graphics surface, MenuItem item,
                              Rectangle bounds, MenuItemState state);

    /// Fill the strip a toolbar's buttons sit on, before any of them is drawn.
    ///
    /// **A toolbar is not measured here and a menu is**, which is the one
    /// place the two halves of this class differ in shape. comctl32 lays a
    /// toolbar out itself -- it knows the picture size, the caption, whether
    /// captions are shown at all, and how a wrapped bar breaks -- and taking
    /// that over would mean reimplementing it to change how a button is
    /// coloured. So the layout stays native and only the paint is borrowed.
    public abstract void DrawToolBackground(Graphics surface, Rectangle bounds);

    /// Draw one toolbar button, background included.
    ///
    /// `bounds` is the rectangle comctl32 decided on, so a renderer arranges
    /// the picture and the caption inside a box it did not choose.
    public abstract void DrawTool(Graphics surface, ToolButton button,
                                  Rectangle bounds, ToolItemState state);
}

/// The platform's own drawing, which is what a menu has unless asked
/// otherwise.
///
/// `Measure` and `Draw` are never called: `OwnerDrawn` is false, so nothing is
/// ever handed over. They are here because the base class declares them and an
/// abstract method with no body is not a thing.
public sealed class SystemChromeRenderer : ChromeRenderer
{
    public override bool OwnerDrawn => false;

    public override Size Measure(Graphics surface, MenuItem item) => Size.Of(0, 0);

    public override void Draw(Graphics surface, MenuItem item,
                              Rectangle bounds, MenuItemState state)
    {
    }

    public override void DrawToolBackground(Graphics surface, Rectangle bounds)
    {
    }

    public override void DrawTool(Graphics surface, ToolButton button,
                                  Rectangle bounds, ToolItemState state)
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
public class OfficeXpRenderer : ChromeRenderer
{
    /// How wide the gutter is: the strip down the left where a tick or an icon
    /// goes.
    public int GutterWidth { get; set; }

    /// Room above and below the text.
    public int Padding { get; set; }

    /// The gap between a toolbar button's picture and its caption.
    public int ToolGap { get; set; }

    /// How much of a disabled button's picture is drawn, as a percentage.
    ///
    /// Office XP drew a greyscale emboss of the icon, which needs the picture's
    /// pixels read back; a `Bitmap` here can be made from pixels and not turned
    /// back into them, so this fades it into the background instead. It reads
    /// as unavailable, which is the job, and it is what WinForms' own
    /// `CreateDisabledImage` does for the alpha half of the same effect.
    public int DisabledOpacity { get; set; }

    public OfficeXpRenderer()
    {
        GutterWidth = 24;
        Padding = 4;
        ToolGap = 4;
        DisabledOpacity = 35;
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

        // **Hiding the underline is drawing a caption that has no `&` in it.**
        // `DrawTextW` has a `DT_HIDEPREFIX` for this, and reaching it would
        // mean a new field on `TextFormat`, a new flag through the graphics
        // seam and an answer for a backend that has no such idea. Taking the
        // marker out instead needs none of that, produces the same pixels, and
        // is a function this renderer already has -- it is what every caption
        // is measured with, which is also why the width does not move when the
        // underline appears.
        String caption = state.HasFlag(MenuItemState.NoAccelerators)
                       ? Spoken(item.Text) : item.Text;

        if (item.OnMenuBar)
        {
            DrawOnBar(surface, caption, bounds, disabled, selected);
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
            Wash(surface, bounds, HotFill);
        }

        if (state.HasFlag(MenuItemState.Checked))
            DrawTick(surface, gutter, disabled);

        var text = Rectangle.Of(bounds.X + GutterWidth + 8, bounds.Y,
                                bounds.Width - GutterWidth - 16, bounds.Height);

        TextFormat format;
        format.Horizontal = HorizontalAlignment.Left;
        format.Vertical = VerticalAlignment.Middle;
        format.Wrap = false;

        surface.DrawString(caption, Font,
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
    void DrawOnBar(Graphics surface, String caption, Rectangle bounds,
                   bool disabled, bool selected)
    {
        surface.FillRectangle(new Brush(BarBackground), bounds);

        if (selected)
        {
            Wash(surface, bounds, HotFill);
        }

        TextFormat format;
        format.Horizontal = HorizontalAlignment.Center;
        format.Vertical = VerticalAlignment.Middle;
        format.Wrap = false;

        surface.DrawString(caption, Font,
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

    // ------------------------------------------------------------- toolbars

    /// What a toolbar sits on: the window's own furniture colour, the same one
    /// the menu bar uses. Deliberately the same -- a bar and the strip under it
    /// in two shades of nearly-grey is the thing that reads as unfinished.
    public virtual Color ToolBackground => BarBackground;

    /// A button held down, and a ticked one under the pointer.
    public virtual Color PressedFill => Blend(SystemColors.Highlight, SystemColors.Window, 45);

    /// A toggle that is on while the pointer is somewhere else.
    ///
    /// **Deeper than hot, not fainter**, which is the opposite of the first
    /// guess and the numbers are why. Fainter put it at 14 percent of the
    /// highlight against hot's 20, and on this scheme that is 219 against 204
    /// -- fifteen levels of grey apart, on two rectangles that are never side
    /// by side. A toggle that is on was indistinguishable from the button the
    /// pointer happened to be over.
    ///
    /// Deeper separates them by more than twice as much and says the right
    /// thing as well: being on is a state the button is *in*, and looking
    /// pressed is how a flat toolbar has spelled that since Office XP. Hot
    /// stays where it is, because the menu shares it and the menu was
    /// measured.
    public virtual Color CheckedFill => Blend(SystemColors.Highlight, SystemColors.Window, 32);

    /// The line between groups of buttons, well short of the full contrast:
    /// `ControlDark` at full strength is a rule that shouts.
    public virtual Color SeparatorInk => Blend(SystemColors.ControlDark, SystemColors.Control, 60);

    public override void DrawToolBackground(Graphics surface, Rectangle bounds)
    {
        surface.FillRectangle(new Brush(ToolBackground), bounds);
    }

    public override void DrawTool(Graphics surface, ToolButton button,
                                  Rectangle bounds, ToolItemState state)
    {
        if (button.IsSeparator)
        {
            // Down the middle and short of both edges, which is what makes it
            // read as a divider rather than as a border.
            int line = bounds.X + bounds.Width / 2;
            surface.DrawLine(new Pen(SeparatorInk),
                             line, bounds.Y + 3, line, bounds.Bottom - 4);
            return;
        }

        bool disabled = state.HasFlag(ToolItemState.Disabled);
        bool pressed  = state.HasFlag(ToolItemState.Pressed) && !disabled;
        bool hot      = state.HasFlag(ToolItemState.Hot) && !disabled;
        bool ticked   = state.HasFlag(ToolItemState.Checked);

        // **A disabled button gets no wash at all**, not even a ticked one's.
        // Colouring something that cannot be pressed is how a toolbar ends up
        // looking like it is offering what it is refusing.
        if (!disabled)
        {
            // A ticked button that is also hot reads as pressed, which is what
            // it is about to become.
            if (pressed || (ticked && hot))
                Wash(surface, bounds, PressedFill);
            else if (ticked)
                Wash(surface, bounds, CheckedFill);
            else if (hot)
                Wash(surface, bounds, HotFill);
        }

        DrawToolContent(surface, button, bounds, disabled);
    }

    /// The picture and the caption, centred together in whatever box comctl32
    /// decided on.
    ///
    /// **Centred rather than placed at a known offset**, which is the one
    /// decision here worth explaining. comctl32 sized this button to fit its
    /// own idea of the content plus its own padding, and that padding differs
    /// with the toolbar's style, the system metrics and the theme. Measuring
    /// the content and centring it lands on the platform's arrangement without
    /// this code having to know any of those numbers -- and where it is wrong
    /// it is wrong symmetrically, which is the failure a reader forgives.
    void DrawToolContent(Graphics surface, ToolButton button, Rectangle bounds,
                         bool disabled)
    {
        Bitmap? picture = button.Picture;
        int pictureWidth = 0;
        int pictureHeight = 0;
        if (picture != null)
        {
            pictureWidth = ((Bitmap)picture).Width;
            pictureHeight = ((Bitmap)picture).Height;
        }

        String caption = button.ShowsText ? button.Text : "";
        var text = caption.IsEmpty ? Size.Of(0, 0)
                                   : surface.MeasureString(Spoken(caption), Font);

        int gap = pictureWidth > 0 && text.Width > 0 ? ToolGap : 0;
        int at = bounds.X + (bounds.Width - (pictureWidth + gap + text.Width)) / 2;
        int middle = bounds.Y + bounds.Height / 2;

        if (picture != null)
        {
            surface.DrawBitmap((Bitmap)picture,
                               Point.At(at, middle - pictureHeight / 2),
                               disabled ? DisabledOpacity : 100);
            at = at + pictureWidth + gap;
        }

        if (text.Width <= 0)
            return;

        TextFormat format;
        format.Horizontal = HorizontalAlignment.Left;
        format.Vertical = VerticalAlignment.Middle;
        format.Wrap = false;

        // The caption as written, not as measured: `DrawTextW` eats the
        // ampersand, and `Spoken` above is what keeps the two in step.
        surface.DrawString(caption, Font, disabled ? DisabledText : TextColor,
                           Rectangle.Of(at, bounds.Y, text.Width, bounds.Height),
                           format);
    }

    /// The Office XP rectangle: a wash of colour and a one-pixel line round it.
    ///
    /// Shared by the menu and the toolbar because it is the same rectangle --
    /// the single shape the whole look is built out of.
    void Wash(Graphics surface, Rectangle bounds, Color fill)
    {
        surface.FillRectangle(new Brush(fill), bounds);
        surface.DrawRectangle(new Pen(HotBorder),
                              Rectangle.Of(bounds.X, bounds.Y,
                                           bounds.Width - 1, bounds.Height - 1));
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
