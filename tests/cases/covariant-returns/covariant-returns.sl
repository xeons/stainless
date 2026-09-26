// SPDX-License-Identifier: 0BSD
module CovariantReturns;

import Standard.Console;

public interface IShape
{
    String Describe();
}

public class Animal
{
    public String Name;

    public Animal(String name) => Name = name;
    ~Animal() { Console.WriteLine("~" + Name); }

    public virtual String Speak() => "...";
}

public class Dog : Animal
{
    public Dog(String name) : base(name) { }

    public override String Speak() => "woof";
    public String Fetch() => Name + " fetches";
}

public class Puppy : Dog
{
    public Puppy(String name) : base(name) { }

    public override String Speak() => "yip";
}

public class Circle : IShape
{
    public String Describe() => "circle";
    public double Radius => 2.0;
}

public class Shelter
{
    public virtual Animal Adopt() => new Animal("generic");
    public virtual Animal? Find(String name) => null;
    public virtual IShape Badge() => new Circle();
    public virtual Animal Favorite => new Animal("favorite");
}

// Each override narrows what it returns; a caller holding a DogShelter sees a Dog.
public class DogShelter : Shelter
{
    public override Dog Adopt() => new Dog("rex");
    public override Dog Find(String name) => new Dog(name);
    public override Circle Badge() => new Circle();
    public override Dog Favorite => new Dog("fido");
}

// And a further step narrows again.
public class PuppyShelter : DogShelter
{
    public override Puppy Adopt() => new Puppy("bit");
}

// A generic class overriding with a type argument.
public class Pen<T> : Shelter where T : Animal
{
    T _kept;

    public Pen(T kept) => _kept = kept;
    public override T Adopt() => _kept;
}

String Through(Shelter shelter) => shelter.Adopt().Speak();

int Main()
{
    var dogs = new DogShelter();
    Dog dog = dogs.Adopt();
    Console.WriteLine(dog.Fetch());
    Console.WriteLine(dogs.Find("max").Fetch());
    Console.WriteLine(Text.FromDouble(dogs.Badge().Radius));
    Console.WriteLine(dogs.Favorite.Fetch());

    // Through the base, the same override runs and is seen as the base type.
    Shelter shelter = dogs;
    Animal animal = shelter.Adopt();
    Console.WriteLine(animal.Speak());
    Console.WriteLine(shelter.Badge().Describe());
    Console.WriteLine(Through(new PuppyShelter()));
    Console.WriteLine(new PuppyShelter().Adopt().Fetch());

    var pen = new Pen<Dog>(new Dog("spot"));
    Console.WriteLine(pen.Adopt().Fetch());
    Console.WriteLine(Through(pen));

    // A lambda holding the narrower result.
    var make = () => dogs.Adopt();
    Console.WriteLine(make().Fetch());
    return 0;
}
