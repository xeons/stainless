// SPDX-License-Identifier: 0BSD
//
// A control the program draws every pixel of, and that takes the keyboard.
//
//   stainless run samples/forms/drawn.sl forms/src bindings/win32 \
//       -l user32 -l gdi32
//
// `CustomControl` is the half of the control set with no platform widget behind
// it at all: no `EDIT`, no `GtkEntry`, nothing that already knows what text is.
// What it has is a window of its own, which is what the focus, the keyboard and
// a caret each need -- and what a `PaintBox`, being windowless, can never have.
//
// So this is a text field written from nothing: a string, a position in it, and
// the handlers that move one and edit the other. It is not a `TextBox` and is
// not meant to replace one. It is the smallest thing that shows the primitive
// working, and the shape every drawn control has: paint what you have, put the
// caret where it goes, and say what each key means.
//
// Pass `--selftest` and it builds the form, pumps the queue, checks what can be
// checked with nobody in front of it, and quits.
module Drawn;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32.Handles;
import Win32.User32;
#endif

/// A one-line text field, drawn rather than delegated.
///
/// **The caret is a byte offset**, because that is what a `String` position is
/// here: the text is UTF-8 and nothing counts characters, so moving left and
/// right means finding the next and previous character *boundary* rather than
/// adding one. `SkipCodePoint` does the first, and `Previous` below does the
/// second the only way a UTF-8 string allows -- by walking from the start.
public class Scratch : CustomControl
{
    String _text;
    nuint _at;

    /// Where a click landed and has not been turned into a position yet, or -1
    /// for none. Answered during the next paint, because turning an x into a
    /// position means measuring text and a `Graphics` to measure with exists
    /// only while painting.
    int _pending;

    public Scratch(WindowedControl parent)
    {
        base(parent);
        _text = "";
        _at = 0u;
        _pending = -1;
        Border = ControlBorder.Sunken;
        BackColor = Colors.White;
    }

    /// What has been typed into it.
    public String Content => _text;

    /// Everything, every time, and nothing behind it.
    ///
    /// The platform does not erase a `CustomControl` before this runs: the
    /// whole client area is the control's, and whatever it does not draw shows
    /// what the off-screen buffer held. Hence `Clear` on the first line, which
    /// is what nearly every one of these begins with.
    protected override void OnPaint(PaintEventArgs args)
    {
        var canvas = args.Graphics;
        canvas.Clear(BackColor);

        int inset = 4;
        // **The height comes from the font, not from the text.** Measuring
        // `""` answers a height of zero, so a field taking its line height from
        // its own contents has no line and no caret until something is typed
        // into it. Measuring a letter with an ascender and a descender is what
        // every text control here has to do instead.
        int height = canvas.MeasureString("Ag", Font).Height;
        int line = (ClientBounds.Height - height) / 2;
        if (line < 0)
            line = 0;

        if (_pending >= 0)
            PlaceFromClick(canvas, inset);

        canvas.DrawString(_text, Font, ForeColor, inset, line);

        // The caret goes after whatever is behind it, so what has to be
        // measured is the text up to the position rather than all of it.
        var behind = canvas.MeasureString(_text.Substring(0u, _at), Font);
        Caret = Rectangle.Of(inset + behind.Width, line, 1, height);
    }

    /// The keys that mean a movement or a deletion.
    ///
    /// A typed character is not one of these. It arrives at `OnKeyPress`
    /// instead, after the platform has applied the keyboard layout and any dead
    /// keys, which is the only place it is a character rather than a key that
    /// happens to have a letter printed on it.
    protected override void OnKeyDown(KeyEventArgs args)
    {
        nuint size = _text.ByteLength();

        if (args.Key == Key.Left)
        {
            Move(Previous(_at));
        }
        else if (args.Key == Key.Right)
        {
            Move(_text.SkipCodePoint(_at));
        }
        else if (args.Key == Key.Home)
        {
            Move(0u);
        }
        else if (args.Key == Key.End)
        {
            Move(size);
        }
        else if (args.Key == Key.Backspace && _at > 0u)
        {
            nuint back = Previous(_at);
            _text = _text.Substring(0u, back) + _text.Substring(_at);
            Move(back);
        }
        else if (args.Key == Key.Delete && _at < size)
        {
            _text = _text.Substring(0u, _at) + _text.Substring(_text.SkipCodePoint(_at));
            Invalidate();
        }

        base.OnKeyDown(args);
    }

    /// One character, already through the keyboard layout.
    protected override void OnKeyPress(KeyPressEventArgs args)
    {
        // Backspace and Return arrive here as characters as well, and neither
        // is one to insert. Everything below a space is a control code, and
        // so is DEL.
        if (args.KeyChar >= ' ' && args.KeyChar != '\x7F')
        {
            // Qualified, because `Text` inside a `Control` is the control's
            // own caption property and not the module the function is in.
            String typed = Standard.Text.FromChar(args.KeyChar);
            _text = _text.Substring(0u, _at) + typed + _text.Substring(_at);
            Move(_at + typed.ByteLength());
        }
        base.OnKeyPress(args);
    }

    /// Clicking puts the caret where it was clicked.
    ///
    /// The peer has taken the focus by the time this runs, which is what lets a
    /// handler for a click assume the control it is on has the keyboard.
    protected override void OnMouseDown(MouseEventArgs args)
    {
        _pending = args.X;
        Invalidate();
        base.OnMouseDown(args);
    }

    void Move(nuint to)
    {
        _at = to;
        Invalidate();
    }

    /// The character boundary before `index`, found by walking forward from the
    /// start -- which is the only way a UTF-8 string offers, since a byte does
    /// not say whether the one before it began a character.
    nuint Previous(nuint index)
    {
        if (index == 0u)
            return 0u;
        nuint walk = 0u;
        nuint last = 0u;
        while (walk < index)
        {
            last = walk;
            walk = _text.SkipCodePoint(walk);
        }
        return last;
    }

    /// Turns a click into a position, now that there is something to measure
    /// with: the first boundary whose text is wider than the click.
    void PlaceFromClick(Graphics canvas, int inset)
    {
        nuint size = _text.ByteLength();
        nuint walk = 0u;
        _at = size;
        while (walk <= size)
        {
            var run = canvas.MeasureString(_text.Substring(0u, walk), Font);
            if (inset + run.Width >= _pending)
            {
                _at = walk;
                break;
            }
            if (walk == size)
                break;
            walk = _text.SkipCodePoint(walk);
        }
        _pending = -1;
    }
}

public class DrawnForm : Form
{
    Label _explain;
    Scratch _field;
    Label _note;

    public DrawnForm()
    {
        base(WindowBorder.Sizable);
        Text = "A drawn control";
        SetBounds(0, 0, 470, 180);

        _explain = new Label(this);
        _explain.SetBounds(12, 14, 440, 34);
        _explain.Text = "The box below is not a TextBox. It is a CustomControl: "
                     + "a window with nothing in it, painting its own text and caret.";

        _field = new Scratch(this);
        _field.SetBounds(12, 58, 430, 28);

        _note = new Label(this);
        _note.SetBounds(12, 98, 440, 34);
        _note.Text = "Type into it. Arrows, Home, End, Backspace and Delete work, "
                  + "and clicking puts the caret where you clicked.";
    }

    public Scratch Field => _field;

    /// What can be checked with nobody in front of it.
    public bool SelfTest()
    {
        bool ok = true;

        _field.Focus();
        Application.DoEvents();
        if (!_field.Focused)
        {
            Console.WriteLine("FAIL: a CustomControl did not take the focus");
            ok = false;
        }

        // The caret is worked out while painting, so it means nothing until one
        // has happened.
        _field.Update();
        Application.DoEvents();
        if (_field.Caret.Height <= 0)
        {
            Console.WriteLine("FAIL: no caret after a paint");
            ok = false;
        }

        // Typed through the notification interface rather than through the
        // keyboard, which is the only half of this a machine can drive: what it
        // proves is the control's own editing, not the platform's routing.
        _field.OnPlatformKeyPress('a');
        _field.OnPlatformKeyPress('b');
        _field.OnPlatformKeyPress('c');
        if (_field.Content != "abc")
        {
            Console.WriteLine("FAIL: typing gave '" + _field.Content + "', not 'abc'");
            ok = false;
        }

        _field.OnPlatformKeyDown(Key.Left, ModifierKeys.None);
        _field.OnPlatformKeyDown(Key.Backspace, ModifierKeys.None);
        if (_field.Content != "ac")
        {
            Console.WriteLine("FAIL: left then backspace gave '" + _field.Content
                              + "', not 'ac'");
            ok = false;
        }

        // A caret that is moved has to reach the platform, and the peer answers
        // an unchanged one with nothing at all -- so the check is that it moved
        // rather than that it was set.
        _field.Update();
        Application.DoEvents();
        int atEnd = _field.Caret.X;
        _field.OnPlatformKeyDown(Key.Home, ModifierKeys.None);
        _field.Update();
        Application.DoEvents();
        if (_field.Caret.X >= atEnd)
        {
            Console.WriteLine("FAIL: Home did not move the caret back");
            ok = false;
        }

        // A letter past ASCII and one past U+FFFF, which Windows sends as two
        // `WM_CHAR`s. On Windows they go through the window procedure, so the
        // backend's joining is what is tested.
#if WINDOWS
        HWND window = (HWND)(void*)_field.Handle;
        SendMessageW(window, WmChar, 0x0444u, 0);
        SendMessageW(window, WmChar, 0xD83Du, 0);
        SendMessageW(window, WmChar, 0xDE00u, 0);
#else
        _field.OnPlatformKeyPress('ф');
        _field.OnPlatformKeyPress('\U0001F600');
#endif
        if (_field.Content != "ф😀ac")
        {
            Console.WriteLine("FAIL: typing past ASCII gave '" + _field.Content
                              + "', not 'ф😀ac'");
            ok = false;
        }

        if (ok)
        {
            Console.WriteLine("  focus, caret, typing, movement, deletion and Unicode");
        }
        return ok;
    }
}

int Main()
{
    Application.Initialize();
    var form = new DrawnForm();

    bool testing = false;
    var arguments = Standard.Env.Arguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (testing)
    {
        Console.WriteLine("CustomControl -- self test");
        form.Show();
        for (int i = 0; i < 20; i++)
            Application.DoEvents();
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
