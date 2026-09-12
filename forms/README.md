# Forms

A GUI framework for Stainless: **the LCL's architecture, C#'s names.**

> An extreme rough draft, like everything else here. Windows only so far, and
> the control set is the standard tier and nothing above it.

```csharp
module Hello;

import Forms;
import Forms.Drawing;
import Forms.Platform;

public class MainForm : Form {
    Button greet;
    Label  said;

    public MainForm() {
        base(WindowBorder.Sizable);
        Text = "Hello";
        SetBounds(0, 0, 320, 140);

        greet = new Button(this);
        greet.Text = "Greet";
        greet.SetBounds(12, 12, 90, 26);
        greet.Click += this.OnGreet;

        said = new Label(this);
        said.SetBounds(12, 52, 280, 22);
    }

    void OnGreet(Control sender) { said.Text = "Hello from Stainless."; }
}

int Main() {
    Application.Initialize();
    var form = new MainForm();
    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
```

Those are real Windows controls — a real `BUTTON`, a real `STATIC` — in a real
window. No VM, no GC, no designer, no generated code.

---

## Where it comes from

Two parents, and the split between them is deliberate.

**The architecture is Lazarus's LCL.** Everything load-bearing is theirs: the
`TControl`/`TWinControl` split between controls that own a platform window and
controls that do not; the widgetset seam that lets one control hierarchy sit on
several platforms; the layout pass where docked controls take their bite out of
the client area in order and anchored ones stretch in what is left. Those are
the LCL's answers and they are still the right ones thirty years on.

**The names and the shapes are C#'s.** `TAlign` is `DockStyle`, `TAnchors` is
`AnchorStyles`, `TCanvas` is `Graphics`, `clBtnFace` is `SystemColors.Control`.
`TCustomEdit`/`TEdit` is `TextBoxBase`/`TextBox` — the LCL's "machinery versus
published version" pair *is* C#'s `XBase`/`X` pair, so that translation is one
for one. A published `OnClick: TNotifyEvent` becomes the two halves C# uses: a
public `event Click` anyone may subscribe to, and a `protected virtual OnClick`
that raises it and that a derived class overrides.

**What is not from either is the seam.** The LCL dispatches to a platform
through `class of TWSxxx` metaclasses with a registration pass — which needs
metaclasses, a `published` section, and something that runs before any control
is constructed. Stainless has none of those and does not want them. So a
control owns a **peer**: an object implementing an interface from
`Forms.Platform`, made by an `IWidgetSet` factory. Calls go down through
`IControlPeer`, notifications come up through `IControlNotify`, and neither side
names a type from the other's module.

That is the arrangement C# itself reached for the same problem — WPF's and
Avalonia's `I*Impl` — and it pays for itself three times:

| | LCL | here |
|---|---|---|
| per-window state | side table keyed by `HWND`, a global atom, a `GetProp` per message | fields on the peer |
| handle teardown | `DestroyHandle`, called by hand | a destructor, run by ARC |
| what a control needs | `TWSWinControl`: 40 class methods, most ignored | the capability interfaces it implements |

---

## The layout

```
src/Drawing.sl              Color, Point, Size, Rectangle, Font, Pen, Brush,
                            Graphics, SystemColors          (lcl/graphics.pp)
src/Platform.sl             the seam: peers, notifications, IWidgetSet
                                                            (lcl/widgetset/ws*.pp)
src/Control.sl              Control: bounds, layout, appearance, events
src/Container.sl            GraphicControl, WindowedControl, the layout pass
                                                            (lcl/controls.pp)
src/Form.sl                 Form, Screen                    (lcl/forms.pp)
src/Application.sl          Application                     (lcl/forms.pp)
src/Controls/*.sl           Button, CheckBox, RadioButton, Label, TextBox,
                            ListBox, ComboBox, Panel, GroupBox, ScrollBar
                                                            (lcl/stdctrls.pp)
src/Platform/Select.sl      which backend this build links  (lcl/interfaces/)
src/Platform/Win32/*.sl     the Windows backend       (lcl/interfaces/win32/)
```

Roughly 4,900 lines against the LCL's 276,000 — which is the scope difference,
not a compression ratio. See *What is not here* below.

---

## Building it

```
stainless build forms                      # the library, from stainless.json
stainless run samples/forms/demo.sl forms/src bindings/win32/api \
    bindings/win32/Win32.sl -l user32 -l gdi32
```

The demo takes `--selftest`, which builds the same form, pumps the message
queue, and checks thirteen things against the real controls — docking,
anchoring, native handles, text round-tripping through Windows, a click reaching
its handler — then quits. It is what makes a GUI something a build can run.

---

## Decisions worth knowing about

**A `Graphics` carries no state.** `TCanvas` has a current `Pen`, `Brush` and
`Font`, so any routine that draws must save and restore three things or corrupt
its caller — every LCL painting bug of the shape "the colour was wrong the
second time" is that. Here each call takes what it draws with.

**A `Font` is immutable.** `TFont` is a `TPersistent` that controls share and
mutate, with an `OnChange` to repaint whoever was listening. Here a control that
wants a bigger font is *assigned* a new one, so it already knows, and nothing
needs a change notification. Sharing one `Font` across a hundred controls still
costs one `HFONT`, which is what the LCL's sharing was for.

**A font's colour belongs to the control.** `TFont.Color` means a font cannot be
shared between two controls of different colours. C# puts it on the control as
`ForeColor`, and that is plainly the better of the two.

**Inheritance needs no flag.** `ParentFont`, `ParentColor` and `ParentShowHint`
are three booleans saying "nothing was set here" — which a null field already
says. So `Font`, `ForeColor` and `BackColor` walk up to the parent when unset,
and there is no flag to get out of step.

**A parent is chosen once.** Assigning `TControl.Parent` moves a control between
forms; on Windows that means destroying and re-creating the window for several
control classes, so the thing that looks like an assignment is a rebuild. A
control is given its parent when it is made.

**A control's `Bounds` is its window rectangle, not its client area.** Windows
reports a resize as the new *client* extent, which for anything with a frame --
every `EDIT` and `LISTBOX` here carries `WS_EX_CLIENTEDGE` -- is 4 pixels
smaller than the control. Feeding that back in made each resize shrink every
bordered control a little more, compounding, while the borderless button beside
it stayed exactly put. So the peer asks for the rectangle rather than taking the
one the message carried. `Bounds` is the window, `ClientBounds` is the room
inside it, and a `Form`'s `Bounds` is in screen coordinates, as in C#.

**`ClientBounds` starts at the origin; `ClientOrigin` says where it begins.**
Keeping the two apart is what makes a control placed at (0, 0) land in the same
place whether or not its parent has a frame. Only a group box has a non-zero
origin, and without it a control placed at the origin is drawn across the
caption -- while a *docked* one lands correctly, so the two disagreed.

**Reporting a message is not consuming it.** Each peer puts its own window
procedure in front of a system control's, and everything it reports it then
hands on. That is easy to get wrong in one direction only: a drag inside a text
box is a run of `WM_MOUSEMOVE` between the button going down and coming up, so
answering the moves left clicking able to place the caret and dragging unable to
select anything -- and the wheel went the same way, taking a multiline box's
scrolling with it. `tests/cases/forms-input` synthesises both and checks what
the control did.

**A group box erases its own interior, alone among the subclassed controls.**
`BS_GROUPBOX` paints a frame and a caption and nothing else, expecting whatever
is behind it to show through -- and nothing is, because the form carries
`WS_CLIPCHILDREN` and so never paints under a child. `WS_CLIPCHILDREN` has to
stay, since dropping it is what makes every other control flicker on resize, so
the group box fills its own interior instead.

**An input field is the window colour, not its parent's.** `BackColor` is
inherited from the parent, which is right for a label or a panel and wrong for
anything you type into: pushing the form's grey at a text box overrides what
Windows would have drawn. `DefaultBackColor` is virtual for that reason, and
`TextBoxBase` and `ListControl` override it to `SystemColors.Window` -- which is
what C# does, and why it has `TextBoxBase.DefaultBackColor` at all.

**A form erases its own background.** A window class registered with a null
background brush is erased by nothing, so swallowing `WM_ERASEBKGND` on the
promise that the paint handler would do it left the client area showing whatever
memory held -- and left every region a moved control vacated showing the old
picture. The default paint handler raises an event nobody has subscribed to, so
there was no such promise to keep.

**An empty event raises nothing** — that is the language's choice, not this
library's, and it removes `?.Invoke` from every raise site.

**Forms are kept alive by the `Application`.** Under ARC a form built in a local
and shown would be destroyed when the function returned: the platform holds a
window, but nothing would hold the object that answers its messages. `Show`
registers it and closing unregisters it, and the last one out stops the loop.

---

## What is not here

Deliberate omissions, so nobody has to wonder whether they were forgotten:

- **Other platforms.** The seam is designed for several and only Win32 is
  written. GTK is next and is mostly an adapter — `bindings/gtk/Widgets.sl`
  already wraps twenty widgets.
- **Form files.** No `.lfm`, no designer, no component streaming. Forms are
  built in code. The control tree is shaped so a reflection-based loader stays
  possible later.
- **The common controls tier.** No `TreeView`, `ListView`, `TabControl`,
  `ToolBar`, `StatusBar`, `TrackBar`, `ProgressBar`, menus or image lists.
- **Grids and DB controls**, which are half of `lcl/` by line count.
- **Docking, drag and drop, actions, hints, accessibility, bi-directional text,
  and per-monitor DPI.** Each is a real feature of the LCL and each is its own
  piece of work.
- **`TStrings`.** `String[]` and `List<String>` do the job.
- **`BorderSpacing` and `ChildSizing`.** The LCL's finer layout controls; only
  `Dock` and `Anchors` are here.
- **Bitmaps and image loading.** `Graphics` draws shapes and text.
- **A GDI object cache.** Every pen and brush is made and deleted per call,
  which cannot leak and is slower than it needs to be.

## Known rough edges

- **`Application` and `WidgetSet` hold static state and warn (SL0377).** A GUI
  toolkit is *thread-affine* — one thread owns the widgets — which is true of
  WinForms, WPF, GTK and Cocoa alike. Stainless can say `threadsafe`, which
  would be a lie here, and cannot yet say "one thread only". The warning is
  accurate and is left standing rather than silenced untruthfully.
- **A combo box's editability and a text box's multiline-ness are fixed at
  construction**, because on Windows they are creation-time style bits.
- **`InvalidateRegion` repaints the whole control**, since no peer interface
  takes a region yet.
- **Not DPI aware.** On a scaled display Windows renders the window at 96 DPI
  and scales the result, so text is soft. Per-monitor awareness is a manifest
  setting and a layout that scales with it, and neither is here.
- **`SelectAll` uses a large sentinel length** rather than asking for the text's
  length in characters.
