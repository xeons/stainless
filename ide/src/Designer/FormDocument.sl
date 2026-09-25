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

// A form file, `.slfm`, read and written.
//
// This is the only reader of the format. The compiler never sees one: the
// designer and `slforms` generate `.designer.sl` from it, and that is what is
// built. docs/slfm.md is the format.
//
// Comments and order survive a read and a write, because the file is edited
// by hand as well as by the designer. A file already in the writer's layout
// comes back byte for byte; any other is reindented.
module Ide.Designer;

import Standard.Ascii;
import Standard.Collections;
import Standard.File;
import Standard.IO;
import Standard.Text;

// ================================================================== the model

/// One line of a block: a property, a handler or a nested component.
///
/// Carries the comments written above it, so a member moved or removed takes
/// its explanation with it.
public abstract class FormMember
{
    /// The comments above this member, each without its `//`.
    public List<String> Comments;

    /// Whether a blank line separates this member from the one before.
    public bool HasBlankLineBefore;

    protected FormMember()
    {
        Comments = new List<String>();
        HasBlankLineBefore = false;
    }
}

/// `Name = value;`
public class FormProperty : FormMember
{
    public String Name;
    public FormValue Value;

    /// A comment on the same line, after the `;`, without its `//`. Empty for
    /// none.
    public String TrailingComment;

    public FormProperty(String name, FormValue value)
    {
        base();
        Name = name;
        Value = value;
        TrailingComment = "";
    }
}

/// `Event += Method;` -- a handler, which is a method of the form's class.
public class FormHandler : FormMember
{
    public String EventName;
    public String MethodName;
    public String TrailingComment;

    public FormHandler(String eventName, String methodName)
    {
        base();
        EventName = eventName;
        MethodName = methodName;
        TrailingComment = "";
    }
}

/// `Type Name { ... }` -- a control, and what is set on it.
///
/// The form itself is one of these too, whose `TypeName` is what it derives
/// from.
public class FormComponent : FormMember
{
    public String TypeName;
    public String Name;
    public List<FormMember> Members;

    /// The comments between the last member and the `}`.
    public List<String> ClosingComments;
    public bool HasBlankLineBeforeClosing;

    public FormComponent(String typeName, String name)
    {
        base();
        TypeName = typeName;
        Name = name;
        Members = new List<FormMember>();
        ClosingComments = new List<String>();
        HasBlankLineBeforeClosing = false;
    }

    /// The property of that name, or null.
    public FormProperty? FindProperty(String name)
    {
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormProperty property)
            {
                if (property.Name == name)
                    return property;
            }
        }
        return null;
    }

    /// Sets a property, keeping its place and its comments if it is already
    /// there and adding it after the last property if not.
    public void SetProperty(String name, FormValue value)
    {
        FormProperty? existing = FindProperty(name);
        if (existing != null)
        {
            ((FormProperty)existing).Value = value;
            return;
        }

        nuint at = 0u;
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormProperty)
                at = i + 1u;
        }
        Members.Insert(at, new FormProperty(name, value));
    }

    /// Removes a property, answering whether there was one.
    public bool RemoveProperty(String name)
    {
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormProperty property)
            {
                if (property.Name == name)
                {
                    Members.RemoveAt(i);
                    return true;
                }
            }
        }
        return false;
    }

    /// The handler on that event, or null.
    public FormHandler? FindHandler(String eventName)
    {
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormHandler handler)
            {
                if (handler.EventName == eventName)
                    return handler;
            }
        }
        return null;
    }

    /// Wires an event to a method, replacing whatever it was wired to. An
    /// empty method name removes the handler.
    public void SetHandler(String eventName, String methodName)
    {
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormHandler handler)
            {
                if (handler.EventName != eventName)
                    continue;
                if (methodName == "")
                    Members.RemoveAt(i);
                else
                    handler.MethodName = methodName;
                return;
            }
        }

        if (methodName == "")
            return;

        nuint at = 0u;
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (!(Members[i] is FormComponent))
                at = i + 1u;
        }
        Members.Insert(at, new FormHandler(eventName, methodName));
    }

    /// The components directly inside this one, in order.
    public List<FormComponent> ListChildren()
    {
        var children = new List<FormComponent>();
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormComponent child)
                children.Add(child);
        }
        return children;
    }

    /// The component of that name at any depth, this one included, or null.
    public FormComponent? FindComponent(String name)
    {
        if (Name == name)
            return this;

        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormComponent child)
            {
                FormComponent? found = child.FindComponent(name);
                if (found != null)
                    return found;
            }
        }
        return null;
    }

    /// Removes a component at any depth below this one, answering whether it
    /// was found.
    public bool RemoveComponent(String name)
    {
        for (nuint i = 0u; i < Members.Count; i++)
        {
            if (Members[i] is FormComponent child)
            {
                if (child.Name == name)
                {
                    Members.RemoveAt(i);
                    return true;
                }
                if (child.RemoveComponent(name))
                    return true;
            }
        }
        return false;
    }
}

/// What a property is set to: one item, or several separated by commas.
///
/// An item is kept as the text it is written as, which is also its Stainless
/// spelling -- a string literal with its quotes and escapes, a number, or one
/// or more names joined by `|`. So the generator copies it rather than
/// rendering it, and nothing is lost to a round trip through a number.
public class FormValue
{
    public List<String> Items;

    public FormValue() => Items = new List<String>();

    /// Several items, which the generator passes to `SetName(...)` rather than
    /// assigning to `Name`.
    public bool IsList => Items.Count > 1u;

    /// A string, quoted and escaped.
    public static FormValue FromText(String text)
    {
        var value = new FormValue();
        value.Items.Add(QuoteFormText(text));
        return value;
    }

    public static FormValue FromInteger(long number)
    {
        var value = new FormValue();
        value.Items.Add(Text.FromInteger(number));
        return value;
    }

    public static FormValue FromBoolean(bool truth)
    {
        var value = new FormValue();
        value.Items.Add(truth ? "true" : "false");
        return value;
    }

    /// A name, or several joined by `|`: `DockStyle.Fill`,
    /// `AnchorStyles.Top | AnchorStyles.Left`.
    public static FormValue FromName(String name)
    {
        var value = new FormValue();
        value.Items.Add(name);
        return value;
    }

    /// Four integers, which is how `Bounds` is written.
    public static FormValue FromRectangle(int x, int y, int width, int height)
    {
        var value = new FormValue();
        value.Items.Add(Text.FromInteger(x));
        value.Items.Add(Text.FromInteger(y));
        value.Items.Add(Text.FromInteger(width));
        value.Items.Add(Text.FromInteger(height));
        return value;
    }

    /// The items as the file writes them.
    public String ToFormText()
    {
        var text = new StringBuilder();
        for (nuint i = 0u; i < Items.Count; i++)
        {
            if (i > 0u)
                text.Append(", ");
            text.Append(Items[i]);
        }
        return text.ToText();
    }
}

/// A form file: the module its class belongs to, what that class imports, and
/// the form.
public class FormDocument
{
    /// The comments above `module`, each without its `//`.
    public List<String> HeaderComments;

    public String Module;

    /// Modules the generated half imports besides `Forms`, in order.
    public List<String> Imports;

    /// The form. Its `Name` is the class, and its `TypeName` what the class
    /// derives from.
    public FormComponent Form;

    /// The comments after the form's `}`.
    public List<String> TrailingComments;

    public FormDocument(String moduleName, String name, String baseType)
    {
        HeaderComments = new List<String>();
        Module = moduleName;
        Imports = new List<String>();
        Form = new FormComponent(baseType, name);
        TrailingComments = new List<String>();
    }
}

/// Why a form file could not be read, and where.
public class FormSyntaxError
{
    /// One-based, as an editor counts.
    public int Line;
    public int Column;
    public String Message;

    public FormSyntaxError(int line, int column, String message)
    {
        Line = line;
        Column = column;
        Message = message;
    }

    /// `path:line:column: message`, the compiler's shape.
    public String Describe(String path) =>
        path + ":" + Text.FromInteger(Line) + ":" + Text.FromInteger(Column) + ": " + Message;
}

// ================================================================== reading

/// Reads a form file.
public Result<FormDocument, FormSyntaxError> ReadFormDocument(String path)
{
    var read = File.ReadAllText(path);
    if (!read.Ok)
        return Fail(new FormSyntaxError(1, 1, "could not read '" + path + "'"));
    return ParseFormDocument(read.Value);
}

/// Reads a form file from text already in hand.
public Result<FormDocument, FormSyntaxError> ParseFormDocument(String text)
{
    var parser = new FormParser(text);
    return parser.ParseDocument();
}

enum FormTokenKind
{
    Word,
    Number,
    Text,
    Comment,
    Punctuation,
    End,
}

struct FormToken
{
    public FormTokenKind Kind;
    public nuint Start;
    public nuint Length;
    public int Line;
    public int Column;
    /// The line the token ends on, which differs from `Line` for nothing today
    /// and is what a blank line is measured from.
    public int EndLine;
}

class FormParser
{
    private String _text;
    private List<FormToken> _tokens;
    private nuint _next;
    private FormSyntaxError? _error;

    public FormParser(String text)
    {
        _text = text;
        _tokens = new List<FormToken>();
        _next = 0u;
        _error = null;
    }

    public Result<FormDocument, FormSyntaxError> ParseDocument()
    {
        ScanFormText();
        if (_error != null)
            return Fail((FormSyntaxError)_error);

        var header = ReadComments();
        if (!AcceptWord("module"))
            return Fail(ReportHere("a form file starts with 'module Name;'"));
        String moduleName = ReadDottedName("the module's name");
        ExpectPunctuation(";");

        var imports = new List<String>();
        while (_error == null && IsWordAt(SkipComments(), "import"))
        {
            if (ReadComments().Count > 0u)
                return Fail(ReportHere("a comment between imports would be lost; " +
                                       "put it above 'module'"));
            AcceptWord("import");
            imports.Add(ReadDottedName("the imported module's name"));
            ExpectPunctuation(";");
        }

        var above = ReadComments();
        if (_error == null && !AcceptWord("form"))
            return Fail(ReportHere("expected 'form Name : BaseType'"));
        String name = ReadName("the form's name");
        ExpectPunctuation(":");
        String baseType = ReadDottedName("what the form derives from");
        if (_error != null)
            return Fail((FormSyntaxError)_error);

        var document = new FormDocument(moduleName, name, baseType);
        document.HeaderComments = header;
        document.Imports = imports;
        document.Form.Comments = above;
        ReadBlock(document.Form);

        document.TrailingComments = ReadComments();
        if (_error == null && Peek().Kind != FormTokenKind.End)
            Report(Peek(), "a form file holds one form, and this is after its '}'");

        if (_error != null)
            return Fail((FormSyntaxError)_error);
        return Ok(document);
    }

    // ---------------------------------------------------------------- blocks

    private void ReadBlock(FormComponent into)
    {
        ExpectPunctuation("{");

        while (_error == null)
        {
            nuint first = SkipComments();
            bool blank = HasBlankLineBefore(_next);
            var comments = ReadComments();
            FormToken token = Peek();

            if (IsPunctuationAt(first, "}"))
            {
                into.ClosingComments = comments;
                into.HasBlankLineBeforeClosing = blank;
                _next++;
                return;
            }

            if (token.Kind != FormTokenKind.Word)
            {
                Report(token, token.Kind == FormTokenKind.End
                    ? "the file ends inside '" + into.Name + "'; a '}' is missing"
                    : "expected a property, a handler or a control");
                return;
            }

            FormMember? member = ReadMember();
            if (member == null)
                return;

            var read = (FormMember)member;
            read.Comments = comments;
            read.HasBlankLineBefore = blank && into.Members.Count > 0u;
            into.Members.Add(read);
        }
    }

    /// `Name = value;`, `Event += Method;` or `Type Name { ... }`, decided by
    /// what follows the first name.
    private FormMember? ReadMember()
    {
        String first = ReadDottedName("a name");
        FormToken after = Peek();

        if (IsPunctuation(after, "="))
        {
            _next++;
            var value = ReadValue();
            if (value == null)
                return null;
            var property = new FormProperty(first, (FormValue)value);
            ExpectPunctuation(";");
            property.TrailingComment = ReadTrailingComment();
            return property;
        }

        if (IsPunctuation(after, "+="))
        {
            _next++;
            var handler = new FormHandler(first, ReadName("the handler's method"));
            ExpectPunctuation(";");
            handler.TrailingComment = ReadTrailingComment();
            return handler;
        }

        if (after.Kind == FormTokenKind.Word)
        {
            var child = new FormComponent(first, ReadName("the control's name"));
            if (_error == null)
                ReadBlock(child);
            return child;
        }

        Report(after, "expected '=', '+=' or a control's name after '" + first + "'");
        return null;
    }

    private FormValue? ReadValue()
    {
        var value = new FormValue();
        while (true)
        {
            String item = ReadValueItem();
            if (_error != null)
                return null;
            value.Items.Add(item);

            if (!IsPunctuation(Peek(), ","))
                return value;
            _next++;
        }
    }

    /// A string, a number, or names joined by `|`.
    private String ReadValueItem()
    {
        FormToken token = Peek();

        if (token.Kind == FormTokenKind.Text || token.Kind == FormTokenKind.Number)
        {
            _next++;
            return SpellToken(token);
        }

        if (IsPunctuation(token, "-") && PeekAt(_next + 1u).Kind == FormTokenKind.Number)
        {
            _next += 2u;
            return "-" + SpellToken(PeekAt(_next - 1u));
        }

        if (token.Kind != FormTokenKind.Word)
        {
            Report(token, "expected a value: a string, a number, or a name");
            return "";
        }

        var names = new StringBuilder();
        names.Append(ReadDottedName("a name"));
        while (_error == null && IsPunctuation(Peek(), "|"))
        {
            _next++;
            names.Append(" | ");
            names.Append(ReadDottedName("a name after '|'"));
        }
        return names.ToText();
    }

    // ---------------------------------------------------------------- names

    private String ReadName(String what)
    {
        FormToken token = Peek();
        if (token.Kind != FormTokenKind.Word)
        {
            Report(token, "expected " + what);
            return "";
        }
        _next++;
        return SpellToken(token);
    }

    private String ReadDottedName(String what)
    {
        var name = new StringBuilder();
        name.Append(ReadName(what));
        while (_error == null && IsPunctuation(Peek(), ".") &&
               PeekAt(_next + 1u).Kind == FormTokenKind.Word)
        {
            name.Append(".");
            name.Append(SpellToken(PeekAt(_next + 1u)));
            _next += 2u;
        }
        return name.ToText();
    }

    // ---------------------------------------------------------------- comments

    /// The comments at the cursor, consumed.
    private List<String> ReadComments()
    {
        var comments = new List<String>();
        while (Peek().Kind == FormTokenKind.Comment)
        {
            comments.Add(SpellComment(Peek()));
            _next++;
        }
        return comments;
    }

    /// A comment on the line the last token ended on, consumed; empty if there
    /// is none.
    private String ReadTrailingComment()
    {
        if (_next == 0u || _error != null)
            return "";
        FormToken token = Peek();
        if (token.Kind != FormTokenKind.Comment || token.Line != PeekAt(_next - 1u).EndLine)
            return "";
        _next++;
        return SpellComment(token);
    }

    /// Where the first token after any comments is, without consuming them.
    private nuint SkipComments()
    {
        nuint at = _next;
        while (PeekAt(at).Kind == FormTokenKind.Comment)
            at++;
        return at;
    }

    private bool HasBlankLineBefore(nuint at)
    {
        if (at == 0u)
            return false;
        return PeekAt(at).Line > PeekAt(at - 1u).EndLine + 1;
    }

    private String SpellComment(FormToken token) =>
        _text.Substring(token.Start + 2u, token.Length - 2u).TrimEnd();

    // ---------------------------------------------------------------- tokens

    private FormToken Peek() => PeekAt(_next);

    private FormToken PeekAt(nuint at) =>
        at < _tokens.Count ? _tokens[at] : _tokens[_tokens.Count - 1u];

    private String SpellToken(FormToken token) => _text.Substring(token.Start, token.Length);

    private bool IsPunctuation(FormToken token, String spelling) =>
        token.Kind == FormTokenKind.Punctuation && SpellToken(token) == spelling;

    private bool IsPunctuationAt(nuint at, String spelling) => IsPunctuation(PeekAt(at), spelling);

    private bool IsWordAt(nuint at, String word)
    {
        FormToken token = PeekAt(at);
        return token.Kind == FormTokenKind.Word && SpellToken(token) == word;
    }

    private bool AcceptWord(String word)
    {
        if (!IsWordAt(_next, word))
            return false;
        _next++;
        return true;
    }

    private void ExpectPunctuation(String spelling)
    {
        if (_error != null)
            return;
        if (IsPunctuation(Peek(), spelling))
        {
            _next++;
            return;
        }
        Report(Peek(), "expected '" + spelling + "'");
    }

    private FormSyntaxError ReportHere(String message)
    {
        if (_error == null)
            Report(Peek(), message);
        return (FormSyntaxError)_error;
    }

    /// Keeps the first error; the rest follow from it.
    private void Report(FormToken token, String message)
    {
        if (_error == null)
            _error = new FormSyntaxError(token.Line, token.Column, message);
    }

    // ---------------------------------------------------------------- scanning

    private void ScanFormText()
    {
        nuint size = _text.ByteLength();
        nuint at = 0u;
        int line = 1;
        nuint lineStart = 0u;

        // A byte order mark is three bytes to skip.
        if (size >= 3u && _text.GetByteAt(0u) == (byte)0xEF && _text.GetByteAt(1u) == (byte)0xBB &&
            _text.GetByteAt(2u) == (byte)0xBF)
        {
            at = 3u;
            lineStart = 3u;
        }

        while (at < size && _error == null)
        {
            byte c = _text.GetByteAt(at);
            int column = (int)(at - lineStart) + 1;

            if (c == (byte)'\n')
            {
                at++;
                line++;
                lineStart = at;
                continue;
            }

            if (c == (byte)' ' || c == (byte)'\t' || c == (byte)'\r')
            {
                at++;
                continue;
            }

            nuint start = at;
            FormTokenKind kind = FormTokenKind.Punctuation;

            if (c == (byte)'/' && at + 1u < size && _text.GetByteAt(at + 1u) == (byte)'/')
            {
                kind = FormTokenKind.Comment;
                while (at < size && _text.GetByteAt(at) != (byte)'\n')
                    at++;
                if (at > start && _text.GetByteAt(at - 1u) == (byte)'\r')
                    at--;
            }
            else if (c == (byte)'"')
            {
                kind = FormTokenKind.Text;
                at = ScanQuoted(at, line, column);
            }
            else if (Ascii.IsDigit(c))
            {
                kind = FormTokenKind.Number;
                at = ScanNumber(at);
            }
            else if (Ascii.IsLetter(c) || c == (byte)'_')
            {
                kind = FormTokenKind.Word;
                while (at < size && (Ascii.IsLetterOrDigit(_text.GetByteAt(at)) ||
                                     _text.GetByteAt(at) == (byte)'_'))
                    at++;
            }
            else if (c == (byte)'+' && at + 1u < size && _text.GetByteAt(at + 1u) == (byte)'=')
            {
                at += 2u;
            }
            else
            {
                switch (c)
                {
                    case (byte)'{':
                    case (byte)'}':
                    case (byte)';':
                    case (byte)',':
                    case (byte)'=':
                    case (byte)':':
                    case (byte)'.':
                    case (byte)'|':
                    case (byte)'-':
                        at++;
                        break;
                    default:
                        _error = new FormSyntaxError(line, column,
                            "'" + _text.Substring(at, 1u) + "' has no meaning in a form file");
                        return;
                }
            }

            FormToken token;
            token.Kind = kind;
            token.Start = start;
            token.Length = at - start;
            token.Line = line;
            token.Column = column;
            token.EndLine = line;
            _tokens.Add(token);
        }

        FormToken end;
        end.Kind = FormTokenKind.End;
        end.Start = size;
        end.Length = 0u;
        end.Line = line;
        end.Column = (int)(size - lineStart) + 1;
        end.EndLine = line;
        _tokens.Add(end);
    }

    /// Past the closing quote. A string MUST end on the line it starts on.
    private nuint ScanQuoted(nuint at, int line, int column)
    {
        nuint size = _text.ByteLength();
        at++;
        while (at < size)
        {
            byte c = _text.GetByteAt(at);
            if (c == (byte)'"')
                return at + 1u;
            if (c == (byte)'\n')
                break;
            at += c == (byte)'\\' && at + 1u < size ? 2u : 1u;
        }
        _error = new FormSyntaxError(line, column, "this string is not closed on its line");
        return at;
    }

    /// Decimal with an optional fraction, or hexadecimal after `0x`.
    private nuint ScanNumber(nuint at)
    {
        nuint size = _text.ByteLength();
        if (at + 1u < size && _text.GetByteAt(at) == (byte)'0' &&
            (_text.GetByteAt(at + 1u) == (byte)'x' || _text.GetByteAt(at + 1u) == (byte)'X'))
        {
            at += 2u;
            while (at < size && Ascii.IsHexDigit(_text.GetByteAt(at)))
                at++;
            return at;
        }

        while (at < size && Ascii.IsDigit(_text.GetByteAt(at)))
            at++;
        if (at + 1u < size && _text.GetByteAt(at) == (byte)'.' &&
            Ascii.IsDigit(_text.GetByteAt(at + 1u)))
        {
            at++;
            while (at < size && Ascii.IsDigit(_text.GetByteAt(at)))
                at++;
        }
        return at;
    }
}

// ================================================================== writing

/// The document as text, four spaces to a level.
public String WriteFormDocument(FormDocument document)
{
    var text = new StringBuilder();

    WriteFormComments(text, document.HeaderComments, "");
    if (document.HeaderComments.Count > 0u)
        text.AppendLine();

    text.AppendLine("module " + document.Module + ";");
    if (document.Imports.Count > 0u)
    {
        text.AppendLine();
        for (nuint i = 0u; i < document.Imports.Count; i++)
            text.AppendLine("import " + document.Imports[i] + ";");
    }

    text.AppendLine();
    WriteFormComments(text, document.Form.Comments, "");
    text.AppendLine("form " + document.Form.Name + " : " + document.Form.TypeName);
    WriteFormBlock(text, document.Form, "");

    if (document.TrailingComments.Count > 0u)
    {
        text.AppendLine();
        WriteFormComments(text, document.TrailingComments, "");
    }
    return text.ToText();
}

/// Writes the document back to a file.
public Result<bool, String> SaveFormDocument(FormDocument document, String path)
{
    if (File.WriteAllText(path, WriteFormDocument(document)) != IOError.None)
        return Fail("could not write '" + path + "'");
    return Ok(true);
}

void WriteFormBlock(StringBuilder text, FormComponent component, String indent)
{
    String inner = indent + "    ";
    text.AppendLine(indent + "{");

    for (nuint i = 0u; i < component.Members.Count; i++)
    {
        FormMember member = component.Members[i];
        if (member.HasBlankLineBefore && i > 0u)
            text.AppendLine();
        WriteFormComments(text, member.Comments, inner);

        if (member is FormProperty property)
        {
            text.Append(inner + property.Name + " = " + property.Value.ToFormText() + ";");
            WriteTrailingFormComment(text, property.TrailingComment);
        }
        else if (member is FormHandler handler)
        {
            text.Append(inner + handler.EventName + " += " + handler.MethodName + ";");
            WriteTrailingFormComment(text, handler.TrailingComment);
        }
        else if (member is FormComponent child)
        {
            text.AppendLine(inner + child.TypeName + " " + child.Name);
            WriteFormBlock(text, child, inner);
        }
    }

    if (component.ClosingComments.Count > 0u)
    {
        if (component.HasBlankLineBeforeClosing && component.Members.Count > 0u)
            text.AppendLine();
        WriteFormComments(text, component.ClosingComments, inner);
    }
    text.AppendLine(indent + "}");
}

void WriteFormComments(StringBuilder text, List<String> comments, String indent)
{
    for (nuint i = 0u; i < comments.Count; i++)
        text.AppendLine(indent + "//" + comments[i]);
}

void WriteTrailingFormComment(StringBuilder text, String comment)
{
    if (comment != "")
        text.Append(" //" + comment);
    text.AppendLine();
}

/// A string as a form file and Stainless both write it: quoted, with `"`,
/// `\` and the control characters escaped.
public String QuoteFormText(String text)
{
    var quoted = new StringBuilder();
    quoted.Append("\"");
    nuint size = text.ByteLength();
    for (nuint i = 0u; i < size; i++)
    {
        byte c = text.GetByteAt(i);
        switch (c)
        {
            case (byte)'"': quoted.Append("\\\""); break;
            case (byte)'\\': quoted.Append("\\\\"); break;
            case (byte)'\n': quoted.Append("\\n"); break;
            case (byte)'\r': quoted.Append("\\r"); break;
            case (byte)'\t': quoted.Append("\\t"); break;
            default: quoted.AppendByte(c); break;
        }
    }
    quoted.Append("\"");
    return quoted.ToText();
}

/// The text a quoted item stands for. An item that is not quoted is answered
/// as it is.
public String UnquoteFormText(String item)
{
    nuint size = item.ByteLength();
    if (size < 2u || item.GetByteAt(0u) != (byte)'"')
        return item;

    var text = new StringBuilder();
    for (nuint i = 1u; i + 1u < size; i++)
    {
        byte c = item.GetByteAt(i);
        if (c != (byte)'\\' || i + 2u >= size)
        {
            text.AppendByte(c);
            continue;
        }

        i++;
        switch (item.GetByteAt(i))
        {
            case (byte)'n': text.Append("\n"); break;
            case (byte)'r': text.Append("\r"); break;
            case (byte)'t': text.Append("\t"); break;
            case (byte)'0': text.AppendByte((byte)0); break;
            default: text.AppendByte(item.GetByteAt(i)); break;
        }
    }
    return text.ToText();
}
