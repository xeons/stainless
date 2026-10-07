# Diagnostics

Every diagnostic the compiler can report, with what it means. Generated from
`src/Stainless.Compiler/Source/Codes.cs` by `stainless explain --markdown`;
edit that file, not this one.

522 codes: 496 errors and 26 warnings.

A code is `SL`, the letter of its category, and a number within it:

| Letter | Category | Covers | Codes |
|---|---|---|---|
| P | Parsing | lexing, tokens, literals, preprocessor directives and grammar | 53 |
| N | Names | name lookup, modules and imports, duplicate declarations, visibility and receivers | 23 |
| T | Types | expression typing, operators, calls and arguments, conversions, casts, arrays, ranges, vectors and constants | 94 |
| G | Generics | type parameters and arguments, inference, constraints, variance and static abstract members | 24 |
| C | Classes and members | type and member declarations: inheritance, interfaces, overrides, constructors, properties, events, operators, enums, variants, records and attributes | 129 |
| F | Flow and patterns | statements and jumps, returns, switch, patterns, try, deconstruction, lambdas and local functions | 49 |
| O | Ownership and safety | ARC and weak references, null safety, zero values and definite initialisation, late, statics, parallel and thread safety | 34 |
| I | Interop | C and C++ linkage, foreign signatures, layout attributes and bit-fields, inline assembly, COM and Objective-C | 78 |
| L | Lint | warnings about legal but suspicious code, and documentation comments | 16 |
| D | Driver and build | entry point, libraries and their metadata, embedded files and sections, target-specific build output | 22 |

## P: Parsing

| Code | Severity | Means |
|---|---|---|
| SLP0001 | error | a character in the source begins no token |
| SLP0002 | error | a block comment is never closed |
| SLP0003 | error | a numeric literal has a prefix but no digits |
| SLP0004 | error | a numeric literal has a suffix it cannot take |
| SLP0005 | error | an integer literal does not fit in 64 bits |
| SLP0006 | error | a string literal, raw or interpolated, is never closed |
| SLP0007 | error | a character literal is never closed |
| SLP0008 | error | a hex escape has too few or the wrong number of hex digits |
| SLP0009 | error | a backslash escape is not one the language defines |
| SLP0010 | error | a character literal holds no character |
| SLP0011 | error | a floating-point literal is malformed |
| SLP0012 | error | the parser expected something other than what it found |
| SLP0013 | error | an extern or export names a linkage convention other than C or C++ |
| SLP0014 | error | extern or export is not followed by a linkage convention string |
| SLP0015 | error | a destructor's name is not the name of its enclosing type |
| SLP0016 | error | source is nested deeper than the compiler can process |
| SLP0017 | error | a property body contains something other than 'get', 'set' or 'init' |
| SLP0018 | error | a statement in a switch is not under a 'case' or 'default' label |
| SLP0019 | error | an indexing expression has no index |
| SLP0020 | error | an '#if' is never closed by '#endif' |
| SLP0021 | error | an '#elif' or second '#else' follows an '#else' |
| SLP0022 | error | a '#define' or '#undef' comes after the first declaration in the file |
| SLP0023 | error | a '#define' or '#undef' is given something other than one name |
| SLP0024 | error | an '#error' directive is reached |
| SLP0025 | warning | a '#warning' directive is reached |
| SLP0026 | error | a '#' line names no directive the language has |
| SLP0027 | error | an '#elif', '#else' or '#endif' has no '#if' to belong to |
| SLP0028 | error | a conditional directive's condition is missing or malformed |
| SLP0029 | error | a '#pragma' is not 'comment(lib, ...)' or 'comment(framework, ...)' |
| SLP0030 | error | a '#pragma comment(lib, ...)' library name is missing or not quoted |
| SLP0031 | error | a Unicode escape names a value that is not a Unicode scalar |
| SLP0032 | error | an interpolated string has a '}' that closes nothing |
| SLP0033 | error | an interpolated string has an empty '{}' hole |
| SLP0034 | error | an interpolation hole holds more than one expression |
| SLP0035 | error | an operator that cannot be overloaded is declared |
| SLP0036 | error | an indexer declares no index parameters |
| SLP0037 | error | a tuple type is written with fewer than two elements |
| SLP0038 | error | an 'asm' block is never closed |
| SLP0039 | error | 'asm' is not followed by a braced block of instructions |
| SLP0040 | error | an 'asm' operand does not say 'in', 'out' or 'inout' |
| SLP0041 | error | a constructor is followed by something other than ': base(...)' or ': this(...)' |
| SLP0042 | error | a constructor chains to another both after its parameters and in its body |
| SLP0043 | error | text follows the opening quotes of a multi-line raw string on the same line |
| SLP0044 | error | a multi-line raw string has no content or its closing quotes are not on their own line |
| SLP0045 | error | a line of a raw string is indented less than its closing quotes |
| SLP0046 | error | a raw string contains a run of quotes as long as its delimiter |
| SLP0047 | error | a run of braces in an interpolated string does not match the hole delimiter |
| SLP0048 | error | more than one '$' prefixes a string that is not raw |
| SLP0049 | error | an interpolated string is given the 'u8' suffix |
| SLP0050 | error | a conditional expression in an interpolation hole is not parenthesized |
| SLP0051 | error | a bare 'default' is used as a case pattern |
| SLP0052 | error | '[:]' is written in a type where 'Span<T>' or 'ReadOnlySpan<T>' is meant |
| SLP0053 | error | a variable named 'field' is declared inside a property accessor |

## N: Names

| Code | Severity | Means |
|---|---|---|
| SLN0001 | error | a name is declared twice in one module |
| SLN0002 | error | an import names a module that is not among the compiled sources |
| SLN0003 | warning | a file imports the module it belongs to |
| SLN0004 | error | a variable is declared at module scope, where only constants are allowed |
| SLN0005 | error | a type declares two members of one name |
| SLN0006 | error | two overloads of one function, operator, constructor or conversion share a signature |
| SLN0007 | error | two parameters of one function share a name |
| SLN0008 | error | a local name is declared twice in one scope |
| SLN0009 | error | a local takes the name of a parameter |
| SLN0010 | error | this is used outside an instance method, constructor or destructor |
| SLN0011 | error | a name matches nothing in scope |
| SLN0012 | error | a module has no public member with the name accessed |
| SLN0013 | error | a type has no member of the name used |
| SLN0014 | error | a declaration is not visible from where it is used |
| SLN0015 | error | an unqualified type name matches types in more than one module |
| SLN0016 | error | a qualified type name names a module that declares no such type |
| SLN0017 | error | a type name matches nothing in scope |
| SLN0018 | error | a file does not declare which module it belongs to |
| SLN0019 | error | a module-level function has the name of a variant case, which a bare call would build |
| SLN0020 | error | a member name is declared by more than one nameless member of a type |
| SLN0021 | error | a type is constructed from outside the module that owns its constructors |
| SLN0022 | error | an instance member is reached without an instance |
| SLN0023 | error | a static method is called through a value rather than its type |

## T: Types

| Code | Severity | Means |
|---|---|---|
| SLT0001 | error | a constant is initialized with something that is not a constant expression |
| SLT0002 | error | a var declaration has no initializer to infer its type from |
| SLT0003 | error | a condition is not of type bool |
| SLT0004 | error | the address of something with no storage is taken |
| SLT0005 | error | something other than a pointer is dereferenced |
| SLT0006 | error | an operator cannot be applied to the operands' types |
| SLT0007 | error | two operands have no common type for a binary operator |
| SLT0008 | error | an assignment or update targets a constant or something that is not a location |
| SLT0009 | error | a value is indexed by a type with no matching indexer |
| SLT0010 | error | an index, slice bound, from-end count or range bound is not an integer |
| SLT0011 | error | an explicit cast names a conversion that does not exist |
| SLT0012 | error | a method is used as a value without being called |
| SLT0013 | error | a call is made through a value that is not a delegate or closure |
| SLT0014 | error | a call passes the wrong number of arguments |
| SLT0015 | error | an argument's type does not match its parameter's type |
| SLT0016 | error | no overload accepts the arguments of a call |
| SLT0017 | error | more than one overload matches a call equally well |
| SLT0018 | error | a value cannot be implicitly converted to the type required |
| SLT0019 | error | a constant value lies outside the range of its target type |
| SLT0020 | error | a raw pointer type is formed over a reference type |
| SLT0021 | error | an optional type is formed over a type that cannot be null |
| SLT0022 | error | a variant case is constructed with the wrong number of fields |
| SLT0023 | error | a string operator is applied to a string and a value of another type |
| SLT0024 | error | 'void' is used where a value or its type is needed |
| SLT0025 | error | an array length is not an integer |
| SLT0026 | error | 'typeof' names a type that carries no metadata because it lacks '[Reflect]' |
| SLT0027 | error | 'typeof' is used without Standard.Reflection in the compilation |
| SLT0028 | error | an arm of a conditional expression produces no value |
| SLT0029 | error | the arms of a conditional expression have no common type |
| SLT0030 | error | an enum is compared with a value of a different type |
| SLT0031 | error | a function is converted to a type that is not a delegate or closure |
| SLT0032 | error | no overload of a method group matches the delegate or closure type |
| SLT0033 | error | a method group matches a delegate or closure type through more than one overload |
| SLT0034 | error | a function that carries state is converted to a delegate |
| SLT0035 | error | a field or property of a temporary struct is written, so the write is lost |
| SLT0036 | error | a flag operation is used on an enum that is not marked '[Flags]' |
| SLT0037 | error | 'HasFlag' is not given exactly one argument of the enum's own type |
| SLT0038 | error | a flag test reads the same expression twice; it must be put in a variable first |
| SLT0039 | error | a variant's case is named where a value of another type is expected |
| SLT0040 | error | a division or remainder has a constant zero divisor |
| SLT0041 | error | an expression with no storage is passed by 'ref' or 'out' |
| SLT0042 | error | a read-only location is passed as 'ref' or 'out' |
| SLT0043 | error | an argument for a ref or out parameter omits the keyword |
| SLT0044 | error | 'ref' or 'out' is written for a parameter of another mode |
| SLT0045 | error | a 'ref' or 'out' argument's type does not exactly match the parameter's |
| SLT0046 | error | an 'in' parameter is written to |
| SLT0047 | error | a slice is taken of a value that cannot be sliced |
| SLT0048 | error | a 'const' is declared with a type a constant cannot hold |
| SLT0049 | error | a 'const' is given a literal of the wrong kind for its declared type |
| SLT0050 | error | an inline array's length is not a constant |
| SLT0051 | error | an inline array asks for fewer than one element |
| SLT0052 | error | an inline array would be larger than a value can be |
| SLT0053 | error | a constant index is outside a fixed-length array or vector |
| SLT0054 | error | a parameter takes an inline array by value rather than by 'ref' or 'in' |
| SLT0055 | error | '->' is applied to a non-pointer, or a pointer to a type with no members |
| SLT0056 | error | a character value converts implicitly between encodings or does not fit one code unit |
| SLT0057 | error | an array literal targets a type that cannot be built from elements |
| SLT0058 | error | an array literal has a different number of elements than its inline array type |
| SLT0059 | error | an empty array literal has no element type to infer |
| SLT0060 | error | the elements of an array literal do not share one type |
| SLT0061 | error | 'var' is given an initializer whose type cannot be inferred |
| SLT0062 | error | an interpolation hole holds a value with no defined text form |
| SLT0063 | error | no declared operator overload accepts the operand types |
| SLT0064 | error | more than one operator overload accepts the operand types |
| SLT0065 | error | 'nameof' is given an expression that is not a name |
| SLT0066 | error | an increment or decrement is applied to a type that is not a number or pointer |
| SLT0067 | error | a call's arguments do not fit the parameters of the function or constructor it names |
| SLT0068 | error | a named argument is passed to something that takes its arguments only by position |
| SLT0069 | error | an element of a tuple is an expression that produces no value |
| SLT0070 | error | 'as' is applied to a value or a type it cannot ask about |
| SLT0071 | error | two user-defined conversions apply and nothing chooses between them |
| SLT0072 | error | an 'as' can never succeed, because no object is both types |
| SLT0073 | error | the type after 'as' is written optional, which 'as' already makes it |
| SLT0074 | error | an interpolation hole's format string is not allowed or not valid for its value |
| SLT0075 | error | an interpolation's alignment is not a constant integer |
| SLT0076 | error | a target-typed expression has no type to take |
| SLT0077 | error | a type name stands where a value is expected |
| SLT0078 | error | an assignment is made through '?.' or '?[' |
| SLT0079 | error | '^' or a range is applied to a type with no length |
| SLT0080 | error | a '..' spread names a value that is not an array, slice or enumerable |
| SLT0081 | error | a spread of unknown length fills a fixed-length inline array |
| SLT0082 | error | an element of a read-only span is written |
| SLT0083 | error | a setter or method that writes a struct is used on a read-only struct value |
| SLT0084 | error | a 128-bit integer type is used on a 32-bit target |
| SLT0085 | error | a generic function is used as a value rather than called |
| SLT0086 | error | a '..' spread yields elements that do not convert to the target's |
| SLT0087 | error | a vector constructor argument is named or passed by 'ref' or 'out' |
| SLT0088 | error | a lane write names one lane twice |
| SLT0089 | error | a vector function is applied to a vector of an element kind it does not take |
| SLT0090 | error | a vector is made from a vector with a different element type |
| SLT0091 | error | a vector is made from values that do not fill its lanes |
| SLT0092 | error | a compound lane write targets a vector that is not a stable location |
| SLT0093 | error | a constant expression's value lies outside its type |
| SLT0094 | error | a constant's value depends on itself |

## G: Generics

| Code | Severity | Means |
|---|---|---|
| SLG0001 | error | a property or field declares type parameters |
| SLG0002 | error | a 'static abstract' or 'static virtual' interface member is generic |
| SLG0003 | error | a generic is given the wrong number of type arguments |
| SLG0004 | error | a generic type is named without its type arguments |
| SLG0005 | error | type arguments for a generic cannot be inferred from the values passed |
| SLG0006 | error | a type argument does not meet its parameter's constraint |
| SLG0007 | error | a type cannot be used as a constraint because it is sealed or cannot be derived from |
| SLG0008 | error | a 'where' clause names something that is not a type parameter of its declaration |
| SLG0009 | error | a 'where' clause is written on a declaration that is not generic |
| SLG0010 | error | a dispatched or interface-implementing member of a generic type has its own 'where' |
| SLG0011 | error | a generic type name matches more than one template for its arguments |
| SLG0012 | error | a 'new()' constraint lists parameters |
| SLG0013 | error | a constraint is out of order in a type parameter's clause |
| SLG0014 | error | a type parameter's constraints contradict each other |
| SLG0015 | error | a type parameter has more than one 'where' clause |
| SLG0016 | error | a type parameter is given the same constraint twice |
| SLG0017 | error | a type parameter is constrained to derive from more than one class |
| SLG0018 | error | type parameter constraints refer to each other in a cycle |
| SLG0019 | error | a 'default' constraint is written outside an override, where it means nothing |
| SLG0020 | error | a static abstract or virtual interface member is reached through the interface itself |
| SLG0021 | error | a generic instantiates itself with ever-larger type arguments without end |
| SLG0022 | error | 'in' or 'out' is written on a type parameter that is not an interface's or a delegate's |
| SLG0023 | error | a variant type parameter is used in a position its variance forbids |
| SLG0024 | error | a member is called that its type's constraint-dependent arguments leave out |

## C: Classes and members

| Code | Severity | Means |
|---|---|---|
| SLC0001 | error | a modifier is written twice on one declaration |
| SLC0002 | error | a constructor is declared on a type that is neither a class nor a struct |
| SLC0003 | error | a struct declares a destructor, which only a class can have |
| SLC0004 | error | a type declares more than one destructor or static constructor |
| SLC0005 | error | a function that needs a body has none |
| SLC0006 | error | a struct contains itself by value and so has no finite size |
| SLC0007 | error | new is applied to a type that is neither a class nor a struct |
| SLC0008 | error | arguments are passed to a class with no constructor that takes any |
| SLC0009 | error | an interface declares state, a constructor or a destructor, or a property naming storage |
| SLC0010 | error | a struct is converted to an interface reference |
| SLC0011 | error | a type extends something that is not an interface |
| SLC0012 | warning | a type lists the same interface, COM interface or protocol more than once |
| SLC0013 | error | a type does not provide a member its interface requires |
| SLC0014 | error | a member implementing an interface member is not public |
| SLC0015 | error | a member implementing an interface member does not match its signature |
| SLC0016 | error | a variant or union lists an interface to implement |
| SLC0017 | error | an attribute type declares a member that is not a field |
| SLC0018 | error | a type that is not an attribute is written as an attribute |
| SLC0019 | error | an attribute is given a number of arguments different from its field count |
| SLC0020 | error | an attribute argument is not a constant of its field's type |
| SLC0021 | error | an attribute is used as a type |
| SLC0022 | error | an enum is built on a type that is not an integer |
| SLC0023 | error | an enum member's value is not an integer constant |
| SLC0024 | error | a property declares the same accessor twice |
| SLC0025 | error | a property declares no getter |
| SLC0026 | error | a property mixes an automatic accessor with a written one |
| SLC0027 | error | a declared method already has the name a generated accessor needs |
| SLC0028 | error | a property getter is given narrower accessibility than its property |
| SLC0029 | error | a property without a setter is assigned |
| SLC0030 | error | a property's getter or setter method is called by name instead of the property |
| SLC0031 | error | a property is declared at module level, where there is no instance for it |
| SLC0032 | error | an automatic property has no setter and its type has no constructor to fill it |
| SLC0033 | error | a variant declares no cases |
| SLC0034 | error | a variant has more cases than its one-byte tag can number |
| SLC0035 | error | a variant case declares two fields with the same name |
| SLC0036 | error | 'abstract' or 'sealed' is applied to a type that is not a class |
| SLC0037 | error | a field is given a dispatch modifier such as 'virtual' or 'override' |
| SLC0038 | error | an abstract member has a body |
| SLC0039 | error | a member marked 'override' matches nothing it inherits |
| SLC0040 | error | a method overrides one that is not virtual or abstract |
| SLC0041 | error | a method overrides a sealed override |
| SLC0042 | error | an override does not match the signature of what it overrides |
| SLC0043 | error | a member has the same signature as an inherited one and is not marked 'override' |
| SLC0044 | error | a concrete class does not implement an inherited abstract method |
| SLC0045 | error | an abstract method is declared in a class that is not abstract |
| SLC0046 | error | a virtual, abstract or override method is neither public nor protected |
| SLC0047 | error | two modifiers on one declaration contradict each other |
| SLC0048 | error | a base class is listed after an interface in a base list |
| SLC0049 | error | a class derives from a sealed class |
| SLC0050 | error | a type derives from a second base where only one is allowed |
| SLC0051 | error | a type inherits from itself, directly or through others |
| SLC0052 | error | a class derives from a type the runtime provides rather than this compilation |
| SLC0053 | error | an abstract class is constructed with 'new' |
| SLC0054 | error | 'base' is used where there is no base class to reach |
| SLC0055 | error | a 'base(...)' or 'this(...)' call is outside a constructor or in the wrong place in one |
| SLC0056 | error | a base has no parameterless constructor and no 'base(...)' says which |
| SLC0057 | error | a dispatch modifier or 'protected' is used on a member outside a class |
| SLC0058 | error | constructors delegate to themselves or to each other in a cycle |
| SLC0059 | error | a type alias is defined in terms of itself |
| SLC0060 | error | a type alias is declared inside a type rather than at module level |
| SLC0061 | error | an attribute is written more than once on one declaration |
| SLC0062 | error | a type is declared again in its module as a different kind of type |
| SLC0063 | error | a further declaration of a type says what only the first may |
| SLC0064 | error | an operator is declared at module level rather than in a type |
| SLC0065 | error | an operator is not declared 'public' |
| SLC0066 | error | an operator declares the wrong number of operands |
| SLC0067 | error | no operand of an operator is the type that declares it |
| SLC0068 | error | a comparison operator does not return 'bool' |
| SLC0069 | error | a type declares one operator of a pair without its counterpart |
| SLC0070 | error | a static interface member has an invalid combination of body and modifiers |
| SLC0071 | error | a static class is constructed with 'new' |
| SLC0072 | error | a parameter's default value is not a constant |
| SLC0073 | error | a parameter without a default follows one with a default |
| SLC0074 | error | a conversion is declared outside both types it converts between |
| SLC0075 | error | a field or property of a type that is not a class has an initializer |
| SLC0076 | error | a brace initializer mixes member entries and element entries |
| SLC0077 | error | a 'ref', 'out' or 'in' parameter, or one of a variadic function, has a default |
| SLC0078 | error | an override or interface implementation gives a parameter a default |
| SLC0079 | error | a conversion operator is not 'public' |
| SLC0080 | error | a conversion does not take exactly one non-variadic parameter |
| SLC0081 | error | a conversion converts a type to itself |
| SLC0082 | error | a conversion is to or from an interface |
| SLC0083 | error | a conversion between two types is declared twice |
| SLC0084 | error | a field initializer reads the object it belongs to |
| SLC0085 | error | a computed property has an initializer |
| SLC0086 | error | a brace list of elements initializes a type with no 'Add' method |
| SLC0087 | error | a static class declares an instance member |
| SLC0088 | error | 'base' is used as a value rather than as 'base.Member' or 'base(...)' |
| SLC0089 | error | 'base(...)' is written and nothing derived from declares a constructor |
| SLC0090 | error | a type already declared in the module is declared again with no body |
| SLC0091 | error | an interface declares an operator that is not 'static abstract' or 'static virtual' |
| SLC0092 | error | an attribute argument names a field the attribute does not have |
| SLC0093 | error | a member is given a value twice in one list |
| SLC0094 | error | a positional attribute argument follows a named one |
| SLC0095 | error | an attribute field is set with ':' rather than '=' |
| SLC0096 | error | an attribute is written on a declaration it does not apply to |
| SLC0097 | error | a 'record struct' is declared, which is not supported |
| SLC0098 | error | a 'with' expression is applied to a value that is not a record |
| SLC0099 | error | a 'with' expression assigns a name the record has no parameter or settable property for |
| SLC0100 | error | a struct declares a constructor taking no arguments |
| SLC0101 | error | a parameter is marked 'params' where it is not allowed |
| SLC0102 | error | a static property declares an 'init' accessor |
| SLC0103 | error | an 'init' property is assigned outside of the object's construction |
| SLC0104 | error | a property's 'init' or 'set' differs from that of the member it implements or overrides |
| SLC0105 | error | a member is marked 'required' that cannot be |
| SLC0106 | error | a construction does not set every required member |
| SLC0107 | error | a constructor of a type with a primary constructor does not chain to it |
| SLC0108 | error | a parameter list follows the name of a type that is not a class or struct |
| SLC0109 | error | a by-reference primary constructor parameter is used by a member body |
| SLC0110 | error | an explicit interface member is a field or an automatic property |
| SLC0111 | error | an explicit interface member names something that is not an implemented interface slot |
| SLC0112 | error | an explicit interface member is declared with a modifier |
| SLC0113 | error | two interfaces give equally specific defaults for a member a class does not define |
| SLC0114 | error | a class that is not a record derives from a record |
| SLC0115 | error | a 'base' call names a member that is abstract in the base |
| SLC0116 | error | an event is declared with an initial value |
| SLC0117 | error | an event is declared with a type that is not a closure |
| SLC0118 | error | an event's closure type returns a value rather than void |
| SLC0119 | error | an event is declared static |
| SLC0120 | error | an event is raised from outside the type that declares it |
| SLC0121 | error | an event is read as a value from outside its declaring type |
| SLC0122 | error | an event is assigned with an operator other than '+=' or '-=' |
| SLC0123 | error | a modifier is written on a declaration it does not apply to |
| SLC0124 | error | a required member of a public type, or its setter, is not public |
| SLC0125 | error | base constructor arguments follow a base type other than the first in the list |
| SLC0126 | error | a dependency container is asked for a type it cannot construct |
| SLC0127 | error | a dependency container cannot choose between equally wide public constructors |
| SLC0128 | error | a constructor parameter is of a kind a dependency container cannot supply |
| SLC0129 | error | a default implementation named for a contract is not a matching generic class |

## F: Flow and patterns

| Code | Severity | Means |
|---|---|---|
| SLF0001 | error | some path through a function or lambda ends without returning a value |
| SLF0002 | error | a return in a function that returns a value has no value |
| SLF0003 | error | a return in a void function carries a value |
| SLF0004 | error | break appears outside a loop or a switch |
| SLF0005 | error | continue appears outside a loop |
| SLF0006 | error | a variant case's field is read where no check established the case |
| SLF0007 | error | 'foreach' iterates something that is not an array and has no 'GetEnumerator()' |
| SLF0008 | error | 'GetEnumerator()' returns a type lacking 'MoveNext()' and 'Current' |
| SLF0009 | error | a lambda is converted to a type that is not a delegate or single-method interface |
| SLF0010 | error | a lambda declares a parameter count different from its target type |
| SLF0011 | error | a lambda parameter's written type differs from what its target expects |
| SLF0012 | error | a switch is over a type that cannot have constant labels |
| SLF0013 | error | a 'case' label is not a constant of the switched type |
| SLF0014 | error | a switch has two cases or arms for the same value |
| SLF0015 | error | a switch has more than one 'default' section |
| SLF0016 | error | a switch section runs off its end without 'break', 'return', 'continue' or 'goto' |
| SLF0017 | error | a switch over a variant leaves cases uncovered and has no 'default' |
| SLF0018 | error | a case or class pattern is matched against something neither a variant nor an object |
| SLF0019 | error | a switch section binds more than one variant case |
| SLF0020 | error | a pattern asks about a type its subject's type cannot answer |
| SLF0021 | error | 'try' is applied to a value that is not a 'Result' |
| SLF0022 | error | 'try' is used where the enclosing code does not return a 'Result' |
| SLF0023 | error | 'try' passes on a failure type that differs from the function's |
| SLF0024 | error | a pattern variable is used where its pattern may not have matched |
| SLF0025 | error | a name is bound to a variant case that carries nothing |
| SLF0026 | error | a pattern names or deconstructs a value tested against an interface |
| SLF0027 | error | a label is declared twice in one function |
| SLF0028 | error | a 'goto' names a label that does not exist in its function |
| SLF0029 | error | a jump enters a block it is not already in |
| SLF0030 | error | a value is neither a tuple nor has a 'Deconstruct' of the needed arity |
| SLF0031 | error | a positional pattern or deconstruction names the wrong number of elements |
| SLF0032 | error | a pattern names a variable that is not assigned wherever it would be used |
| SLF0033 | error | a switch expression has no arm for some input |
| SLF0034 | error | an arm of a switch expression produces no value |
| SLF0035 | error | a variant is taken apart by a pattern that does not name its case |
| SLF0036 | error | a static lambda or local function reads from around it |
| SLF0037 | error | a lambda's declared return type differs from its target delegate's |
| SLF0038 | error | a local function is called where a variable it captures is not in scope or not yet known |
| SLF0039 | error | a local function assigns its enclosing function's parameter, of which it has a copy |
| SLF0040 | error | a variable is declared inside an expression where no deconstruction statement holds it |
| SLF0041 | error | a 'foreach' deconstruction names existing variables rather than declaring new ones |
| SLF0042 | error | a list pattern is matched against a type that cannot be indexed element by element |
| SLF0043 | error | a '..' stands outside a list pattern, or a list pattern has two |
| SLF0044 | error | a name in a positional pattern is not that position's name |
| SLF0045 | error | 'goto case' or 'goto default' is written outside a switch statement |
| SLF0046 | error | 'goto case' or 'goto default' has no section to run |
| SLF0047 | error | a '..' names what it skips on a type that cannot be sliced |
| SLF0048 | error | a property pattern names a method rather than a field or property |
| SLF0049 | error | 'goto case' names a value that is not a constant |

## O: Ownership and safety

| Code | Severity | Means |
|---|---|---|
| SLO0001 | error | a value that may be null is used without a check |
| SLO0002 | error | weak is applied to a type that is not a class or interface reference |
| SLO0003 | error | 'spawn' is used outside a 'parallel' block |
| SLO0004 | error | 'spawn' is given something other than a function or method call |
| SLO0005 | error | a spawned result is assigned to something other than a variable, field or element |
| SLO0006 | error | a spawned call returning nothing is assigned to a target |
| SLO0007 | error | a spawned result needs a conversion to the type it is stored into |
| SLO0008 | error | a 'for parallel' does not start by declaring an integer loop variable |
| SLO0009 | error | a 'for parallel' condition is not a '<' or '<=' bound on its loop variable |
| SLO0010 | error | a 'for parallel' step is not an increment of its loop variable |
| SLO0011 | error | a 'for parallel' stride is not a positive integer literal |
| SLO0012 | error | a 'for parallel' body assigns a variable declared outside it |
| SLO0013 | error | a spawned call's receiver or argument is a temporary rather than a held value |
| SLO0014 | error | a static is declared without an initial value |
| SLO0015 | warning | a value reached by more than one thread has no declared thread safety |
| SLO0016 | error | a static initializer or static constructor depends on itself through other statics |
| SLO0017 | error | a 'static readonly' or a field of the struct it holds is written after initialization |
| SLO0018 | error | 'spawn' is used as a value inside a larger expression |
| SLO0019 | error | a spawned call passes a 'ref', 'out' or 'in' parameter, sharing the caller's storage |
| SLO0020 | error | an inline array's element type holds a counted reference |
| SLO0021 | error | 'threadsafe' is written on a kind of type that cannot claim it |
| SLO0022 | error | a jump leaves a parallel block |
| SLO0023 | error | a function can return without assigning one of its 'out' parameters |
| SLO0024 | error | a null-testing operator is applied to a type that cannot be null |
| SLO0025 | error | a '?.' reaches a type with no null to stand for a missing receiver |
| SLO0026 | error | a weak reference is used or tested without first being read into an optional |
| SLO0027 | error | 'default' is taken of a type that has no zero value |
| SLO0028 | error | a slot with no zero value is read before it is assigned |
| SLO0029 | error | 'new T[n]' is written for an element type that has no zero value |
| SLO0030 | error | a field with no zero value may be left unassigned by construction |
| SLO0031 | error | a static or global whose type has no zero value has no initializer |
| SLO0032 | error | a constructor reaches the object or returns before 'base(...)' has run |
| SLO0033 | error | a field with no zero value is still unset when the object becomes reachable |
| SLO0034 | error | 'late' is written on a field that cannot be late |

## I: Interop

| Code | Severity | Means |
|---|---|---|
| SLI0001 | error | a function declared extern has a body |
| SLI0002 | error | a parameter or return type cannot cross a foreign boundary |
| SLI0003 | error | a String is passed where a byte pointer is expected |
| SLI0004 | error | two declarations, or a declaration and the runtime, claim one C symbol name |
| SLI0005 | error | '[Pack(N)]' is written on a type already marked '[Packed]' |
| SLI0006 | error | '[Packed]' is on a field that cannot be packed |
| SLI0007 | error | '[Pack(N)]' or '[Align(N)]' asks for an alignment that is not a power of two |
| SLI0008 | error | '[Pack(N)]' or '[Align(N)]' asks for more than the largest alignment allowed |
| SLI0009 | error | a union declares no members |
| SLI0010 | error | a union member holds a counted reference |
| SLI0011 | error | a bit-field is declared in a type that is not a struct or union |
| SLI0012 | error | a packed type has bit-fields, whose layout C compilers disagree on |
| SLI0013 | error | a bit-field's type is not an integer or a bool |
| SLI0014 | error | a bit-field's width is not a constant |
| SLI0015 | error | a bit-field's width is less than one bit |
| SLI0016 | error | a bit-field asks for more bits than its type has |
| SLI0017 | error | '[Reflect]' is applied to a type with bit-fields, which have no byte offset |
| SLI0018 | error | 'offsetof' names a type that has no fixed field offsets |
| SLI0019 | error | 'offsetof' names a field the type does not have |
| SLI0020 | error | 'offsetof' names a bit-field, which has no byte offset |
| SLI0021 | error | '...' is written on a declaration that cannot be variadic |
| SLI0022 | error | a type is declared without a body where only a non-generic struct may be |
| SLI0023 | error | a type declared without a body is used by value rather than through a pointer |
| SLI0024 | error | 'com' is written on a type that is neither an interface nor a class |
| SLI0025 | error | a com interface extends an interface that is not com |
| SLI0026 | error | a type other than a class implements a com interface |
| SLI0027 | error | a class implements a com interface without being declared 'com class' |
| SLI0028 | warning | a com interface declares no methods, so it is just IUnknown |
| SLI0029 | error | a com class implements no com interface |
| SLI0030 | error | a com class derives from a base class |
| SLI0031 | error | a com interface has no '[Guid]' attribute |
| SLI0032 | error | '[Guid]' is not given exactly one string literal |
| SLI0033 | error | a '[Guid]' string is not in GUID form |
| SLI0034 | error | 'iidof' names a type that is not a com interface |
| SLI0035 | error | a class with '[Guid]' cannot be made by a class factory with no arguments |
| SLI0036 | error | a COM interface and the one it extends disagree about '[NoUnknown]' |
| SLI0037 | error | a '[NoUnknown]' com interface also has a '[Guid]' nothing could query for |
| SLI0038 | error | an Objective-C category names a class no import declares, or one several do |
| SLI0039 | error | an extern C++ variable is declared, whose mangled name is not supported |
| SLI0040 | error | an 'extern "C"' variable is given an initializer |
| SLI0041 | error | an 'asm' operand names a register the target architecture does not have |
| SLI0042 | error | an 'asm' operand names a register that cannot be used as an operand |
| SLI0043 | error | an 'asm' block names the same register more than once in one direction |
| SLI0044 | error | an 'asm' operand's type cannot travel in a register |
| SLI0045 | error | an 'asm' operand's value is wider than the register named for it |
| SLI0046 | error | an 'asm' operand's type belongs in a different kind of register than the one named |
| SLI0047 | error | an 'asm' output is written to a bit-field, which has no address |
| SLI0048 | error | the assembler rejected a line of an 'asm' block |
| SLI0049 | error | an argument of no settled type is passed to a C variadic parameter list |
| SLI0050 | error | 'objc' is written on something other than an interface, class or closure |
| SLI0051 | error | 'extern' is written on an Objective-C type that cannot take it |
| SLI0052 | error | a member of an Objective-C class or protocol has no '[Selector]' |
| SLI0053 | error | a protocol member or an existing class's selector member is given a body |
| SLI0054 | error | a '[Selector]' has the wrong arguments or names an invalid selector |
| SLI0055 | error | a selector's colon count disagrees with the member's parameter count |
| SLI0056 | error | a parameter or return type cannot be carried by an Objective-C message or block |
| SLI0057 | error | '[ObjCRoot]' or '[ObjCName]' has the wrong arguments |
| SLI0058 | error | an 'extern objc class' declares a member it cannot have, such as a field |
| SLI0059 | error | an Objective-C type names a base or protocol of a kind it cannot take |
| SLI0060 | error | an Objective-C class does not reach exactly one '[ObjCRoot]' root class |
| SLI0061 | error | 'new' is used on an 'extern objc class' |
| SLI0062 | error | an Objective-C message is sent on a target that is not macOS |
| SLI0063 | error | a method of an Objective-C class is marked 'abstract' or 'virtual' |
| SLI0064 | error | an Objective-C type is declared in a shape the runtime cannot support |
| SLI0065 | error | an Objective-C constructor's selector does not begin with 'init' |
| SLI0066 | error | an Objective-C object owned by a C library is written to |
| SLI0067 | error | '[CFType]' has arguments other than one type-ID function name |
| SLI0068 | error | a class member of a protocol is sent to the protocol rather than a class |
| SLI0069 | error | more than three vectors cross a foreign boundary on 32-bit Windows |
| SLI0070 | error | 'VaList.Start()' is called in a function that is not variadic |
| SLI0071 | error | a class derives from a Core Foundation type without being marked '[CFType]' |
| SLI0072 | error | 'VaList.Start()' or 'Next<T>()' is given arguments |
| SLI0073 | error | 'Next<T>()' names a type a variadic argument cannot be read as |
| SLI0074 | error | an override of an Objective-C message names a different selector |
| SLI0075 | error | an Objective-C class answers one selector with two methods |
| SLI0076 | error | 'typeof' is applied to an Objective-C type, which the runtime describes |
| SLI0077 | error | an Objective-C class is constructed and nothing it is built on declares 'init' |
| SLI0078 | error | a Core Foundation type has a root, base, protocol or message it cannot have |

## L: Lint

| Code | Severity | Means |
|---|---|---|
| SLL0001 | warning | an expression statement computes a value and discards it |
| SLL0002 | warning | a type test always succeeds because the subject's type already is the tested type |
| SLL0003 | warning | a label is never jumped to |
| SLL0004 | warning | a lambda captures a variable by value that is changed afterwards |
| SLL0005 | warning | a switch label or arm is unreachable because earlier ones cover it |
| SLL0006 | warning | a documentation comment uses a tag that does not exist |
| SLL0007 | warning | a '@param' tag names a parameter the function does not have |
| SLL0008 | warning | a documentation comment documents some parameters but not all |
| SLL0009 | warning | a documentation tag names a type parameter that does not exist |
| SLL0010 | warning | a documentation tag is written on a declaration it says nothing about |
| SLL0011 | warning | a '@failure' tag names no case of the function's error type |
| SLL0012 | warning | a documentation cross-reference names nothing or names something not in scope |
| SLL0013 | warning | a lambda parameter's default differs from the one its target type gives |
| SLL0014 | warning | a lambda assigns its own copy of a captured variable or member, changing nothing |
| SLL0015 | warning | a parameter is documented by more than one '@param' tag |
| SLL0016 | warning | a '@failure' tag is on a function that reports no failure |

## D: Driver and build

| Code | Severity | Means |
|---|---|---|
| SLD0001 | error | more than one Main is declared in the program |
| SLD0002 | error | Main returns something other than int or void |
| SLD0003 | error | Main takes parameters other than none or one String array |
| SLD0004 | error | an executable is built with no Main in any compiled module |
| SLD0005 | error | a type is declared both in the program and in a referenced library |
| SLD0006 | error | a referenced library's member uses a type the program does not know |
| SLD0007 | warning | a public declaration is not described in the library's metadata |
| SLD0008 | warning | a library has no 'export "C"' function to export |
| SLD0009 | warning | a type in a library's metadata refers to a type the metadata does not describe |
| SLD0010 | warning | a program carries Windows-only resources while building for another platform |
| SLD0011 | error | '[Embed]' is written without a file path |
| SLD0012 | error | an '[Embed]' argument is not a string literal |
| SLD0013 | error | an embed's relative path cannot be resolved because the source is not a file on disk |
| SLD0014 | error | the file named by an embed is missing, invalid, a directory, unreadable or too large |
| SLD0015 | error | an embed's access string is not a valid combination of 'r', 'w' and 'x' |
| SLD0016 | error | an embed asks for writable and executable memory with no section that can hold it |
| SLD0017 | error | an embed names a section that cannot be one |
| SLD0018 | warning | an embed's section name is longer than a PE image keeps and will be truncated |
| SLD0019 | error | an embed is placed in a section whose kind or permissions cannot hold it |
| SLD0020 | error | a static with '[Embed]' is not declared 'byte[]' |
| SLD0021 | error | a static with '[Embed]' also has an initializer |
| SLD0022 | error | a library's metadata describes a slot or event incompletely, as if edited |
