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

// The clipboard, which every program shares and no program owns.
module Forms;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;

/// What Ctrl+C put somewhere and Ctrl+V takes back.
///
/// ```
/// Clipboard.SetText(editor.SelectedText);
/// if (Clipboard.HasText)
///     editor.TypeText(Clipboard.GetText());
/// ```
///
/// **Four formats both platforms convert for themselves, and any a program
/// names.** Text, HTML, a picture and a list of files each have a `Get`, a
/// `Set` and a `Has`; `SetData` and `GetData` carry bytes under a name of the
/// program's choosing, which is how two copies of one program pass something
/// richer than text between them. A name is a MIME type by convention --
/// `application/x-myapp-shapes` -- because that is what GTK calls a format,
/// and Windows accepts any string.
///
/// **Each `Set` replaces everything.** A clipboard holds several formats at
/// once only when they are put there together, which is what `Set` with a
/// `ClipboardData` is for: text for a plain editor, HTML for a word processor,
/// and the program's own format for itself, all from one copy.
///
/// **Static, because there is one.** `TClipboard` in the LCL is an object with
/// a global instance, and C#'s `Clipboard` is static; the second is the honest
/// spelling of the first, since a second instance would refer to the same
/// desktop-wide thing as the first. The one thing here that is an object is
/// `ClipboardWatcher`, because a subscription has a lifetime.
///
/// **Every call can fail quietly, and none of them says so.** On Windows the
/// clipboard is a lock another process may be holding; on X11 it lives in
/// whichever client last claimed it, and reading one is a round trip to a
/// program that may have exited. A failed read answers something empty and a
/// failed write does nothing, because there is no answer a caller could
/// usefully act on -- a text editor whose paste failed has nothing to offer the
/// user but the paste they already asked for.
///
/// Not the X11 primary selection. Select-to-copy and middle-click paste are a
/// second clipboard with rules of their own, GTK's entries already take part
/// in it, and Windows has nothing to map it on to.
public class Clipboard
{
    /// Not constructible: everything here is static, and an instance would
    /// suggest there could be two clipboards.
    Clipboard() { }

    // ------------------------------------------------------------------ text

    /// What the clipboard holds as text, or `""` when it holds none.
    ///
    /// `""` rather than a null: a paste of nothing and a paste of an empty
    /// string do the same thing, so a caller that had to tell them apart would
    /// only be writing the test twice.
    public static String GetText() => WidgetSet.Current.GetClipboardText();

    /// Puts text on the clipboard, replacing whatever was there.
    public static void SetText(String text)
    {
        var content = new ClipboardContent();
        content.Text = text;
        WidgetSet.Current.SetClipboard(content);
    }

    /// Whether there is text to be had.
    ///
    /// What a paste command greys itself out on. Cheaper than fetching the text
    /// on both platforms -- and on X11 much cheaper, since it does not wait for
    /// another process to hand the contents over.
    public static bool HasText => WidgetSet.Current.ContainsClipboardKind(ClipboardKind.Text);

    // ------------------------------------------------------------------ HTML

    /// The HTML fragment that was copied, or `""`.
    ///
    /// The fragment and not a document: what a browser copies from the middle
    /// of a page is the markup of the selection, and Windows' wrapping of it in
    /// `<html>` and a header of byte offsets is taken off.
    public static String GetHtml() => WidgetSet.Current.GetClipboardHtml();

    /// Puts an HTML fragment on the clipboard with the same content as plain
    /// text beside it, for a program that cannot read markup.
    ///
    /// The plain text is the caller's to write, because turning markup into
    /// text is a judgement: a table can become tabs or lines, a link its text
    /// or its address.
    public static void SetHtml(String html, String plainText)
    {
        var content = new ClipboardContent();
        content.Html = html;
        content.Text = plainText;
        WidgetSet.Current.SetClipboard(content);
    }

    /// Puts an HTML fragment on the clipboard and nothing else.
    public static void SetHtml(String html)
    {
        var content = new ClipboardContent();
        content.Html = html;
        WidgetSet.Current.SetClipboard(content);
    }

    public static bool HasHtml => WidgetSet.Current.ContainsClipboardKind(ClipboardKind.Html);

    // -------------------------------------------------------------- pictures

    /// The picture on the clipboard, or null when there is none.
    ///
    /// Also null where there is no imaging library to hold it in; `GetBitmap`
    /// needs none, and is what a program that only shows the picture wants.
    public static Standard.Drawing.Image? GetImage()
    {
        var found = WidgetSet.Current.GetClipboardImage();
        if (found == null)
            return null;

        var picture = (ClipboardImage)found;
        var made = Standard.Drawing.Image.FromBgra(picture.Width, picture.Height,
                                                   picture.Pixels);
        if (!made.Ok)
            return null;
        return made.Value;
    }

    /// The picture on the clipboard as the widget set holds one, ready for an
    /// `Image` control, or null when there is none.
    public static Bitmap? GetBitmap()
    {
        var found = WidgetSet.Current.GetClipboardImage();
        if (found == null)
            return null;

        var picture = (ClipboardImage)found;
        var made = Bitmap.FromPixels(picture.Width, picture.Height, picture.Pixels);
        if (!made.Ok)
            return null;
        return made.Value;
    }

    /// Puts a picture on the clipboard, transparency included.
    ///
    /// An `Image` rather than a `Bitmap`, because a `Bitmap` is the toolkit's
    /// and can be drawn but not read back.
    public static void SetImage(Standard.Drawing.Image picture)
    {
        var data = new ClipboardData();
        data.Picture = picture;
        SetDataObject(data);
    }

    public static bool HasImage => WidgetSet.Current.ContainsClipboardKind(ClipboardKind.Image);

    // ----------------------------------------------------------------- files

    /// The files that were copied, as absolute paths, or an empty array.
    ///
    /// What Explorer's and a Linux file manager's Copy put there. Names only:
    /// nothing is read, and a file may be gone by the time it is pasted.
    public static String[] GetFiles() => WidgetSet.Current.GetClipboardFiles();

    /// Puts files on the clipboard for a file manager to paste as copies.
    ///
    /// The paths MUST be absolute. A relative one means nothing to the program
    /// that pastes it, which has a working directory of its own, and GTK
    /// cannot turn one into a `file:` URI at all.
    public static void SetFiles(String[] paths)
    {
        var content = new ClipboardContent();
        content.Files = paths;
        WidgetSet.Current.SetClipboard(content);
    }

    public static bool HasFiles => WidgetSet.Current.ContainsClipboardKind(ClipboardKind.Files);

    // ------------------------------------------------------ a program's own

    /// The bytes on the clipboard under `format`, or an empty array.
    ///
    /// On Windows the array MAY be longer than what was put there: the
    /// clipboard hands back a memory block, and a block's size is rounded up.
    /// A format that must know its own length says so inside its bytes.
    public static byte[] GetData(String format) => WidgetSet.Current.GetClipboardFormat(format);

    /// Puts bytes on the clipboard under a name of the program's choosing,
    /// replacing whatever was there.
    public static void SetData(String format, byte[] data)
    {
        var content = new ClipboardContent();
        content.Custom.Add(new ClipboardEntry(format, data));
        WidgetSet.Current.SetClipboard(content);
    }

    /// Whether something is on offer under `format`.
    public static bool HasFormat(String format) =>
        WidgetSet.Current.ContainsClipboardFormat(format);

    // ------------------------------------------------------------ everything

    /// Replaces the clipboard with every format `data` holds, in one copy.
    ///
    /// ```
    /// var data = new ClipboardData();
    /// data.Text = "3 shapes";
    /// data.Html = "<b>3</b> shapes";
    /// data.SetData("application/x-shapes", Serialise(selection));
    /// Clipboard.SetDataObject(data);
    /// ```
    public static void SetDataObject(ClipboardData data) =>
        WidgetSet.Current.SetClipboard(data.ToContent());

    /// Empties the clipboard, whichever program filled it.
    public static void Clear() => WidgetSet.Current.SetClipboard(new ClipboardContent());

    /// The name of every format on offer, as the platform spells it --
    /// `CF_UNICODETEXT` and `HTML Format` on Windows, `UTF8_STRING` and
    /// `text/html` on GTK.
    ///
    /// For a program that wants to show what it could paste, and for finding
    /// out what name another program's format goes by. A method rather than a
    /// property because it is a question for another process.
    public static String[] GetFormats() => WidgetSet.Current.GetClipboardFormatNames();
}

/// Several formats for one copy.
///
/// Each is absent until set, and `Clipboard.SetDataObject` puts on every one
/// that is present. The data is copied out when it is set on the clipboard, so
/// a `ClipboardData` may be reused or changed afterwards.
public sealed class ClipboardData
{
    List<ClipboardEntry> _custom;

    public ClipboardData()
    {
        Text = null;
        Html = null;
        Picture = null;
        Files = new String[0u];
        _custom = new List<ClipboardEntry>();
    }

    public String? Text { get; set; }

    /// A fragment, as `Clipboard.SetHtml` takes.
    public String? Html { get; set; }

    public Standard.Drawing.Image? Picture { get; set; }

    /// Absolute paths, as `Clipboard.SetFiles` takes. Empty for none.
    public String[] Files { get; set; }

    /// Adds bytes under a name of the program's choosing. Setting a name a
    /// second time replaces the bytes.
    public void SetData(String format, byte[] data)
    {
        for (nuint i = 0u; i < _custom.Count; i++)
        {
            if (_custom[i].Name == format)
            {
                _custom[i] = new ClipboardEntry(format, data);
                return;
            }
        }
        _custom.Add(new ClipboardEntry(format, data));
    }

    /// Whether nothing has been set.
    public bool IsEmpty => Text == null && Html == null && Picture == null
                           && Files.Length == 0u && _custom.Count == 0u;

    /// What the widget set is handed.
    ClipboardContent ToContent()
    {
        var content = new ClipboardContent();
        content.Text = Text;
        content.Html = Html;
        content.Files = Files;

        var picture = Picture;
        if (picture != null)
        {
            var image = (Standard.Drawing.Image)picture;
            var pixels = image.ToBgra();
            if (pixels.Length != 0u)
                content.Image = new ClipboardImage(image.Width, image.Height, pixels);
        }

        for (nuint i = 0u; i < _custom.Count; i++)
            content.Custom.Add(_custom[i]);
        return content;
    }
}

/// Reports every change to the clipboard's contents, by this program or any
/// other, for as long as it is held.
///
/// ```
/// _watcher = new ClipboardWatcher();
/// _watcher.Changed += this.OnClipboardChanged;
/// ```
///
/// **An object and not a static event**, because a static event's subscribers
/// would outlive everything that subscribed -- the language refuses one for
/// that reason. A watcher that nothing holds is released, and stops.
///
/// A copy this program makes is reported too, since it is a change like any
/// other. The event says only that something changed; what the clipboard holds
/// now is `Clipboard`'s to answer.
public class ClipboardWatcher : IClipboardNotify
{
    IClipboardWatchPeer _peer;
    bool _enabled;

    /// A watcher that is already watching.
    public ClipboardWatcher()
    {
        _enabled = false;
        _peer = WidgetSet.Current.CreateClipboardWatch(this);
        Start();
    }

    public bool Enabled
    {
        get => _enabled;
        set
        {
            if (value)
            {
                Start();
            }
            else
            {
                Stop();
            }
        }
    }

    public void Start()
    {
        if (_enabled)
            return;
        _enabled = true;
        _peer.Start();
    }

    public void Stop()
    {
        if (!_enabled)
            return;
        _enabled = false;
        _peer.Stop();
    }

    /// The clipboard's contents changed.
    public event ClipboardHandler Changed;

    protected virtual void OnChanged() => Changed(this);

    /// What the platform calls.
    public void OnPlatformClipboardChanged() => OnChanged();
}

/// What a clipboard watcher's handler is given. Not `EventHandler`, because a
/// watcher is not a `Control`.
public closure void ClipboardHandler(ClipboardWatcher sender);
