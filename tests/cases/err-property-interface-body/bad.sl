// SPDX-License-Identifier: 0BSD
module Bad;

public interface INamed {
    // An interface declares signatures, so an accessor has no body.
    String Name { get { return "x"; } }
}

int Main() { return 0; }
