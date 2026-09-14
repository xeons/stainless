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

/// A one-line text field, drawn rather than delegated.
///
/// **The caret is a byte offset**, because that is what a `String` position is
/// here: the text is UTF-8 and nothing counts characters, so moving left and
/// right means finding the next and previous character *boundary* rather than
/// adding one. `NextCodePoint` does the first, and `Previous` below does the
/// second the only way a UTF-8 string allows -- by walking from the start.
public class Scratch : CustomControl {
    String text;
    nuint  at;

    /// Where a click landed and has not been turned into a position yet, or -1
    /// for none. Answered during the next paint, because turning an x into a
    /// position means measuring text and a `Graphics` to measure with exists
    /// only while painting.
    int pending;

    public Scratch(WindowedControl parent) {
        base(parent);
        text = "";
        at = 0u;
        pending = -1;
        Border = ControlBorder.Sunken;
        BackColor = Colors.White;
    }

    /// What has been typed into it.
    public String Content => text;

    /// Everything, every time, and nothing behind it.
    ///
    /// The platform does not erase a `CustomControl` before this runs: the
    /// whole client area is the control's, and whatever it does not draw shows
    /// what the off-screen buffer held. Hence `Clear` on the first line, which
    /// is what nearly every one of these begins with.
    protected override void OnPaint(PaintEventArgs args) {
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
        if (line < 0) { line = 0; }

        if (pending >= 0) { PlaceFromClick(canvas, inset); }

        canvas.DrawString(text, Font, ForeColor, inset, line);

        // The caret goes after whatever is behind it, so what has to be
        // measured is the text up to the position rather than all of it.
        var behind = canvas.MeasureString(text.Substring(0u, at), Font);
        Caret = Rectangle.Of(inset + behind.Width, line, 1, height);
    }

    /// The keys that mean a movement or a deletion.
    ///
    /// A typed character is not one of these. It arrives at `OnKeyPress`
    /// instead, after the platform has applied the keyboard layout and any dead
    /// keys, which is the only place it is a character rather than a key that
    /// happens to have a letter printed on it.
    protected override void OnKeyDown(KeyEventArgs args) {
        nuint size = text.ByteLength();

        if (args.Key == Key.Left) { Move(Previous(at)); }
        else if (args.Key == Key.Right) { Move(text.NextCodePoint(at)); }
        else if (args.Key == Key.Home) { Move(0u); }
        else if (args.Key == Key.End)  { Move(size); }
        else if (args.Key == Key.Backspace && at > 0u) {
            nuint back = Previous(at);
            text = text.Substring(0u, back) + text.Substring(at);
            Move(back);
        }
        else if (args.Key == Key.Delete && at < size) {
            text = text.Substring(0u, at) + text.Substring(text.NextCodePoint(at));
            Invalidate();
        }

        base.OnKeyDown(args);
    }

    /// One character, already through the keyboard layout.
    protected override void OnKeyPress(KeyPressEventArgs args) {
        // Backspace and Return arrive here as characters as well, and neither
        // is one to insert. Everything below a space is a control code.
        if (args.KeyChar >= ' ') {
            // Qualified, because `Text` inside a `Control` is the control's
            // own caption property and not the module the function is in.
            String typed = Standard.Text.FromChar((char32)args.KeyChar);
            text = text.Substring(0u, at) + typed + text.Substring(at);
            Move(at + typed.ByteLength());
        }
        base.OnKeyPress(args);
    }

    /// Clicking puts the caret where it was clicked.
    ///
    /// The peer has taken the focus by the time this runs, which is what lets a
    /// handler for a click assume the control it is on has the keyboard.
    protected override void OnMouseDown(MouseEventArgs args) {
        pending = args.X;
        Invalidate();
        base.OnMouseDown(args);
    }

    void Move(nuint to) {
        at = to;
        Invalidate();
    }

    /// The character boundary before `index`, found by walking forward from the
    /// start -- which is the only way a UTF-8 string offers, since a byte does
    /// not say whether the one before it began a character.
    nuint Previous(nuint index) {
        if (index == 0u) { return 0u; }
        nuint walk = 0u;
        nuint last = 0u;
        while (walk < index) {
            last = walk;
            walk = text.NextCodePoint(walk);
        }
        return last;
    }

    /// Turns a click into a position, now that there is something to measure
    /// with: the first boundary whose text is wider than the click.
    void PlaceFromClick(Graphics canvas, int inset) {
        nuint size = text.ByteLength();
        nuint walk = 0u;
        at = size;
        while (walk <= size) {
            var run = canvas.MeasureString(text.Substring(0u, walk), Font);
            if (inset + run.Width >= pending) { at = walk; break; }
            if (walk == size) { break; }
            walk = text.NextCodePoint(walk);
        }
        pending = -1;
    }
}

public class DrawnForm : Form {
    Label   explain;
    Scratch field;
    Label   note;

    public DrawnForm() {
        base(WindowBorder.Sizable);
        Text = "A drawn control";
        SetBounds(0, 0, 470, 180);

        explain = new Label(this);
        explain.SetBounds(12, 14, 440, 34);
        explain.Text = "The box below is not a TextBox. It is a CustomControl: "
                     + "a window with nothing in it, painting its own text and caret.";

        field = new Scratch(this);
        field.SetBounds(12, 58, 430, 28);

        note = new Label(this);
        note.SetBounds(12, 98, 440, 34);
        note.Text = "Type into it. Arrows, Home, End, Backspace and Delete work, "
                  + "and clicking puts the caret where you clicked.";
    }

    public Scratch Field => field;

    /// What can be checked with nobody in front of it.
    public bool SelfTest() {
        bool ok = true;

        field.Focus();
        Application.DoEvents();
        if (!field.Focused) {
            Console.WriteLine("FAIL: a CustomControl did not take the focus");
            ok = false;
        }

        // The caret is worked out while painting, so it means nothing until one
        // has happened.
        field.Update();
        Application.DoEvents();
        if (field.Caret.Height <= 0) {
            Console.WriteLine("FAIL: no caret after a paint");
            ok = false;
        }

        // Typed through the notification interface rather than through the
        // keyboard, which is the only half of this a machine can drive: what it
        // proves is the control's own editing, not the platform's routing.
        field.OnPlatformKeyPress('a');
        field.OnPlatformKeyPress('b');
        field.OnPlatformKeyPress('c');
        if (field.Content != "abc") {
            Console.WriteLine("FAIL: typing gave '" + field.Content + "', not 'abc'");
            ok = false;
        }

        field.OnPlatformKeyDown(Key.Left, ModifierKeys.None);
        field.OnPlatformKeyDown(Key.Backspace, ModifierKeys.None);
        if (field.Content != "ac") {
            Console.WriteLine("FAIL: left then backspace gave '" + field.Content
                              + "', not 'ac'");
            ok = false;
        }

        // A caret that is moved has to reach the platform, and the peer answers
        // an unchanged one with nothing at all -- so the check is that it moved
        // rather than that it was set.
        field.Update();
        Application.DoEvents();
        int atEnd = field.Caret.X;
        field.OnPlatformKeyDown(Key.Home, ModifierKeys.None);
        field.Update();
        Application.DoEvents();
        if (field.Caret.X >= atEnd) {
            Console.WriteLine("FAIL: Home did not move the caret back");
            ok = false;
        }

        if (ok) {
            Console.WriteLine("  focus, caret, typing, movement and deletion");
        }
        return ok;
    }
}

int Main() {
    Application.Initialize();
    var form = new DrawnForm();

    bool testing = false;
    var arguments = Standard.Env.Arguments();
    for (nuint i = 0u; i < arguments.Length; i += 1u) {
        if (arguments[i] == "--selftest") { testing = true; }
    }

    if (testing) {
        Console.WriteLine("CustomControl -- self test");
        form.Show();
        for (int i = 0; i < 20; i += 1) { Application.DoEvents(); }
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
