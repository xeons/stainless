// Deriving across a module boundary.
//
// `protected` is the one visibility that crosses without being public, because
// deriving is exactly what the word is about. Module privacy is unchanged: a
// private member of the base is no more reachable here for being inherited.
module App;

import Standard.Console;
import Standard.Text;
import Zoo;

public class Dog : Quadruped {
    Dog(String called) {
        base(called);
    }

    public override String Sound() { return "woof"; }

    /// Both protected members of a base two modules away.
    public String Report() {
        return name + " on " + Legs() + " legs";
    }
}

public class Bird : Animal {
    Bird(String called) {
        base(called, 2);
    }

    public override String Sound() { return "tweet"; }

    /// An override that reaches the base implementation it replaced.
    public override String Speak() {
        return base.Speak() + ", quietly";
    }
}

int Main() {
    Animal dog = new Dog("rex");
    Animal bird = new Bird("pip");

    Console.WriteLine(dog.Speak());
    Console.WriteLine(bird.Speak());

    Console.WriteLine(((Dog)dog).Report());
    Console.WriteLine("public wrapper over a private base method: "
        + Text.FromInteger(dog.OwnTag()));

    Console.WriteLine("dog is Quadruped: " + Text.FromBool(dog is Quadruped));
    Console.WriteLine("bird is Quadruped: " + Text.FromBool(bird is Quadruped));

    return 0;
}
