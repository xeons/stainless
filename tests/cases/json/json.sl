// SPDX-License-Identifier: 0BSD
//
// `Standard.Json`, in both of its layers: the document, which needs no type,
// and the mapping onto one, which reads the field tables a `[Reflect]` type
// carries.
module JsonTest;

import Standard.Json;
import Standard.Console;
import Standard.Collections;
import Standard.Reflection;

// --------------------------------------------------------------- the document

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

void Round(String label, String text)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Json.Describe(parsed.Error));
        return;
    }
    Say(label, Json.Write(parsed.Value));
}

void Refuse(String label, String text)
{
    var parsed = Json.Parse(text);
    if (parsed.Ok)
    {
        Say(label, "accepted, and should not have been");
        return;
    }
    Say(label, Json.Describe(parsed.Error));
}

// ---------------------------------------------------------------- the mapping

[Reflect]
public class Address
{
    public String City;
    public String Country;

    public Address()
    {
        City = "";
        Country = "";
    }
}

[Reflect]
public class Person
{
    public String Name;
    public int Years;
    public bool Active;
    public double Rating;

    // The document calls this something else.
    [JsonName("id")]
    public long Identifier;

    // And never mentions this one, in either direction.
    [JsonIgnore]
    public int Secret;

    // A nested object is walked rather than stopped at.
    public Address Where;

    public Person()
    {
        Name = "";
        Years = 0;
        Active = false;
        Rating = 0.0;
        Identifier = 0;
        Secret = 999;
        Where = new Address();
    }
}

// An array walks; a `List<T>` still cannot, because its own fields are its
// private storage and filling one would mean calling `Add`. What cannot be
// walked is left out rather than misstated -- writing `null` for it says the
// value was absent when it was not.
// An array field the constructor never sized. There is no length for a reader
// to fill in place, which used to mean the document was dropped and the field
// stayed null -- so an array had to be pre-sized by a constructor that could
// not know the size.
[Reflect]
public class Sparse
{
    public String Name;
    public String[] Tags;
    public int[] Counts;

    public Sparse() => Name = "kept";
}

[Reflect]
public class Bag
{
    public String Name;
    public String[] Tags;
    public List<String> More;
    public Plain Untagged;
    public int[] Counts;

    public Bag()
    {
        Name = "kept";
        Tags = new String[2];
        More = new List<String>();
        Untagged = new Plain();
        Counts = new int[2];
        Tags[0u] = "";
        Tags[1u] = "";
    }
}

// A class with no [Reflect] of its own: nothing to walk, so nothing written.
public class Plain
{
    public int Value;
    public Plain() => Value = 1;
}

public int Main()
{
    // ------------------------------------------------------- round trips
    Round("empty-object", "{}");
    Round("empty-array", "[]");
    Round("scalars", "[1,-2,3.5,1e2,true,false,null]");
    Round("nested", "{\"a\":{\"b\":{\"c\":[1,[2,[3]]]}}}");
    Round("spaces", "  {  \"a\"  :  1  ,  \"b\"  :  2  }  ");

    // Escapes, in both directions. The tab and the newline come back as their
    // short forms rather than as \u0009.
    Round("escapes", "\"a\\\"b\\\\c\\/d\\te\\nf\"");
    Round("control", "\"\\u0001\\u001f\"");

    // A surrogate pair is one code point; a lone half is U+FFFD, which is what
    // the rest of the library does with anything malformed.
    Round("astral", "\"\\ud83d\\ude00\"");
    Round("lone-surrogate", "\"\\ud83d\"");

    // A number keeps its integer spelling when it has one, because JSON has
    // only the one numeric type and a reader wanting an integer should get it.
    Round("integers", "[0,-0,42,-42,9007199254740992]");
    Round("fractions", "[0.5,-0.25,1.5e3]");

    // ------------------------------------------------------------ refusals
    Refuse("trailing", "{} {}");
    Refuse("unclosed-object", "{\"a\":1");
    Refuse("unclosed-string", "\"abc");
    Refuse("leading-zero", "01");
    Refuse("bare-dot", "1.");
    Refuse("plus", "+1");
    Refuse("bad-escape", "\"\\q\"");
    Refuse("bad-literal", "tru");
    Refuse("empty", "");
    Refuse("comma-only", "[1,]");

    // ---------------------------------------------------------- the document
    var built = Json.NewObject();
    var members = Json.MembersOf(built);
    members.Add("name", JsonValue.Text("built by hand"));
    members.Add("count", Json.NumberOf(3));

    var items = Json.NewArray();
    Json.ItemsOf(items).Add(JsonValue.Bool(true));
    Json.ItemsOf(items).Add(JsonValue.Null);
    members.Add("items", items);

    Say("built", Json.Write(built));
    Say("found", Json.TextOr(members.Find("name"), "?"));
    Say("missing", Json.TextOr(members.Find("nope"), "(default)"));
    Say("as-number", Text.FromInteger(Json.IntegerOr(members.Find("count"), 0)));

    Console.WriteLine("indented =");
    Console.WriteLine(Json.WriteIndented(built));

    // ----------------------------------------------------------- serializing
    var person = new Person();
    person.Name = "Ada Lovelace";
    person.Years = 36;
    person.Active = true;
    person.Rating = 9.5;
    person.Identifier = 1815;
    person.Secret = 42;
    person.Where.City = "London";
    person.Where.Country = "England";

    Say("serialized", Json.Serialize(person));

    // --------------------------------------------------------- deserializing
    var loaded = new Person();
    var failure = Json.Populate(loaded,
        "{\"Name\":\"Grace Hopper\",\"Years\":85,\"Active\":false," +
        "\"Rating\":10.0,\"id\":1906,\"Secret\":7," +
        "\"Where\":{\"City\":\"New York\",\"Country\":\"USA\"}}");

    Say("populate", Json.Describe(failure));
    Say("round-tripped", Json.Serialize(loaded));

    // `Secret` is ignored in both directions, so the constructor's value stands
    // even though the document named it.
    Say("ignored-kept", Text.FromInteger((long)loaded.Secret));

    // A field the document leaves out keeps what the constructor gave it.
    var partial = new Person();
    partial.Name = "unchanged";
    Json.Populate(partial, "{\"Years\":1}");
    Say("partial", partial.Name + "/" + Text.FromInteger((long)partial.Years));

    // A document of the wrong shape is refused rather than half-applied.
    Say("not-an-object", Json.Describe(Json.Populate(partial, "[1,2]")));
    Say("bad-document", Json.Describe(Json.Populate(partial, "{")));

    // And a value of the wrong type for its field is skipped, which leaves the
    // field as it was rather than guessing at a conversion.
    var typed = new Person();
    typed.Years = 5;
    Json.Populate(typed, "{\"Years\":\"not a number\",\"Name\":123}");
    Say("wrong-types", typed.Name + "/" + Text.FromInteger((long)typed.Years));

    // A document read into an object made for it, which is the whole of what
    // deserializing is here: there is no `Deserialize<Person>(text)`, because
    // a type argument cannot be written at a call.
    var made = new Person();
    var madeFailure = Json.Populate(made, "{\"Name\":\"Alan Turing\",\"Years\":41}");
    Say("deserialized", Json.Describe(madeFailure) + "/" + made.Name + "/"
        + Text.FromInteger((long)made.Years) + "/[" + made.Where.City + "]");

    var bag = new Bag();
    bag.Tags[0u] = "walked";
    bag.More.Add("not walked");
    Say("arrays", Json.Serialize(bag));

    // Read back into an array the object already has. A document with more
    // elements than the array fills what fits; one with fewer leaves the rest.
    var filled = new Bag();
    Json.Populate(filled, "{\"Tags\":[\"one\",\"two\",\"three\"]}");
    Say("array-longer", Json.Serialize(filled));

    var shorter = new Bag();
    shorter.Tags[0u] = "kept";
    Json.Populate(shorter, "{\"Tags\":[]}");
    Say("array-shorter", Json.Serialize(shorter));

    // An array the constructor never made. The elements have already been
    // parsed by the time this is reached, so taking the length from the
    // document costs an allocation the document has paid for.
    var sparse = new Sparse();
    Json.Populate(sparse, "{\"Tags\":[\"a\",\"b\",\"c\"],\"Counts\":[4,5]}");
    Say("array-null", Json.Serialize(sparse));

    // And an empty one is still an array rather than a null, so a reader can
    // tell "the document said none" from "the document said nothing".
    var none = new Sparse();
    Json.Populate(none, "{\"Tags\":[]}");
    Say("array-empty", Json.Serialize(none));

    // A file with a UTF-8 byte order mark in front of it, which is what
    // Notepad and PowerShell 5.1 write by default -- so a hand-edited config
    // file on Windows very often has one. It is skipped rather than refused:
    // RFC 8259 says a parser may ignore one, and refusing it rejects a file
    // that looks perfectly correct in every editor.
    String marked = "﻿{\"Tags\":[\"x\"]}";
    var withMark = new Sparse();
    Json.Populate(withMark, marked);
    Say("bom", Json.Serialize(withMark));

    // And one that is *only* a mark is still an empty document, not a value.
    Say("bom-alone", Json.Parse("﻿").Ok ? "parsed" : "refused");

    // A mark that is not at the start is content, and content is not a value
    // the grammar allows before a brace.
    Say("bom-inside", Json.Parse("{﻿}").Ok ? "parsed" : "refused");

    return 0;
}
