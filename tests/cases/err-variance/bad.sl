// SPDX-License-Identifier: 0BSD
module Bad;

public class Animal { }
public class Dog : Animal { }

public interface ISink<in T>
{
    void Put(T item);
}

// An `out` parameter taken in: a source of dogs seen as a source of animals
// would be handed a cat.
public interface ISource<out T>
{
    T Next();
    void Push(T item);                           // SLG0023
}

// An `in` parameter handed out.
public interface IConsumer<in T>
{
    T Last();                                    // SLG0023
}

// Through an `in` parameter of another interface the position turns round.
public interface IFactory<out T>
{
    ISink<T> Sink();                             // SLG0023
}

// An array is written through as well as read.
public interface IBatch<out T>
{
    T[] All();                                   // SLG0023
}

// A property with a setter is both.
public interface IHolder<out T>
{
    T Value { get; set; }                        // SLG0023
}

public interface IList2<T>
{
    T At(int index);
}

public class Dogs : IList2<Dog>
{
    public Dog At(int index) => new Dog();
}

public interface IBox<out T>
{
    T Get();
}

public class IntBox : IBox<int>
{
    public int Get() => 1;
}

int Main()
{
    // An invariant interface does not convert, whatever its argument does.
    IList2<Animal> animals = new Dogs();         // SLT0018

    // Variance is for references: an int is not a long by the same pointer.
    IBox<long> longs = new IntBox();             // SLT0018
    return 0;
}
