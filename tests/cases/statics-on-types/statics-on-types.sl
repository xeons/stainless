// SPDX-License-Identifier: 0BSD
//
// `static` as C# means it: storage and members that belong to the type rather
// than to an instance of it, mutable or not.
//
// The one thing not copied is when a static constructor runs. C# runs it lazily
// before the type is first used, behind a guard checked on every static access
// -- a guard that has to become atomic the moment threads exist. This runs in
// the same pass the field initializers do, before `Main`, so there is no guard
// and no per-access cost. A program that can tell those apart is timing its own
// startup.
module StaticsOnTypes;

import Standard.Collections;

extern "C" int printf(byte* format, ...);

// -------------------------------------------------------- module storage

// Mutable, which the language refused until now on the grounds that nothing
// synchronizes it. What replaced that rule is a warning at the places a value
// really can reach a second thread, which is where the question is.
static int Started = 0;
static String Phase = "before";
static readonly int Limit = 10;

// -------------------------------------------------- storage on a type

public class Registry
{
    // Private to the type, and mutable: the count of everything ever made.
    static int s_made = 0;

    // Public, so it is read and written by naming the type.
    public static String Kind = "registry";

    // Readonly, so it is written once by its initializer -- and immortal, so
    // no retain or release touches it again.
    public static readonly String Version = "1";

    String _name;

    public Registry(String called)
    {
        _name = called;
        s_made = s_made + 1;
    }

    public String Name() => _name;

    // A static method reads the type's storage with no receiver at all.
    public static int Made() => s_made;

    // And a static property, which is two static methods wearing the spelling
    // of a field.
    public static int Doubled { get { return s_made * 2; } }

    public static String Label
    {
        get => Kind;
        set => Kind = value;
    }
}

// ------------------------------------------------------- a static class

// A class with no instances. A module is the better answer most of the time --
// it is a scope, so its members need no prefix inside it -- but this is a name
// that can sit inside a module, which is what a C# programmer reaches for.
public static class Defaults
{
    public static int Retries = 3;
    static readonly String s_Note = "defaults";

    public static String Describe() => s_Note;
    public static int Doubled() => Retries * 2;
}

// ---------------------------------------------------- a static constructor

public class Late
{
    public static int Ready = 0;
    public static String Note = "";
    public static List<String> Steps = new List<String>();

    // Runs after every static field's initializer, which is C#'s order and the
    // only one that makes a block able to arrange the fields it is there for.
    static Late()
    {
        Ready = 1;
        Note = "arranged";
        Steps.Add("first");
        Steps.Add("second");
    }
}

// One static reading another, which is what the initializers are sorted for:
// `Doubled` is computed from `Limit`, so `Limit` runs first whatever order
// they were written in.
static readonly int Doubled = Limit * 2;

public int Main()
{
    // Module storage, written.
    Started = Started + 5;
    Phase = "running";
    printf("module   = %d %s %d %d\n", Started, Phase.ToPointer(), Limit, Doubled);

    // Storage on a type, counted by the constructor.
    var a = new Registry("a");
    var b = new Registry("b");
    printf("made     = %d doubled=%d version=%s\n",
        Registry.Made(), Registry.Doubled, Registry.Version.ToPointer());

    // Read and written by naming the type, both as a field and as a property.
    printf("kind     = %s %s\n", Registry.Kind.ToPointer(), Registry.Label.ToPointer());
    Registry.Label = "renamed";
    printf("renamed  = %s %s\n", Registry.Kind.ToPointer(), Registry.Label.ToPointer());

    Registry.Kind = "direct";
    printf("direct   = %s\n", Registry.Label.ToPointer());

    // A static class.
    printf("defaults = %d %d %s\n",
        Defaults.Retries, Defaults.Doubled(), Defaults.Describe().ToPointer());

    Defaults.Retries = 9;
    printf("retries  = %d %d\n", Defaults.Retries, Defaults.Doubled());

    // The static constructor ran before any of this.
    printf("late     = %d %s %llu %s\n",
        Late.Ready, Late.Note.ToPointer(), Late.Steps.Count(),
        Late.Steps.At(1u).ToPointer());

    // A mutable static holding a reference is counted like any other slot: the
    // list it held is released when the next one replaces it.
    Late.Steps = new List<String>();
    Late.Steps.Add("replaced");
    printf("replaced = %llu %s\n", Late.Steps.Count(), Late.Steps.At(0u).ToPointer());

    printf("name     = %s %s\n", a.Name().ToPointer(), b.Name().ToPointer());
    return 0;
}
