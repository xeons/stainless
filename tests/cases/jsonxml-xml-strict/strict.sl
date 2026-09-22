// SPDX-License-Identifier: 0BSD
//
// `Standard.Xml` held to XML 1.0: line ends and attribute values normalized,
// malformed documents refused, well-formed ones accepted, and a document that
// reads back as what was written.
module XmlStrictTest;

import Standard.Xml;
import Standard.Console;
import Standard.Collections;
import Standard.Reflection;

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

/// The text with its whitespace made visible.
String Visible(String text)
{
    return text.Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");
}

void Round(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Xml.Describe(parsed.Error));
        return;
    }
    Say(label, Visible(Xml.Write(parsed.Value)));
}

void TextOf(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Xml.Describe(parsed.Error));
        return;
    }
    Say(label, "[" + Visible(parsed.Value.Text) + "]");
}

void AttributeOf(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Xml.Describe(parsed.Error));
        return;
    }
    Say(label, "[" + Visible(parsed.Value.Attributes.Find("x", "?")) + "]");
}

void Refuse(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (parsed.Ok)
    {
        Say(label, "accepted, and should not have been");
        return;
    }
    Say(label, Xml.Describe(parsed.Error));
}

/// Writes indented, reads that back, and writes it again: the two MUST match.
void Settle(String label, String source)
{
    var first = Xml.Parse(source);
    if (!first.Ok)
    {
        Say(label, "failed: " + Xml.Describe(first.Error));
        return;
    }

    var once = Xml.WriteIndented(first.Value);
    var second = Xml.Parse(once);
    if (!second.Ok)
    {
        Say(label, "failed to read back: " + Xml.Describe(second.Error));
        return;
    }

    var twice = Xml.WriteIndented(second.Value);
    Say(label, Visible(once) + (once == twice ? " (stable)" : " (grew: " + Visible(twice) + ")"));
}

[Reflect]
public class Service
{
    [XmlAttribute]
    public int Weight;

    public int Port;
    public bool Enabled;
    public double Ratio;
    public long Count;

    public Service()
    {
        Weight = 0;
        Port = 0;
        Enabled = false;
        Ratio = 0.0;
        Count = 0;
    }
}

public int Main()
{
    // ------------------------------------------------------------ writing
    Settle("text-and-child", "<a>hello<b/></a>");
    Settle("children", "<a><b>1</b><c><d/></c></a>");
    Settle("deep-text", "<a><b>x<c>y</c></b><e/></a>");

    // Whitespace between child elements is indentation, not content.
    TextOf("indentation", "<a>\n  <b/>\n  <c/>\n</a>");
    TextOf("leaf-spaces", "<a>  </a>");
    TextOf("mixed", "<a>x <b/> </a>");
    TextOf("cdata-space", "<a><![CDATA[ ]]><b/></a>");
    TextOf("reference-space", "<a>&#32;<b/></a>");

    // ---------------------------------------------------------- line ends
    TextOf("crlf", "<a>1\r\n2\r3\n4</a>");
    TextOf("cr-reference", "<a>1&#13;2</a>");
    Round("cr-written", "<a>1&#13;2</a>");
    TextOf("cdata-crlf", "<a><![CDATA[1\r\n2]]></a>");
    Round("crlf-document", "<a>\r\n  <b>x</b>\r\n</a>\r\n");

    // --------------------------------------------------- attribute values
    AttributeOf("attribute-whitespace", "<a x=\"1\t2\n3\r\n4\"/>");
    AttributeOf("attribute-references", "<a x=\"1&#9;2&#10;3&#13;4\"/>");
    Round("attribute-written", "<a x=\"1&#9;2&#10;3\"/>");

    // ----------------------------------------------------------- refusals
    Refuse("lt-in-attribute", "<a x=\"<\"/>");
    Refuse("attributes-touching", "<a b=\"1\"c=\"2\"/>");
    Refuse("reference-zero", "<a>&#0;</a>");
    Refuse("reference-control", "<a>&#1;</a>");
    Refuse("reference-surrogate", "<a>&#xD800;</a>");
    Refuse("reference-fffe", "<a>&#xFFFE;</a>");
    Refuse("reference-too-big", "<a>&#x110000;</a>");
    Refuse("reference-huge", "<a>&#99999999999999999999;</a>");
    Refuse("reference-upper-x", "<a>&#X41;</a>");
    Refuse("cdata-end-in-text", "<a>]]></a>");
    Refuse("double-hyphen", "<!-- a -- b --><a/>");
    Refuse("comment-hyphen-end", "<a><!-- x ---></a>");
    Refuse("doctype-after-root", "<a/><!DOCTYPE a>");
    Refuse("doctype-twice", "<!DOCTYPE a><!DOCTYPE a><a/>");
    Refuse("doctype-inside", "<a><!DOCTYPE a></a>");
    Refuse("declaration-after-root", "<a/><?xml version=\"1.0\"?>");
    Refuse("declaration-late", "<!-- c --><?xml version=\"1.0\"?><a/>");
    Refuse("declaration-inside", "<a><?xml version=\"1.0\"?></a>");
    Refuse("raw-control", "<a>\u0001</a>");

    // ---------------------------------------------------------- accepted
    Round("leading-zeros-hex", "<a>&#x0000000041;</a>");
    Round("leading-zeros-decimal", "<a>&#0000000065;</a>");
    Round("brackets-in-text", "<a>]] ]></a>");
    Round("subset-literal", "<!DOCTYPE a [ <!ENTITY e \"]>\"> ]><a/>");
    Round("subset-apostrophe", "<!DOCTYPE a [ <!ENTITY e ']>'> ]><a/>");
    Round("subset-comment", "<!DOCTYPE a [ <!-- ] > --> ]><a/>");
    Round("system-literal", "<!DOCTYPE a SYSTEM \"x>y\"><a/>");
    Round("stylesheet", "<?xml version=\"1.0\"?><?xml-stylesheet href=\"s\"?><a/>");
    Round("empty-comment", "<a><!----></a>");
    Round("byte-order-mark", "\uFEFF<?xml version=\"1.0\"?><a/>");

    // --------------------------------------------------------- the mapping
    var service = new Service();
    var failure = Xml.Populate(service,
        "<Service Weight=\" 3 \">\r\n  <Port>\r\n 8080\r\n</Port>\r\n" +
        "  <Enabled> true </Enabled>\r\n  <Ratio> 0.5 </Ratio>\r\n" +
        "  <Count>\n7\n</Count>\r\n</Service>");
    Say("populate", Xml.Describe(failure));
    Say("trimmed", Xml.Serialize(service, "Service"));

    // A double with no finite value is written in XML Schema's spelling, and
    // read back as itself.
    double zero = 0.0;
    var odd = new Service();
    odd.Ratio = -1.0 / zero;
    var written = Xml.Serialize(odd, "Service");
    Say("infinite", written);
    var back = new Service();
    Xml.Populate(back, written);
    Say("infinite-back", Xml.Serialize(back, "Service"));

    odd.Ratio = zero / zero;
    written = Xml.Serialize(odd, "Service");
    Say("nan", written);
    var nan = new Service();
    Xml.Populate(nan, written);
    Say("nan-back", nan.Ratio != nan.Ratio ? "NaN" : "not NaN");

    // A numeral past what a double holds is not read as an infinity.
    var over = new Service();
    over.Ratio = 2.0;
    Xml.Populate(over, "<Service><Ratio>1e400</Ratio></Service>");
    Say("overflow", Xml.Serialize(over, "Service"));

    return 0;
}
