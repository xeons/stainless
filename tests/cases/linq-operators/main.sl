// SPDX-License-Identifier: 0BSD
//
// LINQ's operators over an array and over a list, called both as functions
// and on the sequence.
module LinqOperators;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

public class Person
{
    public String Name { get; }
    public String City { get; }
    public int Age { get; }

    public Person(String name, String city, int age)
    {
        Name = name;
        City = city;
        Age = age;
    }
}

String Show(IEnumerable<int> values)
{
    String text = "[";
    foreach (int v in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger(v);
    return text + "]";
}

String Names(IEnumerable<Person> people)
{
    String text = "";
    foreach (var p in people)
        text += (text == "" ? "" : ",") + p.Name;
    return text;
}

int Main()
{
    int[] numbers = [5, 3, 8, 1, 9, 2];
    var list = ToList(numbers);

    // Elements.
    Console.WriteLine("first " + Text.FromInteger(numbers.First()) + " " +
        Text.FromInteger(list.First((n) => n > 5)) + " " + Text.FromInteger(list.FirstOrDefault(0)) + " " +
        Text.FromInteger(Enumerable.Empty<int>().FirstOrDefault(-1)));
    Console.WriteLine("last " + Text.FromInteger(numbers.Last()) + " " +
        Text.FromInteger(list.Last((n) => n < 5)) + " " + Text.FromInteger(list.LastOrDefault((n) => n > 100, 7)));
    Console.WriteLine("single " + Text.FromInteger(numbers.Single((n) => n == 8)) + " " +
        Text.FromInteger(list.SingleOrDefault((n) => n > 100, 4)) + " " +
        Text.FromInteger(ToList([42]).Single()));
    Console.WriteLine("at " + Text.FromInteger(list.ElementAt(2)) + " " +
        Text.FromInteger(list.ElementAtOrDefault(20, -1)) + " " + (list.Any() ? "any" : "none") + " " +
        Text.FromInteger((int)list.Count()) + " " + (list.Contains(9) ? "has 9" : "no 9"));

    // Aggregates.
    Console.WriteLine("sum " + Text.FromInteger(numbers.Sum()) + " " + Text.FromInteger(list.Sum()) + " " +
        Text.FromDouble(numbers.Average()) + " " + Text.FromInteger(numbers.Min()) + " " +
        Text.FromInteger(list.Max()));
    long[] big = [4000000000, 5000000000];
    double[] halves = [0.5, 1.5];
    Console.WriteLine("types " + Text.FromInteger(big.Sum()) + " " + Text.FromDouble(halves.Sum()) + " " +
        Text.FromDouble(halves.Average()));

    var people = new List<Person>();
    people.Add(new Person("Ada", "London", 36));
    people.Add(new Person("Alan", "London", 41));
    people.Add(new Person("Grace", "New York", 85));
    people.Add(new Person("Linus", "Helsinki", 21));
    people.Add(new Person("Barbara", "New York", 36));

    Console.WriteLine("by " + Text.FromInteger(people.Sum((p) => p.Age)) + " " +
        Text.FromDouble(people.Average((p) => (double)p.Age)) + " " +
        Text.FromInteger(people.Max((p) => p.Age)) + " " + people.MinBy((p) => p.Age).GetValue().Name + " " +
        people.MaxBy((p) => p.Age).GetValue().Name + " " + Text.FromInteger(numbers.Aggregate((a, b) => a * b)));

    // Ordering.
    Console.WriteLine("order " + Show(numbers.Order()) + " " + Show(list.OrderDescending()) + " " +
        Names(people.OrderBy((p) => p.Age).ThenBy((p) => p.Name)) + " " +
        Names(people.OrderByDescending((p) => p.City).ThenByDescending((p) => p.Age)));
    Console.WriteLine("cities " + Names(OrderBy(people, (a, b) => a.City.CompareTo(b.City)).ThenBy((p) => p.Name)));

    // Grouping and gathering.
    foreach (var group in people.GroupBy((p) => p.City))
        Console.WriteLine("group " + group.Key + " " + Text.FromInteger((int)group.Count) + " " + Names(group));
    foreach (var group in numbers.GroupBy((n) => n % 2, (n) => n * 10))
        Console.WriteLine("parity " + Text.FromInteger(group.Key) + " " + Show(group));

    var ages = people.ToDictionary((p) => p.Name, (p) => p.Age);
    Console.WriteLine("dictionary " + Text.FromInteger(ages.GetValue("Grace")) + " " +
        Text.FromInteger((int)people.ToDictionary((p) => p.Name).GetValue("Ada").Age) + " " +
        Text.FromInteger((int)ToList([1, 2, 2, 3, 3, 3]).ToHashSet().Count));

    // Combining.
    int[] more = [7, 3];
    Console.WriteLine("combine " + Show(numbers.Concat(more)) + " " + Show(list.Append(0)) + " " +
        Show(list.Prepend(0)) + " " + Show(numbers.Zip(more, (a, b) => a + b)));
    foreach (var (n, m) in numbers.Zip(more))
        Console.WriteLine("pair " + Text.FromInteger(n) + " " + Text.FromInteger(m));
    foreach (var chunk in numbers.Chunk(4))
        Console.WriteLine("chunk " + Show(ToList(chunk)));
    Console.WriteLine("while " + Show(numbers.TakeWhile((n) => n > 2)) + " " + Show(list.SkipWhile((n) => n > 2)) +
        " " + Show(numbers.TakeLast(2)) + " " + Show(list.SkipLast(4)));
    Console.WriteLine("many " + Show(more.SelectMany((n) => Enumerable.Repeat(n, 2))) + " " +
        Show(Enumerable.Range(3, 4)));

    int[] left = [1, 2, 3, 4, 2];
    int[] right = [3, 4, 5, 3];
    Console.WriteLine("sets " + Show(left.Union(right)) + " " + Show(left.Intersect(right)) + " " +
        Show(left.Except(right)) + " " + Names(people.DistinctBy((p) => p.City)));
    Console.WriteLine("setsBy " + Names(people.ExceptBy(["London"], (p) => p.City)) + " " +
        Names(people.IntersectBy(["Helsinki"], (p) => p.City)) + " " +
        Show(left.UnionBy(right, (n) => n % 3)) + " " +
        (list.SequenceEqual(ToList(numbers)) ? "equal" : "differ"));
    return 0;
}
