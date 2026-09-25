// SPDX-License-Identifier: 0BSD
//
// The form file reader, writer and generator.
//
//   stainless run ide/tests/formtest.sl ide/src/Designer
//
// A form file is edited by hand and by the designer both, so the thing most
// worth checking is that a read and a write lose nothing a person wrote.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Ide.Designer;

class Harness
{
    public nuint Failures;

    public Harness() => Failures = 0u;

    public void Check(String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
            Failures++;
    }

    public void CheckSame(String what, String expected, String actual)
    {
        bool passed = expected == actual;
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
        {
            Console.WriteLine("         expected:\n" + expected);
            Console.WriteLine("         actual:\n" + actual);
            Failures++;
        }
    }
}

int Main()
{
    var harness = new Harness();

    TestRoundTrip(harness);
    TestReindenting(harness);
    TestRefusing(harness);
    TestEditing(harness);
    TestQuoting(harness);
    TestGenerating(harness);

    Console.WriteLine(harness.Failures == 0u ? "all checks passed" : "checks FAILED");
    return harness.Failures == 0u ? 0 : 1;
}

/// Everything the format can hold, in the writer's own layout.
String CreateWholeForm() =>
    "// The greeter.\n"
    + "//\n"
    + "// Two lines of header.\n"
    + "\n"
    + "module Samples.Greeter;\n"
    + "\n"
    + "import Forms.Drawing;\n"
    + "import Samples.Shared;\n"
    + "\n"
    + "// The window.\n"
    + "form MainForm : Form\n"
    + "{\n"
    + "    Text = \"Say \\\"hello\\\"\\n\";\n"
    + "    Bounds = 0, 0, 320, 140; // x, y, width, height\n"
    + "    Shown += OnShown;\n"
    + "\n"
    + "    // The one button.\n"
    + "    Button _greet\n"
    + "    {\n"
    + "        Text = \"Greet\";\n"
    + "        Bounds = 12, 12, 90, 26;\n"
    + "        Anchors = AnchorStyles.Top | AnchorStyles.Right;\n"
    + "        Click += OnGreet; // wired by the designer\n"
    + "    }\n"
    + "\n"
    + "    Panel _box\n"
    + "    {\n"
    + "        Dock = DockStyle.Bottom;\n"
    + "        Height = 0x20;\n"
    + "        Tag = -3;\n"
    + "        Ratio = 1.5;\n"
    + "\n"
    + "        Label _note\n"
    + "        {\n"
    + "            Text = \"\";\n"
    + "            Visible = false;\n"
    + "        }\n"
    + "\n"
    + "        // Nothing else yet.\n"
    + "    }\n"
    + "}\n"
    + "\n"
    + "// Trailing.\n";

void TestRoundTrip(Harness harness)
{
    Console.WriteLine("round trip");

    String whole = CreateWholeForm();
    var read = ParseFormDocument(whole);
    harness.Check("the whole form reads", read.Ok);
    if (!read.Ok)
    {
        Console.WriteLine("         " + read.Error.Describe("whole.slfm"));
        return;
    }

    var document = read.Value;
    harness.CheckSame("module", "Samples.Greeter", document.Module);
    harness.Check("imports", document.Imports.Count == 2u &&
                             document.Imports[1u] == "Samples.Shared");
    harness.CheckSame("form name", "MainForm", document.Form.Name);
    harness.CheckSame("form base", "Form", document.Form.TypeName);
    harness.Check("header comments", document.HeaderComments.Count == 3u);
    harness.Check("trailing comments", document.TrailingComments.Count == 1u);

    FormComponent? greet = document.Form.FindComponent("_greet");
    harness.Check("a control is found by name", greet != null);
    if (greet != null)
    {
        var button = (FormComponent)greet;
        harness.CheckSame("its type", "Button", button.TypeName);
        FormProperty? anchors = button.FindProperty("Anchors");
        harness.Check("flags read as one item", anchors != null &&
            ((FormProperty)anchors).Value.Items.Count == 1u &&
            ((FormProperty)anchors).Value.Items[0u] == "AnchorStyles.Top | AnchorStyles.Right");
        FormHandler? click = button.FindHandler("Click");
        harness.Check("a handler", click != null && ((FormHandler)click).MethodName == "OnGreet");
    }

    FormProperty? bounds = document.Form.FindProperty("Bounds");
    harness.Check("a list has four items", bounds != null &&
                  ((FormProperty)bounds).Value.IsList &&
                  ((FormProperty)bounds).Value.Items.Count == 4u);
    harness.Check("a nested control is found", document.Form.FindComponent("_note") != null);

    harness.CheckSame("it writes back byte for byte", whole, WriteFormDocument(document));
}

void TestReindenting(Harness harness)
{
    Console.WriteLine("reindenting");

    String untidy = "module   M ;\r\nform F:Form{Text=\"x\";   Button b {Bounds=1,2 ,3,4;}\r\n\r\n\r\n"
        + "  Click+=OnClick;}";
    var read = ParseFormDocument(untidy);
    harness.Check("an untidy form reads", read.Ok);
    if (!read.Ok)
    {
        Console.WriteLine("         " + read.Error.Describe("untidy.slfm"));
        return;
    }

    String tidy = "module M;\n"
        + "\n"
        + "form F : Form\n"
        + "{\n"
        + "    Text = \"x\";\n"
        + "    Button b\n"
        + "    {\n"
        + "        Bounds = 1, 2, 3, 4;\n"
        + "    }\n"
        + "\n"
        + "    Click += OnClick;\n"
        + "}\n";
    harness.CheckSame("it is written in the one layout", tidy, WriteFormDocument(read.Value));
}

void CheckRefused(Harness harness, String what, String text, int line, String saying)
{
    var read = ParseFormDocument(text);
    if (read.Ok)
    {
        harness.Check(what, false);
        return;
    }

    var error = read.Error;
    bool passed = error.Line == line && error.Message.Contains(saying);
    harness.Check(what, passed);
    if (!passed)
        Console.WriteLine("         got: " + error.Describe("refused.slfm"));
}

void TestRefusing(Harness harness)
{
    Console.WriteLine("refusing");

    CheckRefused(harness, "no module", "form F : Form {}", 1, "starts with 'module");
    CheckRefused(harness, "a missing brace, where the file ends",
                 "module M;\nform F : Form\n{\n    Button b\n    {\n}\n", 7, "'}' is missing");
    CheckRefused(harness, "a stray character", "module M;\nform F : Form\n{\n    Text = @;\n}", 4,
                 "'@' has no meaning");
    CheckRefused(harness, "an open string", "module M;\nform F : Form\n{\n    Text = \"x;\n}", 4,
                 "not closed");
    CheckRefused(harness, "a second form", "module M;\nform F : Form {}\nform G : Form {}", 3,
                 "one form");
    CheckRefused(harness, "a comment between imports",
                 "module M;\nimport A;\n// lost\nimport B;\nform F : Form {}", 4, "would be lost");
    CheckRefused(harness, "a member that is none of the three",
                 "module M;\nform F : Form\n{\n    Text;\n}", 4, "expected '=', '+='");
    CheckRefused(harness, "a value that is not one",
                 "module M;\nform F : Form\n{\n    Text = ;\n}", 4, "expected a value");
}

void TestEditing(Harness harness)
{
    Console.WriteLine("editing");

    var read = ParseFormDocument(CreateWholeForm());
    if (!read.Ok)
    {
        harness.Check("the whole form reads", false);
        return;
    }
    var document = read.Value;
    FormComponent form = document.Form;

    form.SetProperty("Text", FormValue.FromText("Changed"));
    harness.CheckSame("an existing property keeps its place", "Text=\"Changed\"",
                      DescribeFormMember(form.Members[0u]));

    form.SetProperty("Enabled", FormValue.FromBoolean(false));
    harness.CheckSame("a new property goes after the last property", "Enabled=false",
                      DescribeFormMember(form.Members[2u]));

    form.SetHandler("Shown", "OnFirstShown");
    FormHandler? shown = form.FindHandler("Shown");
    harness.Check("a handler is rewired", shown != null &&
                  ((FormHandler)shown).MethodName == "OnFirstShown");

    form.SetHandler("Closed", "OnClosed");
    harness.CheckSame("a new handler goes before the controls", "Closed+=OnClosed",
                      DescribeFormMember(form.Members[4u]));

    form.SetHandler("Closed", "");
    harness.Check("an empty method unwires", form.FindHandler("Closed") == null);

    harness.Check("a nested control is removed", form.RemoveComponent("_note"));
    harness.Check("and is gone", form.FindComponent("_note") == null);
    harness.Check("removing what is not there says so", !form.RemoveComponent("_note"));

    var greet = (FormComponent)form.FindComponent("_greet");
    greet.SetProperty("Bounds", FormValue.FromRectangle(20, 30, 100, 40));
    harness.CheckSame("a rectangle is four integers", "20, 30, 100, 40",
                      ((FormProperty)greet.FindProperty("Bounds")).Value.ToFormText());

    harness.Check("a property is removed", greet.RemoveProperty("Anchors"));
    harness.Check("and is gone", greet.FindProperty("Anchors") == null);

    var reread = ParseFormDocument(WriteFormDocument(document));
    harness.Check("what an edit wrote reads back", reread.Ok);
}

/// A member in a line, for comparing one.
String DescribeFormMember(FormMember member)
{
    if (member is FormProperty property)
        return property.Name + "=" + property.Value.ToFormText();
    if (member is FormHandler handler)
        return handler.EventName + "+=" + handler.MethodName;
    if (member is FormComponent component)
        return component.TypeName + " " + component.Name;
    return "";
}

void TestQuoting(Harness harness)
{
    Console.WriteLine("quoting");

    String awkward = "a \"quote\", a \\ and\na line";
    String quoted = QuoteFormText(awkward);
    harness.CheckSame("quoted", "\"a \\\"quote\\\", a \\\\ and\\na line\"", quoted);
    harness.CheckSame("and back", awkward, UnquoteFormText(quoted));
    harness.CheckSame("what is not quoted is itself", "DockStyle.Fill",
                      UnquoteFormText("DockStyle.Fill"));
}

void TestGenerating(Harness harness)
{
    Console.WriteLine("generating");

    String form = "module Samples.Greeter;\n"
        + "\n"
        + "import Forms.Drawing;\n"
        + "\n"
        + "form MainForm : Form\n"
        + "{\n"
        + "    Text = \"Hello\";\n"
        + "    Bounds = 0, 0, 320, 140;\n"
        + "\n"
        + "    Button _greet\n"
        + "    {\n"
        + "        Text = \"Greet\";\n"
        + "        Click += OnGreet;\n"
        + "    }\n"
        + "\n"
        + "    Panel _box\n"
        + "    {\n"
        + "        Label _note\n"
        + "        {\n"
        + "            Dock = DockStyle.Fill;\n"
        + "        }\n"
        + "    }\n"
        + "}\n";

    String expected = "// Generated from MainForm.slfm. Edit that file or the designer;\n"
        + "// this one is rewritten from it.\n"
        + "module Samples.Greeter;\n"
        + "\n"
        + "import Forms;\n"
        + "import Forms.Drawing;\n"
        + "\n"
        + "public class MainForm : Form\n"
        + "{\n"
        + "    private Button _greet;\n"
        + "    private Panel _box;\n"
        + "    private Label _note;\n"
        + "\n"
        + "    private void InitializeComponent()\n"
        + "    {\n"
        + "        Text = \"Hello\";\n"
        + "        SetBounds(0, 0, 320, 140);\n"
        + "\n"
        + "        _greet = new Button(this);\n"
        + "        _greet.Text = \"Greet\";\n"
        + "        _greet.Click += this.OnGreet;\n"
        + "\n"
        + "        _box = new Panel(this);\n"
        + "\n"
        + "        _note = new Label(_box);\n"
        + "        _note.Dock = DockStyle.Fill;\n"
        + "    }\n"
        + "}\n";

    var read = ParseFormDocument(form);
    harness.Check("the form reads", read.Ok);
    if (!read.Ok)
        return;
    harness.CheckSame("the generated half", expected,
                      GenerateFormSource(read.Value, "MainForm.slfm"));
    harness.CheckSame("its path", "forms" + "/" + "MainForm.designer.sl",
                      FindDesignerPath("forms/MainForm.slfm").Replace("\\", "/"));
}
