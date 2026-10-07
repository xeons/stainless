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

// One thing a program can do, behind every menu item, button and key that
// does it: the LCL's TAction and TActionList.
module Forms;

import Standard.Collections;
import Standard.Text;
import Forms.Platform;
#if FORMS_REFLECT
import Standard.Reflection;
#endif

public closure void CommandEventHandler(Command sender);
public closure void CommandListEventHandler(CommandList sender, CommandEventArgs args);

/// Which command a list's handler is asked about, and whether it answered.
public class CommandEventArgs
{
    public Command Command { get; }

    /// Set it when the list's handler has done the work, so the command's own
    /// handler is not run as well.
    public bool Handled { get; set; }

    public CommandEventArgs(Command command)
    {
        Command = command;
        Handled = false;
    }
}

/// One thing the program can do, with the caption, the enabled state and the
/// shortcut every way of doing it shares.
///
/// ```
/// _save = _commands.Add("&Save");
/// _save.Shortcut = Shortcut.FromKey(Key.S, ModifierKeys.Control);
/// _save.Execute += this.OnSave;
/// _save.Update += (sender) => { sender.Enabled = _document.IsModified; };
/// saveItem.Command = _save;
/// saveButton.Command = _save;
/// ```
///
/// **Called `Command` rather than `Action`**, which is the LCL's name and the
/// standard library's closure type both, and so would be ambiguous in every
/// file that imports this module.
///
/// A menu item, a control or a toolbar button given a command takes its state
/// from it and keeps taking it: setting `Enabled` here greys every one of them.
/// Choosing any of them runs `Execute`.
///
/// **A command does not keep what shows it alive.** Each client subscribes to
/// `Changed` with a method of its own, which the language makes weak, so a
/// button that is freed stops being told and the command never notices.
#if FORMS_REFLECT
[Reflect]
#endif
public class Command
{
    String _text;
    String _hint;
    bool _enabled;
    bool _checked;
    bool _visible;
    bool _autoCheck;
    int _groupIndex;
    int _imageIndex;
    Shortcut _shortcut;
    weak CommandList? _list;

    public Command(String text)
    {
        _text = text;
        _hint = "";
        _enabled = true;
        _checked = false;
        _visible = true;
        _autoCheck = false;
        _groupIndex = 0;
        _imageIndex = -1;
        _shortcut = Shortcut.Empty;
        _list = null;
    }

    /// A command with no caption yet, which is how a form file makes one
    /// before it sets `Text`.
    public Command() => this("");

    /// The caption every client shows, with `&` marking a mnemonic.
    public String Text
    {
        get => _text;
        set
        {
            _text = value;
            OnChanged();
        }
    }

    /// What a control shows as its tool tip.
    public String Hint
    {
        get => _hint;
        set
        {
            _hint = value;
            OnChanged();
        }
    }

    /// Whether it may be carried out. A disabled command greys every client
    /// and ignores its shortcut.
    public bool Enabled
    {
        get => _enabled;
        set
        {
            if (_enabled == value)
                return;
            _enabled = value;
            OnChanged();
        }
    }

    /// The tick on a menu item, the pressed state of a toolbar or speed button.
    ///
    /// Checking a command with a `GroupIndex` unchecks the others in its list
    /// that share the index, which is how a set of commands behaves as radio
    /// buttons.
    public bool Checked
    {
        get => _checked;
        set
        {
            if (_checked == value)
                return;
            _checked = value;
            if (value && _groupIndex > 0)
            {
                CommandList? list = _list;
                if (list != null)
                    ((CommandList)list).UncheckGroup(this);
            }
            OnChanged();
        }
    }

    /// Whether the controls that show it are visible. A hidden command is not
    /// carried out.
    public bool Visible
    {
        get => _visible;
        set
        {
            if (_visible == value)
                return;
            _visible = value;
            OnChanged();
        }
    }

    /// Whether carrying it out flips `Checked` first: on, and for a command in
    /// a group, on and the rest of the group off.
    public bool AutoCheck
    {
        get => _autoCheck;
        set => _autoCheck = value;
    }

    /// Zero for none. Commands of one list with the same index are checked one
    /// at a time.
    public int GroupIndex
    {
        get => _groupIndex;
        set => _groupIndex = value;
    }

    /// The picture a toolbar button shows, from its bar's image list, or -1.
    public int ImageIndex
    {
        get => _imageIndex;
        set
        {
            _imageIndex = value;
            OnChanged();
        }
    }

    /// The key that carries it out from anywhere in the form that owns its
    /// list, and that a menu item showing it displays.
    public Shortcut Shortcut
    {
        get => _shortcut;
        set
        {
            _shortcut = value;
            OnChanged();
        }
    }

    /// The list it belongs to. Setting it moves the command from the list it
    /// was in.
    public CommandList? List
    {
        get
        {
            CommandList? held = _list;
            return held;
        }
        set
        {
            CommandList? old = _list;
            if (old != null)
                ((CommandList)old).Remove(this);
            if (value != null)
                ((CommandList)value).Add(this);
        }
    }

    /// Records the list, for `CommandList.Add` and `Remove`, which keep the
    /// list's own collection.
    public void SetListOnly(CommandList? list) => _list = list;

    /// The command was carried out: a client was chosen, or its shortcut
    /// pressed.
    public event CommandEventHandler Execute;

    /// Asked when the program goes idle, which is where `Enabled` and
    /// `Checked` are brought up to date. Not raised when the list's own
    /// `Update` handler answers for it.
    public event CommandEventHandler Update;

    /// Something a client shows has changed. What each client subscribes to.
    public event CommandEventHandler Changed;

    protected virtual void OnExecute() => Execute(this);
    protected virtual void OnUpdate() => Update(this);
    protected virtual void OnChanged() => Changed(this);

    /// Carries it out, as choosing a client would. Does nothing and answers
    /// false while it is disabled or hidden.
    public bool PerformExecute()
    {
        if (!_enabled || !_visible)
            return false;
        if (_autoCheck)
            Checked = _groupIndex > 0 ? true : !_checked;
        OnExecute();
        return true;
    }

    /// Brings its state up to date: the list's `Update` first, then its own.
    public void PerformUpdate()
    {
        CommandList? list = _list;
        if (list != null && ((CommandList)list).UpdateCommand(this))
            return;
        OnUpdate();
    }
}

/// The commands of one form, kept up to date while the program is idle and
/// carried out by their shortcuts.
///
/// ```
/// _commands = new CommandList(this);
/// var save = _commands.Add("&Save");
/// ```
///
/// **Made with its form**, which is what makes the shortcuts work: a form asks
/// each of its lists for a key after its menu has declined it, and updates
/// each list's commands every time the loop goes idle. The form holds the
/// list; the list does not hold the form.
#if FORMS_REFLECT
[Reflect]
#endif
public class CommandList
{
    List<Command> _commands;
    weak Form? _owner;
    ImageList? _images;

    public CommandList(Form owner)
    {
        _commands = new List<Command>();
        _owner = owner;
        _images = null;
        owner.AddCommandList(this);
    }

    /// A list no form owns: its commands work when their clients are chosen,
    /// and nothing updates them or presses their shortcuts. What a designer
    /// makes, so that a command being designed cannot be carried out.
    public CommandList()
    {
        _commands = new List<Command>();
        _owner = null;
        _images = null;
    }

    /// The form it belongs to, or null once that has gone.
    public Form? Owner
    {
        get
        {
            Form? held = _owner;
            return held;
        }
    }

    /// The commands, in the order they were added.
    public IReadOnlyList<Command> Commands => _commands;

    public nuint Count => _commands.Count;

    /// The pictures a command's `ImageIndex` names.
    public ImageList? Images
    {
        get => _images;
        set => _images = value;
    }

    /// Adds a command and answers it, so a handler can be attached to the
    /// result of the call.
    public Command Add(Command command)
    {
        CommandList? old = command.List;
        if (old != null && (CommandList)old != this)
            ((CommandList)old).Remove(command);
        if (FindIndexOf(command) < 0)
            _commands.Add(command);
        command.SetListOnly(this);
        return command;
    }

    long FindIndexOf(Command command)
    {
        for (nuint i = 0u; i < _commands.Count; i++)
        {
            if (_commands[i] == command)
                return (long)i;
        }
        return -1;
    }

    /// The same, making the command from its caption.
    public Command Add(String text) => Add(new Command(text));

    public void Remove(Command command)
    {
        long at = FindIndexOf(command);
        if (at >= 0)
            _commands.RemoveAt((nuint)at);
        CommandList? held = command.List;
        if (held != null && (CommandList)held == this)
            command.SetListOnly(null);
    }

    /// Asked about each command before the command's own `Update`. Setting
    /// `Handled` answers for it.
    public event CommandListEventHandler Update;

    protected virtual void OnUpdate(CommandEventArgs args) => Update(this, args);

    /// Runs the list's handler for one command. True when it answered.
    public bool UpdateCommand(Command command)
    {
        var args = new CommandEventArgs(command);
        OnUpdate(args);
        return args.Handled;
    }

    /// Brings every command up to date. The form calls it when the loop goes
    /// idle.
    public void UpdateCommands()
    {
        foreach (var command in _commands)
            command.PerformUpdate();
    }

    /// The enabled, visible command whose shortcut `key` is, if any.
    public Command? FindCommandForShortcut(Key key, ModifierKeys modifiers)
    {
        foreach (var command in _commands)
        {
            if (command.Enabled && command.Visible && command.Shortcut.Matches(key, modifiers))
                return command;
        }
        return null;
    }

    /// Unchecks every command in `checkedOne`'s group but it.
    public void UncheckGroup(Command checkedOne)
    {
        foreach (var command in _commands)
        {
            if (command != checkedOne && command.GroupIndex == checkedOne.GroupIndex)
                command.Checked = false;
        }
    }
}
