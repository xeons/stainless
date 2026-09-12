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
src/Controls/Buttons.sl     Button, CheckBox, RadioButton
src/Controls/Text.sl        Label, TextBox                  (lcl/stdctrls.pp)
src/Controls/Lists.sl       ListBox, ComboBox
src/Controls/Containers.sl  Panel, GroupBox, ScrollBar
src/Controls/Menus.sl       MainMenu, PopupMenu, MenuItem      (lcl/menus.pp)
src/Controls/Common.sl      ToolBar, StatusBar, ProgressBar, TrackBar,
                            TabControl, TreeView, ListView, ImageList
                                                            (lcl/comctrls.pp)
src/Platform/Select.sl      which backend this build links  (lcl/interfaces/)
src/Platform/Win32/*.sl     the Windows backend       (lcl/interfaces/win32/)
```

Roughly 4,900 lines against the LCL's 276,000 — which is the scope difference,
not a compression ratio. See *What is not here* below.

---

## Building it

```
stainless run samples/forms/demo.sl   forms/src bindings/win32/api \
    bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
stainless run samples/forms/common.sl forms/src bindings/win32/api \
    bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
```

or `.\samples\forms\build.ps1`, which builds both into `samples/forms/build`
(git-ignored), writes the visual-styles manifest each one needs, and takes
`-Test` to run every self-check and `-Run <name>` to open a window.

Both samples take `--selftest`, which builds the same window, pumps the message
queue, checks what can be checked without a person in front of it, and quits.
`demo` makes 21 such checks and `common` 24 — docking, anchoring, native
handles, text round-tripping through Windows, a click reaching its handler, a
menu item resolving from its command id. That is what makes a GUI something a
build can run, and it is how every bug listed under *Decisions worth knowing
about* was found.

Two end-to-end cases go further, driving real messages at the controls:
`tests/cases/forms-input` synthesises a mouse drag and a wheel turn and checks
what the control did with them; `tests/cases/forms-menus` sends `WM_COMMAND` for
a menu item, a nested item, a heading and a toolbar button, and checks which
handler ran.

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
| `Button`, `CheckBox`, `RadioButton`, `Label`, `TextBox`, `ListBox`, `ComboBox`, `Panel`, `GroupBox`, `ScrollBar` | `stdctrls.pp` |
| `MainMenu`, `PopupMenu`, `MenuItem` | `menus.pp` |
| `ToolBar`, `StatusBar`, `ProgressBar`, `TrackBar`, `TabControl`, `TreeView`, `ListView` | `comctrls.pp` |
| `ImageList` | `imglist.pp` |
| `Color`, `Point`, `Size`, `Rectangle`, `Font`, `Pen`, `Brush`, `Graphics`, `Bitmap` | `graphics.pp` |
| the widgetset seam | `widgetset/ws*.pp`, `interfaces/win32` |

### Next, and each a day rather than a week

Every one of these is either a composite of what already exists or a Win32 call
that is already bound.

- **Common dialogs** — `TOpenDialog`, `TSaveDialog`, `TSelectDirectoryDialog`
  (`dialogs.pp`). The single most-missed thing, and the cheapest:
  `bindings/win32/Dialogs.sl` already has all three, by both the legacy
  `ComDlg32` route and the modern `IFileDialog` one. What is left is wrapping
  them as classes. `TColorDialog` and `TFontDialog` need `ChooseColorW` and
  `ChooseFontW` bound first, which is a dozen lines each.
- **`Timer`** (`customtimer.pas`) — `SetTimer`/`KillTimer` are already bound;
  what it needs is a peer that routes `WM_TIMER` to a closure.
- **`PaintBox`, `Bevel`, `Shape`** (`extctrls.pp`) — `GraphicControl` exists and
  each of these is an `OnPaint` and a few properties. `PaintBox` is the one that
  makes custom drawing usable at all, and should probably come first of the
  three.
- **`Splitter`** (`extctrls.pp`) — pure layout arithmetic over a mouse drag, with
  no platform widget behind it.
- **`RadioGroup`, `CheckGroup`** (`extctrls.pp`) — a `GroupBox` that builds its
  own children. `LabeledEdit` likewise.
- **`SpinEdit`, `UpDown`** (`spin.pp`, `comctrls.pp`) — the `UDM_*` messages are
  bound in `ComCtl32.sl` already.
- **`CheckListBox`** (`checklst.pas`) — a `ListView` with `LVS_EX_CHECKBOXES`, or
  an owner-drawn list box.
- **`HeaderControl`, `CoolBar`** (`comctrls.pp`) — two more `comctl32` classes on
  the pattern the seven existing ones establish.

### Worth having, and a week each

- **`BitBtn`, `SpeedButton`** (`buttons.pp`) — a button with a picture. Needs
  either `BS_BITMAP` or owner drawing, and owner drawing is the thing several
  entries below also want.
- **`DateTimePicker`, `Calendar`** (`calendar.pp`) — `comctl32` has both; the
  work is a date type this library does not have yet.
- **`MaskEdit`** (`maskedit.pp`) and the `editbtn.pas` family — `FileNameEdit`,
  `DirectoryEdit`, `DateEdit`: an edit with a button that opens a dialog, which
  is why the dialogs come first.
- **`ColorBox`, `ColorListBox`** (`colorbox.pas`) — owner-drawn lists.
- **Owner drawing** across list, combo, menu and button. One mechanism
  (`WM_DRAWITEM`, `WM_MEASUREITEM`) that half a dozen controls want, so it is
  worth doing once and properly rather than per control.
- **Accelerators.** `&O` underlines a letter and works while a menu is open;
  `Ctrl+O` needs an accelerator table and `TranslateAccelerator` in the message
  loop.
- **Tab navigation.** `WS_TABSTOP` is set, but nothing calls `IsDialogMessage`,
  so Tab does not move between controls. Small, and very noticeable.
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

### Before several of the above

Two things are worth doing regardless of which control comes next.

- **The GTK backend.** The seam was designed for more than one platform and has
  only ever had one, which is the state in which a seam quietly stops being one.
  `bindings/gtk/Widgets.sl` already wraps twenty widgets, so much of it is an
  adapter — and it is the only real test of whether `IControlPeer` is portable
  or merely Win32-shaped.
- **DPI awareness.** Not a control, but every control is wrong without it on a
  scaled display.

## Known rough edges

Things that are here and imperfect, as opposed to the things above that are not
here at all.

- **A GDI object cache.** Every pen and brush is made and deleted per drawing
  call, which cannot leak and is slower than it needs to be.
- **Tab does not move between controls.** `WS_TABSTOP` is set on everything that
  should have it, but the message loop does not call `IsDialogMessage`, so
  nothing acts on it.
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
- **Visual styles need a manifest.** The themed common controls are version 6
  of `comctl32`, reachable only through a side-by-side manifest naming it;
  without one Windows loads version 5 and the tabs, toolbar and progress bar
  look like Windows 2000. They work either way, which is what makes it easy to
  miss. `samples/forms/build.ps1` writes one beside each executable, because
  Stainless has `#pragma comment(lib, ...)` and no way to ask the linker for
  anything else.
- **A `ListView` row is an index, not an object.** `TListItem` is a
  `TPersistent` with a `TStrings` hanging off it, so a thousand rows is two
  thousand objects before any text. Cells are set and read through the list,
  which is what the platform stores anyway.
- **Pictures are `.bmp` only**, because `LoadImageW` is the whole of what
  Windows decodes without a library. PNG needs WIC or GDI+, each a binding of
  its own. An `ImageList` treats magenta as transparent, as toolbar bitmaps
  have since Windows 95.
- **Not DPI aware.** On a scaled display Windows renders the window at 96 DPI
  and scales the result, so text is soft. Per-monitor awareness is a manifest
  setting and a layout that scales with it, and neither is here.
- **`SelectAll` uses a large sentinel length** rather than asking for the text's
  length in characters.
