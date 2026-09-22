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

// The clipboard, as GTK keeps it.
//
// **Nothing is copied when a program copies.** On X11 and Wayland the
// clipboard is a promise: the program that copied announces which targets it
// can produce, and produces one only when another program pastes it. So a copy
// here is `gtk_clipboard_set_with_data` with a list of targets, and the content
// rides along as the callbacks' `data` until another program takes the
// clipboard. `gtk_clipboard_set_can_store` asks a clipboard manager, where
// there is one, to take a copy of everything when this program exits.
//
// **A read waits.** Every `gtk_clipboard_wait_*` spins the main loop until the
// owner answers, which for another process is a round trip and for this one is
// a call back into `AnswerPaste`.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Signals;
import Gtk.Events;

/// The `info` each target is offered under, which is how `AnswerPaste` knows
/// what it is being asked for. A custom format's is `OfferCustom` plus its
/// index.
const guint OfferText = 1u;
const guint OfferHtml = 2u;
const guint OfferImage = 3u;
const guint OfferFiles = 4u;
const guint OfferFileManager = 5u;
const guint OfferCustom = 16u;

/// What Nautilus, Nemo and Caja read on a paste: `copy`, then one URI a line.
/// Without it they paste a list of files as a text file of names.
static readonly String FileManagerTarget = "x-special/gnome-copied-files";

static readonly String HtmlTarget = "text/html";

/// The clipboard Ctrl+C and Ctrl+V use, **borrowed**.
gpointer DefaultClipboard() => gtk_clipboard_get(ClipboardSelection());

GdkAtom AtomNamed(String name) => gdk_atom_intern((gchar*)name.ToPointer(), 0);

// ============================================================== pixel order

/// A pixbuf holding a copy of pixels in the seam's order, or null.
///
/// gdk-pixbuf wants red first where the seam hands over blue first, so two
/// bytes of each pixel swap on the way in. The alpha stays straight: cairo
/// composites premultiplied, and `gdk_cairo_set_source_pixbuf` converts.
GdkPixbuf* PixbufFromBgra(int width, int height, byte[] pixels)
{
    GdkPixbuf* made = gdk_pixbuf_new(0, 1, 8, width, height);
    if (made == null)
        return null;

    byte* into = gdk_pixbuf_get_pixels(made);
    nuint stride = (nuint)gdk_pixbuf_get_rowstride(made);
    nuint row = (nuint)width * 4u;

    for (nuint y = 0u; y < (nuint)height; y++)
    {
        nuint source = y * row;
        nuint target = y * stride;
        for (nuint x = 0u; x < row; x = x + 4u)
        {
            into[target + x]      = pixels[source + x + 2u];   // red
            into[target + x + 1u] = pixels[source + x + 1u];   // green
            into[target + x + 2u] = pixels[source + x];        // blue
            into[target + x + 3u] = pixels[source + x + 3u];   // alpha
        }
    }
    return made;
}

/// A pixbuf's pixels in the seam's order. A pixbuf with no alpha channel is
/// three bytes a pixel and opaque.
ClipboardImage? BgraFromPixbuf(GdkPixbuf* pixbuf)
{
    int width = gdk_pixbuf_get_width(pixbuf);
    int height = gdk_pixbuf_get_height(pixbuf);
    nuint channels = (nuint)gdk_pixbuf_get_n_channels(pixbuf);
    if (width <= 0 || height <= 0 || channels < 3u
        || gdk_pixbuf_get_bits_per_sample(pixbuf) != 8)
    {
        return null;
    }

    byte* from = gdk_pixbuf_get_pixels(pixbuf);
    nuint stride = (nuint)gdk_pixbuf_get_rowstride(pixbuf);
    var pixels = new byte[(nuint)width * (nuint)height * 4u];

    for (nuint y = 0u; y < (nuint)height; y++)
    {
        for (nuint x = 0u; x < (nuint)width; x++)
        {
            nuint source = y * stride + x * channels;
            nuint target = (y * (nuint)width + x) * 4u;
            pixels[target]      = from[source + 2u];
            pixels[target + 1u] = from[source + 1u];
            pixels[target + 2u] = from[source];
            pixels[target + 3u] = channels >= 4u ? from[source + 3u] : (byte)255;
        }
    }
    return new ClipboardImage(width, height, pixels);
}

// ================================================================= offering

/// Answers another program's paste, or this one's, from the content `data`
/// is.
///
/// Module-level so that its address is a plain C function pointer for
/// `gtk_clipboard_set_with_data`.
void AnswerPaste(gpointer clipboard, gpointer selection, guint info, gpointer data)
{
    var content = (ClipboardContent)data;

    switch (info)
    {
        case OfferText:
        {
            var text = content.Text;
            if (text != null)
            {
                var value = (String)text;
                gtk_selection_data_set_text(selection, (gchar*)value.ToPointer(),
                                            (gint)value.ByteLength());
            }
            return;
        }

        case OfferHtml:
        {
            var html = content.Html;
            if (html != null)
                AnswerWithText(selection, (String)html);
            return;
        }

        case OfferImage:
        {
            var image = content.Image;
            if (image == null)
                return;
            var picture = (ClipboardImage)image;
            GdkPixbuf* pixbuf = PixbufFromBgra(picture.Width, picture.Height, picture.Pixels);
            if (pixbuf == null)
                return;
            gtk_selection_data_set_pixbuf(selection, pixbuf);
            g_object_unref((gpointer)pixbuf);
            return;
        }

        case OfferFiles:
            AnswerWithUris(selection, content.Files);
            return;

        case OfferFileManager:
            AnswerWithText(selection, "copy\n" + JoinUris(content.Files));
            return;
    }

    if (info >= OfferCustom)
    {
        nuint index = (nuint)(info - OfferCustom);
        if (index >= content.Custom.Count)
            return;
        var bytes = content.Custom[index].Data;
        gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
                               bytes.Length == 0u ? null : &bytes[0u], (gint)bytes.Length);
    }
}

/// Answers with the UTF-8 bytes of `text`, under whatever target was asked.
void AnswerWithText(gpointer selection, String text)
{
    gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
                           text.ToPointer(), (gint)text.ByteLength());
}

/// A `file:` URI for each path GLib can make one of, which is every absolute
/// one.
List<String> UrisOf(String[] paths)
{
    var uris = new List<String>();
    for (nuint i = 0u; i < paths.Length; i++)
    {
        gchar* uri = g_filename_to_uri((gchar*)paths[i].ToPointer(), null, null);
        if (uri == null)
            continue;
        uris.Add(Text.FromNullTerminated(uri));
        g_free((gpointer)uri);
    }
    return uris;
}

String JoinUris(String[] paths)
{
    var uris = UrisOf(paths);
    var joined = new StringBuilder();
    for (nuint i = 0u; i < uris.Count; i++)
    {
        if (i > 0u)
            joined.Append("\n");
        joined.Append(uris[i]);
    }
    return joined.ToText();
}

/// Answers with `text/uri-list`. The array is GLib's, so that `g_strfreev`
/// can free it and every string in it.
void AnswerWithUris(gpointer selection, String[] paths)
{
    var uris = UrisOf(paths);
    gchar** list = (gchar**)g_malloc0((gsize)((uris.Count + 1u) * sizeof(nuint)));
    for (nuint i = 0u; i < uris.Count; i++)
        list[i] = g_strdup((gchar*)uris[i].ToPointer());
    gtk_selection_data_set_uris(selection, list);
    g_strfreev(list);
}

/// Called once an offer is withdrawn: another program took the clipboard, or
/// this one replaced or cleared it. The release that matches `WriteClipboard`'s
/// retain.
void WithdrawOffer(gpointer clipboard, gpointer data)
{
    sl_release(data);
}

/// A copy of `content` that shares no array with it, since a paste may come
/// long after the caller has reused its own.
ClipboardContent SnapshotOfContent(ClipboardContent content)
{
    var copy = new ClipboardContent();
    copy.Text = content.Text;
    copy.Html = content.Html;

    var image = content.Image;
    if (image != null)
    {
        var picture = (ClipboardImage)image;
        copy.Image = new ClipboardImage(picture.Width, picture.Height,
                                        CopyOfBytes(picture.Pixels));
    }

    var files = new String[content.Files.Length];
    for (nuint i = 0u; i < files.Length; i++)
        files[i] = content.Files[i];
    copy.Files = files;

    for (nuint i = 0u; i < content.Custom.Count; i++)
    {
        var entry = content.Custom[i];
        copy.Custom.Add(new ClipboardEntry(entry.Name, CopyOfBytes(entry.Data)));
    }
    return copy;
}

byte[] CopyOfBytes(byte[] bytes)
{
    var copy = new byte[bytes.Length];
    for (nuint i = 0u; i < bytes.Length; i++)
        copy[i] = bytes[i];
    return copy;
}

/// Takes the clipboard, offering every target `content` can produce.
///
/// **Empty content still takes it**, with one placeholder target, and then
/// clears it. `gtk_clipboard_clear` gives up only what this program owns, so
/// emptying a clipboard another program filled means owning it first.
void WriteClipboard(ClipboardContent given)
{
    var content = SnapshotOfContent(given);
    gpointer clipboard = DefaultClipboard();
    gpointer list = gtk_target_list_new(null, 0u);

    if (content.Text != null)
        gtk_target_list_add_text_targets(list, OfferText);
    if (content.Html != null)
        gtk_target_list_add(list, AtomNamed(HtmlTarget), 0u, OfferHtml);
    if (content.Image != null)
        gtk_target_list_add_image_targets(list, OfferImage, 1);
    if (content.Files.Length != 0u)
    {
        gtk_target_list_add_uri_targets(list, OfferFiles);
        gtk_target_list_add(list, AtomNamed(FileManagerTarget), 0u, OfferFileManager);
    }
    for (nuint i = 0u; i < content.Custom.Count; i++)
    {
        gtk_target_list_add(list, AtomNamed(content.Custom[i].Name), 0u,
                            OfferCustom + (guint)i);
    }

    bool empty = content.IsEmpty;
    if (empty)
        gtk_target_list_add(list, AtomNamed("application/x-stainless-nothing"), 0u, 0u);

    gint count = 0;
    GtkTargetEntry* table = gtk_target_table_new_from_list(list, &count);

    // Retained by hand because GTK is about to hold the only reference. A
    // refused offer is never withdrawn, so its release is here instead.
    sl_retain((gpointer)content);
    if (gtk_clipboard_set_with_data(clipboard, table, (guint)count, AnswerPaste,
                                    WithdrawOffer, (gpointer)content) != 0)
    {
        if (empty)
        {
            gtk_clipboard_clear(clipboard);
        }
        else
        {
            gtk_clipboard_set_can_store(clipboard, null, 0);
        }
    }
    else
    {
        sl_release((gpointer)content);
    }

    gtk_target_table_free(table, count);
    gtk_target_list_unref(list);
}

// ================================================================== reading

String ReadClipboardText()
{
    gchar* text = gtk_clipboard_wait_for_text(DefaultClipboard());
    if (text == null)
        return "";
    // Owned by the caller, unlike almost everything else GTK answers.
    String answer = Text.FromNullTerminated((byte*)text);
    g_free((gpointer)text);
    return answer;
}

/// One target's bytes, or an empty array.
byte[] ReadClipboardTarget(String name)
{
    gpointer selection = gtk_clipboard_wait_for_contents(DefaultClipboard(), AtomNamed(name));
    if (selection == null)
        return new byte[0u];

    gint length = gtk_selection_data_get_length(selection);
    byte* from = gtk_selection_data_get_data(selection);
    if (length <= 0 || from == null)
    {
        gtk_selection_data_free(selection);
        return new byte[0u];
    }

    var bytes = new byte[(nuint)length];
    for (nuint i = 0u; i < (nuint)length; i++)
        bytes[i] = from[i];
    gtk_selection_data_free(selection);
    return bytes;
}

/// `text/html`, which Firefox and Chromium write as UTF-16 with a byte-order
/// mark, and everything else as UTF-8.
String ReadClipboardHtml()
{
    var bytes = ReadClipboardTarget(HtmlTarget);
    if (bytes.Length >= 2u && bytes[0u] == (byte)0xFF && bytes[1u] == (byte)0xFE)
    {
        nuint units = (bytes.Length - 2u) / 2u;
        var wide = new char16[units + 1u];
        for (nuint i = 0u; i < units; i++)
            wide[i] = (char16)((uint)bytes[2u + i * 2u] | ((uint)bytes[3u + i * 2u] << 8));
        nuint used = 0u;
        while (used < units && wide[used] != (char16)0u)
            used++;
        return Text.FromUtf16(&wide[0u], used);
    }

    nuint length = 0u;
    while (length < bytes.Length && bytes[length] != (byte)0)
        length++;
    if (length == 0u)
        return "";
    return Text.FromBytes(&bytes[0u], length);
}

ClipboardImage? ReadClipboardImage()
{
    GdkPixbuf* pixbuf = gtk_clipboard_wait_for_image(DefaultClipboard());
    if (pixbuf == null)
        return null;
    var picture = BgraFromPixbuf(pixbuf);
    g_object_unref((gpointer)pixbuf);
    return picture;
}

/// The local paths among the URIs on offer. A URI that names no local file --
/// `https:`, an `sftp:` mount GVfs has not mapped -- is left out.
String[] ReadClipboardFiles()
{
    gchar** uris = gtk_clipboard_wait_for_uris(DefaultClipboard());
    if (uris == null)
        return new String[0u];

    var paths = new List<String>();
    for (nuint i = 0u; uris[i] != null; i++)
    {
        gchar* path = g_filename_from_uri(uris[i], null, null);
        if (path == null)
            continue;
        paths.Add(Text.FromNullTerminated(path));
        g_free((gpointer)path);
    }
    g_strfreev(uris);
    return paths.ToArray();
}

String[] ReadClipboardTargetNames()
{
    GdkAtom* targets = null;
    gint count = 0;
    if (gtk_clipboard_wait_for_targets(DefaultClipboard(), &targets, &count) == 0)
        return new String[0u];

    var names = new List<String>();
    for (nuint i = 0u; i < (nuint)count; i++)
    {
        gchar* name = gdk_atom_name(targets[i]);
        if (name == null)
            continue;
        names.Add(Text.FromNullTerminated(name));
        g_free((gpointer)name);
    }
    g_free((gpointer)targets);
    return names.ToArray();
}

// ================================================================ watching

/// What the signal handler holds. Not the peer: a handler that held the peer
/// would keep it alive for as long as the handler was connected, and the peer
/// is what disconnects the handler.
class ClipboardRelay
{
    weak IClipboardNotify? _target;

    public ClipboardRelay(IClipboardNotify owner)
    {
        _target = owner;
        Listening = false;
    }

    /// Whether the watch is started. Only the widget set's own reports read
    /// it; a connected signal handler is itself the answer.
    public bool Listening;

    /// Whether the watcher it reports to still exists.
    public bool IsAlive => _target != null;

    public void Raise()
    {
        IClipboardNotify? held = _target;
        if (held != null)
            ((IClipboardNotify)held).OnPlatformClipboardChanged();
    }
}

/// Whether the display can say when the clipboard changes hands. Where it
/// cannot, `owner-change` never fires and the widget set reports this
/// program's own copies itself.
bool DisplayReportsClipboardOwner()
{
    gpointer display = gdk_display_get_default();
    return display != null && gdk_display_supports_selection_notification(display) != 0;
}

/// `owner-change` on the clipboard, which GTK emits whenever any program
/// takes it. It needs the XFixes extension on X11, which every server since
/// 2006 has.
public class GtkClipboardWatchPeer : IClipboardWatchPeer
{
    ClipboardRelay _relay;
    gulong _handler;

    public GtkClipboardWatchPeer(ClipboardRelay relay)
    {
        _relay = relay;
        _handler = 0u;
    }

    ~GtkClipboardWatchPeer() { Stop(); }

    public void Start()
    {
        _relay.Listening = true;
        if (_handler != 0u)
            return;
        var relay = _relay;
        _handler = ConnectEvent((GtkWidget*)DefaultClipboard(), "owner-change",
                                (sender, carried) =>
                                {
                                    relay.Raise();
                                    return false;
                                });
    }

    public void Stop()
    {
        _relay.Listening = false;
        if (_handler == 0u)
            return;
        Disconnect((GtkWidget*)DefaultClipboard(), _handler);
        _handler = 0u;
    }
}

#endif
