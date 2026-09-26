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
    void Push(T item);                           // SL0801
}

// An `in` parameter handed out.
public interface IConsumer<in T>
{
    T Last();                                    // SL0801
}

// Through an `in` parameter of another interface the position turns round.
public interface IFactory<out T>
{
    ISink<T> Sink();                             // SL0801
}

// An array is written through as well as read.
public interface IBatch<out T>
{
    T[] All();                                   // SL0801
}

// A property with a setter is both.
public interface IHolder<out T>
{
    T Value { get; set; }                        // SL0801
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
    IList2<Animal> animals = new Dogs();         // SL0265

    // Variance is for references: an int is not a long by the same pointer.
    IBox<long> longs = new IntBox();             // SL0265
    return 0;
}
