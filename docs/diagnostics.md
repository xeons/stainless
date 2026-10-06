# Diagnostics

Every diagnostic the compiler can report, with what it means. Generated from
`src/Stainless.Compiler/Source/Codes.cs` by `stainless explain --markdown`;
edit that file, not this one.

564 codes: 534 errors and 30 warnings.

## SL00xx

| Code | Severity | Means |
|---|---|---|
| SL0001 | error | a character in the source begins no token |
| SL0002 | error | a block comment is never closed |
| SL0003 | error | a numeric literal has a prefix but no digits |
| SL0004 | error | a numeric literal has an unknown or unsuitable suffix, or is not a valid float |
| SL0005 | error | an integer literal does not fit in 64 bits |
| SL0006 | error | a string literal, raw or interpolated, is never closed |
| SL0007 | error | a character literal is never closed |
| SL0008 | error | a hex escape has too few or the wrong number of hex digits |
| SL0009 | error | a backslash escape is not one the language defines |
| SL0010 | error | a character literal holds no character |

## SL01xx

| Code | Severity | Means |
|---|---|---|
| SL0100 | error | the parser found a token other than the one the grammar requires |
| SL0101 | error | an identifier is required and something else was found |
| SL0102 | error | an extern or export names a linkage convention other than C or C++ |
| SL0103 | error | extern or export is not followed by a linkage convention string |
| SL0104 | error | a destructor's name is not the name of its enclosing type |
| SL0105 | error | a function declared extern has a body |
| SL0106 | error | a type name stands where a value is expected |
| SL0107 | error | an expression is required and something else was found |
| SL0108 | error | source is nested deeper than the compiler can process |
| SL0109 | error | a modifier is written twice, or conflicts with another, on one declaration |

## SL02xx

| Code | Severity | Means |
|---|---|---|
| SL0201 | error | a name is declared twice in one module |
| SL0202 | error | an import names a module that is not among the compiled sources |
| SL0203 | warning | a file imports the module it belongs to |
| SL0204 | error | a variable is declared at module scope, where only constants are allowed |
| SL0205 | error | a type declares two members with the same name |
| SL0207 | error | a constructor is declared on a type that is neither a class nor a struct |
| SL0208 | error | a struct declares a destructor, which only a class can have |
| SL0209 | error | a type declares more than one destructor or static constructor |
| SL0210 | error | a function that must be defined where it is declared has no body |
| SL0211 | error | two overloads of one function, operator, constructor or conversion share a signature |
| SL0212 | error | two parameters of one function share a name |
| SL0213 | error | a parameter is declared with type void |
| SL0215 | error | a constant is initialized with something other than a literal |
| SL0216 | error | a struct contains itself by value and so has no finite size |
| SL0217 | error | some path through a function or lambda ends without returning a value |
| SL0218 | error | a local name is declared twice in one scope |
| SL0219 | error | a local takes the name of a parameter |
| SL0220 | error | a var declaration has no initializer to infer its type from |
| SL0221 | error | a var declaration's initializer has type void |
| SL0222 | warning | an expression statement computes a value and discards it |
| SL0223 | error | a return in a function that returns a value has no value |
| SL0224 | error | a return in a void function carries a value |
| SL0225 | error | break appears outside a loop or a switch |
| SL0226 | error | continue appears outside a loop |
| SL0227 | error | a condition is not of type bool |
| SL0228 | error | this is used outside an instance method, constructor or destructor |
| SL0229 | error | a name used as a value is not defined |
| SL0230 | error | the address of a temporary value is taken |
| SL0231 | error | something other than a pointer is dereferenced |
| SL0232 | error | a unary operator is applied to an operand type it does not accept |
| SL0233 | error | a logical operator is applied to operands that are not bool |
| SL0234 | error | a binary operator is applied to operand types it does not accept |
| SL0235 | error | a shift operator is applied to operands that are not integers |
| SL0236 | error | an operator that bool does not support is applied to bool operands |
| SL0238 | error | two operands have no common type for a binary operator |
| SL0239 | error | an integer-only operator is applied to operands that are not integers |
| SL0240 | error | an assignment or update targets a constant or something that is not a location |
| SL0241 | error | a value is indexed by a type with no matching indexer |
| SL0242 | error | an index, slice bound, from-end count or range bound is not an integer |
| SL0243 | error | an explicit cast names a conversion that does not exist |
| SL0244 | error | new is applied to a type that is neither a class nor a struct |
| SL0245 | error | new passes arguments to, or is applied to, a type that declares no constructor |
| SL0246 | error | a module has no public member with the name accessed |
| SL0247 | error | a type, variant or variant case has no member with the name accessed |
| SL0248 | error | a value that may be null or dead is used without a check proving it is not |
| SL0249 | error | a field, property, event or constant is not visible from here |
| SL0250 | error | a method is named as a value without being called |
| SL0252 | error | no function with the called name is in scope |
| SL0253 | error | a call is made through a value that is not a delegate or closure |
| SL0254 | error | a method is called on a value that may be null without a check |
| SL0255 | error | a type has no method with the called name |
| SL0257 | error | a called method, or a member named through a type, is not visible from here |
| SL0260 | error | a call passes the wrong number of arguments |
| SL0262 | error | an argument's type does not match its parameter's type |
| SL0263 | error | no overload accepts the arguments of a call |
| SL0264 | error | more than one overload matches a call equally well |
| SL0265 | error | a value cannot be implicitly converted to the type required |
| SL0266 | error | a constant value lies outside the range of its target type |
| SL0270 | error | a raw pointer type is formed over a reference type |
| SL0271 | error | an optional type is formed over a type that cannot be null |
| SL0272 | error | weak is applied to a type that is not a class or interface reference |
| SL0273 | error | an unqualified type name matches types in more than one module |
| SL0274 | error | a type or type alias named from another module is not public |
| SL0275 | error | a qualified type name names a module that declares no such type |
| SL0276 | error | a type name matches no type in scope |
| SL0280 | error | more than one Main is declared in the program |
| SL0281 | error | Main returns something other than int or void |
| SL0282 | error | Main takes parameters other than none or one String array |
| SL0284 | error | a foreign function's parameter or return type cannot cross the C boundary |
| SL0285 | error | a variant case field is read from something other than a local or parameter |
| SL0286 | error | a variant case field is read where the case is not known to carry it |
| SL0287 | error | a var is initialized with a variant case that does not name its variant |
| SL0289 | error | a variant case is constructed with the wrong number of fields |
| SL0290 | error | an executable is built with no Main in any compiled module |
| SL0291 | error | an operator that strings do not support is applied to two strings |
| SL0292 | error | a string operator is applied to a string and a value of another type |
| SL0293 | error | a String is used where a byte pointer is required without ToPointer |
| SL0294 | error | a String is passed to a C variadic function without ToPointer |
| SL0295 | error | two declarations, or a declaration and the runtime, claim one C symbol name |

## SL03xx

| Code | Severity | Means |
|---|---|---|
| SL0300 | error | an interface declares state, a constructor or a destructor, or a property naming storage |
| SL0302 | error | a struct or other plain value type is used as or declared to implement an interface |
| SL0303 | error | a type implements or extends something that is not an interface |
| SL0304 | warning | a type lists the same interface, COM interface or protocol more than once |
| SL0305 | error | a type does not implement a member its interface requires |
| SL0306 | error | a member implementing an interface member is not public |
| SL0307 | error | a member implementing an interface member does not match its signature |
| SL0308 | error | 'new' passes arguments to a class that has no constructor taking any |
| SL0309 | error | 'void' is used as the type of a variable, field, parameter or type argument |
| SL0310 | error | an array is declared or built with 'void' elements |
| SL0312 | error | an array length is not an integer |
| SL0313 | error | an array or inline array is accessed for a member other than 'Length' |
| SL0320 | error | a property or field declares type parameters |
| SL0322 | error | a 'static abstract' or 'static virtual' interface member is generic |
| SL0323 | error | a generic is given the wrong number of type arguments |
| SL0324 | error | inference produced the wrong number of type arguments for a generic |
| SL0325 | error | a generic type is named without its type arguments |
| SL0326 | error | no generic type of the given name is in scope |
| SL0327 | error | type arguments for a generic cannot be inferred from the values passed |
| SL0328 | error | a type argument does not satisfy a constraint on its type parameter |
| SL0329 | error | a type cannot be used as a constraint because it is sealed or cannot be derived from |
| SL0330 | error | a 'where' clause names something that is not a type parameter of its declaration |
| SL0331 | error | a 'where' clause is written on a member that cannot have one |
| SL0332 | error | a file does not declare which module it belongs to |
| SL0333 | error | two interfaces extend each other |
| SL0340 | error | an attribute type declares a member that is not a field |
| SL0341 | error | '[Reflect]' is written on something other than a Stainless class or struct |
| SL0342 | error | a type that is not an attribute is written as an attribute |
| SL0343 | error | an attribute is given a number of arguments different from its field count |
| SL0344 | error | an attribute argument is not a constant of its field's type |
| SL0345 | error | an attribute is used as a type |
| SL0346 | error | 'typeof' names a type that carries no metadata because it lacks '[Reflect]' |
| SL0347 | error | 'typeof' is used without Standard.Reflection in the compilation |
| SL0348 | error | an arm of a conditional expression produces no value |
| SL0349 | error | the arms of a conditional expression have no common type |
| SL0350 | error | an enum is built on a type that is not an integer |
| SL0351 | error | an enum declares two members with the same name |
| SL0352 | error | an enum member's value is not an integer constant |
| SL0353 | error | an enum is compared with a value of a different type |
| SL0354 | error | an arithmetic or bitwise operator is applied to an enum that does not support it |
| SL0355 | error | an enum has no member of the given name |
| SL0356 | error | 'foreach' iterates something that is not an array and has no 'GetEnumerator()' |
| SL0357 | error | 'GetEnumerator()' returns a type lacking 'MoveNext()' and 'Current' |
| SL0358 | error | a declaration that cannot be called safely as variadic is declared variadic |
| SL0359 | error | a parameter of a delegate, closure or similar type declaration is 'void' |
| SL0360 | error | a function or method is converted to a type that cannot hold it |
| SL0361 | error | no overload of a method group matches the delegate or closure type |
| SL0362 | error | a method group matches a delegate or closure type through more than one overload |
| SL0363 | error | a delegate or closure value is called with the wrong number of arguments |
| SL0364 | error | 'spawn' is used outside a 'parallel' block |
| SL0365 | error | 'spawn' is given something other than a function or method call |
| SL0366 | error | a spawned result is assigned to something other than a variable, field or element |
| SL0367 | error | a spawned call returning nothing is assigned to a target |
| SL0368 | error | a spawned result needs a conversion to the type it is stored into |
| SL0369 | error | a 'for parallel' does not start by declaring an integer loop variable |
| SL0370 | error | a 'for parallel' condition is not a '<' or '<=' bound on its loop variable |
| SL0371 | error | a 'for parallel' step is not an increment of its loop variable |
| SL0372 | error | a 'for parallel' stride is not a positive integer literal |
| SL0373 | error | a 'for parallel' body assigns a variable declared outside it |
| SL0374 | error | 'return' leaves a 'parallel' block |
| SL0375 | error | a spawned call's receiver or argument is a temporary rather than a held value |
| SL0376 | error | a static is declared without an initial value |
| SL0377 | warning | a value reached by more than one thread has no declared thread safety |
| SL0378 | error | a static initializer or static constructor depends on itself through other statics |
| SL0379 | error | a 'static readonly' or a field of the struct it holds is written after initialization |
| SL0381 | error | a lambda or local function that captures state is converted to a delegate |
| SL0382 | error | a lambda is converted to a type that is not a delegate or single-method interface |
| SL0383 | error | a lambda declares a parameter count different from its target type |
| SL0384 | error | a lambda parameter's written type differs from what its target expects |
| SL0385 | error | a property body contains something other than 'get', 'set' or 'init' |
| SL0387 | error | a property is declared with type 'void' |
| SL0388 | error | a property declares the same accessor twice |
| SL0389 | error | a property declares no getter |
| SL0390 | error | 'spawn' is used as a value inside a larger expression |
| SL0391 | error | a property mixes an automatic accessor with a written one |
| SL0392 | error | an accessor of an abstract property has a body |
| SL0393 | error | a method already uses the name and parameters a property accessor needs |
| SL0394 | error | a property getter is given narrower accessibility than its property |
| SL0395 | error | a property without a setter is assigned |
| SL0396 | error | a property is assigned from outside where its setter is accessible |
| SL0398 | error | a property's getter or setter method is called by name instead of the property |
| SL0399 | error | a field or property of a temporary struct is written, so the write is lost |

## SL04xx

| Code | Severity | Means |
|---|---|---|
| SL0400 | error | a property is declared at module level, where there is no instance for it |
| SL0401 | error | an automatic property has no setter and its type has no constructor to fill it |
| SL0402 | error | a statement in a switch is not under a 'case' or 'default' label |
| SL0403 | error | a switch is over a type that cannot have constant labels |
| SL0404 | error | a 'case' label is not a constant of the switched type, or not one of the variant's cases |
| SL0405 | error | a switch has two cases or arms for the same value |
| SL0406 | error | a switch has more than one 'default' section |
| SL0407 | error | a switch section runs off its end without 'break', 'return', 'continue' or 'goto' |
| SL0408 | error | a flag operation is used on an enum that is not marked '[Flags]' |
| SL0409 | error | 'HasFlag' is not given exactly one argument of the enum's own type |
| SL0410 | error | a flag test reads the same expression twice; it must be put in a variable first |
| SL0411 | error | '[Flags]' is applied to a type that is not an enum |
| SL0412 | error | a built-in member is called with the wrong number of arguments |
| SL0413 | error | a variant's case is named where a value of another type is expected |
| SL0414 | error | a module-level function has the name of a variant case, which a bare call would build |
| SL0415 | error | a division or remainder has a constant zero divisor |
| SL0417 | error | a type is declared both in the program and in a referenced library |
| SL0418 | error | a referenced library's member uses a type the program does not know |
| SL0419 | warning | a generic is left out of a library's metadata, since it crosses as source only |
| SL0420 | warning | a type that implements an interface is left out of a library's metadata |
| SL0421 | error | '[Pack(N)]' is on something other than a struct or union, or N is not a valid alignment |
| SL0430 | error | a variant declares no cases |
| SL0431 | error | a variant case declares variadic parameters |
| SL0432 | error | a variant has more cases than its one-byte tag can number |
| SL0433 | error | a variant declares two cases with the same name |
| SL0434 | error | a variant case declares two fields with the same name |
| SL0435 | error | a variant has no case of the given name |
| SL0436 | error | a switch over a variant leaves cases uncovered and has no 'default' |
| SL0438 | error | a case or class pattern is matched against something neither a variant nor an object |
| SL0439 | error | a case that carries nothing is given a name to bind |
| SL0440 | error | a switch section binds more than one variant case |
| SL0441 | warning | a variant is left out of a library's metadata, since it crosses as source only |
| SL0442 | error | '[Reflect]' is applied to a variant, whose cases cannot be described yet |
| SL0443 | error | an expression with no addressable storage is passed by 'ref' or 'out', or addressed |
| SL0444 | error | a read-only location is passed as 'ref' or 'out' |
| SL0445 | error | an argument to a 'ref' parameter is passed without 'ref' |
| SL0446 | error | 'ref' is written on an argument to a parameter taken by value or as 'in' |
| SL0447 | error | a 'ref' or 'out' argument's type does not exactly match the parameter's |
| SL0448 | error | an 'in' parameter is written to |
| SL0449 | error | a spawned call passes a 'ref', 'out' or 'in' parameter, sharing the caller's storage |
| SL0450 | error | an indexing expression has no index |
| SL0451 | error | a span or read-only span of 'void' is written |
| SL0452 | error | a slice is taken of a value that cannot be sliced |
| SL0453 | error | a generic type name matches more than one template for its arguments |
| SL0454 | error | an '#if' is never closed by '#endif' |
| SL0455 | error | an '#elif' or second '#else' follows an '#else' |
| SL0456 | error | a '#define' or '#undef' comes after the first declaration in the file |
| SL0457 | error | a '#define' or '#undef' is given something other than one name |
| SL0458 | error | an '#error' directive is reached |
| SL0459 | warning | a '#warning' directive is reached |
| SL0460 | error | a '#' line names no directive the language has |
| SL0461 | error | an '#elif', '#else' or '#endif' has no '#if' to belong to |
| SL0462 | error | a conditional directive's condition is missing or malformed |
| SL0463 | error | '[Packed]' is on a non-struct, or on a field that cannot be packed |
| SL0464 | error | '[Align]' is applied to a type that is not a struct |
| SL0465 | error | '[Align(N)]' asks for an alignment that is not a power of two |
| SL0466 | error | '[Align(N)]' asks for more than the largest alignment allowed |
| SL0467 | error | a union declares no members |
| SL0468 | error | a union member holds a counted reference |
| SL0469 | error | a bit-field is declared in a type that is not a struct or union |
| SL0470 | error | a packed type has bit-fields, whose layout C compilers disagree on |
| SL0471 | error | a bit-field's type is not an integer or a bool |
| SL0472 | error | a bit-field's width is not a constant |
| SL0473 | error | a bit-field's width is less than one bit |
| SL0474 | error | a bit-field asks for more bits than its type has |
| SL0475 | error | '[Reflect]' is applied to a type with bit-fields, which have no byte offset |
| SL0476 | warning | a library has no 'export "C"' function to export |
| SL0477 | warning | a type in a library's metadata refers to a type the metadata does not describe |
| SL0478 | error | a 'const' is declared with a type a constant cannot hold |
| SL0479 | error | a 'const' is given a literal of the wrong kind for its declared type |
| SL0480 | error | 'offsetof' names a type that has no fixed field offsets |
| SL0481 | error | 'offsetof' names a field the type does not have |
| SL0482 | error | 'offsetof' names a bit-field, which has no byte offset |
| SL0483 | error | a '#pragma' is not 'comment(lib, ...)' or 'comment(framework, ...)' |
| SL0484 | error | a '#pragma comment(lib, ...)' library name is missing or not quoted |
| SL0486 | error | an inline array's element type holds a counted reference |
| SL0487 | error | an inline array's length is not a constant |
| SL0488 | error | an inline array asks for fewer than one element |
| SL0489 | error | an inline array would be larger than a value can be |
| SL0490 | error | a constant index is outside a fixed-length array or vector |
| SL0491 | error | a parameter takes an inline array by value rather than by 'ref' or 'in' |
| SL0492 | error | a member name is declared by more than one nameless member of a type |
| SL0493 | error | '...' is written on something other than a module-level function or foreign message |
| SL0494 | error | '->' is applied to a non-pointer, or a pointer to a type with no members |
| SL0495 | error | 'abstract' or 'sealed' is applied to a type that is not a class |
| SL0496 | error | a class is marked both 'abstract' and 'sealed' |
| SL0497 | error | a field is given a dispatch modifier such as 'virtual' or 'override' |
| SL0498 | error | an abstract method has a body |
| SL0499 | error | a member marked 'override' matches nothing it inherits |

## SL05xx

| Code | Severity | Means |
|---|---|---|
| SL0500 | error | a method overrides one that is not virtual or abstract |
| SL0501 | error | a method overrides a sealed override |
| SL0502 | error | an override does not match the signature of what it overrides |
| SL0503 | error | a member has the same signature as an inherited one and is not marked 'override' |
| SL0504 | error | a concrete class does not implement an inherited abstract method |
| SL0505 | error | an abstract method is declared in a class that is not abstract |
| SL0506 | error | a virtual, abstract or override method is neither public nor protected |
| SL0507 | error | a method combines dispatch modifiers that contradict each other |
| SL0508 | error | a base class is listed after an interface in a base list |
| SL0509 | error | a class derives from a sealed class |
| SL0510 | error | a class names more than one base class |
| SL0511 | error | a class derives from itself, directly or through a cycle |
| SL0512 | error | an interface names a class as a base |
| SL0513 | error | a class derives from a type the runtime provides rather than this compilation |
| SL0514 | error | an abstract class is constructed with 'new' |
| SL0515 | error | 'base' is used with no base class, or not as a member access or constructor call |
| SL0516 | error | a 'base(...)' or 'this(...)' call is outside a constructor or in the wrong place in one |
| SL0517 | error | a base constructor call is missing where one is required, or written where none exists |
| SL0518 | error | an 'is' test asks something the subject's type cannot answer |
| SL0519 | error | a dispatch modifier or 'protected' is used on a member outside a class |
| SL0520 | warning | a type test always succeeds because the subject's type already is the tested type |
| SL0521 | error | constructors delegate to themselves or to each other in a cycle |
| SL0522 | error | a type alias is defined in terms of itself |
| SL0523 | error | a type is declared without a body where only a non-generic struct may be |
| SL0524 | error | a type declared without a body is used by value rather than through a pointer |
| SL0525 | error | a type alias is declared inside a type rather than at module level |
| SL0526 | error | a Unicode escape names a value that is not a Unicode scalar |
| SL0527 | error | a character value converts implicitly between encodings or does not fit one code unit |
| SL0528 | error | 'com' is written on a type that is neither an interface nor a class |
| SL0529 | error | a com interface extends an interface that is not com |
| SL0530 | error | a com interface extends more than one com interface |
| SL0531 | error | a com interface extends itself, directly or through a cycle |
| SL0532 | error | a type other than a class implements a com interface |
| SL0533 | error | a class implements a com interface without being declared 'com class' |
| SL0534 | warning | a com interface declares no methods, so it is just IUnknown |
| SL0535 | error | a com class implements no com interface |
| SL0536 | error | a com class derives from a base class |
| SL0537 | error | a com interface has no '[Guid]' attribute |
| SL0538 | error | '[Guid]' is written on a type that is not a com interface or com class |
| SL0539 | error | a type carries more than one '[Guid]' attribute |
| SL0540 | error | '[Guid]' is not given exactly one string literal |
| SL0541 | error | a '[Guid]' string is not in GUID form |
| SL0542 | error | 'iidof' names a type that is not a com interface |
| SL0543 | warning | a public com interface is left out of a library's metadata |
| SL0544 | warning | a public com class is left out of a library's metadata |
| SL0545 | warning | a public interface is left out of a library's metadata |
| SL0546 | error | an array literal targets a type that cannot be built from elements |
| SL0547 | error | an array literal has a different number of elements than its inline array type |
| SL0548 | error | an empty array literal has no element type to infer |
| SL0549 | error | the elements of an array literal do not share one type |
| SL0550 | error | a further declaration of a type cannot be matched to the type it adds to |
| SL0551 | error | a further declaration of a type restates what only one declaration may say |
| SL0552 | error | a further declaration of a non-class type adds a field |
| SL0553 | error | a 'var' is given a value whose type cannot be inferred |
| SL0554 | error | an interpolated string has a '}' that closes nothing |
| SL0555 | error | an interpolated string has an empty '{}' hole |
| SL0556 | error | an interpolation hole holds more than one expression |
| SL0557 | error | an interpolation hole holds a value with no defined text form |
| SL0558 | error | an operator that cannot be overloaded is declared |
| SL0559 | error | an operator declaration has no body |
| SL0560 | error | an operator is declared somewhere other than the concrete type it is for |
| SL0561 | error | an operator is not declared 'public' |
| SL0562 | error | an operator declares the wrong number of operands |
| SL0563 | error | no operand of an operator is the type that declares it |
| SL0564 | error | a comparison operator does not return 'bool' |
| SL0565 | error | no declared operator overload accepts the operand types |
| SL0566 | error | more than one operator overload accepts the operand types |
| SL0567 | error | a type declares one operator of a pair without its counterpart |
| SL0568 | error | an indexer declares no index parameters |
| SL0569 | error | 'try' is applied to a value that is not a 'Result' |
| SL0570 | error | 'try' is used where the enclosing code does not return a 'Result' |
| SL0571 | error | 'try' passes on a failure type that differs from the function's |
| SL0572 | error | a type is constructed from outside the module that owns its constructors |
| SL0573 | error | a module-level function is marked 'static' |
| SL0574 | error | a static interface member has an invalid combination of body and modifiers |
| SL0575 | error | a static method is also marked with a dispatch modifier or 'protected' |
| SL0576 | error | an instance member is reached without an instance, or a static one through a value |
| SL0578 | error | 'static' is written on a kind of type that cannot be static |
| SL0579 | error | a 'new()' constraint lists parameters |
| SL0580 | error | a constraint is out of order in a type parameter's clause |
| SL0581 | error | a type parameter's constraints contradict each other |
| SL0582 | error | 'threadsafe' is written on a kind of type that cannot claim it |
| SL0583 | error | a static class is instantiated or declares an instance member |
| SL0585 | error | a pattern variable is used where its pattern may not have matched |
| SL0586 | error | a pattern names a variable for a variant case that carries nothing |
| SL0587 | error | a pattern names or deconstructs a value tested against an interface |
| SL0588 | error | a label is declared twice in one function |
| SL0589 | error | a 'goto' names a label that does not exist in its function |
| SL0590 | error | a jump leaves a 'parallel' block |
| SL0591 | warning | a label is never jumped to |
| SL0592 | error | 'nameof' is given an expression that is not a name |
| SL0593 | error | an increment or decrement targets a property with no setter |
| SL0594 | error | an increment or decrement is applied to a type that is not a number or pointer |
| SL0595 | error | a jump enters a block it is not already in |
| SL0596 | error | 'nameof' names something that does not exist |
| SL0597 | error | an argument for an 'out' parameter is not written with 'out' |
| SL0598 | error | an argument is written 'out' for a parameter that is not 'out' |

## SL06xx

| Code | Severity | Means |
|---|---|---|
| SL0600 | error | a function can return without assigning one of its 'out' parameters |
| SL0601 | error | a call's arguments do not fit the parameters of the function or constructor it names |
| SL0602 | error | a named argument is passed to something that takes its arguments only by position |
| SL0603 | error | 'default' is used where the type is 'void', which has no value |
| SL0604 | error | a null-testing operator is applied to a type that cannot be null |
| SL0605 | error | a '?.' reaches a type with no null to stand for a missing receiver |
| SL0606 | error | a tuple type is written with fewer than two elements |
| SL0607 | error | an element of a tuple is an expression that produces no value |
| SL0608 | error | a value is neither a tuple nor has a 'Deconstruct' of the needed arity |
| SL0609 | error | a positional pattern or deconstruction names the wrong number of elements |
| SL0610 | warning | a lambda captures a variable by value that is changed afterwards |
| SL0611 | error | a class with '[Guid]' cannot be made by a class factory with no arguments |
| SL0612 | error | an 'as' expression is redundant, misapplied or can never succeed |
| SL0613 | error | a parameter's default value is not allowed |
| SL0614 | error | a parameter default is placed where it would be ambiguous or leave a hole |
| SL0615 | error | a user-defined conversion operator is declared in a way that is not allowed |
| SL0616 | error | two user-defined conversions apply and nothing chooses between them |
| SL0617 | error | a field or property initializer is written where it cannot run |
| SL0618 | error | an entry in an object or collection initializer cannot be applied |
| SL0619 | error | a pattern in a switch binds a name that is never assigned or asks something it cannot |
| SL0620 | error | a switch expression does not produce a value for every input |
| SL0621 | warning | a switch label or arm is unreachable because earlier ones cover it |
| SL0622 | error | a COM interface and the one it extends disagree about '[NoUnknown]' |
| SL0623 | error | '[NoUnknown]' is written on a type that is not a com interface |
| SL0624 | error | a '[NoUnknown]' com interface also has a '[Guid]' nothing could query for |

## SL07xx

| Code | Severity | Means |
|---|---|---|
| SL0700 | warning | a program carries Windows-only resources while building for another platform |
| SL0701 | error | an extern C++ variable is declared, whose mangled name is not supported |
| SL0702 | error | an 'extern "C"' variable is given an initializer |
| SL0703 | error | '[Embed]' is written without a file path |
| SL0704 | error | an '[Embed]' argument is not a string literal |
| SL0705 | error | an embed's relative path cannot be resolved because the source is not a file on disk |
| SL0706 | error | the file named by an embed is missing, invalid, a directory, unreadable or too large |
| SL0707 | error | an embed's access string is not a valid combination of 'r', 'w' and 'x' |
| SL0708 | error | an embed asks for writable and executable memory with no section that can hold it |
| SL0709 | error | an embed's section name is not a valid section name |
| SL0710 | warning | an embed's section name is longer than a PE image keeps and will be truncated |
| SL0711 | error | an embed is placed in a section whose kind or permissions cannot hold it |
| SL0713 | error | an 'asm' block is never closed |
| SL0714 | error | 'asm' is not followed by a braced block of instructions |
| SL0715 | error | an 'asm' operand does not say 'in', 'out' or 'inout' |
| SL0716 | error | an 'asm' operand names a register the target architecture does not have |
| SL0717 | error | an 'asm' operand names a register that cannot be used as an operand |
| SL0718 | error | an 'asm' block names the same register more than once in one direction |
| SL0719 | error | an 'asm' operand's type cannot travel in a register |
| SL0720 | error | an 'asm' operand's value is wider than the register named for it |
| SL0721 | error | an 'asm' operand's type belongs in a different kind of register than the one named |
| SL0722 | error | an 'asm' output is written to a bit-field, which has no address |
| SL0723 | error | the assembler rejected a line of an 'asm' block |
| SL0724 | error | an attribute argument names a field the attribute does not have |
| SL0725 | error | an attribute field is given a value more than once |
| SL0726 | error | a positional attribute argument follows a named one |
| SL0727 | error | an attribute field is set with ':' rather than '=' |
| SL0728 | error | an attribute is written on a declaration that cannot carry it |
| SL0729 | error | '[Embed]' is written on something other than a static, or more than once |
| SL0730 | error | a static with '[Embed]' is not declared 'byte[]' |
| SL0731 | error | a static with '[Embed]' also has an initializer |
| SL0732 | error | a constructor is followed by something other than ': base(...)' or ': this(...)' |
| SL0733 | error | a constructor chains to another both after its parameters and in its body |
| SL0734 | error | a 'record struct' is declared, which is not supported |
| SL0735 | error | a 'with' expression is applied to a value that is not a record |
| SL0736 | error | a 'with' expression assigns a name the record has no parameter or settable property for |
| SL0737 | error | a 'with' expression assigns the same member twice |
| SL0738 | error | a struct declares a constructor taking no arguments |
| SL0739 | warning | a documentation comment uses a tag that does not exist |
| SL0740 | warning | a '@param' tag names a parameter that does not exist or was already documented |
| SL0741 | warning | a documentation comment documents some parameters but not all |
| SL0742 | warning | a documentation tag names a type parameter that does not exist |
| SL0743 | warning | a documentation tag is written on a declaration it says nothing about |
| SL0744 | warning | a '@failure' tag is on a function that cannot fail or does not name a valid error case |
| SL0745 | warning | a documentation cross-reference names nothing or names something not in scope |
| SL0746 | error | text follows the opening quotes of a multi-line raw string on the same line |
| SL0747 | error | a multi-line raw string has no content or its closing quotes are not on their own line |
| SL0748 | error | a line of a raw string is indented less than its closing quotes |
| SL0749 | error | a raw string contains a run of quotes as long as its delimiter |
| SL0750 | error | a run of braces in an interpolated string does not match the hole delimiter |
| SL0751 | error | more than one '$' prefixes a string that is not raw |
| SL0752 | error | an interpolated string is given the 'u8' suffix |
| SL0753 | error | an interpolation hole's format string is not allowed or not valid for its value |
| SL0754 | error | an interpolation's alignment is not a constant integer |
| SL0755 | error | a conditional expression in an interpolation hole is not parenthesized |
| SL0756 | error | a 'new(...)' has no target type to take its type from |
| SL0757 | error | a bare 'default' has no target type to take its type from |
| SL0758 | error | a bare 'default' is used as a case pattern |
| SL0759 | error | type arguments are written on a function that is not generic |
| SL0760 | error | a call writes a number of type arguments no candidate takes |
| SL0761 | error | a type or an uninstantiated generic is used where a value is expected |
| SL0762 | error | an assignment is made through '?.' or '?[' |
| SL0763 | error | a parameter is marked 'params' where it is not allowed |
| SL0764 | error | a 'static' lambda reads a variable from its enclosing scope |
| SL0765 | error | a lambda's declared return type differs from its target delegate's |
| SL0766 | warning | a lambda parameter's default differs from the one its target type gives |
| SL0767 | error | a 'static' local function reads a variable or 'this' from its enclosing function |
| SL0768 | error | a local function is called where a variable it captures is not in scope or not yet known |
| SL0769 | error | a local function assigns its enclosing function's parameter, of which it has a copy |
| SL0770 | error | a local variable is declared 'static' |
| SL0771 | error | a variable is declared inside an expression where no deconstruction statement holds it |
| SL0772 | error | a 'foreach' deconstruction names existing variables rather than declaring new ones |
| SL0773 | error | a tuple has an element that needs a target type and none is available |
| SL0774 | error | a list pattern is matched against a type that cannot be indexed element by element |
| SL0775 | error | a '..' in a pattern is misplaced, repeated or cannot name what it skips |
| SL0776 | error | a name in a positional or property pattern does not match a readable member |
| SL0777 | error | '^' or a range is applied to a type with no length |
| SL0778 | error | a '..' spread in a collection expression cannot be spread into its target |
| SL0779 | error | a spread of unknown length fills a fixed-length inline array |
| SL0780 | error | a static property declares an 'init' accessor |
| SL0781 | error | an 'init' property is assigned outside of the object's construction |
| SL0782 | error | a property's 'init' or 'set' differs from that of the member it implements or overrides |
| SL0783 | error | a member is marked 'required' where that is not allowed |
| SL0784 | error | a construction does not set every required member |
| SL0785 | error | a constructor of a type with a primary constructor does not chain to it |
| SL0786 | error | a primary constructor parameter list or base arguments are written where not allowed |
| SL0787 | error | a by-reference primary constructor parameter is used by a member body |
| SL0788 | error | a type parameter has more than one 'where' clause |
| SL0789 | error | a type parameter is given the same constraint twice |
| SL0790 | error | a type parameter is constrained to derive from more than one class |
| SL0791 | error | type parameter constraints refer to each other in a cycle |
| SL0792 | error | a 'default' constraint is written outside an override, where it means nothing |
| SL0793 | error | an explicit interface member is a field or an automatic property |
| SL0794 | error | an explicit interface member names something that is not an implemented interface slot |
| SL0795 | error | an explicit interface member is declared with a modifier |
| SL0796 | error | two interfaces give equally specific defaults for a member a class does not define |
| SL0797 | error | a static abstract or virtual interface member is reached through the interface itself |
| SL0798 | error | a generic instantiates itself with ever-larger type arguments without end |
| SL0799 | warning | a type with a generic virtual method is left out of the library's metadata |

## SL08xx

| Code | Severity | Means |
|---|---|---|
| SL0800 | error | 'in' or 'out' is written on a type parameter that is not an interface's or a delegate's |
| SL0801 | error | a variant type parameter is used in a position its variance forbids |
| SL0802 | error | 'goto case' or 'goto default' is written outside a switch statement |
| SL0803 | error | 'goto case' or 'goto default' names no section the switch can run |
| SL0804 | error | a class that is not a record derives from a record |
| SL0805 | error | an argument of no settled type is passed to a C variadic parameter list |
| SL0806 | error | a 'base' call names a member that is abstract in the base |
| SL0807 | error | '[:]' is written in a type where 'Span<T>' or 'ReadOnlySpan<T>' is meant |
| SL0808 | error | an element of a read-only span is written |
| SL0809 | error | a setter or method that writes a struct is used on a read-only struct value |
| SL0810 | error | 'default' is taken of a type that has no zero value |
| SL0811 | error | a local whose type has no zero value is read before it is assigned on every path |
| SL0812 | error | 'new T[n]' is written for an element type that has no zero value |
| SL0813 | error | a field whose type has no zero value can be left unassigned by construction |
| SL0814 | error | a static or global whose type has no zero value has no initializer |
| SL0815 | error | a type argument with no zero value is given for a 'zeroable' type parameter |
| SL0816 | error | a member is called that its type's constraint-dependent arguments leave out |
| SL0817 | error | an event is declared with an initial value |
| SL0818 | error | an event is declared with a type that is not a closure |
| SL0819 | error | an event's closure type returns a value rather than void |
| SL0820 | error | an event is declared static |
| SL0821 | error | a method already declared takes the name and signature an event's generated method needs |
| SL0822 | error | an instance event is raised, cleared or subscribed to from a static method |
| SL0823 | error | an event is raised from outside the type that declares it |
| SL0824 | error | an event is read as a value from outside its declaring type |
| SL0825 | error | an event is assigned with an operator other than '+=' or '-=' |
| SL0826 | error | a library's metadata describes a slot or event incompletely, as if edited |
| SL0827 | error | a calling convention is written on something that is not a function or delegate |
| SL0828 | error | 'readonly' or 'static' is written on a declaration it cannot apply to |
| SL0829 | warning | a lambda assigns its own copy of a captured variable or member, changing nothing |
| SL0830 | error | an embed names a section the target's object format cannot have |
| SL0831 | error | a 128-bit integer type is used on a 32-bit target |

## SL09xx

| Code | Severity | Means |
|---|---|---|
| SL0900 | error | 'objc' is written on a declaration that cannot be an Objective-C type |
| SL0901 | error | 'extern' is written on an Objective-C type that cannot take it |
| SL0902 | error | a member of an Objective-C class or protocol has no '[Selector]' |
| SL0903 | error | a protocol member or an existing class's selector member is given a body |
| SL0904 | error | a '[Selector]' attribute is repeated, malformed or names an invalid selector |
| SL0905 | error | a selector's colon count disagrees with the member's parameter count |
| SL0906 | error | an attribute is written on an Objective-C member it does not apply to |
| SL0907 | error | a parameter or return type cannot be carried by an Objective-C message or block |
| SL0908 | error | an Objective-C type attribute is on the wrong type or malformed |
| SL0909 | error | an 'extern objc class' declares a member it cannot have, such as a field |
| SL0910 | error | an Objective-C type's base or protocol list is cyclic, misordered or names a wrong kind |
| SL0911 | error | an Objective-C class does not reach exactly one '[ObjCRoot]' root class |
| SL0913 | error | a member of an Objective-C type is taken as a value without being called |
| SL0914 | error | 'new' is used on an 'extern objc class' |
| SL0915 | error | an Objective-C message is sent on a target that is not macOS |
| SL0916 | error | an Objective-C object crosses a C++ or exported C boundary |
| SL0917 | error | a dependency container is asked for a type it cannot construct |
| SL0918 | error | a dependency container cannot choose between equally wide public constructors |
| SL0919 | error | a constructor parameter is of a kind a dependency container cannot supply |
| SL0920 | error | a default implementation named for a contract is not a matching generic class |
| SL0921 | error | an Objective-C class method's override, selector or modifier is inconsistent |
| SL0922 | error | a class adopting a protocol does not answer one of its required messages |
| SL0923 | error | an Objective-C type is used or declared in a way the runtime cannot support |
| SL0924 | error | an Objective-C class's constructor has no valid init message to run |
| SL0925 | error | a field of an Objective-C class has no zero value and no initializer |
| SL0926 | error | an Objective-C object owned by a C library is written to |
| SL0927 | error | '[CFType]' is misplaced or malformed, or a Core Foundation type is misused |
| SL0928 | error | a class member of a protocol is sent to the protocol rather than a class |
| SL0929 | error | a vector is constructed with wrong arguments |
| SL0930 | error | a vector member access names no lane or swizzle |
| SL0931 | error | a lane write repeats a lane or writes back to a non-repeatable vector expression |
| SL0932 | error | a binary operator is applied to vectors it does not accept |
| SL0933 | error | more than three vectors cross a foreign boundary on 32-bit Windows |
| SL0934 | error | a vector type's static member or function is unknown or wrongly applied |
| SL0935 | error | 'VaList.Start' or 'Next<T>' is used where or how it cannot be |
| SL0936 | error | a variable named 'field' is declared inside a property accessor |
| SL0937 | error | a constructor reaches the object or returns before 'base(...)' has run |
| SL0938 | error | a field with no zero value is still unset when the object becomes reachable |
| SL0939 | error | a field with no zero value is read in a constructor before it is assigned |
| SL0940 | error | 'late' is written on a field that cannot be late |
| SL0941 | error | '[Throws]' is written where it cannot apply |
