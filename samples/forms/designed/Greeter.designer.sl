// SPDX-License-Identifier: 0BSD

// Generated from Greeter.slfm. Edit that file or the designer;
// this one is rewritten from it.
module Greeter;

import Forms;
import Forms.Drawing;

public class GreeterForm : Form
{
    private late MainMenu _mainMenu;
    private late MenuItem _fileMenu;
    private late MenuItem _greetItem;
    private late MenuItem _separator1;
    private late MenuItem _exitItem;
    private late ToolBar _tools;
    private late ToolButton _greetButton;
    private late Label _prompt;
    private late TextBox _name;
    private late Button _greet;
    private late Panel _footer;
    private late Label _greeting;

    [Embed("greet.png")]
    private static readonly byte[] s_greetImage;

    private void InitializeComponent()
    {
        Text = "Greeter";
        SetBounds(0, 0, 360, 240);

        _mainMenu = new MainMenu();

        _fileMenu = new MenuItem();
        _fileMenu.Text = "&File";

        _greetItem = new MenuItem();
        _greetItem.Text = "&Greet";
        _greetItem.Click += this.OnGreetItem;
        _fileMenu.Add(_greetItem);

        _separator1 = MenuItem.CreateSeparator();
        _fileMenu.Add(_separator1);

        _exitItem = new MenuItem();
        _exitItem.Text = "E&xit";
        _exitItem.Click += this.OnExit;
        _fileMenu.Add(_exitItem);
        _mainMenu.Add(_fileMenu);

        _tools = new ToolBar(this);
        _tools.Dock = DockStyle.Top;

        _greetButton = new ToolButton();
        _greetButton.Text = "Greet";
        _greetButton.Click += this.OnGreet;
        _tools.Add(_greetButton);

        _prompt = new Label(this);
        _prompt.Text = "Your name:";
        _prompt.SetBounds(16, 52, 80, 20);

        _name = new TextBox(this);
        _name.Text = "world";
        _name.SetBounds(100, 48, 240, 24);
        _name.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        _greet = new Button(this);
        _greet.Text = "Greet";
        _greet.SetBounds(250, 88, 90, 28);
        _greet.Image = Bitmap.FromEmbedded(s_greetImage);
        _greet.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _greet.Click += this.OnGreet;

        _footer = new Panel(this);
        _footer.Dock = DockStyle.Bottom;
        _footer.Height = 40;

        _greeting = new Label(_footer);
        _greeting.Text = "";
        _greeting.SetBounds(16, 10, 320, 20);

        Menu = _mainMenu;
    }
}
