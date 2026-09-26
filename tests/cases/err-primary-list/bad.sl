// SPDX-License-Identifier: 0BSD
//
// A parameter list after the name is a constructor, so only a class or a
// struct takes one, and arguments after a base type are that constructor's
// call to the base's.
module Bad;

public interface INamed { }

public class Shape(String name) { }

public class Square : Shape("square") { }

public class Circle(double radius) : INamed, Shape("circle") { }

public interface IMeasured(int unit) { }

int Main() => 0;
