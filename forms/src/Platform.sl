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

// The seam between the portable controls and the platform that draws them.
//
// **What this replaces.** The LCL's answer is `widgetset/ws*.pp`: a parallel
// hierarchy of `TWSWinControl`, `TWSButton`, `TWSCustomEdit` whose members are
// all `class procedure`s, dispatched through `class of` metaclass references
// that each widgetset registers for each control class. It works, and it needs
// three things Stainless does not have: metaclasses, a registration pass that
// runs before anything is constructed, and a `published` section to hang the
// virtual class methods on.
//
// **What replaces it.** Interfaces, and one object per live control. A control
// owns a *peer* -- the platform's side of it -- and talks to the platform only
// through that peer's interface. This is the arrangement C# reached for the
// same problem: WPF's and Avalonia's `I*Impl`, one implementation per platform,
// created by a factory the application sets once at startup.
//
// Three things fall out of it that the LCL pays for elsewhere:
//
//   1. **A peer is an object, so it holds state.** The Win32 backend keeps a
//      window's original window procedure next to its `HWND` for subclassing,
//      which in the LCL needs a side table keyed by `HWND` (`AllocWindowInfo`,
//      a global atom, `GetProp` on every message).
//   2. **The peer's lifetime is the control's.** ARC destroys it, so
//      `DestroyHandle` is a destructor and cannot be forgotten.
//   3. **Capabilities are separate interfaces.** A `Button` needs what every
//      control needs plus a click; a `TextBox` needs selection and a read-only
//      flag. Rather than one interface with every method any control might
//      want -- `TWSWinControl` is 40 class methods, most of which most controls
//      ignore -- each capability is its own interface, and a backend that does
//      not implement one is a compile error rather than an empty override.
//
// **Which way calls go.** Down through `I*Peer`, up through `I*Notify`. The
// control calls `peer.SetText(...)`; the platform calls `notify.OnClicked()`.
// Neither side names a type from the other's module, which is what lets the
// Win32 backend be compiled without the GTK one and vice versa.
module Forms.Platform;

import Standard.Collections;
import Forms.Drawing;

/// Aborts with a message, for a mistake in the calling program rather than a
/// value to hand back. The same one `Standard.Collections` uses.
extern "C" void sl_fail(byte* message);

// ============================================================ system colours

/// The theme colours a backend can be asked for. An enum rather than a string,
/// so a backend's switch is exhaustive at a glance and a typo does not compile.
public enum SystemColorId
{
    Control,
    ControlText,
    ControlDark,
    ControlLight,
    Window,
    WindowText,
    Highlight,
    HighlightText,
    GrayText,
}

// ============================================================ input, as data

/// Which mouse button. `None` exists because a move carries no button and the
/// alternative is a nullable the handler must unwrap for nothing.
public enum MouseButton { None, Left, Right, Middle }

/// The modifier keys held when something happened. Bits, so they combine.
[Flags]
public enum ModifierKeys
{
    None    = 0,
    Shift   = 1,
    Control = 2,
    Alt     = 4,
}

/// A key, by what it means rather than where it is. The values are the Win32
/// virtual-key codes because one backend must own the numbering and Windows'
/// is the one with names for everything; the GTK backend maps `GDK_KEY_*` on to
/// this on the way in.
public enum Key
{
    None = 0,
    Backspace = 8, Tab = 9, Enter = 13,
    Shift = 16, Control = 17, Alt = 18,
    Pause = 19, CapsLock = 20, Escape = 27, Space = 32,
    PageUp = 33, PageDown = 34, End = 35, Home = 36,
    Left = 37, Up = 38, Right = 39, Down = 40,
    Insert = 45, Delete = 46,
    D0 = 48, D1 = 49, D2 = 50, D3 = 51, D4 = 52,
    D5 = 53, D6 = 54, D7 = 55, D8 = 56, D9 = 57,
    A = 65, B = 66, C = 67, D = 68, E = 69, F = 70, G = 71, H = 72, I = 73,
    J = 74, K = 75, L = 76, M = 77, N = 78, O = 79, P = 80, Q = 81, R = 82,
    S = 83, T = 84, U = 85, V = 86, W = 87, X = 88, Y = 89, Z = 90,
    F1 = 112, F2 = 113, F3 = 114, F4  = 115, F5  = 116, F6  = 117,
    F7 = 118, F8 = 119, F9 = 120, F10 = 121, F11 = 122, F12 = 123,
}

// ====================================================== platform to control

/// What the platform tells a control happened to it.
///
/// A control implements this and hands itself to its peer. Every method is a
/// *notification*: it reports, it does not ask, and a backend never waits on
/// what a handler decides -- except `OnClosing`, which is on `IWindowNotify`
/// where the one case that must ask is visible on its own.
///
/// **Coordinates are already client-relative and already scaled.** Turning a
/// platform's idea of a position into this one is the backend's job, so no
/// control anywhere contains a coordinate adjustment.
public interface IControlNotify
{
    void OnPlatformPaint(Graphics surface);
    void OnPlatformResized(Size extent);
    void OnPlatformMoved(Point position);

    void OnPlatformMouseDown(MouseButton button, Point at, ModifierKeys modifiers);
    void OnPlatformMouseUp(MouseButton button, Point at, ModifierKeys modifiers);
    void OnPlatformMouseMove(Point at, ModifierKeys modifiers);
    void OnPlatformMouseEnter();
    void OnPlatformMouseLeave();
    void OnPlatformMouseWheel(int delta, Point at, ModifierKeys modifiers);

    void OnPlatformKeyDown(Key key, ModifierKeys modifiers);
    void OnPlatformKeyUp(Key key, ModifierKeys modifiers);
    /// One typed character, after the platform has applied the keyboard layout
    /// and any dead keys -- which is why it is a separate notification from
    /// `OnPlatformKeyDown` and not derivable from it.
    void OnPlatformKeyPress(char typed);

    void OnPlatformGotFocus();
    void OnPlatformLostFocus();

    /// The user activated the control: clicked a button, ticked a box, chose a
    /// menu item. Distinct from a mouse click because the keyboard does it too.
    void OnPlatformActivated();

    /// The left button was pressed twice inside the double-click time.
    ///
    /// Separate from a second `OnPlatformMouseDown` because the platform is
    /// what owns the time and the distance that make two clicks one gesture,
    /// and a control counting them itself would get a different answer from
    /// every other program on the desktop.
    ///
    /// The mouse-down for the second click is still reported, before this: a
    /// control that only tracks presses must not miss one, and a control that
    /// wants the gesture is looking at this instead. Win32 substitutes
    /// `WM_LBUTTONDBLCLK` for that second `WM_LBUTTONDOWN` rather than sending
    /// both, so the backend raises both from the one message to make the two
    /// platforms agree.
    void OnPlatformDoubleClick();

    /// The control's own value changed by the user's doing -- text typed, an
    /// item selected. Never raised for a change the program itself made, which
    /// is what stops a two-way binding oscillating.
    void OnPlatformValueChanged();

    /// A button on a toolbar was pressed. Separate from `OnPlatformActivated`
    /// because a toolbar is one control with many buttons, so the report has to
    /// say which.
    void OnPlatformToolClicked(int index);
}

/// What a top-level window additionally reports.
public interface IWindowNotify : IControlNotify
{
    /// The user asked to close it. **True lets it close**, false keeps it open,
    /// which is the one place the platform waits for an answer.
    bool OnPlatformClosing();
    void OnPlatformClosed();
    void OnPlatformActivatedWindow();
    void OnPlatformDeactivated();
}

// ====================================================== control to platform

/// How a window is framed, which decides both its border and what it does when
/// dragged. The LCL's `TBorderStyle` plus `TFormBorderStyle`, merged: they
/// differed only in which values each accepted.
public enum WindowBorder
{
    /// No frame at all: a splash screen, a tooltip.
    None,
    /// A caption and a frame that cannot be dragged to resize.
    Fixed,
    /// The ordinary resizable window.
    Sizable,
    /// A thin caption, and absent from the task bar.
    Tool,
}

/// Whether a window is normal, minimised or maximised.
public enum WindowState { Normal, Minimized, Maximized }

/// The frame drawn around a control that has one.
public enum ControlBorder { None, Single, Sunken }

/// What the pointer looks like over a control.
///
/// The shapes every platform has, and no more: a cursor from a file is a
/// resource story, and the list below is what a layout actually needs -- the
/// resize shapes are what make a splitter look draggable.
public enum CursorKind
{
    Default,
    Arrow,
    Hand,
    Text,
    Wait,
    Cross,
    SizeWestEast,
    SizeNorthSouth,
    SizeAll,
    No,
}

/// What every control's peer can do.
///
/// **`Destroy` is here and is not a destructor.** A peer is destroyed when its
/// control is, and ARC would do that on its own -- but a control can also be
/// asked to give up its platform window and make a new one, which is what
/// changing a border style costs on Windows. So the release is a method, and
/// the destructor calls it if nothing else has.
public interface IControlPeer
{
    void SetBounds(Rectangle bounds);
    void SetVisible(bool visible);
    void SetEnabled(bool enabled);
    void SetText(String text);
    String GetText();
    void SetFont(Font font);
    void SetForeColor(Color colour);
    void SetBackColor(Color colour);

    /// Marks the control as needing repainting. Does not paint: the platform
    /// decides when, and coalesces several of these into one paint.
    void Invalidate();
    /// Paints it now, rather than when the platform gets to it.
    void Update();

    void Focus();
    bool HasFocus { get; }

    /// What the pointer looks like over this control.
    void SetCursor(CursorKind cursor);

    /// Takes or gives up the mouse, so that a drag keeps being reported after
    /// the pointer has left the control. What every drag needs and what nothing
    /// else does.
    void SetCapture(bool captured);

    /// Puts the control in front of its siblings, so that one overlapping
    /// another covers it rather than being covered.
    ///
    /// **Only among siblings**, which is the whole of what both platforms
    /// offer: a child cannot be raised above its parent's siblings, so a panel
    /// that must cover the whole window has to be a child of the whole window.
    ///
    /// Z-order is otherwise the order controls were made in, and that is a poor
    /// thing to depend on -- it ties what is in front to the order of lines in
    /// a constructor, and the two drift apart the first time a control is added
    /// in a hurry. Anything that deliberately overlaps says so by calling this.
    void BringToFront();

    /// Where the pointer is now, in this control's own coordinates. Outside it
    /// answers a point outside it, including negative ones.
    ///
    /// **Asked, not waited for**, which is the whole reason it exists. Enter
    /// and leave events answer "is the pointer over *this* control", and a
    /// container gets a leave the moment the pointer moves onto one of its own
    /// children -- so anything that has to know whether the pointer is still
    /// somewhere inside a panel, rather than over the panel itself, cannot be
    /// written from events at all. A pane that slides out and has to slide back
    /// when the pointer leaves is exactly that, and it is why this is here.
    Point PointerPosition();

    /// How much room children have, as a size at the origin.
    ///
    /// **Always starts at (0, 0)**, because it is the space a child's own
    /// coordinates are measured in. Where that space begins within the widget
    /// is `ClientOrigin`, and keeping the two apart is what makes a control
    /// placed at (0, 0) land in the same place whether its parent has a frame
    /// or not.
    Rectangle ClientBounds { get; }

    /// Where the client area begins inside the widget.
    ///
    /// Zero for almost everything: on Windows a child's position is already
    /// relative to its parent's client origin. A group box is the exception --
    /// its frame and caption occupy the top of its own rectangle, and a child
    /// placed there would be drawn over them -- so the offset is added when a
    /// child's bounds are pushed down, and taken off again when the platform
    /// reports where one ended up.
    Point ClientOrigin { get; }

    /// What the platform thinks this control ought to be, given its text and
    /// font. What `AutoSize` uses, and the reason a button sized to its caption
    /// looks native rather than merely close.
    Size PreferredSize { get; }

    /// The platform's handle, as an integer. For reaching an API this layer
    /// does not wrap -- an `HWND` on Windows, a `GtkWidget*` on GTK. Zero if
    /// the peer has no handle yet.
    nuint Handle { get; }

    void Destroy();
}

/// A container that other controls can be put inside.
public interface IContainerPeer : IControlPeer
{
    /// Re-parents a child on to this container. Called once, when the child's
    /// peer is made -- a control that changes parent is given a new peer,
    /// because on Win32 re-parenting a window and re-creating it cost the same
    /// and only one of them is correct for every control.
    void AddChild(IControlPeer child);
    void RemoveChild(IControlPeer child);
}

/// A top-level window.
public interface IWindowPeer : IContainerPeer
{
    void SetTitle(String title);

    /// Puts an icon in the title bar and wherever else the desktop shows one,
    /// by the numeric id the program's resource script gave it.
    ///
    /// An id rather than a `Bitmap`, because an icon is not a picture: an
    /// `RT_GROUP_ICON` holds several sizes and the platform picks between them,
    /// which is what makes a title bar sharp and the task switcher sharp at the
    /// same time. Answers false where there is no such icon, or no resource
    /// section to look in.
    bool SetIconResource(int id);

    /// Puts a menu bar across the top, or takes it away with null.
    void SetMenu(IMenuPeer? menu);
    void SetBorder(WindowBorder border);
    void SetState(WindowState state);
    WindowState GetState();
    void Activate();
    void Close();
    /// Centres it on the monitor it is on, which needs to know which that is.
    void CenterOnScreen();
    /// Shows it and does not return until it is closed, which is what a dialog
    /// is. Answers nothing: what the dialog decided is the dialog's business.
    void ShowModal();
}

/// A button, a checkbox or a radio button: something that is pressed.
public interface IButtonPeer : IControlPeer
{
    /// Makes it the one Enter presses. At most one per window, and the platform
    /// is what enforces that, so a control that sets it need not unset the
    /// previous one.
    void SetDefault(bool isDefault);
}

/// Where a button's picture sits relative to its caption.
///
/// Four positions and no more, because four is what both platforms have:
/// Windows' `BUTTON_IMAGELIST_ALIGN_*` and GTK's `GtkPositionType` are the same
/// four, and `TButtonLayout` is the same four again. A ninth-of-a-rectangle
/// alignment like C#'s `ContentAlignment` would be five parts fiction.
public enum ImageAlignment { Left, Right, Top, Bottom }

/// A push button, which is the one of the three that carries a picture.
///
/// **Not on `IButtonPeer`, though a check box would happily draw one.** Windows
/// gives a `BUTTON` its picture with `BCM_SETIMAGELIST`, which on a check box
/// replaces the tick rather than sitting beside it, and GTK's
/// `gtk_button_set_image` does the same to a `GtkCheckButton`'s indicator. So
/// the capability is declared where both platforms can honour it and nowhere
/// else, and a check box does not get a method that would quietly ruin it.
public interface IPushButtonPeer : IButtonPeer
{
    /// The picture, or null for none.
    void SetImage(IBitmapBackend? picture);
    void SetImageAlign(ImageAlignment place);
    /// Pixels between the picture and the caption.
    void SetImageSpacing(int gap);
}

/// Which of the three the platform's button class is being asked for.
///
/// `Toggle` is a check box that stays down instead of ticking -- `BS_PUSHLIKE`
/// on Windows, a `GtkToggleButton` on GTK, `TToggleBox` in the LCL. It is a
/// third value rather than a second boolean beside `radio` because two booleans
/// have a fourth combination that means nothing.
public enum CheckKind { Check, Radio, Toggle }

/// A checkbox, a radio button or a toggle button, which additionally carry a
/// state.
public interface ICheckPeer : IButtonPeer
{
    void SetChecked(bool checked);
    bool GetChecked();
}

/// Anything the user types into.
public interface ITextEntryPeer : IControlPeer
{
    void SetReadOnly(bool readOnly);
    void SetMaxLength(int length);
    /// Hides what is typed. A character rather than a flag, because the
    /// platforms differ on what they hide it with and a caller may care.
    void SetPasswordChar(char mask);
    void SetSelection(int start, int length);
    /// Start and length of what is selected, as a tuple so one call answers
    /// both and they cannot disagree.
    (int, int) GetSelection();
    void SetMultiline(bool multiline);
    /// The lines, for a multiline entry. One entry for a single-line one.
    String[] GetLines();
    void SetLines(String[] lines);
}

/// A list of items the user chooses from: a list box or a combo box.
public interface IListPeer : IControlPeer
{
    void InsertItem(int index, String text);
    void RemoveItem(int index);
    void ClearItems();
    int ItemCount { get; }
    void SetSelectedIndex(int index);
    /// -1 when nothing is selected, which is what every platform reports and
    /// what the control layer turns into something better.
    int  GetSelectedIndex();
}

/// A combo box, which is a list with an edit on top.
public interface IComboPeer : IListPeer
{
    /// Whether the text can be typed as well as chosen.
    void SetEditable(bool editable);
}

/// A scroll bar, standing alone rather than attached to a scrolling container.
public interface IScrollBarPeer : IControlPeer
{
    void SetRange(int minimum, int maximum, int pageSize);
    void SetValue(int value);
    int  GetValue();
}

/// A group box: a frame with a caption that other controls sit inside.
public interface IGroupPeer : IContainerPeer { }

/// A number with arrows beside it.
public interface ISpinPeer : IControlPeer
{
    void SetRange(int minimum, int maximum);
    void SetValue(int value);
    int  GetValue();
}

/// A list whose items each have a tick.
public interface ICheckListPeer : IListPeer
{
    void SetItemChecked(int index, bool checked);
    bool GetItemChecked(int index);
}

/// A row of draggable column headings, standing alone rather than on a list.
public interface IHeaderPeer : IControlPeer
{
    int AddSection(String text, int width);
    void SetSectionWidth(int index, int width);
    int  GetSectionWidth(int index);
    int SectionCount { get; }
}

/// A panel: a plain container with an optional border.
public interface IPanelPeer : IContainerPeer
{
    void SetBorder(ControlBorder border);
}

/// A control the program draws every pixel of, and that takes the keyboard.
///
/// **The one thing a `PaintBox` cannot be.** A `GraphicControl` has no window,
/// so it has nothing to give the focus to and no keystroke ever reaches it;
/// a `Panel` has a window and gives up the focus on purpose, being a container.
/// A code editor, a grid, a chart the arrow keys move around in -- each needs a
/// window of its own that draws nothing by itself and hears everything, and
/// that is the whole of what this is.
///
/// A container as well, so that the scroll bars a drawn control needs are
/// ordinary children of it rather than something the seam has to learn about.
public interface ICustomPeer : IContainerPeer
{
    void SetBorder(ControlBorder border);

    /// Whether clicking it and tabbing to it give it the keyboard.
    ///
    /// A drawn control that only displays -- a chart, a status strip -- says
    /// false and stays out of the tab order, which is the difference between
    /// this and a control that merely happens not to handle any keys.
    void SetFocusable(bool focusable);

    /// Where the insertion point is and how big, or an empty rectangle for a
    /// control that has none.
    ///
    /// **One call rather than a show, a hide and a move**, because a caret is a
    /// rectangle and those three are all the same fact arriving in pieces. The
    /// platform keeps it: a caret belongs to whichever window has the focus, so
    /// the peer puts it back when the control is focused again and takes it
    /// away when it is not, and the control never has to know that.
    ///
    /// Not blinked by the control. Windows blinks the system caret, GTK draws
    /// one at the rate the desktop settings ask for, and a control that blinked
    /// its own would disagree with every other application on the screen.
    void SetCaret(Rectangle place);
}

/// A label, which is drawn by the platform rather than by the control.
public interface ILabelPeer : IControlPeer
{
    void SetAlignment(HorizontalAlignment alignment);
    void SetWordWrap(bool wrap);
}

// ============================================================ the common tier
//
// What `comctl32` adds on Windows and GTK has its own widgets for. Each is its
// own interface for the same reason the standard tier is: a control declares
// the capability it has, and a backend that has not implemented one fails to
// compile rather than inheriting an empty override.

/// A picture, loaded once and drawn many times.
public interface IBitmapBackend
{
    int Width { get; }
    int Height { get; }
    /// The platform's handle -- an `HBITMAP` on Windows.
    nuint Handle { get; }

    /// Whether the picture carries a per-pixel alpha channel that can be
    /// drawn with.
    ///
    /// **Not "has four bytes per pixel".** A `.bmp` read by the platform's own
    /// loader is 32 bits deep and its fourth byte is zero, which is exactly
    /// what "invisible" is spelled as -- so a backend that answered true for
    /// one of those would draw nothing at all and look like a broken blit. It
    /// is true only where the pixels came from somewhere that says what the
    /// channel means, which today is `CreateBitmap`.
    bool HasAlpha { get; }
}

/// Same-sized pictures, indexed by number.
///
/// A toolbar, a tree and a list all take their icons from one of these rather
/// than holding pictures themselves, because that is how every platform does
/// it: the control stores an index, and the list stores the picture.
public interface IImageListBackend
{
    /// Adds a picture and answers its index.
    int Add(IBitmapBackend picture);
    int Count { get; }
    Size ImageSize { get; }
    nuint Handle { get; }
}

// ------------------------------------------------------------------- menus

/// What a menu item tells the program.
public interface IMenuItemNotify
{
    void OnPlatformMenuClicked();
}

/// One item: a command, a separator, or something with a submenu under it.
public interface IMenuItemPeer
{
    /// What the platform calls this item.
    ///
    /// On Windows it is the command id `WM_COMMAND` will carry, which is the
    /// only thing that identifies a chosen item -- so it is also what a program
    /// needs to know if it is going to talk to the menu directly.
    nuint Id { get; }

    void SetText(String text);
    void SetEnabled(bool enabled);
    void SetChecked(bool checked);
    /// Draws it as the default -- bold, and what a double-click would do.
    void SetDefault(bool isDefault);
}

/// A menu: the bar across a window, or one that drops down, or one that pops up
/// under the pointer. All three are the same thing on every platform, which is
/// why there is one interface rather than three.
public interface IMenuPeer
{
    /// The platform's handle -- an `HMENU` on Windows -- for reaching a call
    /// this layer does not wrap.
    nuint Handle { get; }

    /// Adds a command. `submenu` makes it a heading rather than a command, and
    /// an item with one raises nothing when chosen.
    IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu);
    void AddSeparator();
    void Clear();

    /// Shows this menu under the pointer and does not return until the user has
    /// chosen or dismissed it.
    void ShowPopup(IWindowPeer owner, Point atScreen);
}

// ------------------------------------------------------------- the controls

/// What kind of thing a toolbar button is.
public enum ToolButtonKind { Button, Toggle, Separator }

public interface IToolBarPeer : IControlPeer
{
    /// Adds a button and answers its index. `image` is a position in the
    /// toolbar's image list, or -1 for none.
    int AddButton(String text, int image, ToolButtonKind kind);
    /// What the platform calls one button, on the same terms as
    /// `IMenuItemPeer.Id` -- a toolbar's buttons share one window, so this is
    /// what tells them apart.
    nuint ButtonId(int index);

    void SetButtonEnabled(int index, bool enabled);
    void SetButtonChecked(int index, bool checked);
    bool GetButtonChecked(int index);
    void SetImages(IImageListBackend images);
    /// Shows a caption beside each button rather than only its picture.
    void SetTextVisible(bool visible);
    /// Sizes the bar to its buttons, which is what a docked toolbar wants.
    void ResizeToFit();
}

public interface IStatusBarPeer : IControlPeer
{
    /// The right-hand edge of each panel, in pixels from the left; the last may
    /// be -1, meaning "to the end". One call rather than one per panel because
    /// that is the one message Windows has.
    void SetPanels(int[] edges);
    void SetPanelText(int index, String text);
}

public interface IProgressPeer : IControlPeer
{
    void SetRange(int minimum, int maximum);
    void SetValue(int value);
    int  GetValue();
    /// A bar with no value that simply moves, for work of unknown length.
    void SetIndeterminate(bool indeterminate);
}

public interface ITrackBarPeer : IControlPeer
{
    void SetRange(int minimum, int maximum);
    void SetValue(int value);
    int  GetValue();
    /// How often a tick is drawn under the slider.
    void SetTickFrequency(int every);
}

public interface ITabControlPeer : IContainerPeer
{
    /// Adds a tab and answers its index.
    int AddTab(String text, int image);
    void RemoveTab(int index);
    void SetTabText(int index, String text);
    void SetSelectedTab(int index);
    int  GetSelectedTab();
    /// How many tabs the control has.
    int TabCount { get; }
    /// The area inside the tabs, where a page's controls go. Not the client
    /// area: the tabs themselves are part of that.
    Rectangle PageArea { get; }
    void SetImages(IImageListBackend images);
}

/// A place in a tree. Opaque, because a tree is a linked structure and an index
/// would not survive anything being inserted.
public interface ITreeNodeHandle
{
    /// What the platform calls this node.
    ///
    /// Two handles naming the same node are not necessarily the same object --
    /// a backend asked which node is selected may wrap the answer afresh each
    /// time -- so identity is this number rather than the reference.
    nuint Id { get; }
}

public interface ITreeViewPeer : IControlPeer
{
    /// Adds a node under `parent` -- null for a root -- after `previous`, or at
    /// the end when that is null too.
    ITreeNodeHandle AddNode(ITreeNodeHandle? parent, ITreeNodeHandle? previous,
                            String text, int image);
    void RemoveNode(ITreeNodeHandle node);
    void SetNodeText(ITreeNodeHandle node, String text);
    String GetNodeText(ITreeNodeHandle node);
    void Expand(ITreeNodeHandle node, bool expanded);
    void SelectNode(ITreeNodeHandle node);
    ITreeNodeHandle? GetSelectedNode();

    /// Which node is under `at`, or null for none.
    ///
    /// **`at` is the point a mouse event reported**, not an arbitrary point in
    /// the control's client area, and the difference is not pedantry: GTK
    /// gives a button event its position inside the tree's scrolled *bin*
    /// window, which is the coordinate space its own hit test wants, while the
    /// widget's client area is a different origin once the view has been
    /// scrolled. Both backends take what the event carried and neither
    /// converts, so a caller that passes the point it was handed is right on
    /// both and a caller that invents one is right on neither.
    ///
    /// **A right-click does not move the selection**, on either platform, so
    /// this is the only way a context menu can know what it was opened on.
    /// Building one from `GetSelectedNode` instead acts on whatever was
    /// selected beforehand -- which is a menu that renames the wrong file.
    ITreeNodeHandle? NodeAt(Point at);

    void Clear();
    void SetImages(IImageListBackend images);
}

/// How a list shows what it holds.
public enum ListViewStyle { Details, List, SmallIcon, LargeIcon }

public interface IListViewPeer : IControlPeer
{
    void SetStyle(ListViewStyle style);
    int  AddColumn(String text, int width, HorizontalAlignment alignment);
    void SetColumnWidth(int column, int width);
    /// Adds a row and answers its index.
    int  AddRow(String text, int image);
    void SetCell(int row, int column, String text);
    /// What a cell says, asked of the control rather than remembered.
    String GetCell(int row, int column);
    void RemoveRow(int row);
    void Clear();
    int RowCount { get; }
    int  GetSelectedRow();
    void SetSelectedRow(int row);
    void SetImages(IImageListBackend images);
    /// Whether a click anywhere on a row selects the whole of it, and whether
    /// the grid is drawn. Both are the same call because Windows makes them one
    /// extended style word.
    void SetFullRowSelect(bool full, bool gridLines);
}

// -------------------------------------------------------------------- timer

/// What a timer tells the program.
public interface ITimerNotify
{
    void OnPlatformTick();
}

/// A platform timer.
public interface ITimerPeer
{
    void Start(int milliseconds);
    void Stop();
}

/// The platform's font, once it has been made. Opaque: only the backend that
/// made it knows what is inside, and `Font` holds one so the handle is made
/// once however many controls share the font.
public interface IFontBackend
{
    nuint Handle { get; }
}

/// The platform's drawing surface, behind `Graphics`.
public interface IGraphicsBackend
{
    Rectangle ClipBounds { get; }

    /// Narrows drawing to `bounds` and moves the origin to its corner, so that
    /// whatever draws next works in its own coordinates and cannot draw outside
    /// them.
    ///
    /// Answers a token for `PopLayer`. What a `GraphicControl` needs, since it
    /// has no window of its own and would otherwise be drawing in its parent's
    /// coordinates, over its parent's siblings -- the protection a real window
    /// gets from the platform for nothing.
    int PushLayer(Rectangle bounds);
    void PopLayer(int token);
    void Clear(Color colour);
    void DrawLine(Pen pen, int x1, int y1, int x2, int y2);
    void DrawRectangle(Pen pen, Rectangle bounds);
    void FillRectangle(Brush brush, Rectangle bounds);
    void DrawEllipse(Pen pen, Rectangle bounds);
    void FillEllipse(Brush brush, Rectangle bounds);
    void DrawPolygon(Pen pen, Point[] points);
    void FillPolygon(Brush brush, Point[] points);
    void DrawPolyline(Pen pen, Point[] points);
    void DrawString(String text, Font font, Color colour, int x, int y);
    void DrawStringIn(String text, Font font, Color colour,
                      Rectangle bounds, TextFormat format);
    Size MeasureString(String text, Font font);

    /// Draws a picture at its own size, or scaled into a rectangle.
    ///
    /// Two calls rather than one with a flag, because scaling costs a different
    /// platform call and a caller that is not scaling should not pay for the
    /// decision on every frame.
    void DrawBitmap(IBitmapBackend picture, Point at);
    void DrawBitmapIn(IBitmapBackend picture, Rectangle into);
}

// =============================================================== the factory

/// The result of a modal dialog, and of the buttons that produce one.
public enum DialogResult { None, Ok, Cancel, Yes, No, Abort, Retry, Ignore }

/// Which icon a message box shows.
public enum MessageIcon { None, Information, Warning, Error, Question }

/// Why a dialog produced no answer.
///
/// Declared here rather than beside the dialog classes because it is what the
/// *seam* answers with: a backend reports the outcome and the control layer
/// passes it on unchanged.
public enum DialogOutcome
{
    /// The user pressed Cancel or closed it.
    Cancelled,
    /// The platform could not show it at all.
    Failed,
}

/// Which buttons a message box offers.
public enum MessageButtons { Ok, OkCancel, YesNo, YesNoCancel, RetryCancel }

/// One platform, and everything it can make.
///
/// **A factory method per peer kind, not per control class.** The LCL needs a
/// `TWS` class for every control because dispatch is by metaclass; here a
/// `RadioButton` and a `CheckBox` are both `CreateCheck`, differing by an
/// argument, and a new control that is a list with different behaviour needs no
/// new backend code at all. Roughly a dozen methods covers the standard tier,
/// and each is one native widget.
///
/// Every `Create` takes the notification target the peer will report to, which
/// is the control itself. That is the whole of the wiring: no registration
/// pass, no table keyed by class, nothing to forget.
public interface IWidgetSet
{
    /// What this backend is called, for a program that must know -- `"Win32"`,
    /// `"GTK3"`. The only thing anywhere that names a platform as a string.
    String Name { get; }

    IWindowPeer     CreateWindow(IWindowNotify owner, WindowBorder border);
    IPushButtonPeer CreateButton(IControlNotify owner, IContainerPeer parent);
    ICheckPeer      CreateCheck(IControlNotify owner, IContainerPeer parent,
                                CheckKind kind);
    ILabelPeer     CreateLabel(IControlNotify owner, IContainerPeer parent);
    ITextEntryPeer CreateTextEntry(IControlNotify owner, IContainerPeer parent,
                                   bool multiline);
    IListPeer      CreateList(IControlNotify owner, IContainerPeer parent);
    IComboPeer     CreateCombo(IControlNotify owner, IContainerPeer parent);
    IGroupPeer     CreateGroup(IControlNotify owner, IContainerPeer parent);
    IPanelPeer     CreatePanel(IControlNotify owner, IContainerPeer parent);
    ICustomPeer    CreateCustom(IControlNotify owner, IContainerPeer parent);
    IScrollBarPeer CreateScrollBar(IControlNotify owner, IContainerPeer parent,
                                   bool vertical);
    ISpinPeer      CreateSpin(IControlNotify owner, IContainerPeer parent);
    ICheckListPeer CreateCheckList(IControlNotify owner, IContainerPeer parent);
    IHeaderPeer    CreateHeader(IControlNotify owner, IContainerPeer parent);

    IToolBarPeer   CreateToolBar(IControlNotify owner, IContainerPeer parent);
    IStatusBarPeer CreateStatusBar(IControlNotify owner, IContainerPeer parent);
    IProgressPeer  CreateProgress(IControlNotify owner, IContainerPeer parent);
    ITrackBarPeer  CreateTrackBar(IControlNotify owner, IContainerPeer parent,
                                  bool vertical);
    ITabControlPeer CreateTabControl(IControlNotify owner, IContainerPeer parent);
    ITreeViewPeer  CreateTreeView(IControlNotify owner, IContainerPeer parent);
    IListViewPeer  CreateListView(IControlNotify owner, IContainerPeer parent);

    /// An empty popup menu, to be filled and then shown under the pointer.
    IMenuPeer CreateMenu();

    /// An empty menu bar, to be filled and then given to a window. Separate
    /// from `CreateMenu` because Windows makes the two with different calls and
    /// will not exchange one for the other afterwards.
    IMenuPeer CreateMenuBar();

    ITimerPeer CreateTimer(ITimerNotify owner);

    // ------------------------------------------------------------ clipboard

    /// What the clipboard holds as text, or `""` when it holds none.
    ///
    /// **Text and nothing else, for now.** A clipboard carries any number of
    /// formats at once and negotiates which one a paste wants, which is a
    /// design of its own; what an editor needs is the one format both platforms
    /// agree about and every program offers.
    ///
    /// Answering `""` for an empty clipboard rather than a null: a paste of
    /// nothing and a paste of an empty string do the same thing, so a caller
    /// that had to tell them apart would only be writing the test twice.
    String GetClipboardText();

    /// Puts text on the clipboard, replacing whatever was there.
    void SetClipboardText(String text);

    /// Whether there is text to be had. What a paste command greys itself out
    /// on, and cheaper than fetching the text to find out.
    bool ClipboardHasText { get; }

    // ------------------------------------------------------------ dialogs
    //
    // Each answers what was chosen, so there is nothing to read when nothing
    // was -- which is the whole difference from `TOpenDialog.Execute`, where a
    // caller who forgets the test reads a stale path.

    Result<String, DialogOutcome> ChooseFileToOpen(IWindowPeer? owner, String title,
                                                   String start, String[] filters);
    Result<String, DialogOutcome> ChooseFileToSave(IWindowPeer? owner, String title,
                                                   String start, String[] filters);
    Result<String, DialogOutcome> ChooseFolder(IWindowPeer? owner, String title);
    Result<Color, DialogOutcome>  ChooseColor(IWindowPeer? owner, Color start);
    Result<Font, DialogOutcome>   ChooseFont(IWindowPeer? owner, Font start);

    IFontBackend CreateFont(Font font);

    /// A picture read from a file. What the format may be is the backend's
    /// business; Windows reads `.bmp` without a decoder and nothing else.
    ///
    /// **`Bitmap.FromFile` tries `CreateBitmap` first** and only falls back to
    /// this, so what a backend decodes natively decides the speed rather than
    /// the answer. It is still here because it is the path that works when
    /// `Standard.Drawing` has no imaging library to load.
    Result<IBitmapBackend, String> LoadBitmap(String path);

    /// A picture the caller already has the pixels of.
    ///
    /// `pixels` is four bytes each in the order **blue, green, red, alpha**,
    /// rows top to bottom, `width * 4` bytes to a row and no padding -- which
    /// is `Standard.Drawing.Image.CopyPixels`' order, and a Windows DIB's, and
    /// what `Rgba.Packed` already is in memory. The alpha is straight, not
    /// premultiplied; a backend that composites premultiplied does that
    /// conversion itself, because it is the one that knows.
    ///
    /// This is the seam that lets `forms/` show a PNG. Every decoder question
    /// -- which formats, which library, which platform has it -- belongs to
    /// `Standard.Drawing` and stops here, so a widget set only ever has to
    /// know how to turn bytes into whatever its own toolkit holds pictures in.
    Result<IBitmapBackend, String> CreateBitmap(int width, int height, byte[] pixels);

    /// A picture read out of the binary's own resources, by numeric id.
    ///
    /// Windows-only in practice, and deliberately part of the interface
    /// anyway: a backend that cannot do this has to say so in an error a
    /// caller can print, which is more useful than the method not existing and
    /// the program not compiling on the other platform. A resource section is
    /// a PE idea -- ELF has none, and GLib's GResource is a different thing
    /// wearing a similar name.
    Result<IBitmapBackend, String> LoadBitmapResource(int id);

    IImageListBackend CreateImageList(Size imageSize);

    /// The theme's colour for one role, read now rather than cached, so a
    /// theme change between two calls is seen.
    Color SystemColor(SystemColorId which);

    /// The font the platform dresses its own dialogs in. What every control
    /// starts with, so a program that sets no fonts looks native.
    Font DefaultFont();

    /// The whole screen, in pixels.
    Size ScreenSize { get; }
    /// The part of it not covered by a task bar, which is what a window should
    /// be centred in and maximised to.
    Rectangle WorkArea { get; }

    // ------------------------------------------------------------ the loop

    /// Runs until the last window closes. What `Application.Run` calls.
    void RunEventLoop();
    /// Handles everything already queued and returns. For a program driving its
    /// own loop -- a game, an animation -- and the reason `RunEventLoop` is not
    /// the only way in.
    bool PumpEvents();
    /// Makes `RunEventLoop` return.
    void QuitEventLoop();

    /// Arranges for the UI thread to call `Application.Drain` soon.
    ///
    /// **Called from any thread**, and the only member of this interface of
    /// which that is true. Everything else here touches a widget and so belongs
    /// to the one thread that owns them; this exists precisely so that work on
    /// another thread has a way to ask for a turn on that one.
    ///
    /// The queue itself is not here. It is portable -- a list and a lock -- so
    /// it lives in `Application`, and all a backend owes is a way to make its
    /// loop turn.
    void Wake();

    // ---------------------------------------------------------- the common

    /// A message box, which every platform has and nobody wants to build.
    DialogResult ShowMessage(IWindowPeer? owner, String text, String caption,
                             MessageButtons buttons, MessageIcon icon);
}

/// Which platform this program is using.
///
/// **Set once, before any control is made.** `Application.Initialize` does it
/// by picking the backend compiled in, so a program never touches this; it is
/// public because a test that wants a recording backend, or a program that
/// supports two and chooses at run time, has nowhere else to say so.
public static class WidgetSet
{
    static IWidgetSet? s_current = null;

    /// The platform in use.
    ///
    /// Reading it before one is set is a program that built a control before
    /// `Application.Initialize`, and the message says so rather than letting a
    /// null reference happen three calls further on.
    public static IWidgetSet Current
    {
        get
        {
            var set = s_current;
            if (set == null)
            {
                sl_fail("no widget set: call Application.Initialize before making a control".ToPointer());
            }
            return (IWidgetSet)set;
        }
        set => s_current = value;
    }

    /// Whether one has been set, for code that must not trigger the failure
    /// above -- a destructor running during shutdown, most of all.
    public static bool IsReady => s_current != null;
}
