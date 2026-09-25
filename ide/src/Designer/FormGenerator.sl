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

// A form file, turned into the half of the form's class that builds it.
//
// The output is one declaration of the class: a field per control, and
// `InitializeComponent`. The other declaration is the person's, and holds the
// constructor that calls it and the handlers it wires.
//
// It is generated syntactically, with no knowledge of Forms' types. A value
// is copied as written; several values go to `SetName(...)` rather than to
// `Name`; a handler is `+=` on `this.Method`. The compiler checks the result.
module Ide.Designer;

import Standard.Collections;
import Standard.Directory;
import Standard.File;
import Standard.IO;
import Standard.Path;
import Standard.Text;

/// The generated half's path for a form file: `MainForm.slfm` beside
/// `MainForm.designer.sl`.
public String FindDesignerPath(String formPath)
{
    String directory = Path.GetDirectoryName(formPath);
    String name = Path.GetFileNameWithoutExtension(formPath);
    return Path.Join(directory, name + ".designer.sl");
}

/// The source of the generated half, under the form file's header comments --
/// which is where a licence line goes.
///
/// @param document    the form
/// @param sourceName  the form file's name, for the header
public String GenerateFormSource(FormDocument document, String sourceName)
{
    var text = new StringBuilder();
    for (nuint i = 0u; i < document.HeaderComments.Count; i++)
        text.AppendLine("//" + document.HeaderComments[i]);
    if (document.HeaderComments.Count > 0u)
        text.AppendLine();
    text.AppendLine("// Generated from " + sourceName + ". Edit that file or the designer;");
    text.AppendLine("// this one is rewritten from it.");
    text.AppendLine("module " + document.Module + ";");
    text.AppendLine();
    text.AppendLine("import Forms;");
    for (nuint i = 0u; i < document.Imports.Count; i++)
    {
        if (document.Imports[i] != "Forms")
            text.AppendLine("import " + document.Imports[i] + ";");
    }
    text.AppendLine();

    FormComponent form = document.Form;
    text.AppendLine("public class " + form.Name + " : " + form.TypeName);
    text.AppendLine("{");

    var fields = new List<FormComponent>();
    CollectFormFields(form, fields);
    for (nuint i = 0u; i < fields.Count; i++)
        text.AppendLine("    private " + fields[i].TypeName + " " + fields[i].Name + ";");
    if (fields.Count > 0u)
        text.AppendLine();

    text.AppendLine("    private void InitializeComponent()");
    text.AppendLine("    {");
    var body = new StringBuilder();
    GenerateFormMembers(body, form, "");
    text.Append(body.ToText());
    text.AppendLine("    }");
    text.AppendLine("}");
    return text.ToText();
}

/// Generates the half and writes it beside the form file, only if what is
/// there differs -- so a build that regenerates everything does not make
/// everything look changed.
///
/// @returns whether the file was written
public Result<bool, String> WriteFormSource(FormDocument document, String formPath)
{
    String path = FindDesignerPath(formPath);
    String source = GenerateFormSource(document, Path.GetFileName(formPath));

    var existing = File.ReadAllText(path);
    if (existing.Ok && existing.Value == source)
        return Ok(false);

    if (File.WriteAllText(path, source) != IOError.None)
        return Fail("could not write '" + path + "'");
    return Ok(true);
}

void CollectFormFields(FormComponent component, List<FormComponent> into)
{
    for (nuint i = 0u; i < component.Members.Count; i++)
    {
        if (component.Members[i] is FormComponent child)
        {
            into.Add(child);
            CollectFormFields(child, into);
        }
    }
}

/// The statements that set up one component, in the order the file gives
/// them. `target` is empty for the form, and a field's name followed by a dot
/// for a control.
void GenerateFormMembers(StringBuilder text, FormComponent component, String target)
{
    String indent = "        ";
    String parent = target == "" ? "this" : component.Name;

    for (nuint i = 0u; i < component.Members.Count; i++)
    {
        FormMember member = component.Members[i];

        if (member is FormProperty property)
        {
            if (property.Value.IsList)
                text.AppendLine(indent + target + "Set" + property.Name + "(" +
                                property.Value.ToFormText() + ");");
            else
                text.AppendLine(indent + target + property.Name + " = " +
                                property.Value.ToFormText() + ";");
        }
        else if (member is FormHandler handler)
        {
            text.AppendLine(indent + target + handler.EventName + " += this." +
                            handler.MethodName + ";");
        }
        else if (member is FormComponent child)
        {
            if (text.HasContent)
                text.AppendLine();
            text.AppendLine(indent + child.Name + " = new " + child.TypeName + "(" + parent + ");");
            GenerateFormMembers(text, child, child.Name + ".");
        }
    }
}

/// Every form file under a directory, at any depth.
public Result<List<String>, String> FindFormFiles(String root)
{
    var all = Directory.GetAllFiles(root);
    if (!all.Ok)
        return Fail("could not list '" + root + "'");

    var forms = new List<String>();
    foreach (var path in all.Value)
    {
        if (Path.GetExtension(path) == ".slfm")
            forms.Add(path);
    }
    return Ok(forms);
}

/// Regenerates the half of every form file named, writing only what changed.
///
/// Every file is tried, so one bad form does not hide what is wrong with the
/// next. The failure names each form that could not be read or written, one
/// per line.
///
/// @returns how many files were written
public Result<nuint, String> RegenerateFormSources(List<String> formPaths)
{
    nuint written = 0u;
    var failures = new StringBuilder();

    foreach (var path in formPaths)
    {
        var read = ReadFormDocument(path);
        if (!read.Ok)
        {
            failures.AppendLine(read.Error.Describe(path));
            continue;
        }

        var wrote = WriteFormSource(read.Value, path);
        if (!wrote.Ok)
            failures.AppendLine(wrote.Error);
        else if (wrote.Value)
            written++;
    }

    if (failures.HasContent)
        return Fail(failures.ToText().TrimEnd());
    return Ok(written);
}
