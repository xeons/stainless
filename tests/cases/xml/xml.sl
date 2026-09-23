// SPDX-License-Identifier: 0BSD
//
// `Standard.Xml`, in the two layers `Standard.Json` has: the document, which
// needs no type, and the mapping onto one through a `[Reflect]` type's fields.
module XmlTest;

import Standard.Xml;
import Standard.Console;
import Standard.Collections;
import Standard.Reflection;

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

void Round(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Xml.DescribeXmlError(parsed.Error));
        return;
    }
    Say(label, Xml.ToXmlText(parsed.Value));
}

void Refuse(String label, String source)
{
    var parsed = Xml.Parse(source);
    if (parsed.Ok)
    {
        Say(label, "accepted, and should not have been");
        return;
    }
    Say(label, Xml.DescribeXmlError(parsed.Error));
}

// ---------------------------------------------------------------- the mapping

[Reflect]
public class Endpoint
{
    public String Host;
    public int Port;

    public Endpoint()
    {
        Host = "";
        Port = 0;
    }
}

[Reflect]
public class Settings
{
    // An attribute rather than a child element, which is what makes the
    // output look like XML somebody wrote.
    [XmlAttribute]
    public String Environment;

    [XmlAttribute]
    public int Version;

    public String Name;
    public bool Enabled;
    public double Threshold;

    [XmlName("retry-limit")]
    public int Retries;

    [XmlIgnore]
    public int Internal;

    public Endpoint Primary;

    // An array is repeated children of one name, which is how XML says a
    // sequence.
    public String[] Hosts;

    public Settings()
    {
        Environment = "";
        Version = 0;
        Name = "";
        Enabled = false;
        Threshold = 0.0;
        Retries = 0;
        Internal = 77;
        Primary = new Endpoint();
        Hosts = new String[2];
        Hosts[0u] = "";
        Hosts[1u] = "";
    }
}

public int Main()
{
    // -------------------------------------------------------- round trips
    Round("empty", "<a/>");
    Round("empty-pair", "<a></a>");
    Round("text", "<a>hello</a>");
    Round("children", "<a><b>1</b><c>2</c></a>");
    Round("attributes", "<a x=\"1\" y='2'>t</a>");
    Round("nested", "<a><b><c><d>deep</d></c></b></a>");
    Round("spaces", "<a   x = \"1\"   >  t  </a>");

    // The five predefined entities, and numeric references in both bases.
    Round("entities", "<a>&lt;&gt;&amp;&quot;&apos;</a>");
    Round("numeric", "<a>&#65;&#x42;&#x1F600;</a>");
    Round("in-attribute", "<a x=\"&lt;&amp;&gt;\"/>");

    // Everything that is skipped rather than kept.
    Round("comment", "<!-- before --><a><!-- inside -->t</a><!-- after -->");
    Round("declaration", "<?xml version=\"1.0\"?><a/>");
    Round("instruction", "<a><?target data?>t</a>");
    Round("doctype", "<!DOCTYPE a [<!ENTITY x \"y\">]><a/>");

    // CDATA is text with nothing expanded, which is what it is for.
    Round("cdata", "<a><![CDATA[<b>&amp;</b>]]></a>");

    // A name may be anything a namespace prefix makes of it, because prefixes
    // are not resolved -- the name is the whole of what was written.
    Round("prefixed", "<x:a xmlns:x=\"urn:z\"><x:b/></x:a>");

    // --------------------------------------------------------------- refusals
    Refuse("mismatched", "<a></b>");
    Refuse("unclosed", "<a>");
    Refuse("unclosed-tag", "<a");
    Refuse("no-root", "   <!-- only a comment -->  ");
    Refuse("two-roots", "<a/><b/>");
    Refuse("bad-name", "<1a/>");
    Refuse("unknown-entity", "<a>&nbsp;</a>");
    Refuse("unquoted-attribute", "<a x=1/>");
    Refuse("closing-first", "</a>");
    Refuse("empty-document", "");

    // ---------------------------------------------------------- the document
    var parsed = Xml.Parse(
        "<config env=\"live\"><name>server</name><name>second</name>" +
        "<port>8080</port></config>");

    if (parsed.Ok)
    {
        var root = parsed.Value;
        Say("root-name", root.Name);
        Say("attribute", root.Attributes.GetValueOrDefault("env", "?"));
        Say("missing-attribute", root.Attributes.GetValueOrDefault("nope", "(default)"));
        Say("child-text", root.FindChildText("name", "?"));
        Say("missing-child", root.FindChildText("nope", "(default)"));
        Say("named-count", Text.FromInteger((long)root.FindChildren("name").Count));
        Say("child-count", Text.FromInteger((long)root.Children.Count));
    }

    // Building one by hand.
    var built = new XmlNode("root");
    built.Attributes.Add("id", "7");
    var item = new XmlNode("item");
    item.Text = "a < b & c";
    built.Add(item);

    Say("built", Xml.ToXmlText(built));
    Console.WriteLine("document =");
    Console.WriteLine(Xml.ToXmlDocumentText(built));

    // ----------------------------------------------------------- serializing
    var settings = new Settings();
    settings.Environment = "production";
    settings.Version = 3;
    settings.Name = "primary & backup";
    settings.Enabled = true;
    settings.Threshold = 0.75;
    settings.Retries = 5;
    settings.Internal = 42;
    settings.Primary.Host = "example.com";
    settings.Primary.Port = 443;

    Say("serialized", Xml.Serialize(settings, "settings"));

    // --------------------------------------------------------- deserializing
    var loaded = new Settings();
    var failure = Xml.PopulateObject(loaded,
        "<settings Environment=\"staging\" Version=\"9\">" +
        "<Name>read back</Name><Enabled>true</Enabled>" +
        "<Threshold>1.25</Threshold><retry-limit>2</retry-limit>" +
        "<Internal>1</Internal>" +
        "<Primary><Host>localhost</Host><Port>80</Port></Primary>" +
        "</settings>");

    Say("populate", Xml.DescribeXmlError(failure));
    Say("round-tripped", Xml.Serialize(loaded, "settings"));

    // Ignored in both directions, so the constructor's value stands.
    Say("ignored-kept", Text.FromInteger((long)loaded.Internal));

    // A document that mentions nothing leaves everything as it was.
    var partial = new Settings();
    partial.Name = "unchanged";
    Xml.PopulateObject(partial, "<settings><Enabled>1</Enabled></settings>");
    Say("partial", partial.Name + "/" + Text.FromBool(partial.Enabled));

    // A value that is not a number for a number's field is left alone rather
    // than guessed at.
    var typed = new Settings();
    typed.Retries = 4;
    Xml.PopulateObject(typed, "<settings><retry-limit>not a number</retry-limit></settings>");
    Say("wrong-type", Text.FromInteger((long)typed.Retries));

    Say("bad-document", Xml.DescribeXmlError(Xml.PopulateObject(partial, "<a>")));

    // Arrays, out and back.
    var listed = new Settings();
    listed.Hosts[0u] = "one";
    listed.Hosts[1u] = "two";
    Say("array-out", Xml.Serialize(listed, "settings"));

    var read = new Settings();
    Xml.PopulateObject(read, "<settings><Hosts>a</Hosts><Hosts>b</Hosts><Hosts>c</Hosts></settings>");
    Say("array-in", read.Hosts[0u] + "/" + read.Hosts[1u]);

    return 0;
}
