// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Help > About: what this program is and which build of it is running.
module Ide.App;

import Forms;
import Forms.Drawing;
import Forms.Platform;

public class AboutDialog : Form
{
    late Label _name;
    late Label _version;
    late Label _copyright;
    late Button _ok;

    public AboutDialog()
    {
        base(WindowBorder.Fixed);
        Title = "About Stainless IDE";
        SetBounds(0, 0, 380, 200);

        _name = new Label(this);
        _name.Text = "Stainless IDE";
        _name.Font = new Font(Font.Family, 16, FontStyle.Bold);
        _name.SetBounds(20, 18, 330, 32);

        // The IDE is built by the compiler it ships with, from the same tree,
        // so that compiler's version and commit are this build's.
        _version = new Label(this);
        _version.Text = "Version " + Standard.CompilerVersion;
        _version.SetBounds(20, 58, 330, 22);

        _copyright = new Label(this);
        _copyright.Text = "Copyright (C) 2026 Brandon Scott";
        _copyright.SetBounds(20, 82, 330, 22);

        _ok = new Button(this);
        _ok.Text = "OK";
        _ok.SetBounds(270, 118, 80, 28);
        _ok.Click += (sender) => this.Close();
    }
}
