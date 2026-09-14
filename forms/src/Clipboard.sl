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

import Standard.Text;
import Forms.Platform;

/// What Ctrl+C put somewhere and Ctrl+V takes back.
///
/// ```
/// Clipboard.SetText(editor.SelectedText);
/// if (Clipboard.HasText()) { editor.Type(Clipboard.GetText()); }
/// ```
///
/// **Text and nothing else, so far.** A clipboard carries several formats at
/// once and a paste negotiates which one it wants; pictures, files and a
/// program's own private format all belong on it, and each is a design rather
/// than a method. What is here is the one format both platforms agree about and
/// every program offers, which is what an editor needs.
///
/// **Static, because there is one.** `TClipboard` in the LCL is an object with
/// a global instance, and C#'s `Clipboard` is static; the second is the honest
/// spelling of the first, since a second instance would refer to the same
/// desktop-wide thing as the first.
///
/// **Every call can fail quietly, and none of them says so.** On Windows the
/// clipboard is a lock another process may be holding; on X11 it lives in
/// whichever client last claimed it, and reading one is a round trip to a
/// program that may have exited. A failed read answers `""` and a failed write
/// does nothing, because there is no answer a caller could usefully act on --
/// a text editor whose paste failed has nothing to offer the user but the
/// paste they already asked for.
public class Clipboard {
    /// Not constructible: everything here is static, and an instance would
    /// suggest there could be two clipboards.
    Clipboard() { }

    /// What the clipboard holds as text, or `""` when it holds none.
    public static String GetText() {
        return WidgetSet.Current.GetClipboardText();
    }

    /// Puts text on the clipboard, replacing whatever was there.
    public static void SetText(String text) {
        WidgetSet.Current.SetClipboardText(text);
    }

    /// Whether there is text to be had.
    ///
    /// What a paste command greys itself out on. Cheaper than fetching the text
    /// on both platforms -- and on X11 much cheaper, since it does not wait for
    /// another process to hand the contents over.
    public static bool HasText() {
        return WidgetSet.Current.ClipboardHasText();
    }
}
