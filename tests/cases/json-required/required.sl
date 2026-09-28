// SPDX-License-Identifier: 0BSD
//
// What `Standard.Json` makes inside an object it is filling, it makes as `new`
// would and stores only once it is complete: every `required` member given by
// the document, and nothing whose type is never null left null. A document
// short of that fails the whole call, and what was made is released.
module JsonRequired;

import Standard.Json;
import Standard.Console;
import Standard.Reflection;

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

[Reflect]
public class Contact
{
    public required String Email;
    public String[] Phones;

    public Contact() => Phones = [];
}

[Reflect]
public class Customer
{
    public required String Name;
    public required Contact Contact;
    public required String? Note;
}

[Reflect]
public class Line
{
    public required String Sku;
    public required int Quantity;
    public String[] Options;

    public Line() => Options = [];
}

[Reflect]
public struct Money
{
    public String Currency;
    public long Cents;
}

[Reflect]
public class Sealed
{
    public String Reason;
    public Sealed(String reason) => Reason = reason;
}

[Reflect]
public class Order
{
    public String Id;

    [JsonCreate]
    public Customer? Customer;
    public Line[]? Lines;
    public Money[]? Payments;
    public String?[]? Aliases;

    [JsonCreate]
    public Sealed? Seal;

    public Order() => Id = "";
}

String Read(String document)
{
    var order = new Order();
    var failure = Json.PopulateObject(order, document);
    String answer = Json.DescribeJsonError(failure);
    if (failure == JsonError.None)
        return answer + ": " + Json.Serialize(order);

    return answer + ": customer " + (order.Customer == null ? "none" : "kept") +
        ", lines " + (order.Lines == null ? "none" : "kept") +
        ", payments " + (order.Payments == null ? "none" : "kept");
}

public int Main()
{
    // Everything the types need, and a `null` for the one member that may be.
    Say("complete", Read(
        "{\"Id\":\"7\",\"Customer\":{\"Name\":\"Ada\",\"Note\":null," +
        "\"Contact\":{\"Email\":\"ada@example.com\"}}," +
        "\"Lines\":[{\"Sku\":\"A\",\"Quantity\":2},{\"Sku\":\"B\",\"Quantity\":1}]," +
        "\"Payments\":[{\"Currency\":\"EUR\",\"Cents\":250}],\"Aliases\":[\"a\",null]}"));

    // A required member of a nested object the document leaves out.
    Say("no-name", Read(
        "{\"Customer\":{\"Note\":null,\"Contact\":{\"Email\":\"a@b\"}}}"));

    // A required member two levels down: the whole customer is discarded.
    Say("no-email", Read(
        "{\"Customer\":{\"Name\":\"Ada\",\"Note\":null,\"Contact\":{\"Phones\":[]}}}"));

    // A required object member the document leaves out.
    Say("no-contact", Read("{\"Customer\":{\"Name\":\"Ada\",\"Note\":null}}"));

    // A required member that may be null still has to be there.
    Say("no-note", Read(
        "{\"Customer\":{\"Name\":\"Ada\",\"Contact\":{\"Email\":\"a@b\"}}}"));

    // A required member of the wrong type is not a value of its type.
    Say("wrong-type", Read(
        "{\"Lines\":[{\"Sku\":\"A\",\"Quantity\":\"two\"}]}"));

    // One bad element discards the array it was in.
    Say("bad-element", Read(
        "{\"Lines\":[{\"Sku\":\"A\",\"Quantity\":1},{\"Quantity\":1}]}"));

    // A struct element's String is never null, and nothing fills it.
    Say("bad-struct", Read("{\"Payments\":[{\"Cents\":5}]}"));

    // What came before a failure stays filled; what failed is not reachable.
    Say("partial", Read(
        "{\"Customer\":{\"Name\":\"Ada\",\"Note\":\"x\",\"Contact\":{\"Email\":\"a@b\"}}," +
        "\"Lines\":[{\"Quantity\":1}]}"));

    // A type `new` could not make with nothing to say.
    Say("not-creatable", Read("{\"Seal\":{\"Reason\":\"no\"}}"));

    // A `null` clears a member that may be null, and makes nothing.
    var reply = new Order();
    Say("null-customer", Json.DescribeJsonError(
        Json.PopulateObject(reply, "{\"Customer\":null}")));

    return 0;
}
