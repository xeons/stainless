<sub>[Stainless](../README.md) &rsaquo; Form files</sub>

# Form files

A `.slfm` file describes one form: its controls, what is set on each, and which
of the form's methods handle which events. The designer reads and writes it,
and so does a person with a text editor. The compiler never reads it. What is
built is `MainForm.designer.sl`, generated from it and checked in beside it.

```
// SPDX-License-Identifier: 0BSD

module Greeter;

form GreeterForm : Form
{
    Text = "Greeter";
    Bounds = 0, 0, 360, 170;

    Button _greet
    {
        Text = "Greet";
        Bounds = 250, 56, 90, 28;
        Anchors = AnchorStyles.Top | AnchorStyles.Right;
        Click += OnGreet;
    }

    // The answer, along the bottom.
    Panel _footer
    {
        Dock = DockStyle.Bottom;
        Height = 40;

        Label _greeting
        {
            Bounds = 16, 10, 320, 20;
        }
    }
}
```

[samples/forms/designed](../samples/forms/designed) is that form, whole.

## 1. The file

| Part | |
|---|---|
| `// ...` above `module` | header comments, copied to the top of the generated half — which is where a licence line goes |
| `module Name;` | the module the form's class belongs to |
| `import Name;` | a module the generated half imports; `Forms` always is |
| `form Name : Base` | the class, and what it derives from |
| `{ ... }` | the form's members |

A member is one of three things, told apart by what follows its first name:

| Written | Is | Generates |
|---|---|---|
| `Name = value;` | a property | `target.Name = value;` |
| `Name = a, b, c;` | a property set from several values | `target.SetName(a, b, c);` |
| `Event += Method;` | a handler, which is a method of the form | `target.Event += this.Method;` |
| `Type Name { ... }` | a control, whose parent is the block it is in | `Name = new Type(parent);` |

A value is a string literal, a number (decimal, with an optional fraction or a
leading `-`, or hexadecimal after `0x`), or one or more names joined by `|`:
`true`, `DockStyle.Fill`, `AnchorStyles.Top | AnchorStyles.Left`. Each is
copied into the generated half as it is written, so a value means what it would
mean in Stainless and the compiler is what checks it.

**Several values go to a method rather than a property.** `Bounds = 0, 0, 360,
170` becomes `SetBounds(0, 0, 360, 170)`. That is what keeps the generator free
of any knowledge of Forms: it does not need to know that `Bounds` is a
`Rectangle` to write it, and a control with its own `SetSomething(a, b)` is
reachable the same way.

**`+=` rather than `=` for a handler**, which is the Lazarus spelling's one
change. `Click = OnGreet` reads as a property holding a name, and a bare name is
also how an enum member would be written if one were ever allowed unqualified.
`+=` is what the generated line says, and nothing else in the file uses it.

Comments are `//` to the end of a line. One above a member belongs to that
member and moves with it; one after a member's `;` stays on its line; one before
a `}` stays at the end of the block. A comment between two imports has nowhere
to go and is refused, rather than dropped.

## 2. The generated half

`slforms` and the designer write `Name.designer.sl` beside `Name.slfm`. It is
one declaration of the form's class, holding a field per control and
`InitializeComponent`:

```csharp
public class GreeterForm : Form
{
    private Button _greet;
    private Panel _footer;
    private Label _greeting;

    private void InitializeComponent()
    {
        Text = "Greeter";
        SetBounds(0, 0, 360, 170);

        _greet = new Button(this);
        ...
        _greet.Click += this.OnGreet;
        ...
    }
}
```

The person's half is another declaration of the same class, in the same
module. It holds the constructor that calls `InitializeComponent`, the
handlers, and any state of its own:

```csharp
public class GreeterForm
{
    private int _greetings;

    public GreeterForm()
    {
        base(WindowBorder.Sizable);
        InitializeComponent();
        _greetings = 0;
    }

    private void OnGreet(Control sender) { ... }
}
```

That is a class written in two declarations, each adding fields, and one of
them naming the base — [§1.2.1 of the specification](spec/01-modules.md#121-and-so-may-a-type).
The generated half names the base because the form file does, so there is one
place that says it.

**The generated half is checked in.** A build with no IDE and no `slforms`
still compiles, the half is read in review like any other source, and a
debugger steps through it. `slforms --check` fails when one is stale, and
`ide/build.ps1 -Test` runs it over `samples/`.

A half is rewritten only when what would be written differs, so regenerating a
tree touches nothing that did not change.

## 3. `slforms`

```
stainless build --project ide/slforms

slforms <form-or-directory>...            write every stale .designer.sl
slforms --check <form-or-directory>...    write nothing; fail if one is stale
slforms --format <form-or-directory>...   also rewrite each form in the
                                          writer's layout
```

A directory is searched at any depth. It is built from the designer's own
sources, `ide/src/Designer`, so there is one reader of the format.

## 4. Round trips

**A file in the writer's layout comes back byte for byte.** Four spaces to a
level, one member to a line, `Name = value;` with a space either side of the
`=`, and at most one blank line between members. A file in any other layout
reads the same and is written in that one; `slforms --format` does it on
purpose.

A form is edited by the designer and by hand, often both in one afternoon, so
a comment a person wrote surviving the designer is a requirement rather than a
nicety. `ide/tests/formtest.sl` checks it.

## 5. What was rejected

**Reading the form at run time**, which is what Lazarus does with a `.lfm`
compiled into the program as a resource. It needs making an object from a
`Type` and finding a method by name, neither of which Stainless has, and it
puts a parser and a table of every control type into every program that shows
a window. Generating code needs neither, and what it generates is ordinary
source.

**A second reader in the compiler.** The compiler would then have a parser for
a format it does not otherwise care about, and two readers of one format drift.
The generated half being checked in is what makes one reader enough.

**Generating the whole class.** The person's half would then be a derived
class, every handler an `override`, and the class a program shows would not be
the class it wrote. Two declarations of one class is what Visual Studio does
with `partial`, and Stainless now allows it for a class.

## 6. What is not there yet

- **A control whose constructor takes more than its parent.** `TabPage` takes
  its caption, `ImageList` and `Timer` take no parent at all. Neither shape can
  be written yet.
- **Items.** A `ListBox`'s rows, a `MenuItem`'s children and a `ToolBar`'s
  buttons are made by calling methods, not by setting properties.
- **The designer surface itself.** The IDE reads and writes these files; it
  does not yet draw one — see [ide/README.md](../ide/README.md).
