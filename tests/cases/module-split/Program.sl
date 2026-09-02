module Program;

import Standard.Console;
import Shop.Catalog;

int Main() {
    Console.WriteLine(new Bundle(new Book("SICP")).Describe());
    return 0;
}
