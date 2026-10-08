module Main;

import Shapes;
import Stack;

int Main()
{
    Stack.Frame? held = null;
    if (held is Frame)
        return 1;
    return 0;
}
