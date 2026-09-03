// SPDX-License-Identifier: 0BSD
module Bad;

public class Person {
    public int Age { get; set; }
    public Person() { Age = 0; }
}

int Main() {
    var person = new Person();

    // The accessors are the lowering, not the language.
    return person.get_Age();
}
