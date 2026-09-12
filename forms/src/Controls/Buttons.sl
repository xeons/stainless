// Stainless - an experimental systems language.
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

// The things you press: `Button`, `CheckBox` and `RadioButton`.
//
// The LCL calls the shared base `TButtonControl` and hangs `TCustomButton`,
// `TCustomCheckBox` and `TToggleBox` off it. C# calls it `ButtonBase` and hangs
// `Button`, `CheckBox` and `RadioButton` off it, which is the same shape with
// the names a C# reader expects -- and the `TCustom`/`T` pair that the LCL uses
// to separate "the machinery" from "the published version" is exactly C#'s
// `XBase`/`X` pair, so the translation is one for one.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// =============================================================== button base

/// What a button, a check box and a radio button have in common.
///
/// Abstract, because pressing is all it knows how to do and there is no such
/// widget on any platform.
public abstract class ButtonBase : WindowedControl {
    protected ButtonBase(WindowedControl parent) { base(parent); }

    /// The button's caption, which is what `Text` already means.
    public String Caption {
        get => Text;
        set { Text = value; }
    }

    public override Size PreferredSize {
        get {
            var peer = Peer;
            if (peer == null) { return Size.Empty; }
            return ((IControlPeer)peer).PreferredSize();
        }
    }

    /// Raises `Click` as though the user had pressed it.
    ///
    /// C# has this on `ButtonBase` for the same two reasons: a default button
    /// pressed by Enter elsewhere on the form, and a test with nobody in front
    /// of it. Raising the event rather than telling the platform to draw a
    /// press is deliberate -- what a caller wants is the effect, not the
    /// animation.
    public void PerformClick() { OnClick(); }
}

// ==================================================================== button

/// An ordinary push button.
///
/// ```
/// var save = new Button(this);
/// save.Text = "Save";
/// save.SetBounds(10, 10, 90, 26);
/// save.Click += this.OnSave;
/// ```
public class Button : ButtonBase {
    IButtonPeer native;

    public Button(WindowedControl parent) {
        base(parent);
        native = WidgetSet.Current.CreateButton(this, ParentPeer());
        AttachPeer(native);
    }

    /// Whether Enter presses this button. At most one per window, and the
    /// platform is what enforces that -- so setting it on a second button is
    /// enough, and the first need not be unset.
    public bool IsDefault {
        get => isDefault;
        set {
            isDefault = value;
            native.SetDefault(value);
        }
    }

    bool isDefault;
}

// ================================================================= check box

/// A box that is ticked or not.
///
/// **There is no third state.** `TCheckBox` has `cbGrayed` and C# has
/// `CheckState.Indeterminate`, and both exist for a property grid showing a
/// value that differs across a selection. Nothing here needs one yet, and a
/// two-state box whose property is a `bool` is a much better thing to use than
/// a three-state one whose property is an enum that is usually two of three.
public class CheckBox : ButtonBase {
    ICheckPeer native;

    public CheckBox(WindowedControl parent) {
        base(parent);
        native = WidgetSet.Current.CreateCheck(this, ParentPeer(), false);
        AttachPeer(native);
    }

    /// For `RadioButton`, which is the same widget with one style bit changed.
    protected CheckBox(WindowedControl parent, bool radio) {
        base(parent);
        native = WidgetSet.Current.CreateCheck(this, ParentPeer(), radio);
        AttachPeer(native);
    }

    /// Whether it is ticked.
    ///
    /// Read from the platform rather than from a field, because the platform
    /// toggles it when the user clicks and a field would be one click behind.
    ///
    /// Virtual because a radio button has to clear its siblings when it is
    /// ticked, and a check box must not.
    public virtual bool Checked {
        get => native.GetChecked();
        set { native.SetChecked(value); }
    }

    /// Sets the tick without telling anything else, for a derived class that
    /// has more to do around it.
    protected void SetCheckedOnly(bool ticked) { native.SetChecked(ticked); }

    /// The tick changed, whoever changed it.
    public event EventHandler CheckedChanged;

    protected virtual void OnCheckedChanged() { CheckedChanged(this); }

    /// The platform reports a tick as a change of value, which for this control
    /// means the tick and not the caption.
    public override void OnPlatformValueChanged() { OnCheckedChanged(); }
}

// ============================================================== radio button

/// One of a set of choices, of which the platform keeps exactly one chosen.
///
/// **Grouping is by parent, not by a property.** Every radio button sharing a
/// parent is one group, which is Windows' rule, GTK's rule and the LCL's rule,
/// and is why a form with two sets of choices puts each set in its own `Panel`
/// or `GroupBox`. A `GroupName` property would have to fight the platform for
/// the behaviour it already has.
public class RadioButton : CheckBox {
    public RadioButton(WindowedControl parent) { base(parent, true); }

    /// Ticking one unticks the rest of its group.
    ///
    /// **Windows does not do this for a programmatic set.** `BS_AUTORADIOBUTTON`
    /// clears the other buttons when the *user* clicks one; `BM_SETCHECK`
    /// clears nothing, so a program that ticked one by hand ended up with two
    /// ticked and a group whose selected index was whichever came first. C#
    /// does exactly this in `RadioButton.Checked`, for the same reason.
    public override bool Checked {
        get => base.Checked;
        set {
            SetCheckedOnly(value);
            if (!value) { return; }
            ClearSiblings();
        }
    }

    /// Unticks every other radio button with the same parent, which is what
    /// makes a group a group on every platform.
    void ClearSiblings() {
        var parent = Parent;
        if (parent == null) { return; }
        foreach (var sibling in ((WindowedControl)parent).Controls) {
            if (sibling == this) { continue; }
            if (sibling is RadioButton other) { other.SetCheckedOnly(false); }
        }
    }
}
