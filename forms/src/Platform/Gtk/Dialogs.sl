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

// The common dialogs, and the message box.
//
// **Every one of these is a `GtkDialog` and `gtk_dialog_run`**, which is the
// nested main loop `ShowModal` had to build by hand for a plain window. The
// shape is the same six lines each time: make it, fill it in, run it, read the
// answer if it was accepted, destroy it.
//
// **`gtk_file_chooser_dialog_new` is variadic over button-and-response
// pairs**, which a binding cannot spell, so the buttons are added one at a
// time afterwards. That is what the variadic tail does anyway, and it is why
// the GTK bindings' own note about this dialog no longer applies.
//
// The seam answers a `Result`, so a cancelled dialog has nothing to read --
// which is the whole difference from `TOpenDialog.Execute`, where a caller
// who forgets the test reads a stale path.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Standard.Convert;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;

/// The window a dialog is transient for, or null. A dialog with no parent is
/// placed by the window manager wherever it likes, which is why every one of
/// these is given one when the caller has one.
GtkWidget* ParentOf(IWindowPeer? owner)
{
    if (owner == null)
        return null;
    return ((GtkWindowPeer)owner).Widget;
}

/// Runs a dialog and answers its response, destroying it either way.
gint RunAndClose(GtkWidget* dialog)
{
    gint answer = gtk_dialog_run(dialog);
    gtk_widget_destroy(dialog);
    return answer;
}

// ============================================================== file chooser

/// `filters` as the seam gives them: a description and a pattern alternating,
/// which is how every platform's filter list is written.
void AddFilters(GtkWidget* chooser, String[] filters)
{
    nuint i = 0u;
    while (i + 1u < filters.Length)
    {
        gpointer filter = gtk_file_filter_new();
        gtk_file_filter_set_name(filter, filters[i].ToPointer());

        // A pattern may be several, separated by semicolons -- `*.png;*.jpg`
        // -- which is what a Windows filter string looks like and what a
        // program written against the seam will have supplied.
        var patterns = filters[i + 1u].Split(';');
        for (nuint p = 0u; p < patterns.Length; p++)
        {
            var one = patterns[p].Trim();
            if (!one.IsEmpty)
                gtk_file_filter_add_pattern(filter, one.ToPointer());
        }
        gtk_file_chooser_add_filter(chooser, filter);
        i = i + 2u;
    }
}

/// What a chooser chose, or why it did not.
Result<String, DialogOutcome> Chosen(GtkWidget* chooser, gint answer)
{
    if (answer != GTK_RESPONSE_ACCEPT)
    {
        gtk_widget_destroy(chooser);
        return Fail(DialogOutcome.Canceled);
    }

    gchar* raw = gtk_file_chooser_get_filename(chooser);
    gtk_widget_destroy(chooser);
    if (raw == null)
        return Fail(DialogOutcome.Canceled);

    var path = Text.FromNullTerminated(raw);
    g_free((gpointer)raw);
    return Ok(path);
}

public Result<String, DialogOutcome> OpenFile(IWindowPeer? owner, String title,
                                              String start, String[] filters)
{
    GtkWidget* chooser = gtk_file_chooser_dialog_new(
        title.ToPointer(), ParentOf(owner), GTK_FILE_CHOOSER_ACTION_OPEN, null);
    gtk_dialog_add_button(chooser, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button(chooser, "_Open".ToPointer(), GTK_RESPONSE_ACCEPT);

    if (!start.IsEmpty)
        gtk_file_chooser_set_filename(chooser, start.ToPointer());
    AddFilters(chooser, filters);

    return Chosen(chooser, gtk_dialog_run(chooser));
}

public Result<String, DialogOutcome> SaveFile(IWindowPeer? owner, String title,
                                              String start, String[] filters)
{
    GtkWidget* chooser = gtk_file_chooser_dialog_new(
        title.ToPointer(), ParentOf(owner), GTK_FILE_CHOOSER_ACTION_SAVE, null);
    gtk_dialog_add_button(chooser, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button(chooser, "_Save".ToPointer(), GTK_RESPONSE_ACCEPT);
    gtk_file_chooser_set_do_overwrite_confirmation(chooser, 1);

    // A name rather than a filename: a save dialog opens on a directory with
    // the name filled in, and `set_filename` on a file that does not exist
    // yet does nothing at all.
    if (!start.IsEmpty)
    {
        gtk_file_chooser_set_current_name(chooser, start.ToPointer());
    }
    AddFilters(chooser, filters);

    return Chosen(chooser, gtk_dialog_run(chooser));
}

public Result<String, DialogOutcome> PickFolder(IWindowPeer? owner, String title)
{
    GtkWidget* chooser = gtk_file_chooser_dialog_new(
        title.ToPointer(), ParentOf(owner),
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, null);
    gtk_dialog_add_button(chooser, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button(chooser, "_Select".ToPointer(), GTK_RESPONSE_ACCEPT);

    return Chosen(chooser, gtk_dialog_run(chooser));
}

// =================================================================== colour

public Result<Color, DialogOutcome> PickColor(IWindowPeer? owner, Color start)
{
    GtkWidget* chooser = gtk_color_chooser_dialog_new(
        "Choose a colour".ToPointer(), ParentOf(owner));

    GdkRGBA from = ToRgba(start);
    gtk_color_chooser_set_rgba(chooser, &from);

    gint answer = gtk_dialog_run(chooser);
    if (answer != GTK_RESPONSE_OK)
    {
        gtk_widget_destroy(chooser);
        return Fail(DialogOutcome.Canceled);
    }

    GdkRGBA picked;
    gtk_color_chooser_get_rgba(chooser, &picked);
    gtk_widget_destroy(chooser);
    return Ok(FromRgba(picked));
}

// ===================================================================== font

/// **A Pango name has to be read back apart.** The chooser answers
/// `"Cantarell Bold Italic 11"` -- a family, then any number of style words,
/// then a size -- and a `Font` wants the three separately.
///
/// Read as Pango reads it: the size is the last word when it is a number, in
/// points unless it ends in `px`, and may have a fraction; the style words are
/// the run of them before it, whichever they are; the family is what is left
/// in front. A weight from semi-bold up is bold, since `Font` has no other.
public Font ParsePango(String description, Font fallback)
{
    var words = new List<String>();
    foreach (var word in description.Trim().Split(' '))
    {
        if (!word.IsEmpty)
            words.Add(word);
    }
    if (words.IsEmpty)
        return fallback;

    int size = fallback.Size;
    nuint end = words.Count;
    int measured = PangoSizeInPoints(words[end - 1u]);
    if (measured > 0)
    {
        size = measured;
        end--;
    }

    var style = FontStyle.Regular;
    while (end > 0u)
    {
        var word = words[end - 1u].ToLowerAscii();
        if (!IsPangoStyleWord(word))
            break;
        if (IsPangoBoldWord(word))
            style = style | FontStyle.Bold;
        if (word == "italic" || word == "oblique")
            style = style | FontStyle.Italic;
        end--;
    }

    var family = "";
    for (nuint i = 0u; i < end; i++)
    {
        if (!family.IsEmpty)
            family = family + " ";
        family = family + words[i];
    }
    if (family.EndsWith(","))
        family = family.Substring(0u, family.ByteLength() - 1u);

    if (family.IsEmpty)
        family = fallback.Family;
    return new Font(family, size, style);
}

/// A Pango size word in whole points, rounded, or zero for a word that is not
/// a size.
int PangoSizeInPoints(String word)
{
    bool pixels = word.EndsWith("px");
    var number = pixels ? word.Substring(0u, word.ByteLength() - 2u) : word;
    var parsed = Convert.ToDouble(number);
    if (!parsed.Ok || parsed.Value <= 0.0)
        return 0;

    // Pixels at the 96 DPI the rest of this backend assumes.
    double points = pixels ? parsed.Value * 72.0 / 96.0 : parsed.Value;
    return (int)(points + 0.5);
}

/// Whether a lower-cased word is one Pango reads as a style rather than as
/// part of a family: a weight, a slant, a variant, a stretch or a gravity.
bool IsPangoStyleWord(String word)
{
    if (word.ByteLength() > 0u && word.GetByteAt(0u) == (byte)'@')
        return true;
    if (IsPangoBoldWord(word))
        return true;

    switch (word)
    {
        case "thin":
        case "ultra-light":
        case "ultralight":
        case "extra-light":
        case "extralight":
        case "light":
        case "semi-light":
        case "semilight":
        case "demi-light":
        case "demilight":
        case "book":
        case "regular":
        case "normal":
        case "medium":
        case "roman":
        case "italic":
        case "oblique":
        case "small-caps":
        case "all-small-caps":
        case "petite-caps":
        case "all-petite-caps":
        case "unicase":
        case "title-caps":
        case "ultra-condensed":
        case "extra-condensed":
        case "condensed":
        case "semi-condensed":
        case "semi-expanded":
        case "expanded":
        case "extra-expanded":
        case "ultra-expanded":
        case "not-rotated":
        case "south":
        case "upside-down":
        case "north":
        case "rotated-left":
        case "east":
        case "rotated-right":
        case "west":
            return true;
    }
    return false;
}

/// Whether a lower-cased word is a Pango weight of semi-bold or heavier.
bool IsPangoBoldWord(String word)
{
    switch (word)
    {
        case "semi-bold":
        case "semibold":
        case "demi-bold":
        case "demibold":
        case "bold":
        case "ultra-bold":
        case "ultrabold":
        case "extra-bold":
        case "extrabold":
        case "heavy":
        case "ultra-heavy":
        case "ultraheavy":
        case "black":
        case "ultra-black":
        case "ultrablack":
        case "extra-black":
        case "extrablack":
            return true;
    }
    return false;
}

public Result<Font, DialogOutcome> PickFont(IWindowPeer? owner, Font start)
{
    GtkWidget* chooser = gtk_font_chooser_dialog_new(
        "Choose a font".ToPointer(), ParentOf(owner));
    gtk_font_chooser_set_font(chooser, PangoName(start).ToPointer());

    gint answer = gtk_dialog_run(chooser);
    if (answer != GTK_RESPONSE_OK)
    {
        gtk_widget_destroy(chooser);
        return Fail(DialogOutcome.Canceled);
    }

    gchar* raw = gtk_font_chooser_get_font(chooser);
    gtk_widget_destroy(chooser);
    if (raw == null)
        return Fail(DialogOutcome.Canceled);

    var described = Text.FromNullTerminated(raw);
    g_free((gpointer)raw);
    return Ok(ParsePango(described, start));
}

// ============================================================== message box

/// `GtkMessageType`, which is what the seam's icon becomes.
gint MessageTypeOf(MessageIcon icon)
{
    if (icon == MessageIcon.Information)
        return GTK_MESSAGE_INFO;
    if (icon == MessageIcon.Warning)
        return GTK_MESSAGE_WARNING;
    if (icon == MessageIcon.Error)
        return GTK_MESSAGE_ERROR;
    if (icon == MessageIcon.Question)
        return GTK_MESSAGE_QUESTION;
    return GTK_MESSAGE_OTHER;
}

/// A message box.
///
/// **The buttons are added by hand rather than with `GtkButtonsType`**, which
/// only offers five fixed sets and none of them is yes/no/cancel or
/// retry/cancel. Adding them one at a time is what makes the seam's five sets
/// all expressible, and it puts them in the platform's order -- the affirmative
/// last, which is where a GTK user looks for it and the opposite of Windows.
public DialogResult ShowMessageBox(IWindowPeer? owner, String text, String caption,
                                   MessageButtons buttons, MessageIcon icon)
{
    GtkWidget* dialog = gtk_message_dialog_new(
        ParentOf(owner), GTK_DIALOG_MODAL, MessageTypeOf(icon),
        GTK_BUTTONS_NONE, "%s".ToPointer(), text.ToPointer());

    gtk_window_set_title(dialog, caption.ToPointer());

    if (buttons == MessageButtons.Ok)
    {
        gtk_dialog_add_button(dialog, "_OK".ToPointer(), GTK_RESPONSE_OK);
    }
    else if (buttons == MessageButtons.OkCancel)
    {
        gtk_dialog_add_button(dialog, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
        gtk_dialog_add_button(dialog, "_OK".ToPointer(), GTK_RESPONSE_OK);
    }
    else if (buttons == MessageButtons.YesNo)
    {
        gtk_dialog_add_button(dialog, "_No".ToPointer(), GTK_RESPONSE_NO);
        gtk_dialog_add_button(dialog, "_Yes".ToPointer(), GTK_RESPONSE_YES);
    }
    else if (buttons == MessageButtons.YesNoCancel)
    {
        gtk_dialog_add_button(dialog, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
        gtk_dialog_add_button(dialog, "_No".ToPointer(), GTK_RESPONSE_NO);
        gtk_dialog_add_button(dialog, "_Yes".ToPointer(), GTK_RESPONSE_YES);
    }
    else
    {
        gtk_dialog_add_button(dialog, "_Cancel".ToPointer(), GTK_RESPONSE_CANCEL);
        gtk_dialog_add_button(dialog, "_Retry".ToPointer(), GTK_RESPONSE_ACCEPT);
    }

    return MessageAnswer(RunAndClose(dialog), buttons);
}

/// What a message box's response means.
///
/// Cancel, Escape and the title bar's close all mean Cancel -- except on a box
/// with only an OK button, where Windows answers OK to all three, because OK
/// is the only answer it has.
public DialogResult MessageAnswer(gint answer, MessageButtons buttons)
{
    if (answer == GTK_RESPONSE_OK)
        return DialogResult.Ok;
    if (answer == GTK_RESPONSE_YES)
        return DialogResult.Yes;
    if (answer == GTK_RESPONSE_NO)
        return DialogResult.No;
    if (answer == GTK_RESPONSE_ACCEPT)
        return DialogResult.Retry;
    if (buttons == MessageButtons.Ok)
        return DialogResult.Ok;
    return DialogResult.Cancel;
}

#endif
