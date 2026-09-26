// SPDX-License-Identifier: 0BSD
module Variance;

import Standard.Console;
import Standard.Collections;

public class Animal
{
    public String Name;

    public Animal(String name) => Name = name;
    ~Animal() { Console.WriteLine("~" + Name); }

    public virtual String Sound() => "...";
}

public class Dog : Animal, IComparable<Animal>
{
    public Dog(String name) : base(name) { }

    public override String Sound() => "woof";
    public int CompareTo(Animal other) => Name.CompareTo(other.Name);
}

// `out`: a value only comes out, so a source of dogs is a source of animals.
public interface ISource<out T>
{
    T Next();
    ISource<T> Again() => this;

    // A generic method of a variant interface is a slot per instantiation, and
    // the converted reference reaches the same ones.
    String Tagged<U>(U tag) => "tag";
}

// `in`: a value only goes in, so a sink for animals is a sink for dogs.
public interface ISink<in T>
{
    String Put(T item);
}

public class Kennel : ISource<Dog>, ISink<Animal>
{
    int _made;

    public Dog Next()
    {
        _made++;
        return new Dog("rex" + Text.FromInteger(_made));
    }

    public String Put(Animal item) => "put " + item.Name;
    public String Tagged<U>(U tag) => "kennel";
}

// Variance composes: a source of sources of dogs is a source of sources of animals.
public class Nest : ISource<ISource<Dog>>
{
    public ISource<Dog> Next() => new Kennel();
}

public closure TResult Maker<out TResult>();
public closure void Taker<in T>(T item);

String Drain(ISource<Animal> source) => source.Next().Name + " says " + source.Next().Sound();

int Main()
{
    var kennel = new Kennel();

    ISource<Dog> dogs = kennel;
    ISource<Animal> animals = dogs;
    Console.WriteLine(Drain(animals));
    Console.WriteLine(Drain(kennel));
    Console.WriteLine(animals.Again().Next().Name);
    Console.WriteLine(animals.Tagged(1) + " " + dogs.Tagged("x"));

    ISink<Dog> dogSink = kennel;
    Console.WriteLine(dogSink.Put(new Dog("fido")));

    ISource<ISource<Animal>> nested = new Nest();
    Console.WriteLine(nested.Next().Next().Sound());

    // `is` answers for what a reference may be converted to.
    Console.WriteLine(Text.FromBool(kennel is ISource<Animal>) + " " +
                      Text.FromBool(kennel is ISink<Dog>));

    // Closures convert the same way, and need nothing at run time to.
    Maker<Dog> makeDog = () => new Dog("spot");
    Maker<Animal> makeAnimal = makeDog;
    Console.WriteLine(makeAnimal().Sound());

    Taker<Animal> takeAnimal = a => Console.WriteLine("took " + a.Name);
    Taker<Dog> takeDog = takeAnimal;
    takeDog(new Dog("max"));

    // The standard library's interfaces and closures are variant too.
    var pack = new List<Dog>();
    pack.Add(new Dog("b"));
    pack.Add(new Dog("a"));

    IEnumerable<Animal> all = pack;
    foreach (var animal in all)
        Console.WriteLine(animal.Name);

    IReadOnlyList<Animal> listed = pack;
    Console.WriteLine(listed[1].Name);

    Func<Animal, String> named = a => a.Name + "!";
    var names = Select(pack, named);
    Console.WriteLine(names[0]);

    // A constraint is met through variance: Dog compares with any Animal.
    Sort(pack);
    Console.WriteLine(pack[0].Name + pack[1].Name);
    return 0;
}
