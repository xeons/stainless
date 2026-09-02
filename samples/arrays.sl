module Arrays;

import Standard.Console;

int Sum(int[] values) {
    var total = 0;
    for (int i = 0; i < (int)values.Length; i = i + 1) {
        total = total + values[i];
    }
    return total;
}

int Main() {
    var numbers = new int[5];
    for (int i = 0; i < 5; i = i + 1) {
        numbers[i] = i * i;
    }

    Console.WriteLine("length = " + Text.FromInteger(numbers.Length));
    Console.WriteLine("sum    = " + Text.FromInteger(Sum(numbers)));

    // Arrays of references: each element is retained and released.
    var words = new String[3];
    words[0] = "alpha";
    words[1] = "beta";
    words[2] = "gamma" + "!";

    var joined = new StringBuilder();
    for (int i = 0; i < 3; i = i + 1) {
        joined.Append(words[i]);
        joined.Append(" ");
    }
    Console.WriteLine(joined.ToText());

    var zeroed = new int[3];
    Console.WriteLine("zeroed = " + Text.FromInteger(zeroed[0] + zeroed[1] + zeroed[2]));
    return 0;
}
