# Forms

A GUI framework for Stainless: **the LCL's architecture, C#'s names.**

> An extreme rough draft, like everything else here. Two backends now --
> Win32 and GTK 3 -- and the control set is everything the seam declares.

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

Those are real platform controls — a real `BUTTON` and `STATIC` on Windows, a
real `GtkButton` and `GtkLabel` on Linux — in a real window. No VM, no GC, no
designer, no generated code, and **the source above is the same source on
both**.

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
src/Controls/Buttons.sl     Button, CheckBox, RadioButton, ToggleButton,
                            SpeedButton                     (lcl/buttons.pp)
src/Controls/Text.sl        Label, TextBox                  (lcl/stdctrls.pp)
src/Controls/Lists.sl       ListBox, ComboBox
src/Controls/Containers.sl  Panel, GroupBox, ScrollBar, CustomControl,
                            Notebook, NotebookPage
src/Clipboard.sl            Clipboard                        (lcl/clipbrd.pp)
src/Controls/Menus.sl       MainMenu, PopupMenu, MenuItem      (lcl/menus.pp)
src/Controls/Common.sl      ToolBar, StatusBar, ProgressBar, TrackBar,
                            TabControl, TreeView, ListView, ImageList,
                            CoolBar, CoolBand            (lcl/comctrls.pp)
src/Controls/Drawn.sl       PaintBox, Shape, Bevel, Splitter (lcl/extctrls.pp)
src/Controls/Dialogs.sl     OpenDialog, SaveDialog, FolderDialog, ColorDialog,
                            FontDialog, Timer      (lcl/dialogs.pp, customtimer)
src/Controls/Groups.sl      RadioGroup, CheckGroup, LabeledEdit, Image,
                            SpinEdit, CheckListBox, HeaderControl,
                            ButtonPanel                 (lcl/buttonpanel.pas)
src/Platform/Select.sl      which backend this build links  (lcl/interfaces/)
src/Platform/Win32/*.sl     the Windows backend       (lcl/interfaces/win32/)
src/Platform/Gtk/*.sl       the GTK 3 backend           (lcl/interfaces/gtk3/)
```

Roughly 8,200 lines of portable code against the LCL's 276,000 — which is the
scope difference, not a compression ratio — plus about 4,500 per backend. See
*What is not here* below.

---

## Building it

On Windows:

```
stainless run samples/forms/demo.sl   forms/src bindings/win32/api \
    bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
stainless run samples/forms/common.sl forms/src bindings/win32/api \
    bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
```

or `.\samples\forms\build.ps1`, which builds every sample in that directory
into `samples/forms/build` (git-ignored), writes the visual-styles manifest each
one needs, and takes `-Test` to run every self-check and `-Run <name>` to open a
window.

On Linux, the same sources with the other bindings and the other libraries:

```
stainless run samples/forms/demo.sl forms/src bindings/gtk \
    -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
    -l :libglib-2.0.so.0 -l :libcairo.so.2 -l :libgdk_pixbuf-2.0.so.0
```

**Nothing in the sample changes between those two lines**, which is the whole
claim the second backend exists to test. `forms/src/Platform/Select.sl` is
where that choice is made, and it is a four-line `#if`.

Every sample takes `--selftest`, which builds the same window, pumps the
message queue, checks what can be checked without a person in front of it, and
quits. `demo` makes 21 such checks, `common` 43 and `buttons` 51 — docking,
anchoring, native handles, text round-tripping through the platform, a click
reaching its handler, a menu item resolving from its id, a cool bar's bands
wrapping onto a second row when the window narrows. That is what makes a GUI
something a build can run, and it is how every bug listed under *Decisions
worth knowing about* was found.

**And a self-test is not a screenshot, which is the lesson this library keeps
being taught.** `buttons` passed all 51 of its checks on GTK while its three
speed buttons and its button strip's bevel were drawn nowhere at all — because
a windowless control is drawn by its parent, and no GTK container but
`CustomControl` was passing the cairo context down. The same fix made the
`Shape`, the `Bevel` and the `PaintBox` in `common` appear, which had been
invisible on GTK since they were written. Take the screenshot.

**Both suites pass on both backends**, and the last exception is worth keeping
for how it was found. `common`'s "a tree node reads back its text" passed on
GTK and failed on Win32, which turned "the tree control is broken" into "the
*Windows* side is broken" -- a much smaller question. The answer was one
truncated literal: `TVI_ROOT` is a negative number that sign-extends to
`0xFFFFFFFFFFFF0000` on a 64-bit machine, and the binding had it as a 32-bit
`0xFFFF0000u`. Every insert was handed a parent handle naming nothing, so the
Win32 tree view had never actually held an item -- the other tree checks passed
because they read the peer's own mirror list rather than the control.

Two end-to-end cases go further, driving real messages at the controls:
`tests/cases/forms-input` synthesises a mouse drag and a wheel turn and checks
what the control did with them; `tests/cases/forms-menus` sends `WM_COMMAND` for
a menu item, a nested item, a heading and a toolbar button, and checks which
handler ran.

### Taking the screenshot

On Linux there is no window manager on the test box, so the window is opened on
a virtual screen and the screen is captured:

```sh
Xvfb :9 -screen 0 1024x768x24 &
DISPLAY=:9 ./buttons --page 1 &
sleep 3
DISPLAY=:9 import -window root shot.png          # ImageMagick
```

On Windows, `CopyFromScreen` answers black over a disconnected session, so ask
the window to draw itself instead. `PrintWindow` with `PW_RENDERFULLCONTENT`
works with no visible desktop at all:

```powershell
$p = Start-Process .\build\buttons.exe -PassThru; Start-Sleep 3; $p.Refresh()
# GetWindowRect for the size, then:
#   PrintWindow($p.MainWindowHandle, $graphics.GetHdc(), 2)
```

Give it a second between the two: a toolbar renders its buttons lazily, and a
capture taken too early catches half of them.

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

**A composite is a container that builds its own children.** `RadioGroup`,
`CheckGroup` and `LabeledEdit` are not widgets: each is a `GroupBox` or a
`Panel` that makes what goes in it and lays it out. Two consequences worth
knowing. A `RadioGroup` reads its selection *from the buttons* rather than from
a field, because the platform ticks and unticks them itself and a field would be
a second answer to a settled question. And an overridden `OnResize` must do
nothing until the constructor has finished: the base constructor resizes, and
the override then runs before this class's own fields exist — the same trap C#
has with a virtual call from a base constructor.

**Ticking a radio button clears its group, and Windows does not do that for
you.** `BS_AUTORADIOBUTTON` clears the others when the *user* clicks one;
`BM_SETCHECK` clears nothing, so a program that ticked one by hand ended up with
two ticked and a group whose selected index was whichever came first. C# does
the same clearing in `RadioButton.Checked`.

**A windowless control is drawn in a layer, not in its parent's coordinates.**
A `GraphicControl` has no window, so its parent draws it -- and the obvious way
to do that, handing over the parent's `Graphics`, means a control drawing at
(0, 0) draws at the *form's* corner and may draw over its siblings. So the
parent pushes a layer first: `SaveDC`, `IntersectClipRect`,
`OffsetViewportOrgEx`, and one `RestoreDC` that puts both back together. A
`PaintBox` may then draw from its own origin without knowing where it sits.

**And its parent must ask it to.** Only a form handled `WM_PAINT` at first, so a
`PaintBox` on a tab page was simply never drawn -- no error, no warning, an
empty rectangle. Every container now draws the windowless children on it, after
letting the platform control paint itself.

**And on GTK, its parent is the only thing that ever holds the brush.** A
`GraphicControl` has no widget, so the one cairo context it could be drawn with
is the one its parent's `draw` handler is given. Only `CustomControl` connected
that signal, so a `PaintBox` on a `Panel`, a `Bevel` on a tab page and a
`SpeedButton` anywhere were laid out, hit-tested, clickable and invisible --
for months, with every self-test passing. `GtkContainerPeer.ReportPaints` is
now called by the panel, the group box and the window, and answers false so
that GTK still draws the real children over what the program painted.

**A transparent child's `WM_ERASEBKGND` is not the parent's own.** A
`TBSTYLE_FLAT` toolbar draws no background: it offsets its DC into the parent's
coordinates and forwards the erase, meaning "paint yours here". A `Panel` is a
`STATIC`, whose class brush is null, and a `CustomControl` refuses its own
erase on purpose because it double-buffers — so both handed the toolbar back a
DC exactly as they found it, which is black, and hovering a button repainted
more of it black. The two looked like different bugs and were one. Every peer
now tells the two messages apart with `WindowFromDC` and fills the DC's clip
box, which is the only rectangle that is right whatever origin the child chose.

**The mouse reaches a windowless control by hit-testing.** The pointer never
crosses a window boundary for a control that has no window, so entering and
leaving it are the parent's to notice and report, and a drag is the parent
holding the platform capture on the child's behalf. That is what a `Splitter`
needs and what nothing else does.

**A button strip's order is the one thing that is not portable.** Windows puts
OK before Cancel and the GNOME guidelines put Cancel before OK, and both put
the affirmative button on the right. `ButtonPanel` is the only thing in the
portable tier that reads `IWidgetSet.Name`, because what differs is a
convention rather than a capability and there is nothing in the seam to ask
instead. It is asked once, at construction, so a program that chose its backend
at run time gets the right answer too.

**A menu is described first and built second.** Every item is an ordinary
object until a `MainMenu` is given to a form or a `PopupMenu` is shown; only
then does a platform menu exist. On Windows a submenu must exist before the item
that opens it can be created -- the item *is* the submenu's handle -- so building
as you go means either adding bottom-up or patching afterwards, and `TMenuItem`
does the second with a rebuild on every insertion. Describing first removes the
ordering problem instead of managing it.

**A menu command and a control's click are the same message.** `WM_COMMAND`
with `lParam` null is a menu; with a window handle it is a control. The id is
resolved by asking the window's own menu tree, recursively -- so there is no
table of command ids anywhere, and nothing to remember to remove from one. A
*heading* is skipped in that search: Windows sends no command for one, and
matching it would run a handler nothing could have raised.

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

## What is ported, and what is left

The LCL is 276,000 lines across 969 files. This is about 7,600, so the question
"what is missing" has a long answer — and an unhelpful one unless it is ordered.
What follows is every LCL unit that a program would notice the absence of,
grouped by how much work it is rather than by where it lives.

### Ported

| Here | From |
|---|---|
| `Control`, `GraphicControl`, `WindowedControl`, docking, anchors | `controls.pp` |
| `Form`, `Application`, `Screen` | `forms.pp` |
| `Button`, `CheckBox`, `RadioButton`, `ToggleButton`, `Label`, `TextBox`, `ListBox`, `ComboBox`, `Panel`, `GroupBox`, `ScrollBar` | `stdctrls.pp` |
| `MainMenu`, `PopupMenu`, `MenuItem` | `menus.pp` |
| `ToolBar`, `StatusBar`, `ProgressBar`, `TrackBar`, `TabControl`, `TreeView`, `ListView`, `CoolBar` | `comctrls.pp` |
| `ImageList` | `imglist.pp` |
| `PaintBox`, `Shape`, `Bevel`, `Splitter`, `Notebook` | `extctrls.pp` |
| `CustomControl` | `customcontrol` in `controls.pp` |
| `Clipboard`, text only | `clipbrd.pp` |
| `OpenDialog`, `SaveDialog`, `FolderDialog`, `ColorDialog`, `FontDialog` | `dialogs.pp` |
| `Timer` | `customtimer.pas` |
| `RadioGroup`, `CheckGroup`, `LabeledEdit`, `Image` | `extctrls.pp` |
| `SpinEdit` | `spin.pp` |
| `CheckListBox` | `checklst.pas` |
| `HeaderControl` | `comctrls.pp` |
| `SpeedButton`, and `BitBtn` folded into `Button.Image` | `buttons.pp` |
| `ButtonPanel` | `buttonpanel.pas` |
| `Color`, `Point`, `Size`, `Rectangle`, `Font`, `Pen`, `Brush`, `Graphics`, `Bitmap` | `graphics.pp` |
| the widgetset seam | `widgetset/ws*.pp`, `interfaces/win32` |

### Next, and each a day rather than a week

Every one of these is either a composite of what already exists or a call that
is already bound.

- **`TTabControl`** — the LCL distinguishes a tabbed control that owns pages
  from one that only shows tabs. Only the first is here; `Notebook` is now the
  other half of that family, the one with pages and no tabs at all.
- **`ScrollBox`** (`forms.pp`) — a container with the platform's own scroll
  bars, which is a different thing from the standalone `ScrollBar` that is
  here. Both backends register one already.
- **`UpDown`, `ColorButton`, `PairSplitter`** — each is one widget the GTK 3
  widgetset registers and the Win32 side has bound, and each is an afternoon.
- **`FloatSpinEdit`** — `SpinEdit` is integers only, and `GtkSpinButton` and
  `UDM_SETRANGE32` both already carry doubles.

### Worth having, and a week each

- **`DateTimePicker`, `Calendar`** (`calendar.pp`) — `comctl32` has both, and
  so does GTK; the work is a date type this library does not have yet.
- **`MaskEdit`** (`maskedit.pp`) and the `editbtn.pas` family — `FileNameEdit`,
  `DirectoryEdit`, `DateEdit`: an edit with a button that opens a dialog, which
  is why the dialogs come first.
- **`ColorBox`, `ColorListBox`** (`colorbox.pas`) — owner-drawn lists.
- **Owner drawing** across list, combo, menu and button. One mechanism
  (`WM_DRAWITEM`, `WM_MEASUREITEM`) that half a dozen controls want, so it is
  worth doing once and properly rather than per control.
- **Accelerators.** `&O` underlines a letter and works while a menu is open, and
  `IsDialogMessage` now handles Tab, the arrows, Enter and Escape; `Ctrl+O`
  still needs an accelerator table and `TranslateAccelerator` in the loop.
- **`TrayIcon`** (`extctrls.pp`) — needs `Shell_NotifyIconW` bound.

### Large, and each its own project

- **`Grids`** (`grids.pas`, 13,957 lines — the largest unit in the LCL).
  `TStringGrid` and `TDrawGrid` are drawn from nothing: Windows has no grid, so
  this is scrolling, selection, in-place editing and painting, all by hand. It
  is the single biggest thing missing and the one most often wanted.
- **The rest of `Graphics`** — `TBitmap` in formats other than `.bmp`,
  `TPicture`, `TIcon`, `TRegion`, drawing *onto* a bitmap, and pixel access
  (`intfgraphics.pas`, 6,698 lines). PNG on Windows means binding WIC or GDI+.
- **Printing** (`printers.pas`, `postscriptcanvas.pas`) — a `Canvas` that is a
  printer, plus the dialogs.
- **Form streaming** (`lresources.pp`, `propertystorage.pas`) — the `.lfm` tier.
  Possible here through `Standard.Reflection`, and the control tree is shaped
  so it stays possible, but it is a parser, a type registry and a property
  writer.
- **Actions** (`actnlist.pas`, `stdactns.pas`) — one command behind a menu item,
  a toolbar button and a shortcut, with enabled state shared.
- **Docking** (`ldocktree.pas`, 2,192 lines) and drag-and-drop.
- **Themes** (`themes.pas`, `tmschema.pas`) — drawing *with* the theme rather
  than letting each control do it, which is what any owner-drawn control needs
  to look native.
- **DB controls** (`dbctrls.pp`, `dbgrids.pas`) — these want a dataset
  abstraction, and Stainless has no database layer at all, so the dependency
  comes first.
- **Accessibility** (`TLazAccessibleObject`) — UI Automation on Windows.

### Not planned

- **`customdrawn*`** (five units, 10,000 lines) — a widgetset that draws every
  control itself rather than using the platform's. The opposite of what the
  peer design is for.
- **`lcltype.pp`, `lmessages.pp`, `lclproc.pas`, `lclmemmanager.pas`** —
  constants, message records and utility code that exist because Object Pascal
  needed them. `bindings/win32` and the standard library are the answer here.
- **`TStrings` and the `TCollection` families** — `TListItems`, `TListColumns`,
  `TStatusPanels`, `TCoolBands` are all there because Object Pascal has no
  generic list. `List<T>` is one.
- **`interfacebase.pp`, `lclintf.pas`** — the LCL's own seam, replaced by
  `Forms.Platform`.

### The GTK backend, and what it found

**The seam held**, and it is the entry this list existed for: a seam with one
implementation has quietly stopped being a seam, and the only way to find out
whether `IControlPeer` described a control or described an `HWND` was to write
the other side of it.

This entry said **done** for some months, and it was wrong in a way worth
keeping on the page. Both samples passed every check of their self-tests on
GTK -- and a control inside a container was one pixel wide, a tab page was
empty, and nothing a program drew reached the screen at all. None of that is
something a self-test asks. `SelfTest` reads back what it set: a caption, an
index, a count. Whether any of it was *drawn* is a question only a person
looking at the window, or a screenshot, can answer, and nobody had looked.

What looking found is below, under *What running it found*. The lesson is the
general one: a widgetset's tests prove the model, and only a picture proves the
view.

**Not one interface changed.** Thirty of them, `IWidgetSet`'s forty-five
methods, and the answer came back that the seam is about controls. The
sharpest evidence is `Lists.sl`: a list box, a checked list, a column header, a
tree and a details list are five window classes on Windows and five interfaces
in the seam, and GTK answers all five with one `GtkTreeView` over a model.
Neither backend had to know.

What the exercise cost, and it is worth knowing before the next backend:

- **Absolute placement.** Every GTK container computes a layout and `forms/`
  has computed one already, so every container peer's children go into a
  `GtkFixed`. A size request is a *minimum* there, so a control whose content
  wants more room than the layout allowed overflows rather than clips; a label
  ellipsizes to cover it, and the general case is open.
- **A resize is a request.** `MoveWindow` has resized the window by the time it
  returns and `gtk_window_resize` has only asked, so the events already in
  flight describe the size before the request. The window peer drops those
  echoes until one matches; Win32 needed nothing.
- **A bare member read inside a lambda is captured by value** (spec §2.15), so
  the guard that stops a program-driven change being reported back as the
  user's has to name its receiver -- `this.busy`, or a method that reads it.
  Written bare it compiles, runs, and guards nothing: a checked menu item set
  from its own handler recursed until the stack ran out. The compiler warns
  about it now (SL0610), which it did not while this was being written, and
  the comment on `GtkPeer.Echoing` is the long version.
- **A signal's arity has to match the connector's.** `switch-page` carries a
  page *and* a page number, so a handler connected as if it carried one reads
  the boxed closure out of the wrong register. That is a segfault at the first
  tab added with nothing in the backtrace to suggest a cause.

### What running it found

Six faults, none of which any self-test could see. Each is fixed; each is here
because the *shape* of it recurs.

- **An event box painted over everything a program drew.** A handler connected
  to `draw` runs before the class handler, and `GtkEventBox`'s class handler
  renders its own background -- so the program drew and the event box covered
  it, every frame. `OnPaint` was being called throughout, which is why nothing
  measured it. The event box was there to give a windowless `GtkFixed` the
  focus and the input; `gtk_widget_set_has_window` does that instead, and a
  `GtkFixed` renders no background, so the class handler running afterwards
  draws the children and nothing else. This is Lazarus's own answer -- its
  GTK3 widgetset does exactly this behind every custom control.
- **A client area was read from GTK's allocation.** `SetBounds` asks for a size
  by setting a size *request* and GTK negotiates later, so the allocation is
  the size before the one asked for, and 1x1 for a widget never allocated.
  Every child docked into one pixel. A form was unaffected, because the window
  peer answers from its own bounds -- which is why controls placed straight on
  a form always looked right and containers never did.
- **A page's content was parented before its page existed.** `TabPage` builds
  its panel, which reaches `AddChild`, and only then calls `Register`, which
  reaches `AddTab`. A notebook cannot answer `AddChild` when it is asked, so it
  holds the child until it has a page for it.
- **A page area of 1x1, for ever**, because the control layer asks for it
  before GTK has allocated anything. A `size-allocate` handler queues a
  relayout -- queues, because laying out from inside `size-allocate` calls
  `gtk_fixed_move` while GTK is part-way through allocating that container, and
  it segfaults.
- **And that relayout ratcheted the window open to the size of the screen**
  when the page area was read back from the allocation it had just caused.
  `PageArea` is derived from the bounds the layout set, minus what the tabs
  take.
- **Removing a tab freed widgets the control layer still held.** A notebook
  holds the only reference to a page, so `gtk_notebook_remove_page` destroys
  the page and every control on it while the `TabPage` goes on existing. The
  peer takes a reference of its own, so removal unparents rather than destroys.

### Before several of the above

- **DPI awareness.** Not a control, but every control is wrong without it on a
  scaled display -- and now on two platforms, since both backends turn points
  into pixels at a hard-coded 96.

## Known rough edges

Things that are here and imperfect, as opposed to the things above that are not
here at all. Where one is a backend's rather than the library's, it says so.

- **A GDI object cache.** Every pen and brush is made and deleted per drawing
  call, which cannot leak and is slower than it needs to be.
- **`BorderSpacing` and `ChildSizing` are absent.** The LCL's finer layout
  controls; only `Dock` and `Anchors` are here.
- **`Application` and `WidgetSet` hold static state and warn (SL0377).** A GUI
  toolkit is *thread-affine* — one thread owns the widgets — which is true of
  WinForms, WPF, GTK and Cocoa alike. Stainless can say `threadsafe`, which
  would be a lie here, and cannot yet say "one thread only". The warning is
  accurate and is left standing rather than silenced untruthfully.
- **A combo box's editability and a text box's multiline-ness are fixed at
  construction**, because on Windows they are creation-time style bits.
- **`InvalidateRegion` repaints the whole control**, since no peer interface
  takes a region yet.
- **Visual styles need a manifest**, and it is now inside the binary. The
  themed common controls are version 6 of `comctl32`, reachable only through a
  side-by-side manifest naming it; without one Windows loads version 5 and the
  tabs, toolbar and progress bar look like Windows 2000. They work either way,
  which is what makes it easy to miss. `samples/forms/forms.rc` files that
  manifest as `RT_MANIFEST`, and the build compiles it in -- so there is no
  longer a loose `.exe.manifest` to copy beside each program and lose.
- **A `ListView` row is an index, not an object.** `TListItem` is a
  `TPersistent` with a `TStrings` hanging off it, so a thousand rows is two
  thousand objects before any text. Cells are set and read through the list,
  which is what the platform stores anyway.
- **Pictures are `.bmp` only**, because `LoadImageW` is the whole of what
  Windows decodes without a library. PNG needs WIC or GDI+, each a binding of
  its own. An `ImageList` treats magenta as transparent, as toolbar bitmaps
  have since Windows 95. They may come from a file or from the program's own
  resources -- `Bitmap.FromResource(id)` and `ImageList.AddResource(id)` read
  an `RT_BITMAP` compiled into the executable, which is how a toolbar's icons
  stop being something that can go missing between building and running. Both
  backends do it: GTK decodes the same bytes through a `GdkPixbufLoader`, with
  the `BITMAPFILEHEADER` that `rc` strips put back first.
- **Not DPI aware.** On a scaled display Windows renders the window at 96 DPI
  and scales the result, so text is soft. Per-monitor awareness is a manifest
  setting and a layout that scales with it, and neither is here.
- **`SelectAll` uses a large sentinel length** rather than asking for the text's
  length in characters.

### GTK's own

- **Resources work here now, and the note that used to be here was wrong.** It
  argued that `Bitmap.FromResource` could never work because an ELF binary has
  no resource section. The premise was right and the conclusion was not: the
  compiler carries the compiled `.res` in a section of its own and
  `Standard.Resources` walks it, so a bitmap compiled into the program is read
  the same way on both backends. What is genuinely different is
  `Form.UseIconResource`, which still answers false: an `RT_GROUP_ICON` becomes
  a window's icon because *Windows* reads it, and a GTK program's icon comes
  from the desktop's icon theme, keyed by the name in its `.desktop` file.
- **A size request is a minimum.** A control in a `GtkFixed` is given its
  natural size when that is larger than the layout allowed, so a long caption
  overflows rather than clipping. A label ellipsizes and an entry scrolls; a
  button with more text than room does not.
- **Text is cairo's toy API**, so there is no shaping, no bidirectional text
  and no font fallback -- a label in Arabic is drawn wrong. Pango is the fix
  and is a binding of its own.
- **A combo box's editability and a text box's multiline-ness are fixed at
  construction**, which is the same limit the Win32 backend has for the same
  reason: they are different widgets there and creation-time style bits here.
- **A password character is GTK's, not the program's.**
  `gtk_entry_set_visibility` turns hiding on and the theme picks the glyph, so
  the mask is honoured as "hide" or "do not".
- **A details list shows icons in the `Details` style only.** GTK's answer to
  the three icon styles is `GtkIconView`, which is not a tree view and cannot
  be exchanged for one, so they show as a list with its headers hidden.
- **A details list has sixteen columns.** A `GtkListStore`'s column count is
  fixed when it is made and `TListView` programs use two or three; growing one
  would mean rebuilding the model and copying every row.
- **A tab's picture and a menu item's default are not drawn.** Neither has a
  GTK equivalent that matches a theme, so both do nothing rather than
  approximating one.
- **`Tool` and `None` borders are the same window.** GTK has no tool window:
  asking for one is a type hint that several compositors ignore, so both are
  undecorated and unresizable, which is true everywhere rather than sometimes.
