module Bad;

import Standard.Reflection;

// Not marked [Reflect], so it carries no metadata.
public class Plain { public int Value; }

int Main() {
    var type = typeof(Plain);
    return 0;
}
