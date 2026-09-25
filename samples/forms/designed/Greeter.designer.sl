// SPDX-License-Identifier: 0BSD

// Generated from Greeter.slfm. Edit that file or the designer;
// this one is rewritten from it.
module Greeter;

import Forms;

public class GreeterForm : Form
{
    private Label _prompt;
    private TextBox _name;
    private Button _greet;
    private Panel _footer;
    private Label _greeting;

    private void InitializeComponent()
    {
        Text = "Greeter";
        SetBounds(0, 0, 360, 170);

        _prompt = new Label(this);
        _prompt.Text = "Your name:";
        _prompt.SetBounds(16, 20, 80, 20);

        _name = new TextBox(this);
        _name.Text = "world";
        _name.SetBounds(100, 16, 240, 24);
        _name.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        _greet = new Button(this);
        _greet.Text = "Greet";
        _greet.SetBounds(250, 56, 90, 28);
        _greet.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _greet.Click += this.OnGreet;

        _footer = new Panel(this);
        _footer.Dock = DockStyle.Bottom;
        _footer.Height = 40;

        _greeting = new Label(_footer);
        _greeting.Text = "";
        _greeting.SetBounds(16, 10, 320, 20);
    }
}
