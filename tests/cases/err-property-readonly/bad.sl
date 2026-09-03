// SPDX-License-Identifier: 0BSD
module Bad;

public class Person {
    public int Id { get; }
    public String Name { get; set; }

    public Person(int id) { Id = id; Name = "x"; }

    // Computed, so there is nothing to write at all.
    public int Doubled => Id * 2;
}

int Main() {
    var person = new Person(1);

    // Neither of these is storage anything may assign to from out here.
    person.Id = 2;
    person.Doubled = 4;
    return 0;
}
