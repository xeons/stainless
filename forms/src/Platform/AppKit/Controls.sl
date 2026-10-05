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

// The standard controls on AppKit: a native control per peer, as the LCL's
// Cocoa widgetset does it.
//
// **Each native control is a subclass that reports first.** `FormsButton` is
// an `NSButton` that tells its peer of a press, a key and the focus before
// AppKit does what it does with them -- `TCocoaButton`'s arrangement. A click
// or a changed value arrives through AppKit's target and action, which the
// relay `FormsTarget` hands to the peer. AppKit raises neither when the
// program sets a value, which is the seam's rule without anything to guard.
//
// **A control's bounds are its visible shape**, not AppKit's frame, which
// leaves room around a bezel for a focus ring and a shadow. `frameForAlignmentRect:`
// turns one into the other, as `lclGetFrameToLayoutDelta` does.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

// ================================================================ relays

/// The target of a native control's action, handing it to the peer.
public objc class FormsTarget : NSObject
{
    public weak AppKitPeer? Peer;

    [Selector("act:")]
    public void Act(AnyObject? sender)
    {
        AppKitPeer? peer = Peer;
        if (peer != null)
            ((AppKitPeer)peer).ReportAction();
    }
}

/// Points a control's action at a relay for its peer, and answers the relay,
/// which the peer MUST keep: a control holds its target weakly.
FormsTarget ConnectAction(NSControl control, AppKitPeer peer)
{
    var relay = FormsTarget.Alloc().Init()!;
    relay.Peer = peer;
    control.Target = relay;
    control.Action = Selector.Named("act:");
    return relay;
}

// ================================================================ the subclasses

/// A push button, a check box, a radio button or a toggle.
///
/// AppKit's `mouseDown:` tracks the press until the release and only then
/// returns, swallowing the `mouseUp:`; the release is reported after it.
public objc class FormsButton : NSButton
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void MouseDown(NSEvent event)
    {
        var peer = FindPeer();
        if (peer != null)
            ((AppKitPeer)peer).ReportPress(event, FindEventPoint(this, event));
        base.MouseDown(event);
        if (peer != null)
            ((AppKitPeer)peer).ReportRelease(event, FindEventPoint(this, event));
    }

    public override void RightMouseDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPress(event, FindEventPoint(this, event));
        base.RightMouseDown(event);
    }

    public override void KeyDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, true);
        base.KeyDown(event);
    }

    public override void KeyUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, false);
        base.KeyUp(event);
    }

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }

    public override bool ResignFirstResponder()
    {
        bool given = base.ResignFirstResponder();
        if (given && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(false);
        return given;
    }
}

/// A label or a one-line entry. The keys of an entry being edited go to the
/// window's field editor rather than to this, so an entry hears them through
/// its delegate; see `FormsTextDelegate`.
public objc class FormsTextField : NSTextField
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void MouseDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPress(event, FindEventPoint(this, event));
        base.MouseDown(event);
    }

    public override void MouseUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportRelease(event, FindEventPoint(this, event));
        base.MouseUp(event);
    }

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }
}

/// The same, hiding what is typed.
public objc class FormsSecureTextField : NSSecureTextField
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }
}

/// What an entry's editing tells its peer: each change, the end of editing,
/// and the keys that are commands rather than text.
public objc class FormsTextDelegate : NSObject, NSTextFieldDelegate, NSTextViewDelegate
{
    public weak AppKitTextEntryPeer? Peer;

    AppKitTextEntryPeer? FindPeer()
    {
        AppKitTextEntryPeer? held = Peer;
        return held;
    }

    public override void ControlTextDidChange(NSNotification obj)
    {
        if (FindPeer() is AppKitTextEntryPeer peer)
            peer.ReportEdited();
    }

    public override void ControlTextDidEndEditing(NSNotification obj)
    {
        if (FindPeer() is AppKitTextEntryPeer peer)
            peer.ReportFocus(false);
    }

    public void TextDidChange(NSNotification notification)
    {
        if (FindPeer() is AppKitTextEntryPeer peer)
            peer.ReportEdited();
    }

    public bool ControlTextViewDoCommandBySelector(NSControl control, NSTextView textView, Selector commandSelector)
    {
        if (FindPeer() is AppKitTextEntryPeer peer)
            return peer.ReportCommand(commandSelector.Name);
        return false;
    }
}

/// A multiline entry's text, which hears its own keys.
public objc class FormsTextView : NSTextView
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void KeyDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, true);
        base.KeyDown(event);
    }

    public override void KeyUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, false);
        base.KeyUp(event);
    }

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }

    public override bool ResignFirstResponder()
    {
        bool given = base.ResignFirstResponder();
        if (given && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(false);
        return given;
    }
}

/// A slider, which tracks its own drag as a button does.
public objc class FormsSlider : NSSlider
{
    public weak AppKitPeer? Peer;

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void MouseDown(NSEvent event)
    {
        AppKitPeer? peer = Peer;
        if (peer != null)
            ((AppKitPeer)peer).ReportPress(event, FindEventPoint(this, event));
        base.MouseDown(event);
        if (peer != null)
            ((AppKitPeer)peer).ReportRelease(event, FindEventPoint(this, event));
    }
}

// ================================================================ the peers

/// What every native control's peer has: the action, the font, and bounds
/// that are the control's visible shape.
public class AppKitControlPeer : AppKitPeer
{
    FormsTarget? _relay;

    public AppKitControlPeer(NSControl made, IControlNotify owner)
    {
        base(made, owner);
        _relay = null;
    }

    protected NSControl Control => (NSControl)View;

    /// Sends the control's action to `ReportAction`.
    protected void ListenForAction() => _relay = ConnectAction(Control, this);

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        if (_relay is FormsTarget relay)
            relay.Peer = null;
    }

    public override void SetBounds(FRect bounds)
    {
        LastBounds = bounds;
        View.Frame = View.FrameForAlignmentRect(ToNSRect(bounds));
    }

    public override void SetEnabled(bool enabled) => Control.Enabled = enabled;

    public override void SetFont(Forms.Drawing.Font font) => Control.Font = ((AppKitFontBackend)font.Resource).Font;

    public override bool AcceptsTabFocus => !View.Hidden && Control.Enabled && View.AcceptsFirstResponder;

    /// What AppKit thinks the control ought to be, as a visible shape.
    public override FSize PreferredSize
    {
        get
        {
            var fitting = View.FittingSize;
            var shape = View.AlignmentRectForFrame(MakeNSRect(0.0, 0.0, fitting.width, fitting.height));
            return CreateSize(RoundToInt(shape.size.width), RoundToInt(shape.size.height));
        }
    }
}

// ----------------------------------------------------------------- buttons

public class AppKitButtonPeer : AppKitControlPeer, IPushButtonPeer
{
    FormsButton _button;
    ImageAlignment _imageAlign = ImageAlignment.Left;

    public AppKitButtonPeer(IControlNotify owner)
    {
        base(FormsButton.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 80.0, 24.0)), owner);
        var made = (FormsButton)View;
        _button = made;
        _button.Peer = this;
        _button.SetButtonType(NSButtonType.MomentaryPushIn);
        _button.BezelStyle = NSBezelStyle.Push;
        ListenForAction();
    }

    public override void ReportAction()
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformActivated();
    }

    /// A push button's bezel is a fixed height, and one taller than it is
    /// drawn flexible instead, so the bounds asked for are the bounds drawn.
    public override void SetBounds(FRect bounds)
    {
        _button.BezelStyle = bounds.Height > 28 ? NSBezelStyle.FlexiblePush : NSBezelStyle.Push;
        base.SetBounds(bounds);
    }

    public override void SetText(String text) => _button.Title = ToNSString(text);
    public override String GetText() => FromNSString(_button.Title);

    /// Return presses it, which AppKit does for the button whose key
    /// equivalent it is -- one per window, as the seam asks.
    public void SetDefault(bool isDefault) => _button.KeyEquivalent = ToNSString(isDefault ? "\r" : "");

    public void SetImage(IBitmapBackend? picture)
    {
        if (picture == null)
        {
            _button.Image = null;
            return;
        }
        var image = (AppKitBitmapBackend)picture;
        NSSize size;
        size.width = (double)image.Width;
        size.height = (double)image.Height;
        _button.Image = NSImage.Alloc().InitWithCGImageSize(image.Image, size);
        SetImageAlign(_imageAlign);
    }

    /// Where the picture sits beside the caption. AppKit's own default for a
    /// button given a picture is the picture alone, so this is applied with
    /// every picture as well as when it is asked for.
    public void SetImageAlign(ImageAlignment place)
    {
        _imageAlign = place;
        switch (place)
        {
            case ImageAlignment.Right: _button.ImagePosition = NSCellImagePosition.ImageRight; break;
            case ImageAlignment.Top: _button.ImagePosition = NSCellImagePosition.ImageAbove; break;
            case ImageAlignment.Bottom: _button.ImagePosition = NSCellImagePosition.ImageBelow; break;
            default: _button.ImagePosition = NSCellImagePosition.ImageLeft; break;
        }
    }

    /// AppKit spaces a button's picture from its title by its own rule.
    public void SetImageSpacing(int gap) { }
}

public class AppKitCheckPeer : AppKitControlPeer, ICheckPeer
{
    FormsButton _button;
    CheckKind _kind;

    public AppKitCheckPeer(IControlNotify owner, CheckKind kind)
    {
        base(FormsButton.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 100.0, 24.0)), owner);
        var made = (FormsButton)View;
        _button = made;
        _button.Peer = this;
        _kind = kind;
        switch (kind)
        {
            case CheckKind.Radio:
                _button.SetButtonType(NSButtonType.Radio);
                break;
            case CheckKind.Toggle:
                _button.SetButtonType(NSButtonType.PushOnPushOff);
                _button.BezelStyle = NSBezelStyle.Push;
                break;
            default:
                _button.SetButtonType(NSButtonType.Switch);
                break;
        }
        ListenForAction();
    }

    /// A radio button reports only becoming the one chosen; AppKit unticks its
    /// siblings -- those in the same view with the same action -- itself.
    public override void ReportAction()
    {
        var owner = Owner;
        if (owner == null || (_kind == CheckKind.Radio && !GetChecked()))
            return;
        ((IControlNotify)owner).OnPlatformValueChanged();
        ((IControlNotify)owner).OnPlatformActivated();
    }

    public override void SetText(String text) => _button.Title = ToNSString(text);
    public override String GetText() => FromNSString(_button.Title);

    public void SetChecked(bool checked) =>
        _button.State = checked ? 1 : 0;

    public bool GetChecked() => _button.State == 1;

    public void SetDefault(bool isDefault) { }
}

// ------------------------------------------------------------------ label

public class AppKitLabelPeer : AppKitControlPeer, ILabelPeer
{
    FormsTextField _field;

    public AppKitLabelPeer(IControlNotify owner)
    {
        base(FormsTextField.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 80.0, 16.0)), owner);
        var made = (FormsTextField)View;
        _field = made;
        _field.Peer = this;
        _field.Editable = false;
        _field.Selectable = false;
        _field.Bezeled = false;
        _field.Bordered = false;
        _field.DrawsBackground = false;
        SetWordWrap(false);
    }

    public override void SetText(String text) => _field.StringValue = ToNSString(text);
    public override String GetText() => FromNSString(_field.StringValue);

    public override void SetForeColor(Color color) => _field.TextColor = ToNSColor(color);

    /// A label shows what is behind it, as one does everywhere else.
    public override void SetBackColor(Color color) { }

    public override bool AcceptsTabFocus => false;

    public void SetAlignment(HorizontalAlignment alignment)
    {
        switch (alignment)
        {
            case HorizontalAlignment.Center: _field.Alignment = NSTextAlignment.Center; break;
            case HorizontalAlignment.Right: _field.Alignment = NSTextAlignment.Right; break;
            default: _field.Alignment = NSTextAlignment.Left; break;
        }
    }

    /// Several lines broken at words, or one cut short with an ellipsis.
    public void SetWordWrap(bool wrap)
    {
        _field.UsesSingleLineMode = !wrap;
        _field.MaximumNumberOfLines = wrap ? 0 : 1;
        _field.LineBreakMode = wrap ? NSLineBreakMode.WordWrapping : NSLineBreakMode.TruncatingTail;
    }
}

// ------------------------------------------------------------------ entry

/// A text box: an `NSTextField`, or for several lines an `NSTextView` in a
/// scroll view.
///
/// **Masking changes the class.** AppKit hides typing with a different
/// control, `NSSecureTextField`, so a password character set after the box is
/// made puts one of those where the field was, carrying its text and its
/// settings across.
public class AppKitTextEntryPeer : AppKitPeer, ITextEntryPeer
{
    bool _multiline;
    NSTextField? _field;
    FormsTextView? _text;
    FormsTextDelegate _delegate;
    FormsTarget? _relay;
    int _maxLength;
    bool _readOnly;

    public AppKitTextEntryPeer(IControlNotify owner, bool multiline)
    {
        base(CreateEntryView(multiline), owner);
        _multiline = multiline;
        _maxLength = 0;
        _readOnly = false;
        _delegate = FormsTextDelegate.Alloc().Init()!;
        _delegate.Peer = this;

        if (multiline)
        {
            var text = (FormsTextView)((NSScrollView)View).DocumentView!;
            text.Peer = this;
            text.Delegate = _delegate;
            _text = text;
            _field = null;
        }
        else
        {
            var field = (FormsTextField)View;
            field.Peer = this;
            AdoptField(field);
            _text = null;
        }
    }

    static NSView CreateEntryView(bool multiline)
    {
        if (!multiline)
            return FormsTextField.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 22.0));

        var scroller = NSScrollView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 80.0));
        scroller.HasVerticalScroller = true;
        scroller.BorderType = NSBorderType.BezelBorder;
        var text = FormsTextView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 80.0));
        text.VerticallyResizable = true;
        text.HorizontallyResizable = false;
        text.AutoresizingMask = NSAutoresizingMaskOptions.WidthSizable;
        text.RichText = false;
        scroller.DocumentView = text;
        return scroller;
    }

    void AdoptField(NSTextField field)
    {
        field.Editable = !_readOnly;
        field.Selectable = true;
        field.Bezeled = true;
        field.UsesSingleLineMode = true;
        field.Delegate = _delegate;
        _relay = ConnectAction(field, this);
        _field = field;
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _delegate.Peer = null;
        if (_relay is FormsTarget relay)
            relay.Peer = null;
        if (_field is NSTextField field)
            ForgetPeer(field);
        if (_text is FormsTextView text)
            text.Peer = null;
    }

    /// Return in a one-line box, which AppKit sends as the action.
    public override void ReportAction()
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformActivated();
    }

    public void ReportEdited()
    {
        if (_maxLength > 0 && !_multiline)
        {
            String now = GetText();
            nuint end = 0u;
            for (int kept = 0; kept < _maxLength && end < now.ByteLength(); kept++)
                end = now.SkipCodePoint(end);
            if (end < now.ByteLength())
                SetText(now.Substring(0u, end));
        }
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    /// The keys a field editor treats as commands, reported as the keys they
    /// are. Tab moves the focus in the form's order and is taken; the rest go
    /// on to AppKit.
    public bool ReportCommand(String command)
    {
        var owner = Owner;
        if (owner == null)
            return false;
        var notify = (IControlNotify)owner;
        switch (command)
        {
            case "insertNewline:":
                notify.OnPlatformKeyDown(Key.Enter, ModifierKeys.None);
                return false;
            case "cancelOperation:":
                notify.OnPlatformKeyDown(Key.Escape, ModifierKeys.None);
                return false;
            case "moveUp:":
                notify.OnPlatformKeyDown(Key.Up, ModifierKeys.None);
                return false;
            case "moveDown:":
                notify.OnPlatformKeyDown(Key.Down, ModifierKeys.None);
                return false;
            case "insertTab:":
            case "insertBacktab:":
                notify.OnPlatformKeyDown(Key.Tab, command == "insertBacktab:" ? ModifierKeys.Shift : ModifierKeys.None);
                return NavigateFromHere(command == "insertBacktab:");
            default:
                return false;
        }
    }

    public override void SetText(String text)
    {
        var field = _field;
        if (field != null)
            ((NSTextField)field).StringValue = ToNSString(text);
        else if (_text is FormsTextView view)
            view.String = ToNSString(text);
    }

    public override String GetText()
    {
        var field = _field;
        if (field != null)
            return FromNSString(((NSTextField)field).StringValue);
        if (_text is FormsTextView view)
            return FromNSString(view.String);
        return "";
    }

    public override void SetFont(Forms.Drawing.Font font)
    {
        var shown = ((AppKitFontBackend)font.Resource).Font;
        var field = _field;
        if (field != null)
            ((NSTextField)field).Font = shown;
        else if (_text is FormsTextView view)
            view.Font = shown;
    }

    public override void SetForeColor(Color color)
    {
        var field = _field;
        if (field != null)
            ((NSTextField)field).TextColor = ToNSColor(color);
        else if (_text is FormsTextView view)
            view.TextColor = ToNSColor(color);
    }

    public override void SetBackColor(Color color)
    {
        var field = _field;
        if (field != null)
        {
            ((NSTextField)field).DrawsBackground = true;
            ((NSTextField)field).BackgroundColor = ToNSColor(color);
        }
        else if (_text is FormsTextView view)
        {
            view.BackgroundColor = ToNSColor(color);
        }
    }

    public override void SetEnabled(bool enabled)
    {
        var field = _field;
        if (field != null)
            ((NSTextField)field).Enabled = enabled;
        else if (_text is FormsTextView view)
            view.Editable = enabled && !_readOnly;
    }

    public override void SetBounds(FRect bounds)
    {
        LastBounds = bounds;
        View.Frame = View.FrameForAlignmentRect(ToNSRect(bounds));
    }

    public override void Focus()
    {
        var window = View.Window;
        if (window == null)
            return;
        var field = _field;
        if (field != null)
            ((NSWindow)window).MakeFirstResponder((NSTextField)field);
        else if (_text is FormsTextView view)
            ((NSWindow)window).MakeFirstResponder(view);
    }

    public override bool AcceptsTabFocus => !View.Hidden;

    // -------------------------------------------------------- ITextEntryPeer

    public void SetReadOnly(bool readOnly)
    {
        _readOnly = readOnly;
        var field = _field;
        if (field != null)
            ((NSTextField)field).Editable = !readOnly;
        else if (_text is FormsTextView view)
            view.Editable = !readOnly;
    }

    public void SetMaxLength(int length) => _maxLength = length;

    /// Masked or not; AppKit has one bullet, so which character is not asked.
    public void SetPasswordChar(char mask)
    {
        var field = _field;
        if (_multiline || field == null)
            return;
        bool secure = (NSTextField)field is NSSecureTextField;
        if (secure == (mask != (char)0))
            return;

        var old = (NSTextField)field;
        NSTextField made;
        if (mask != (char)0)
        {
            var hidden = FormsSecureTextField.Alloc().InitWithFrame(old.Frame);
            hidden.Peer = this;
            made = hidden;
        }
        else
        {
            var shown = FormsTextField.Alloc().InitWithFrame(old.Frame);
            shown.Peer = this;
            made = shown;
        }
        made.StringValue = old.StringValue;
        made.Font = old.Font;
        made.Enabled = old.Enabled;
        AdoptField(made);
        var parent = old.Superview;
        if (parent != null)
            ((NSView)parent).ReplaceSubviewWith(old, made);
        View = made;
    }

    /// The selection as the field editor or the text view holds it, in
    /// UTF-16 units, which a String is not counted in beyond the basic plane.
    NSText? FindEditor()
    {
        var field = _field;
        if (field != null)
            return ((NSTextField)field).CurrentEditor();
        if (_text is FormsTextView view)
            return view;
        return null;
    }

    public void SetSelection(int start, int length)
    {
        var editor = FindEditor();
        if (editor == null)
        {
            Focus();
            editor = FindEditor();
            if (editor == null)
                return;
        }
        NSRange range;
        range.location = (nuint)start;
        range.length = (nuint)length;
        ((NSText)editor).SelectedRange = range;
    }

    public (int, int) GetSelection()
    {
        var editor = FindEditor();
        if (editor == null)
            return (0, 0);
        var range = ((NSText)editor).SelectedRange;
        return ((int)range.location, (int)range.length);
    }

    /// Fixed when it is made, as on Windows; see `TextBox`.
    public void SetMultiline(bool multiline) { }

    public String[] GetLines()
    {
        String text = GetText();
        if (!_multiline)
            return [text];
        return text.Split("\n");
    }

    public void SetLines(String[] lines) => SetText("\n".Join(lines));

    public void CutToClipboard()
    {
        if (!_readOnly && FindEditorFocused() is NSText editor)
            editor.Cut(null);
    }

    public void CopyToClipboard()
    {
        if (FindEditorFocused() is NSText editor)
            editor.Copy(null);
    }

    public void PasteFromClipboard()
    {
        if (!_readOnly && FindEditorFocused() is NSText editor)
            editor.Paste(null);
    }

    NSText? FindEditorFocused()
    {
        if (FindEditor() == null)
            Focus();
        return FindEditor();
    }
}

// ------------------------------------------------------------------ group

/// A group box: an `NSBox` whose content is a flipped view the children go in.
///
/// **A child's bounds arrive measured from the box's corner**, with
/// `ClientOrigin` already added, as Win32 wants them for a group box whose
/// children are its own windows. Here they go in the content view, so that
/// view's own coordinates are moved by the same origin: a child placed at the
/// box's (8, 30) lands at (8, 8) inside the frame.
public class AppKitGroupPeer : AppKitContainerPeer, IGroupPeer
{
    NSBox _box;
    FormsView _content;

    public AppKitGroupPeer(IControlNotify owner)
    {
        base(NSBox.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 160.0, 96.0)), owner);
        var box = (NSBox)View;
        _box = box;
        _box.BoxType = NSBoxType.Primary;
        _box.TitlePosition = NSTitlePosition.AtTop;
        _content = CreateFormsView();
        _content.Peer = this;
        _content.TrackPointer();
        _box.ContentView = _content;
        ApplyOrigin();
    }

    protected override NSView Content => _content;

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _content.Peer = null;
    }

    /// Moves the content's coordinates by where it sits in the box, which
    /// changes whenever the box is resized.
    void ApplyOrigin()
    {
        var origin = ClientOrigin;
        NSPoint shifted;
        shifted.x = (double)origin.X;
        shifted.y = (double)origin.Y;
        _content.SetBoundsOrigin(shifted);
    }

    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        ApplyOrigin();
    }

    public override void SetText(String text) => _box.Title = ToNSString(text);
    public override String GetText() => FromNSString(_box.Title);

    public override void SetBackColor(Color color) { }

    public override bool AcceptsTabFocus => false;

    /// The room inside the frame and below the caption.
    public override FRect ClientBounds
    {
        get
        {
            var inside = _content.Bounds;
            return CreateRectangle(0, 0, RoundToInt(inside.size.width), RoundToInt(inside.size.height));
        }
    }

    /// Where that room begins, measured down from the box's top: AppKit
    /// places the content up from the bottom.
    public override FPoint ClientOrigin
    {
        get
        {
            var inside = _content.Frame;
            var outside = _box.Bounds;
            return CreatePoint(RoundToInt(inside.origin.x),
                               RoundToInt(outside.size.height - inside.origin.y - inside.size.height));
        }
    }
}

// ------------------------------------------------------------------ ranges

public class AppKitProgressPeer : AppKitPeer, IProgressPeer
{
    NSProgressIndicator _bar;

    public AppKitProgressPeer(IControlNotify owner)
    {
        base(NSProgressIndicator.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 160.0, 20.0)), owner);
        var made = (NSProgressIndicator)View;
        _bar = made;
        _bar.Style = NSProgressIndicatorStyle.Bar;
        _bar.Indeterminate = false;
        _bar.MinValue = 0.0;
        _bar.MaxValue = 100.0;
    }

    public void SetRange(int minimum, int maximum)
    {
        _bar.MinValue = (double)minimum;
        _bar.MaxValue = (double)maximum;
    }

    public void SetValue(int value) => _bar.DoubleValue = (double)value;
    public int GetValue() => RoundToInt(_bar.DoubleValue);

    public void SetIndeterminate(bool indeterminate)
    {
        _bar.Indeterminate = indeterminate;
        if (indeterminate)
            _bar.StartAnimation(null);
        else
            _bar.StopAnimation(null);
    }

    public override bool AcceptsTabFocus => false;
}

public class AppKitTrackBarPeer : AppKitControlPeer, ITrackBarPeer
{
    FormsSlider _slider;
    int _every;

    public AppKitTrackBarPeer(IControlNotify owner, bool vertical)
    {
        base(FormsSlider.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 160.0, 24.0)), owner);
        var made = (FormsSlider)View;
        _slider = made;
        _slider.Peer = this;
        _slider.Vertical = vertical;
        _slider.MinValue = 0.0;
        _slider.MaxValue = 10.0;
        _slider.Continuous = true;
        _every = 1;
        ListenForAction();
        ApplyTicks();
    }

    /// Each step of the drag, as a whole number.
    public override void ReportAction()
    {
        _slider.DoubleValue = (double)GetValue();
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    public void SetRange(int minimum, int maximum)
    {
        _slider.MinValue = (double)minimum;
        _slider.MaxValue = (double)maximum;
        ApplyTicks();
    }

    public void SetValue(int value) => _slider.DoubleValue = (double)value;
    public int GetValue() => RoundToInt(_slider.DoubleValue);

    public void SetTickFrequency(int every)
    {
        _every = every < 1 ? 1 : every;
        ApplyTicks();
    }

    /// A tick every `_every`, the ends included, and no more than AppKit can
    /// draw apart.
    void ApplyTicks()
    {
        int span = RoundToInt(_slider.MaxValue - _slider.MinValue);
        int count = span / _every + 1;
        _slider.NumberOfTickMarks = count > 100 ? 0 : count;
    }
}

/// A number with arrows: a field and a stepper, side by side in one view.
public class AppKitSpinPeer : AppKitContainerPeer, ISpinPeer
{
    FormsTextField _field;
    NSStepper _stepper;
    FormsTarget _fieldRelay;
    FormsTarget _stepperRelay;
    int _minimum;
    int _maximum;
    int _value;

    public AppKitSpinPeer(IControlNotify owner)
    {
        base(CreateFormsView(), owner);
        _minimum = 0;
        _maximum = 100;
        _value = 0;

        _field = FormsTextField.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 60.0, 22.0));
        _field.Peer = this;
        _field.Bezeled = true;
        _field.Editable = true;
        _field.UsesSingleLineMode = true;
        _fieldRelay = ConnectAction(_field, this);
        View.AddSubview(_field);

        _stepper = NSStepper.Alloc().InitWithFrame(MakeNSRect(60.0, 0.0, 19.0, 22.0));
        _stepper.Increment = 1.0;
        _stepper.ValueWraps = false;
        _stepper.Autorepeat = true;
        _stepperRelay = FormsTarget.Alloc().Init()!;
        _stepperRelay.Peer = this;
        _stepper.Target = _stepperRelay;
        _stepper.Action = Selector.Named("act:");
        View.AddSubview(_stepper);
        ApplyValue();
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _field.Peer = null;
        _fieldRelay.Peer = null;
        _stepperRelay.Peer = null;
    }

    /// Either half acted: the stepper stepped, or Return was pressed in the
    /// field. Whichever it was, the other half is brought into line.
    public override void ReportAction()
    {
        int was = _value;
        var typed = Standard.Convert.ToInt(FromNSString(_field.StringValue).Trim());
        int stepped = RoundToInt(_stepper.DoubleValue);
        _value = stepped != was ? stepped : typed.Ok ? typed.Value : was;
        ApplyValue();
        var owner = Owner;
        if (_value != was && owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    void ApplyValue()
    {
        if (_value < _minimum)
            _value = _minimum;
        if (_value > _maximum)
            _value = _maximum;
        _stepper.MinValue = (double)_minimum;
        _stepper.MaxValue = (double)_maximum;
        _stepper.DoubleValue = (double)_value;
        _field.StringValue = ToNSString(Standard.Text.FromInteger(_value));
    }

    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        double arrows = 19.0;
        double width = (double)bounds.Width - arrows - 2.0;
        _field.Frame = _field.FrameForAlignmentRect(MakeNSRect(0.0, 0.0, width < 0.0 ? 0.0 : width, (double)bounds.Height));
        _stepper.Frame = _stepper.FrameForAlignmentRect(MakeNSRect((double)bounds.Width - arrows, 0.0, arrows,
                                                                   (double)bounds.Height));
    }

    public override void SetFont(Forms.Drawing.Font font) => _field.Font = ((AppKitFontBackend)font.Resource).Font;

    public override void SetEnabled(bool enabled)
    {
        _field.Enabled = enabled;
        _stepper.Enabled = enabled;
    }

    public override void Focus()
    {
        var window = View.Window;
        if (window != null)
            ((NSWindow)window).MakeFirstResponder(_field);
    }

    public override bool AcceptsTabFocus => !View.Hidden && _field.Enabled;

    public void SetRange(int minimum, int maximum)
    {
        _minimum = minimum;
        _maximum = maximum;
        ApplyValue();
    }

    public void SetValue(int value)
    {
        _value = value;
        ApplyValue();
    }

    public int GetValue() => _value;
}

/// A scroll bar standing alone: an `NSScroller`, which has a position from 0
/// to 1 and a knob's share of the track rather than a value, so the range is
/// kept here and each part the user hit is turned into a step -- as the LCL
/// does with `TCocoaScrollBar`.
public class AppKitScrollBarPeer : AppKitControlPeer, IScrollBarPeer
{
    NSScroller _scroller;
    int _minimum;
    int _maximum;
    int _page;
    int _value;

    public AppKitScrollBarPeer(IControlNotify owner, bool vertical)
    {
        base(NSScroller.Alloc().InitWithFrame(vertical ? MakeNSRect(0.0, 0.0, 15.0, 100.0)
                                                             : MakeNSRect(0.0, 0.0, 100.0, 15.0)), owner);
        var made = (NSScroller)View;
        _scroller = made;
        _scroller.ScrollerStyle = NSScrollerStyle.Legacy;
        _scroller.Enabled = true;
        _minimum = 0;
        _maximum = 100;
        _page = 10;
        _value = 0;
        ListenForAction();
        ApplyPosition();
    }

    public override void ReportAction()
    {
        int was = _value;
        switch (_scroller.HitPart)
        {
            case NSScrollerPart.DecrementPage: _value -= _page; break;
            case NSScrollerPart.IncrementPage: _value += _page; break;
            case NSScrollerPart.Knob:
            case NSScrollerPart.KnobSlot:
            {
                int travel = _maximum + 1 - _page - _minimum;
                _value = _minimum + RoundToInt(_scroller.DoubleValue * (double)(travel < 0 ? 0 : travel));
                break;
            }
            default: break;
        }
        ApplyPosition();
        var owner = Owner;
        if (_value != was && owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    void ApplyPosition()
    {
        int travel = _maximum + 1 - _page - _minimum;
        if (_value > _minimum + travel)
            _value = _minimum + travel;
        if (_value < _minimum)
            _value = _minimum;
        int span = _maximum + 1 - _minimum;
        _scroller.KnobProportion = span <= 0 ? 1.0 : (double)_page / (double)span;
        _scroller.DoubleValue = travel <= 0 ? 0.0 : (double)(_value - _minimum) / (double)travel;
    }

    public void SetRange(int minimum, int maximum, int pageSize)
    {
        _minimum = minimum;
        _maximum = maximum;
        _page = pageSize < 1 ? 1 : pageSize;
        ApplyPosition();
    }

    public void SetValue(int value)
    {
        _value = value;
        ApplyPosition();
    }

    public int GetValue() => _value;

    public override bool AcceptsTabFocus => false;
}

#endif
