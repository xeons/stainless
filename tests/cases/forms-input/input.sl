// A control must still behave like the native control it is.
//
// Every peer in the Windows backend puts its own window procedure in front of a
// system control's and reports what it sees. Reporting is not consuming, and
// the distinction is invisible until something that needs a run of messages
// stops working: a drag inside an `EDIT` is `WM_MOUSEMOVE` repeated between the
// button going down and coming up, so a dispatch that answered the moves itself
// left clicking able to place the caret and dragging unable to select a thing.
// The wheel went the same way, and a multiline box could not be scrolled.
//
// The messages here are synthesised because nobody is present to perform them.
// An `EDIT` tracks a selection through its own state rather than through the
// real cursor, so sending it the three messages a drag is made of exercises the
// same path a person would.
module FormsInput;

import Standard.Console;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Win32;
import Win32.Handles;
import Win32.User32;

#if WINDOWS

public class InputForm : Form {
    public TextBox Entry;
    public TextBox Notes;

    public InputForm() {
        base(WindowBorder.Sizable);
        SetBounds(0, 0, 500, 300);

        Entry = new TextBox(this);
        Entry.SetBounds(12, 12, 400, 26);
        Entry.Text = "the quick brown fox jumps over the lazy dog";

        Notes = new TextBox(this, true);
        Notes.SetBounds(12, 50, 400, 120);
        Notes.Lines = ["one", "two", "three", "four", "five", "six",
                       "seven", "eight", "nine", "ten", "eleven", "twelve"];
    }
}

/// A point packed into an LPARAM, low word first.
long At(int x, int y) { return (long)((y << 16) | (x & 0xFFFF)); }

/// `MK_LBUTTON`: the left button is down while this message was sent.
const ulong LeftButtonHeld = 0x0001u;

/// `EM_GETFIRSTVISIBLELINE`, which is how a multiline edit reports how far it
/// has scrolled.
const uint EmGetFirstVisibleLine = 0x00CEu;

void Settle() { for (int i = 0; i < 8; i += 1) { Application.DoEvents(); } }

int Main() {
    Application.Initialize();
    var form = new InputForm();
    form.Show();
    Settle();

    HWND box = (HWND)(void*)form.Entry.Handle;
    SetFocus(box);
    Settle();

    // Press at the left edge, drag right in two steps, release.
    SendMessageW(box, WmLeftButtonDown, LeftButtonHeld, At(4, 10));
    Settle();
    SendMessageW(box, WmMouseMove, LeftButtonHeld, At(120, 10));
    Settle();
    SendMessageW(box, WmMouseMove, LeftButtonHeld, At(220, 10));
    Settle();
    SendMessageW(box, WmLeftButtonUp, 0u, At(220, 10));
    Settle();

    Console.WriteLine("drag selected "
        + Standard.Text.FromInteger((long)form.Entry.SelectionLength)
        + " of " + Standard.Text.FromInteger((long)form.Entry.Text.ByteLength())
        + " characters");

    // The wheel, which a multiline box scrolls for itself given the chance.
    HWND notes = (HWND)(void*)form.Notes.Handle;
    int before = (int)SendMessageW(notes, EmGetFirstVisibleLine, 0u, 0);
    SendMessageW(notes, WmMouseWheel, (ulong)((ulong)((-120) & 0xFFFF) << 16), At(40, 40));
    Settle();
    int after = (int)SendMessageW(notes, EmGetFirstVisibleLine, 0u, 0);

    Console.WriteLine("wheel scrolled the top line from "
        + Standard.Text.FromInteger((long)before) + " to "
        + Standard.Text.FromInteger((long)after));

    // And a key press, which goes the same route -- here so that a change
    // fixing the mouse by breaking the keyboard would still be caught.
    var typed = new TextBox(form);
    typed.SetBounds(12, 180, 400, 26);
    Settle();
    HWND third = (HWND)(void*)typed.Handle;
    SetFocus(third);
    SendMessageW(third, WmChar, (ulong)(uint)'h', 0);
    SendMessageW(third, WmChar, (ulong)(uint)'e', 0);
    SendMessageW(third, WmChar, (ulong)(uint)'l', 0);
    SendMessageW(third, WmChar, (ulong)(uint)'l', 0);
    SendMessageW(third, WmChar, (ulong)(uint)'o', 0);
    Settle();
    Console.WriteLine("typing reached the control: " + typed.Text);

    return 0;
}

#else

int Main() { return 0; }

#endif
