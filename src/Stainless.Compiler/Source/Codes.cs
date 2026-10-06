// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

namespace Stainless.Source;

/// <summary>
/// Every diagnostic the compiler can report, each declared once.
///
/// A code is a handle for one rule, so a rule has exactly one code and a code
/// means exactly one thing. This file is the inventory: a new diagnostic MUST
/// be declared here, and a place that reports one MUST name it from here rather
/// than spell its code. Before adding one, read the titles; a rule that is
/// already here gets its existing code. `docs/diagnostics.md` is generated from
/// this file by `stainless explain --markdown`.
/// </summary>
public static class Codes
{
    private static readonly List<DiagnosticDescriptor> s_all = [];

    /// <summary>Every declared diagnostic, in code order.</summary>
    public static IReadOnlyList<DiagnosticDescriptor> All => s_all;

    /// <summary>The diagnostic with this code, or null.</summary>
    public static DiagnosticDescriptor? Find(string code) =>
        s_all.FirstOrDefault(d => string.Equals(d.Code, code, StringComparison.OrdinalIgnoreCase));

    private static DiagnosticDescriptor Error(string code, string title) =>
        Declare(new DiagnosticDescriptor(code, Severity.Error, title));

    private static DiagnosticDescriptor Warning(string code, string title) =>
        Declare(new DiagnosticDescriptor(code, Severity.Warning, title));

    private static DiagnosticDescriptor Declare(DiagnosticDescriptor descriptor)
    {
        s_all.Add(descriptor);
        return descriptor;
    }

    // ---------------------------------------------------------- SL00xx

    public static readonly DiagnosticDescriptor UnexpectedCharacter =
        Error("SL0001", "a character in the source begins no token");

    public static readonly DiagnosticDescriptor UnterminatedBlockComment =
        Error("SL0002", "a block comment is never closed");

    public static readonly DiagnosticDescriptor NumericLiteralWithoutDigits =
        Error("SL0003", "a numeric literal has a prefix but no digits");

    public static readonly DiagnosticDescriptor InvalidNumericLiteral = Error(
        "SL0004",
        "a numeric literal has an unknown or unsuitable suffix, or is not a valid float");

    public static readonly DiagnosticDescriptor IntegerLiteralTooLarge =
        Error("SL0005", "an integer literal does not fit in 64 bits");

    public static readonly DiagnosticDescriptor UnterminatedStringLiteral =
        Error("SL0006", "a string literal, raw or interpolated, is never closed");

    public static readonly DiagnosticDescriptor UnterminatedCharacterLiteral =
        Error("SL0007", "a character literal is never closed");

    public static readonly DiagnosticDescriptor HexEscapeDigitCount =
        Error("SL0008", "a hex escape has too few or the wrong number of hex digits");

    public static readonly DiagnosticDescriptor UnrecognizedEscapeSequence =
        Error("SL0009", "a backslash escape is not one the language defines");

    public static readonly DiagnosticDescriptor EmptyCharacterLiteral =
        Error("SL0010", "a character literal holds no character");

    // ---------------------------------------------------------- SL01xx

    public static readonly DiagnosticDescriptor ExpectedToken =
        Error("SL0100", "the parser found a token other than the one the grammar requires");

    public static readonly DiagnosticDescriptor ExpectedIdentifier =
        Error("SL0101", "an identifier is required and something else was found");

    public static readonly DiagnosticDescriptor UnsupportedLinkageConvention =
        Error("SL0102", "an extern or export names a linkage convention other than C or C++");

    public static readonly DiagnosticDescriptor MissingLinkageConvention =
        Error("SL0103", "extern or export is not followed by a linkage convention string");

    public static readonly DiagnosticDescriptor DestructorNameMismatch =
        Error("SL0104", "a destructor's name is not the name of its enclosing type");

    public static readonly DiagnosticDescriptor ExternFunctionHasBody =
        Error("SL0105", "a function declared extern has a body");

    public static readonly DiagnosticDescriptor TypeNameUsedAsValue =
        Error("SL0106", "a type name stands where a value is expected");

    public static readonly DiagnosticDescriptor ExpectedExpression =
        Error("SL0107", "an expression is required and something else was found");

    public static readonly DiagnosticDescriptor NestingTooDeep =
        Error("SL0108", "source is nested deeper than the compiler can process");

    public static readonly DiagnosticDescriptor ModifierRepeatedOrConflicting = Error(
        "SL0109",
        "a modifier is written twice, or conflicts with another, on one declaration");

    // ---------------------------------------------------------- SL02xx

    public static readonly DiagnosticDescriptor DuplicateModuleMember =
        Error("SL0201", "a name is declared twice in one module");

    public static readonly DiagnosticDescriptor ImportedModuleNotFound =
        Error("SL0202", "an import names a module that is not among the compiled sources");

    public static readonly DiagnosticDescriptor ImportOfOwnModule =
        Warning("SL0203", "a file imports the module it belongs to");

    public static readonly DiagnosticDescriptor ModuleLevelVariable =
        Error("SL0204", "a variable is declared at module scope, where only constants are allowed");

    public static readonly DiagnosticDescriptor DuplicateTypeMember =
        Error("SL0205", "a type declares two members with the same name");

    public static readonly DiagnosticDescriptor ConstructorOnNonConstructibleType =
        Error("SL0207", "a constructor is declared on a type that is neither a class nor a struct");

    public static readonly DiagnosticDescriptor DestructorOnStruct =
        Error("SL0208", "a struct declares a destructor, which only a class can have");

    public static readonly DiagnosticDescriptor DuplicateDestructorOrStaticConstructor =
        Error("SL0209", "a type declares more than one destructor or static constructor");

    public static readonly DiagnosticDescriptor FunctionWithoutBody =
        Error("SL0210", "a function that must be defined where it is declared has no body");

    public static readonly DiagnosticDescriptor DuplicateOverload = Error(
        "SL0211",
        "two overloads of one function, operator, constructor or conversion share a signature");

    public static readonly DiagnosticDescriptor DuplicateParameterName =
        Error("SL0212", "two parameters of one function share a name");

    public static readonly DiagnosticDescriptor VoidParameter =
        Error("SL0213", "a parameter is declared with type void");

    public static readonly DiagnosticDescriptor InvalidConstantInitializer =
        Error("SL0215", "a constant is initialized with something other than a literal");

    public static readonly DiagnosticDescriptor StructContainsItself =
        Error("SL0216", "a struct contains itself by value and so has no finite size");

    public static readonly DiagnosticDescriptor NotAllPathsReturn =
        Error("SL0217", "some path through a function or lambda ends without returning a value");

    public static readonly DiagnosticDescriptor DuplicateLocalName =
        Error("SL0218", "a local name is declared twice in one scope");

    public static readonly DiagnosticDescriptor LocalShadowsParameter =
        Error("SL0219", "a local takes the name of a parameter");

    public static readonly DiagnosticDescriptor VarWithoutInitializer =
        Error("SL0220", "a var declaration has no initializer to infer its type from");

    public static readonly DiagnosticDescriptor VarInferredFromVoid =
        Error("SL0221", "a var declaration's initializer has type void");

    public static readonly DiagnosticDescriptor ExpressionHasNoEffect =
        Warning("SL0222", "an expression statement computes a value and discards it");

    public static readonly DiagnosticDescriptor ReturnMissingValue =
        Error("SL0223", "a return in a function that returns a value has no value");

    public static readonly DiagnosticDescriptor ReturnValueFromVoid =
        Error("SL0224", "a return in a void function carries a value");

    public static readonly DiagnosticDescriptor BreakOutsideLoopOrSwitch =
        Error("SL0225", "break appears outside a loop or a switch");

    public static readonly DiagnosticDescriptor ContinueOutsideLoop =
        Error("SL0226", "continue appears outside a loop");

    public static readonly DiagnosticDescriptor ConditionNotBool =
        Error("SL0227", "a condition is not of type bool");

    public static readonly DiagnosticDescriptor ThisOutsideInstanceMember =
        Error("SL0228", "this is used outside an instance method, constructor or destructor");

    public static readonly DiagnosticDescriptor NameNotDefined =
        Error("SL0229", "a name used as a value is not defined");

    public static readonly DiagnosticDescriptor AddressOfTemporary =
        Error("SL0230", "the address of a temporary value is taken");

    public static readonly DiagnosticDescriptor DereferenceOfNonPointer =
        Error("SL0231", "something other than a pointer is dereferenced");

    public static readonly DiagnosticDescriptor UnaryOperatorTypeMismatch =
        Error("SL0232", "a unary operator is applied to an operand type it does not accept");

    public static readonly DiagnosticDescriptor LogicalOperatorNeedsBool =
        Error("SL0233", "a logical operator is applied to operands that are not bool");

    public static readonly DiagnosticDescriptor BinaryOperatorTypeMismatch =
        Error("SL0234", "a binary operator is applied to operand types it does not accept");

    public static readonly DiagnosticDescriptor ShiftOperandNotInteger =
        Error("SL0235", "a shift operator is applied to operands that are not integers");

    public static readonly DiagnosticDescriptor OperatorOnBoolOperands =
        Error("SL0236", "an operator that bool does not support is applied to bool operands");

    public static readonly DiagnosticDescriptor NoCommonOperandType =
        Error("SL0238", "two operands have no common type for a binary operator");

    public static readonly DiagnosticDescriptor OperatorNeedsIntegers =
        Error("SL0239", "an integer-only operator is applied to operands that are not integers");

    public static readonly DiagnosticDescriptor AssignmentTargetNotAssignable = Error(
        "SL0240",
        "an assignment or update targets a constant or something that is not a location");

    public static readonly DiagnosticDescriptor TypeNotIndexable =
        Error("SL0241", "a value is indexed by a type with no matching indexer");

    public static readonly DiagnosticDescriptor IndexNotInteger =
        Error("SL0242", "an index, slice bound, from-end count or range bound is not an integer");

    public static readonly DiagnosticDescriptor InvalidCast =
        Error("SL0243", "an explicit cast names a conversion that does not exist");

    public static readonly DiagnosticDescriptor NewOfNonConstructibleType =
        Error("SL0244", "new is applied to a type that is neither a class nor a struct");

    public static readonly DiagnosticDescriptor NewWithoutConstructor = Error(
        "SL0245",
        "new passes arguments to, or is applied to, a type that declares no constructor");

    public static readonly DiagnosticDescriptor ModuleMemberNotFound =
        Error("SL0246", "a module has no public member with the name accessed");

    public static readonly DiagnosticDescriptor MemberNotFound =
        Error("SL0247", "a type, variant or variant case has no member with the name accessed");

    public static readonly DiagnosticDescriptor MemberAccessOnMaybeNull = Error(
        "SL0248",
        "a value that may be null or dead is used without a check proving it is not");

    public static readonly DiagnosticDescriptor MemberNotAccessible =
        Error("SL0249", "a field, property, event or constant is not visible from here");

    public static readonly DiagnosticDescriptor MethodUsedAsValue =
        Error("SL0250", "a method is named as a value without being called");

    public static readonly DiagnosticDescriptor FunctionNotFound =
        Error("SL0252", "no function with the called name is in scope");

    public static readonly DiagnosticDescriptor ExpressionNotCallable =
        Error("SL0253", "a call is made through a value that is not a delegate or closure");

    public static readonly DiagnosticDescriptor MethodCallOnMaybeNull =
        Error("SL0254", "a method is called on a value that may be null without a check");

    public static readonly DiagnosticDescriptor MethodNotFound =
        Error("SL0255", "a type has no method with the called name");

    public static readonly DiagnosticDescriptor MethodNotAccessible = Error(
        "SL0257",
        "a called method, or a member named through a type, is not visible from here");

    public static readonly DiagnosticDescriptor ArgumentCountMismatch =
        Error("SL0260", "a call passes the wrong number of arguments");

    public static readonly DiagnosticDescriptor ArgumentTypeMismatch =
        Error("SL0262", "an argument's type does not match its parameter's type");

    public static readonly DiagnosticDescriptor NoMatchingOverload =
        Error("SL0263", "no overload accepts the arguments of a call");

    public static readonly DiagnosticDescriptor AmbiguousCall =
        Error("SL0264", "more than one overload matches a call equally well");

    public static readonly DiagnosticDescriptor NoImplicitConversion =
        Error("SL0265", "a value cannot be implicitly converted to the type required");

    public static readonly DiagnosticDescriptor ConstantOutOfRange =
        Error("SL0266", "a constant value lies outside the range of its target type");

    public static readonly DiagnosticDescriptor PointerToReferenceType =
        Error("SL0270", "a raw pointer type is formed over a reference type");

    public static readonly DiagnosticDescriptor OptionalOfValueType =
        Error("SL0271", "an optional type is formed over a type that cannot be null");

    public static readonly DiagnosticDescriptor WeakOfNonReference =
        Error("SL0272", "weak is applied to a type that is not a class or interface reference");

    public static readonly DiagnosticDescriptor AmbiguousTypeName =
        Error("SL0273", "an unqualified type name matches types in more than one module");

    public static readonly DiagnosticDescriptor TypeNotAccessible =
        Error("SL0274", "a type or type alias named from another module is not public");

    public static readonly DiagnosticDescriptor ModuleTypeNotFound =
        Error("SL0275", "a qualified type name names a module that declares no such type");

    public static readonly DiagnosticDescriptor TypeNotFound =
        Error("SL0276", "a type name matches no type in scope");

    public static readonly DiagnosticDescriptor MultipleEntryPoints =
        Error("SL0280", "more than one Main is declared in the program");

    public static readonly DiagnosticDescriptor EntryPointReturnType =
        Error("SL0281", "Main returns something other than int or void");

    public static readonly DiagnosticDescriptor EntryPointParameters =
        Error("SL0282", "Main takes parameters other than none or one String array");

    public static readonly DiagnosticDescriptor ForeignSignatureCannotCross = Error(
        "SL0284",
        "a foreign function's parameter or return type cannot cross the C boundary");

    public static readonly DiagnosticDescriptor VariantFieldOnNonLocal = Error(
        "SL0285",
        "a variant case field is read from something other than a local or parameter");

    public static readonly DiagnosticDescriptor VariantFieldNotEstablished =
        Error("SL0286", "a variant case field is read where the case is not known to carry it");

    public static readonly DiagnosticDescriptor VarFromUnqualifiedCase =
        Error("SL0287", "a var is initialized with a variant case that does not name its variant");

    public static readonly DiagnosticDescriptor VariantCaseArgumentCount =
        Error("SL0289", "a variant case is constructed with the wrong number of fields");

    public static readonly DiagnosticDescriptor EntryPointNotFound =
        Error("SL0290", "an executable is built with no Main in any compiled module");

    public static readonly DiagnosticDescriptor OperatorOnStrings =
        Error("SL0291", "an operator that strings do not support is applied to two strings");

    public static readonly DiagnosticDescriptor StringOperandTypeMismatch =
        Error("SL0292", "a string operator is applied to a string and a value of another type");

    public static readonly DiagnosticDescriptor StringToBytePointer =
        Error("SL0293", "a String is used where a byte pointer is required without ToPointer");

    public static readonly DiagnosticDescriptor StringToVariadicArgument =
        Error("SL0294", "a String is passed to a C variadic function without ToPointer");

    public static readonly DiagnosticDescriptor DuplicateForeignSymbol = Error(
        "SL0295",
        "two declarations, or a declaration and the runtime, claim one C symbol name");

    // ---------------------------------------------------------- SL03xx

    public static readonly DiagnosticDescriptor InterfaceMemberHasState = Error(
        "SL0300",
        "an interface declares state, a constructor or a destructor, or a property naming storage");

    public static readonly DiagnosticDescriptor StructCannotBeInterface = Error(
        "SL0302",
        "a struct or other plain value type is used as or declared to implement an interface");

    public static readonly DiagnosticDescriptor BaseInterfaceNotInterface =
        Error("SL0303", "a type implements or extends something that is not an interface");

    public static readonly DiagnosticDescriptor InterfaceListedTwice = Warning(
        "SL0304",
        "a type lists the same interface, COM interface or protocol more than once");

    public static readonly DiagnosticDescriptor InterfaceMemberNotImplemented =
        Error("SL0305", "a type does not implement a member its interface requires");

    public static readonly DiagnosticDescriptor ImplementationNotPublic =
        Error("SL0306", "a member implementing an interface member is not public");

    public static readonly DiagnosticDescriptor ImplementationSignatureMismatch =
        Error("SL0307", "a member implementing an interface member does not match its signature");

    public static readonly DiagnosticDescriptor ConstructorTakesNoArguments =
        Error("SL0308", "'new' passes arguments to a class that has no constructor taking any");

    public static readonly DiagnosticDescriptor VoidUsedAsValueType = Error(
        "SL0309",
        "'void' is used as the type of a variable, field, parameter or type argument");

    public static readonly DiagnosticDescriptor VoidArrayElement =
        Error("SL0310", "an array is declared or built with 'void' elements");

    public static readonly DiagnosticDescriptor ArrayLengthNotInteger =
        Error("SL0312", "an array length is not an integer");

    public static readonly DiagnosticDescriptor ArrayMemberNotFound =
        Error("SL0313", "an array or inline array is accessed for a member other than 'Length'");

    public static readonly DiagnosticDescriptor TypeParametersOnNonMethod =
        Error("SL0320", "a property or field declares type parameters");

    public static readonly DiagnosticDescriptor GenericStaticInterfaceMember =
        Error("SL0322", "a 'static abstract' or 'static virtual' interface member is generic");

    public static readonly DiagnosticDescriptor TypeArgumentCountMismatch =
        Error("SL0323", "a generic is given the wrong number of type arguments");

    public static readonly DiagnosticDescriptor InferredTypeArgumentCountMismatch =
        Error("SL0324", "inference produced the wrong number of type arguments for a generic");

    public static readonly DiagnosticDescriptor GenericTypeMissingArguments =
        Error("SL0325", "a generic type is named without its type arguments");

    public static readonly DiagnosticDescriptor GenericTypeNotFound =
        Error("SL0326", "no generic type of the given name is in scope");

    public static readonly DiagnosticDescriptor TypeArgumentNotInferred =
        Error("SL0327", "type arguments for a generic cannot be inferred from the values passed");

    public static readonly DiagnosticDescriptor TypeArgumentConstraintUnmet =
        Error("SL0328", "a type argument does not satisfy a constraint on its type parameter");

    public static readonly DiagnosticDescriptor InvalidConstraintType = Error(
        "SL0329",
        "a type cannot be used as a constraint because it is sealed or cannot be derived from");

    public static readonly DiagnosticDescriptor ConstraintOnUnknownTypeParameter = Error(
        "SL0330",
        "a 'where' clause names something that is not a type parameter of its declaration");

    public static readonly DiagnosticDescriptor WhereClauseNotAllowed =
        Error("SL0331", "a 'where' clause is written on a member that cannot have one");

    public static readonly DiagnosticDescriptor ModuleDeclarationMissing =
        Error("SL0332", "a file does not declare which module it belongs to");

    public static readonly DiagnosticDescriptor InterfaceInheritanceCycle =
        Error("SL0333", "two interfaces extend each other");

    public static readonly DiagnosticDescriptor AttributeMemberNotField =
        Error("SL0340", "an attribute type declares a member that is not a field");

    public static readonly DiagnosticDescriptor ReflectOnUnsupportedType = Error(
        "SL0341",
        "'[Reflect]' is written on something other than a Stainless class or struct");

    public static readonly DiagnosticDescriptor NotAnAttribute =
        Error("SL0342", "a type that is not an attribute is written as an attribute");

    public static readonly DiagnosticDescriptor AttributeArgumentCountMismatch = Error(
        "SL0343",
        "an attribute is given a number of arguments different from its field count");

    public static readonly DiagnosticDescriptor AttributeArgumentNotConstant =
        Error("SL0344", "an attribute argument is not a constant of its field's type");

    public static readonly DiagnosticDescriptor AttributeUsedAsType =
        Error("SL0345", "an attribute is used as a type");

    public static readonly DiagnosticDescriptor TypeofWithoutReflect = Error(
        "SL0346",
        "'typeof' names a type that carries no metadata because it lacks '[Reflect]'");

    public static readonly DiagnosticDescriptor TypeofWithoutReflection =
        Error("SL0347", "'typeof' is used without Standard.Reflection in the compilation");

    public static readonly DiagnosticDescriptor ConditionalArmIsVoid =
        Error("SL0348", "an arm of a conditional expression produces no value");

    public static readonly DiagnosticDescriptor ConditionalArmsNoCommonType =
        Error("SL0349", "the arms of a conditional expression have no common type");

    public static readonly DiagnosticDescriptor EnumUnderlyingTypeNotInteger =
        Error("SL0350", "an enum is built on a type that is not an integer");

    public static readonly DiagnosticDescriptor DuplicateEnumMember =
        Error("SL0351", "an enum declares two members with the same name");

    public static readonly DiagnosticDescriptor EnumValueNotConstant =
        Error("SL0352", "an enum member's value is not an integer constant");

    public static readonly DiagnosticDescriptor EnumComparisonTypeMismatch =
        Error("SL0353", "an enum is compared with a value of a different type");

    public static readonly DiagnosticDescriptor EnumOperatorNotSupported = Error(
        "SL0354",
        "an arithmetic or bitwise operator is applied to an enum that does not support it");

    public static readonly DiagnosticDescriptor EnumMemberNotFound =
        Error("SL0355", "an enum has no member of the given name");

    public static readonly DiagnosticDescriptor ForEachNotEnumerable = Error(
        "SL0356",
        "'foreach' iterates something that is not an array and has no 'GetEnumerator()'");

    public static readonly DiagnosticDescriptor GetEnumeratorReturnsNonEnumerator =
        Error("SL0357", "'GetEnumerator()' returns a type lacking 'MoveNext()' and 'Current'");

    public static readonly DiagnosticDescriptor VariadicNotAllowed = Error(
        "SL0358",
        "a declaration that cannot be called safely as variadic is declared variadic");

    public static readonly DiagnosticDescriptor VoidParameterInTypeDeclaration =
        Error("SL0359", "a parameter of a delegate, closure or similar type declaration is 'void'");

    public static readonly DiagnosticDescriptor FunctionTargetNotDelegate =
        Error("SL0360", "a function or method is converted to a type that cannot hold it");

    public static readonly DiagnosticDescriptor NoOverloadMatchesDelegate =
        Error("SL0361", "no overload of a method group matches the delegate or closure type");

    public static readonly DiagnosticDescriptor AmbiguousDelegateConversion = Error(
        "SL0362",
        "a method group matches a delegate or closure type through more than one overload");

    public static readonly DiagnosticDescriptor DelegateArgumentCountMismatch =
        Error("SL0363", "a delegate or closure value is called with the wrong number of arguments");

    public static readonly DiagnosticDescriptor SpawnOutsideParallel =
        Error("SL0364", "'spawn' is used outside a 'parallel' block");

    public static readonly DiagnosticDescriptor SpawnTargetNotCall =
        Error("SL0365", "'spawn' is given something other than a function or method call");

    public static readonly DiagnosticDescriptor SpawnResultNotStorable = Error(
        "SL0366",
        "a spawned result is assigned to something other than a variable, field or element");

    public static readonly DiagnosticDescriptor SpawnResultIsVoid =
        Error("SL0367", "a spawned call returning nothing is assigned to a target");

    public static readonly DiagnosticDescriptor SpawnResultNeedsConversion =
        Error("SL0368", "a spawned result needs a conversion to the type it is stored into");

    public static readonly DiagnosticDescriptor ParallelForVariableMissing =
        Error("SL0369", "a 'for parallel' does not start by declaring an integer loop variable");

    public static readonly DiagnosticDescriptor ParallelForConditionInvalid = Error(
        "SL0370",
        "a 'for parallel' condition is not a '<' or '<=' bound on its loop variable");

    public static readonly DiagnosticDescriptor ParallelForStepInvalid =
        Error("SL0371", "a 'for parallel' step is not an increment of its loop variable");

    public static readonly DiagnosticDescriptor ParallelForStrideNotLiteral =
        Error("SL0372", "a 'for parallel' stride is not a positive integer literal");

    public static readonly DiagnosticDescriptor ParallelForOuterAssignment =
        Error("SL0373", "a 'for parallel' body assigns a variable declared outside it");

    public static readonly DiagnosticDescriptor ReturnFromParallel =
        Error("SL0374", "'return' leaves a 'parallel' block");

    public static readonly DiagnosticDescriptor SpawnBorrowsTemporary = Error(
        "SL0375",
        "a spawned call's receiver or argument is a temporary rather than a held value");

    public static readonly DiagnosticDescriptor StaticWithoutInitializer =
        Error("SL0376", "a static is declared without an initial value");

    public static readonly DiagnosticDescriptor SharedStateNotThreadSafe =
        Warning("SL0377", "a value reached by more than one thread has no declared thread safety");

    public static readonly DiagnosticDescriptor StaticInitializationCycle = Error(
        "SL0378",
        "a static initializer or static constructor depends on itself through other statics");

    public static readonly DiagnosticDescriptor StaticReadonlyAssigned = Error(
        "SL0379",
        "a 'static readonly' or a field of the struct it holds is written after initialization");

    public static readonly DiagnosticDescriptor CapturingLambdaToDelegate = Error(
        "SL0381",
        "a lambda or local function that captures state is converted to a delegate");

    public static readonly DiagnosticDescriptor LambdaTargetInvalid = Error(
        "SL0382",
        "a lambda is converted to a type that is not a delegate or single-method interface");

    public static readonly DiagnosticDescriptor LambdaParameterCountMismatch =
        Error("SL0383", "a lambda declares a parameter count different from its target type");

    public static readonly DiagnosticDescriptor LambdaParameterTypeMismatch =
        Error("SL0384", "a lambda parameter's written type differs from what its target expects");

    public static readonly DiagnosticDescriptor PropertyAccessorExpected =
        Error("SL0385", "a property body contains something other than 'get', 'set' or 'init'");

    public static readonly DiagnosticDescriptor PropertyTypeIsVoid =
        Error("SL0387", "a property is declared with type 'void'");

    public static readonly DiagnosticDescriptor DuplicatePropertyAccessor =
        Error("SL0388", "a property declares the same accessor twice");

    public static readonly DiagnosticDescriptor PropertyGetterMissing =
        Error("SL0389", "a property declares no getter");

    public static readonly DiagnosticDescriptor SpawnUsedAsValue =
        Error("SL0390", "'spawn' is used as a value inside a larger expression");

    public static readonly DiagnosticDescriptor MixedAutoAndWrittenAccessors =
        Error("SL0391", "a property mixes an automatic accessor with a written one");

    public static readonly DiagnosticDescriptor AbstractAccessorHasBody =
        Error("SL0392", "an accessor of an abstract property has a body");

    public static readonly DiagnosticDescriptor AccessorNameCollision =
        Error("SL0393", "a method already uses the name and parameters a property accessor needs");

    public static readonly DiagnosticDescriptor GetterAccessibilityNarrowed =
        Error("SL0394", "a property getter is given narrower accessibility than its property");

    public static readonly DiagnosticDescriptor PropertyHasNoSetter =
        Error("SL0395", "a property without a setter is assigned");

    public static readonly DiagnosticDescriptor PropertySetterInaccessible =
        Error("SL0396", "a property is assigned from outside where its setter is accessible");

    public static readonly DiagnosticDescriptor AccessorCalledDirectly = Error(
        "SL0398",
        "a property's getter or setter method is called by name instead of the property");

    public static readonly DiagnosticDescriptor WriteToTemporaryStruct = Error(
        "SL0399",
        "a field or property of a temporary struct is written, so the write is lost");

    // ---------------------------------------------------------- SL04xx

    public static readonly DiagnosticDescriptor PropertyAtModuleLevel = Error(
        "SL0400",
        "a property is declared at module level, where there is no instance for it");

    public static readonly DiagnosticDescriptor AutoPropertyNeverAssigned = Error(
        "SL0401",
        "an automatic property has no setter and its type has no constructor to fill it");

    public static readonly DiagnosticDescriptor SwitchStatementOutsideSection =
        Error("SL0402", "a statement in a switch is not under a 'case' or 'default' label");

    public static readonly DiagnosticDescriptor SwitchValueTypeNotSwitchable =
        Error("SL0403", "a switch is over a type that cannot have constant labels");

    public static readonly DiagnosticDescriptor CaseLabelNotConstant = Error(
        "SL0404",
        "a 'case' label is not a constant of the switched type, or not one of the variant's cases");

    public static readonly DiagnosticDescriptor DuplicateSwitchCase =
        Error("SL0405", "a switch has two cases or arms for the same value");

    public static readonly DiagnosticDescriptor DuplicateSwitchDefault =
        Error("SL0406", "a switch has more than one 'default' section");

    public static readonly DiagnosticDescriptor SwitchSectionFallsThrough = Error(
        "SL0407",
        "a switch section runs off its end without 'break', 'return', 'continue' or 'goto'");

    public static readonly DiagnosticDescriptor FlagOperationOnNonFlagsEnum =
        Error("SL0408", "a flag operation is used on an enum that is not marked '[Flags]'");

    public static readonly DiagnosticDescriptor HasFlagArgumentMismatch =
        Error("SL0409", "'HasFlag' is not given exactly one argument of the enum's own type");

    public static readonly DiagnosticDescriptor FlagTestedAgainstItself = Error(
        "SL0410",
        "a flag test reads the same expression twice; it must be put in a variable first");

    public static readonly DiagnosticDescriptor FlagsAttributeOnNonEnum =
        Error("SL0411", "'[Flags]' is applied to a type that is not an enum");

    public static readonly DiagnosticDescriptor BuiltInMemberArgumentCount =
        Error("SL0412", "a built-in member is called with the wrong number of arguments");

    public static readonly DiagnosticDescriptor VariantCaseWhereOtherTypeExpected =
        Error("SL0413", "a variant's case is named where a value of another type is expected");

    public static readonly DiagnosticDescriptor FunctionNamedAfterVariantCase = Error(
        "SL0414",
        "a module-level function has the name of a variant case, which a bare call would build");

    public static readonly DiagnosticDescriptor ConstantDivisionByZero =
        Error("SL0415", "a division or remainder has a constant zero divisor");

    public static readonly DiagnosticDescriptor ReferencedTypeRedeclared =
        Error("SL0417", "a type is declared both in the program and in a referenced library");

    public static readonly DiagnosticDescriptor ReferencedSignatureTypeUnknown =
        Error("SL0418", "a referenced library's member uses a type the program does not know");

    public static readonly DiagnosticDescriptor GenericOmittedFromMetadata = Warning(
        "SL0419",
        "a generic is left out of a library's metadata, since it crosses as source only");

    public static readonly DiagnosticDescriptor InterfaceImplementerOmittedFromMetadata = Warning(
        "SL0420",
        "a type that implements an interface is left out of a library's metadata");

    public static readonly DiagnosticDescriptor PackAttributeInvalid = Error(
        "SL0421",
        "'[Pack(N)]' is on something other than a struct or union, or N is not a valid alignment");

    public static readonly DiagnosticDescriptor VariantHasNoCases =
        Error("SL0430", "a variant declares no cases");

    public static readonly DiagnosticDescriptor VariantCaseVariadic =
        Error("SL0431", "a variant case declares variadic parameters");

    public static readonly DiagnosticDescriptor TooManyVariantCases =
        Error("SL0432", "a variant has more cases than its one-byte tag can number");

    public static readonly DiagnosticDescriptor DuplicateVariantCase =
        Error("SL0433", "a variant declares two cases with the same name");

    public static readonly DiagnosticDescriptor DuplicateVariantCaseField =
        Error("SL0434", "a variant case declares two fields with the same name");

    public static readonly DiagnosticDescriptor VariantCaseNotFound =
        Error("SL0435", "a variant has no case of the given name");

    public static readonly DiagnosticDescriptor VariantSwitchNotExhaustive =
        Error("SL0436", "a switch over a variant leaves cases uncovered and has no 'default'");

    public static readonly DiagnosticDescriptor CasePatternOnNonVariant = Error(
        "SL0438",
        "a case or class pattern is matched against something neither a variant nor an object");

    public static readonly DiagnosticDescriptor EmptyVariantCaseBound =
        Error("SL0439", "a case that carries nothing is given a name to bind");

    public static readonly DiagnosticDescriptor MultipleBoundCasesInSection =
        Error("SL0440", "a switch section binds more than one variant case");

    public static readonly DiagnosticDescriptor VariantOmittedFromMetadata = Warning(
        "SL0441",
        "a variant is left out of a library's metadata, since it crosses as source only");

    public static readonly DiagnosticDescriptor ReflectOnVariant =
        Error("SL0442", "'[Reflect]' is applied to a variant, whose cases cannot be described yet");

    public static readonly DiagnosticDescriptor ArgumentHasNoStorage = Error(
        "SL0443",
        "an expression with no addressable storage is passed by 'ref' or 'out', or addressed");

    public static readonly DiagnosticDescriptor ReadOnlyPassedByReference =
        Error("SL0444", "a read-only location is passed as 'ref' or 'out'");

    public static readonly DiagnosticDescriptor RefArgumentMissingKeyword =
        Error("SL0445", "an argument to a 'ref' parameter is passed without 'ref'");

    public static readonly DiagnosticDescriptor RefArgumentNotExpected =
        Error("SL0446", "'ref' is written on an argument to a parameter taken by value or as 'in'");

    public static readonly DiagnosticDescriptor RefArgumentTypeMismatch =
        Error("SL0447", "a 'ref' or 'out' argument's type does not exactly match the parameter's");

    public static readonly DiagnosticDescriptor InParameterWritten =
        Error("SL0448", "an 'in' parameter is written to");

    public static readonly DiagnosticDescriptor SpawnedCallTakesReference = Error(
        "SL0449",
        "a spawned call passes a 'ref', 'out' or 'in' parameter, sharing the caller's storage");

    public static readonly DiagnosticDescriptor IndexMissing =
        Error("SL0450", "an indexing expression has no index");

    public static readonly DiagnosticDescriptor SpanOfVoid =
        Error("SL0451", "a span or read-only span of 'void' is written");

    public static readonly DiagnosticDescriptor TypeCannotBeSliced =
        Error("SL0452", "a slice is taken of a value that cannot be sliced");

    public static readonly DiagnosticDescriptor AmbiguousGenericType =
        Error("SL0453", "a generic type name matches more than one template for its arguments");

    public static readonly DiagnosticDescriptor UnclosedConditionalDirective =
        Error("SL0454", "an '#if' is never closed by '#endif'");

    public static readonly DiagnosticDescriptor DirectiveAfterElse =
        Error("SL0455", "an '#elif' or second '#else' follows an '#else'");

    public static readonly DiagnosticDescriptor DefineAfterDeclaration =
        Error("SL0456", "a '#define' or '#undef' comes after the first declaration in the file");

    public static readonly DiagnosticDescriptor DefineArgumentNotName =
        Error("SL0457", "a '#define' or '#undef' is given something other than one name");

    public static readonly DiagnosticDescriptor ErrorDirective =
        Error("SL0458", "an '#error' directive is reached");

    public static readonly DiagnosticDescriptor WarningDirective =
        Warning("SL0459", "a '#warning' directive is reached");

    public static readonly DiagnosticDescriptor UnknownDirective =
        Error("SL0460", "a '#' line names no directive the language has");

    public static readonly DiagnosticDescriptor DirectiveWithoutIf =
        Error("SL0461", "an '#elif', '#else' or '#endif' has no '#if' to belong to");

    public static readonly DiagnosticDescriptor MalformedDirectiveCondition =
        Error("SL0462", "a conditional directive's condition is missing or malformed");

    public static readonly DiagnosticDescriptor PackedAttributeInvalid =
        Error("SL0463", "'[Packed]' is on a non-struct, or on a field that cannot be packed");

    public static readonly DiagnosticDescriptor AlignAttributeOnNonStruct =
        Error("SL0464", "'[Align]' is applied to a type that is not a struct");

    public static readonly DiagnosticDescriptor AlignmentNotPowerOfTwo =
        Error("SL0465", "'[Align(N)]' asks for an alignment that is not a power of two");

    public static readonly DiagnosticDescriptor AlignmentTooLarge =
        Error("SL0466", "'[Align(N)]' asks for more than the largest alignment allowed");

    public static readonly DiagnosticDescriptor UnionHasNoMembers =
        Error("SL0467", "a union declares no members");

    public static readonly DiagnosticDescriptor UnionMemberCounted =
        Error("SL0468", "a union member holds a counted reference");

    public static readonly DiagnosticDescriptor BitFieldOutsideStruct =
        Error("SL0469", "a bit-field is declared in a type that is not a struct or union");

    public static readonly DiagnosticDescriptor PackedWithBitFields =
        Error("SL0470", "a packed type has bit-fields, whose layout C compilers disagree on");

    public static readonly DiagnosticDescriptor BitFieldTypeInvalid =
        Error("SL0471", "a bit-field's type is not an integer or a bool");

    public static readonly DiagnosticDescriptor BitFieldWidthNotConstant =
        Error("SL0472", "a bit-field's width is not a constant");

    public static readonly DiagnosticDescriptor BitFieldWidthZero =
        Error("SL0473", "a bit-field's width is less than one bit");

    public static readonly DiagnosticDescriptor BitFieldWidthTooLarge =
        Error("SL0474", "a bit-field asks for more bits than its type has");

    public static readonly DiagnosticDescriptor ReflectWithBitFields = Error(
        "SL0475",
        "'[Reflect]' is applied to a type with bit-fields, which have no byte offset");

    public static readonly DiagnosticDescriptor LibraryExportsNothing =
        Warning("SL0476", "a library has no 'export \"C\"' function to export");

    public static readonly DiagnosticDescriptor MetadataReferencesUndescribedType = Warning(
        "SL0477",
        "a type in a library's metadata refers to a type the metadata does not describe");

    public static readonly DiagnosticDescriptor ConstTypeNotInlinable =
        Error("SL0478", "a 'const' is declared with a type a constant cannot hold");

    public static readonly DiagnosticDescriptor ConstValueTypeMismatch =
        Error("SL0479", "a 'const' is given a literal of the wrong kind for its declared type");

    public static readonly DiagnosticDescriptor OffsetOfInvalidType =
        Error("SL0480", "'offsetof' names a type that has no fixed field offsets");

    public static readonly DiagnosticDescriptor OffsetOfFieldNotFound =
        Error("SL0481", "'offsetof' names a field the type does not have");

    public static readonly DiagnosticDescriptor OffsetOfBitField =
        Error("SL0482", "'offsetof' names a bit-field, which has no byte offset");

    public static readonly DiagnosticDescriptor UnknownPragma =
        Error("SL0483", "a '#pragma' is not 'comment(lib, ...)' or 'comment(framework, ...)'");

    public static readonly DiagnosticDescriptor PragmaLibraryNameInvalid =
        Error("SL0484", "a '#pragma comment(lib, ...)' library name is missing or not quoted");

    public static readonly DiagnosticDescriptor InlineArrayOfCounted =
        Error("SL0486", "an inline array's element type holds a counted reference");

    public static readonly DiagnosticDescriptor InlineArrayLengthNotConstant =
        Error("SL0487", "an inline array's length is not a constant");

    public static readonly DiagnosticDescriptor InlineArrayLengthNotPositive =
        Error("SL0488", "an inline array asks for fewer than one element");

    public static readonly DiagnosticDescriptor InlineArrayTooLarge =
        Error("SL0489", "an inline array would be larger than a value can be");

    public static readonly DiagnosticDescriptor ConstantIndexOutOfRange =
        Error("SL0490", "a constant index is outside a fixed-length array or vector");

    public static readonly DiagnosticDescriptor InlineArrayParameterByValue =
        Error("SL0491", "a parameter takes an inline array by value rather than by 'ref' or 'in'");

    public static readonly DiagnosticDescriptor AmbiguousNamelessMember =
        Error("SL0492", "a member name is declared by more than one nameless member of a type");

    public static readonly DiagnosticDescriptor VariadicNotAllowedHere = Error(
        "SL0493",
        "'...' is written on something other than a module-level function or foreign message");

    public static readonly DiagnosticDescriptor ArrowOnNonPointer =
        Error("SL0494", "'->' is applied to a non-pointer, or a pointer to a type with no members");

    public static readonly DiagnosticDescriptor AbstractOrSealedNonClass =
        Error("SL0495", "'abstract' or 'sealed' is applied to a type that is not a class");

    public static readonly DiagnosticDescriptor AbstractAndSealed =
        Error("SL0496", "a class is marked both 'abstract' and 'sealed'");

    public static readonly DiagnosticDescriptor DispatchModifierOnField =
        Error("SL0497", "a field is given a dispatch modifier such as 'virtual' or 'override'");

    public static readonly DiagnosticDescriptor AbstractMemberHasBody =
        Error("SL0498", "an abstract method has a body");

    public static readonly DiagnosticDescriptor OverrideHasNoBase =
        Error("SL0499", "a member marked 'override' matches nothing it inherits");

    // ---------------------------------------------------------- SL05xx

    public static readonly DiagnosticDescriptor OverriddenMethodNotVirtual =
        Error("SL0500", "a method overrides one that is not virtual or abstract");

    public static readonly DiagnosticDescriptor OverriddenMethodSealed =
        Error("SL0501", "a method overrides a sealed override");

    public static readonly DiagnosticDescriptor OverrideSignatureMismatch =
        Error("SL0502", "an override does not match the signature of what it overrides");

    public static readonly DiagnosticDescriptor InheritedMemberHiddenWithoutOverride = Error(
        "SL0503",
        "a member has the same signature as an inherited one and is not marked 'override'");

    public static readonly DiagnosticDescriptor AbstractMemberNotImplemented =
        Error("SL0504", "a concrete class does not implement an inherited abstract method");

    public static readonly DiagnosticDescriptor AbstractMemberInConcreteClass =
        Error("SL0505", "an abstract method is declared in a class that is not abstract");

    public static readonly DiagnosticDescriptor DispatchedMemberNotAccessible =
        Error("SL0506", "a virtual, abstract or override method is neither public nor protected");

    public static readonly DiagnosticDescriptor DispatchModifiersMisused =
        Error("SL0507", "a method combines dispatch modifiers that contradict each other");

    public static readonly DiagnosticDescriptor BaseClassNotFirst =
        Error("SL0508", "a base class is listed after an interface in a base list");

    public static readonly DiagnosticDescriptor BaseClassSealed =
        Error("SL0509", "a class derives from a sealed class");

    public static readonly DiagnosticDescriptor MultipleBaseClasses =
        Error("SL0510", "a class names more than one base class");

    public static readonly DiagnosticDescriptor CircularClassInheritance =
        Error("SL0511", "a class derives from itself, directly or through a cycle");

    public static readonly DiagnosticDescriptor InterfaceExtendsClass =
        Error("SL0512", "an interface names a class as a base");

    public static readonly DiagnosticDescriptor BaseClassProvidedByRuntime = Error(
        "SL0513",
        "a class derives from a type the runtime provides rather than this compilation");

    public static readonly DiagnosticDescriptor AbstractClassInstantiated =
        Error("SL0514", "an abstract class is constructed with 'new'");

    public static readonly DiagnosticDescriptor NoBaseToReach = Error(
        "SL0515",
        "'base' is used with no base class, or not as a member access or constructor call");

    public static readonly DiagnosticDescriptor ConstructorCallMisplaced = Error(
        "SL0516",
        "a 'base(...)' or 'this(...)' call is outside a constructor or in the wrong place in one");

    public static readonly DiagnosticDescriptor BaseConstructorCallMismatch = Error(
        "SL0517",
        "a base constructor call is missing where one is required, or written where none exists");

    public static readonly DiagnosticDescriptor IsPatternNotApplicable =
        Error("SL0518", "an 'is' test asks something the subject's type cannot answer");

    public static readonly DiagnosticDescriptor ClassOnlyModifierOutsideClass =
        Error("SL0519", "a dispatch modifier or 'protected' is used on a member outside a class");

    public static readonly DiagnosticDescriptor TypeTestAlwaysTrue = Warning(
        "SL0520",
        "a type test always succeeds because the subject's type already is the tested type");

    public static readonly DiagnosticDescriptor CircularConstructorDelegation =
        Error("SL0521", "constructors delegate to themselves or to each other in a cycle");

    public static readonly DiagnosticDescriptor CircularTypeAlias =
        Error("SL0522", "a type alias is defined in terms of itself");

    public static readonly DiagnosticDescriptor BodilessTypeNotAllowed =
        Error("SL0523", "a type is declared without a body where only a non-generic struct may be");

    public static readonly DiagnosticDescriptor IncompleteTypeUsedByValue = Error(
        "SL0524",
        "a type declared without a body is used by value rather than through a pointer");

    public static readonly DiagnosticDescriptor TypeAliasInsideType =
        Error("SL0525", "a type alias is declared inside a type rather than at module level");

    public static readonly DiagnosticDescriptor EscapeNotUnicodeScalar =
        Error("SL0526", "a Unicode escape names a value that is not a Unicode scalar");

    public static readonly DiagnosticDescriptor CodeUnitConversionInvalid = Error(
        "SL0527",
        "a character value converts implicitly between encodings or does not fit one code unit");

    public static readonly DiagnosticDescriptor ComModifierOnWrongKind =
        Error("SL0528", "'com' is written on a type that is neither an interface nor a class");

    public static readonly DiagnosticDescriptor ComInterfaceExtendsNonCom =
        Error("SL0529", "a com interface extends an interface that is not com");

    public static readonly DiagnosticDescriptor ComInterfaceMultipleBases =
        Error("SL0530", "a com interface extends more than one com interface");

    public static readonly DiagnosticDescriptor CircularComInterfaceInheritance =
        Error("SL0531", "a com interface extends itself, directly or through a cycle");

    public static readonly DiagnosticDescriptor ComInterfaceOnNonClass =
        Error("SL0532", "a type other than a class implements a com interface");

    public static readonly DiagnosticDescriptor ComInterfaceOnNonComClass =
        Error("SL0533", "a class implements a com interface without being declared 'com class'");

    public static readonly DiagnosticDescriptor ComInterfaceEmpty =
        Warning("SL0534", "a com interface declares no methods, so it is just IUnknown");

    public static readonly DiagnosticDescriptor ComClassWithoutComInterface =
        Error("SL0535", "a com class implements no com interface");

    public static readonly DiagnosticDescriptor ComClassWithBaseClass =
        Error("SL0536", "a com class derives from a base class");

    public static readonly DiagnosticDescriptor ComInterfaceMissingGuid =
        Error("SL0537", "a com interface has no '[Guid]' attribute");

    public static readonly DiagnosticDescriptor GuidOnNonComType =
        Error("SL0538", "'[Guid]' is written on a type that is not a com interface or com class");

    public static readonly DiagnosticDescriptor DuplicateGuidAttribute =
        Error("SL0539", "a type carries more than one '[Guid]' attribute");

    public static readonly DiagnosticDescriptor GuidArgumentInvalid =
        Error("SL0540", "'[Guid]' is not given exactly one string literal");

    public static readonly DiagnosticDescriptor GuidFormatInvalid =
        Error("SL0541", "a '[Guid]' string is not in GUID form");

    public static readonly DiagnosticDescriptor IidOfNonComInterface =
        Error("SL0542", "'iidof' names a type that is not a com interface");

    public static readonly DiagnosticDescriptor ComInterfaceOmittedFromMetadata =
        Warning("SL0543", "a public com interface is left out of a library's metadata");

    public static readonly DiagnosticDescriptor ComClassOmittedFromMetadata =
        Warning("SL0544", "a public com class is left out of a library's metadata");

    public static readonly DiagnosticDescriptor InterfaceOmittedFromMetadata =
        Warning("SL0545", "a public interface is left out of a library's metadata");

    public static readonly DiagnosticDescriptor ArrayLiteralTargetInvalid =
        Error("SL0546", "an array literal targets a type that cannot be built from elements");

    public static readonly DiagnosticDescriptor InlineArrayLengthMismatch = Error(
        "SL0547",
        "an array literal has a different number of elements than its inline array type");

    public static readonly DiagnosticDescriptor EmptyArrayLiteralUntyped =
        Error("SL0548", "an empty array literal has no element type to infer");

    public static readonly DiagnosticDescriptor ArrayLiteralElementTypesDisagree =
        Error("SL0549", "the elements of an array literal do not share one type");

    public static readonly DiagnosticDescriptor TypeRedeclarationUnresolved =
        Error("SL0550", "a further declaration of a type cannot be matched to the type it adds to");

    public static readonly DiagnosticDescriptor TypeRedeclarationConflicts = Error(
        "SL0551",
        "a further declaration of a type restates what only one declaration may say");

    public static readonly DiagnosticDescriptor FieldInTypeRedeclaration =
        Error("SL0552", "a further declaration of a non-class type adds a field");

    public static readonly DiagnosticDescriptor VarTypeNotInferable =
        Error("SL0553", "a 'var' is given a value whose type cannot be inferred");

    public static readonly DiagnosticDescriptor UnmatchedInterpolationBrace =
        Error("SL0554", "an interpolated string has a '}' that closes nothing");

    public static readonly DiagnosticDescriptor EmptyInterpolation =
        Error("SL0555", "an interpolated string has an empty '{}' hole");

    public static readonly DiagnosticDescriptor InterpolationHasExtraTokens =
        Error("SL0556", "an interpolation hole holds more than one expression");

    public static readonly DiagnosticDescriptor InterpolatedValueNotWritable =
        Error("SL0557", "an interpolation hole holds a value with no defined text form");

    public static readonly DiagnosticDescriptor OperatorNotOverloadable =
        Error("SL0558", "an operator that cannot be overloaded is declared");

    public static readonly DiagnosticDescriptor OperatorMissingBody =
        Error("SL0559", "an operator declaration has no body");

    public static readonly DiagnosticDescriptor OperatorDeclaredOutsideType =
        Error("SL0560", "an operator is declared somewhere other than the concrete type it is for");

    public static readonly DiagnosticDescriptor OperatorNotPublic =
        Error("SL0561", "an operator is not declared 'public'");

    public static readonly DiagnosticDescriptor OperatorOperandCountMismatch =
        Error("SL0562", "an operator declares the wrong number of operands");

    public static readonly DiagnosticDescriptor OperatorOperandNotContainingType =
        Error("SL0563", "no operand of an operator is the type that declares it");

    public static readonly DiagnosticDescriptor ComparisonOperatorNotBool =
        Error("SL0564", "a comparison operator does not return 'bool'");

    public static readonly DiagnosticDescriptor OperatorOverloadNotFound =
        Error("SL0565", "no declared operator overload accepts the operand types");

    public static readonly DiagnosticDescriptor OperatorOverloadAmbiguous =
        Error("SL0566", "more than one operator overload accepts the operand types");

    public static readonly DiagnosticDescriptor OperatorPairIncomplete =
        Error("SL0567", "a type declares one operator of a pair without its counterpart");

    public static readonly DiagnosticDescriptor IndexerWithoutParameters =
        Error("SL0568", "an indexer declares no index parameters");

    public static readonly DiagnosticDescriptor TryOperandNotResult =
        Error("SL0569", "'try' is applied to a value that is not a 'Result'");

    public static readonly DiagnosticDescriptor TryOutsideResultFunction =
        Error("SL0570", "'try' is used where the enclosing code does not return a 'Result'");

    public static readonly DiagnosticDescriptor TryErrorTypeMismatch =
        Error("SL0571", "'try' passes on a failure type that differs from the function's");

    public static readonly DiagnosticDescriptor ConstructorNotAccessible =
        Error("SL0572", "a type is constructed from outside the module that owns its constructors");

    public static readonly DiagnosticDescriptor StaticModuleFunction =
        Error("SL0573", "a module-level function is marked 'static'");

    public static readonly DiagnosticDescriptor StaticInterfaceMemberModifiersInvalid = Error(
        "SL0574",
        "a static interface member has an invalid combination of body and modifiers");

    public static readonly DiagnosticDescriptor StaticMemberWithInstanceModifier =
        Error("SL0575", "a static method is also marked with a dispatch modifier or 'protected'");

    public static readonly DiagnosticDescriptor MemberAccessedWithWrongReceiver = Error(
        "SL0576",
        "an instance member is reached without an instance, or a static one through a value");

    public static readonly DiagnosticDescriptor StaticModifierOnWrongKind =
        Error("SL0578", "'static' is written on a kind of type that cannot be static");

    public static readonly DiagnosticDescriptor NewConstraintWithParameters =
        Error("SL0579", "a 'new()' constraint lists parameters");

    public static readonly DiagnosticDescriptor ConstraintOrderInvalid =
        Error("SL0580", "a constraint is out of order in a type parameter's clause");

    public static readonly DiagnosticDescriptor ConstraintsContradict =
        Error("SL0581", "a type parameter's constraints contradict each other");

    public static readonly DiagnosticDescriptor ThreadsafeOnWrongKind =
        Error("SL0582", "'threadsafe' is written on a kind of type that cannot claim it");

    public static readonly DiagnosticDescriptor StaticClassMisused =
        Error("SL0583", "a static class is instantiated or declares an instance member");

    public static readonly DiagnosticDescriptor PatternVariableNotDefinitelyMatched =
        Error("SL0585", "a pattern variable is used where its pattern may not have matched");

    public static readonly DiagnosticDescriptor PatternBindsEmptyCase =
        Error("SL0586", "a pattern names a variable for a variant case that carries nothing");

    public static readonly DiagnosticDescriptor PatternBindsInterface =
        Error("SL0587", "a pattern names or deconstructs a value tested against an interface");

    public static readonly DiagnosticDescriptor DuplicateLabel =
        Error("SL0588", "a label is declared twice in one function");

    public static readonly DiagnosticDescriptor LabelNotFound =
        Error("SL0589", "a 'goto' names a label that does not exist in its function");

    public static readonly DiagnosticDescriptor JumpOutOfParallelBlock =
        Error("SL0590", "a jump leaves a 'parallel' block");

    public static readonly DiagnosticDescriptor LabelUnused =
        Warning("SL0591", "a label is never jumped to");

    public static readonly DiagnosticDescriptor NameofOperandUnnamed =
        Error("SL0592", "'nameof' is given an expression that is not a name");

    public static readonly DiagnosticDescriptor IncrementOfReadOnlyProperty =
        Error("SL0593", "an increment or decrement targets a property with no setter");

    public static readonly DiagnosticDescriptor IncrementOperandInvalid = Error(
        "SL0594",
        "an increment or decrement is applied to a type that is not a number or pointer");

    public static readonly DiagnosticDescriptor JumpIntoBlock =
        Error("SL0595", "a jump enters a block it is not already in");

    public static readonly DiagnosticDescriptor NameofNameNotFound =
        Error("SL0596", "'nameof' names something that does not exist");

    public static readonly DiagnosticDescriptor OutArgumentMissingModifier =
        Error("SL0597", "an argument for an 'out' parameter is not written with 'out'");

    public static readonly DiagnosticDescriptor OutArgumentForNonOutParameter =
        Error("SL0598", "an argument is written 'out' for a parameter that is not 'out'");

    // ---------------------------------------------------------- SL06xx

    public static readonly DiagnosticDescriptor OutParameterNotAssigned =
        Error("SL0600", "a function can return without assigning one of its 'out' parameters");

    public static readonly DiagnosticDescriptor CallArgumentsDoNotFit = Error(
        "SL0601",
        "a call's arguments do not fit the parameters of the function or constructor it names");

    public static readonly DiagnosticDescriptor NamedArgumentNotAllowed = Error(
        "SL0602",
        "a named argument is passed to something that takes its arguments only by position");

    public static readonly DiagnosticDescriptor DefaultOfVoid =
        Error("SL0603", "'default' is used where the type is 'void', which has no value");

    public static readonly DiagnosticDescriptor NullOperatorOnNonNullable =
        Error("SL0604", "a null-testing operator is applied to a type that cannot be null");

    public static readonly DiagnosticDescriptor ConditionalAccessResultNotNullable =
        Error("SL0605", "a '?.' reaches a type with no null to stand for a missing receiver");

    public static readonly DiagnosticDescriptor TupleTypeTooFewElements =
        Error("SL0606", "a tuple type is written with fewer than two elements");

    public static readonly DiagnosticDescriptor TupleElementHasNoValue =
        Error("SL0607", "an element of a tuple is an expression that produces no value");

    public static readonly DiagnosticDescriptor ValueCannotBeDeconstructed =
        Error("SL0608", "a value is neither a tuple nor has a 'Deconstruct' of the needed arity");

    public static readonly DiagnosticDescriptor DeconstructionArityMismatch = Error(
        "SL0609",
        "a positional pattern or deconstruction names the wrong number of elements");

    public static readonly DiagnosticDescriptor CapturedByValueThenChanged =
        Warning("SL0610", "a lambda captures a variable by value that is changed afterwards");

    public static readonly DiagnosticDescriptor GuidClassNotFactoryConstructible = Error(
        "SL0611",
        "a class with '[Guid]' cannot be made by a class factory with no arguments");

    public static readonly DiagnosticDescriptor InvalidAsExpression =
        Error("SL0612", "an 'as' expression is redundant, misapplied or can never succeed");

    public static readonly DiagnosticDescriptor InvalidParameterDefault =
        Error("SL0613", "a parameter's default value is not allowed");

    public static readonly DiagnosticDescriptor MisplacedParameterDefault = Error(
        "SL0614",
        "a parameter default is placed where it would be ambiguous or leave a hole");

    public static readonly DiagnosticDescriptor InvalidConversionDeclaration = Error(
        "SL0615",
        "a user-defined conversion operator is declared in a way that is not allowed");

    public static readonly DiagnosticDescriptor AmbiguousConversion =
        Error("SL0616", "two user-defined conversions apply and nothing chooses between them");

    public static readonly DiagnosticDescriptor InvalidMemberInitializer =
        Error("SL0617", "a field or property initializer is written where it cannot run");

    public static readonly DiagnosticDescriptor InvalidBraceInitializerEntry =
        Error("SL0618", "an entry in an object or collection initializer cannot be applied");

    public static readonly DiagnosticDescriptor InvalidPatternInSwitch = Error(
        "SL0619",
        "a pattern in a switch binds a name that is never assigned or asks something it cannot");

    public static readonly DiagnosticDescriptor SwitchExpressionIncomplete =
        Error("SL0620", "a switch expression does not produce a value for every input");

    public static readonly DiagnosticDescriptor UnreachableSwitchCase =
        Warning("SL0621", "a switch label or arm is unreachable because earlier ones cover it");

    public static readonly DiagnosticDescriptor ComInterfaceUnknownMismatch =
        Error("SL0622", "a COM interface and the one it extends disagree about '[NoUnknown]'");

    public static readonly DiagnosticDescriptor NoUnknownOnNonComInterface =
        Error("SL0623", "'[NoUnknown]' is written on a type that is not a com interface");

    public static readonly DiagnosticDescriptor GuidOnNoUnknownInterface = Error(
        "SL0624",
        "a '[NoUnknown]' com interface also has a '[Guid]' nothing could query for");

    // ---------------------------------------------------------- SL07xx

    public static readonly DiagnosticDescriptor WindowsResourcesOnOtherTarget = Warning(
        "SL0700",
        "a program carries Windows-only resources while building for another platform");

    public static readonly DiagnosticDescriptor CppVariableNotSupported =
        Error("SL0701", "an extern C++ variable is declared, whose mangled name is not supported");

    public static readonly DiagnosticDescriptor ExternVariableInitialized =
        Error("SL0702", "an 'extern \"C\"' variable is given an initializer");

    public static readonly DiagnosticDescriptor EmbedPathMissing =
        Error("SL0703", "'[Embed]' is written without a file path");

    public static readonly DiagnosticDescriptor EmbedArgumentNotLiteral =
        Error("SL0704", "an '[Embed]' argument is not a string literal");

    public static readonly DiagnosticDescriptor EmbedRelativePathWithoutFile = Error(
        "SL0705",
        "an embed's relative path cannot be resolved because the source is not a file on disk");

    public static readonly DiagnosticDescriptor EmbedFileUnreadable = Error(
        "SL0706",
        "the file named by an embed is missing, invalid, a directory, unreadable or too large");

    public static readonly DiagnosticDescriptor EmbedAccessInvalid =
        Error("SL0707", "an embed's access string is not a valid combination of 'r', 'w' and 'x'");

    public static readonly DiagnosticDescriptor EmbedWritableExecutableSection = Error(
        "SL0708",
        "an embed asks for writable and executable memory with no section that can hold it");

    public static readonly DiagnosticDescriptor EmbedSectionNameInvalid =
        Error("SL0709", "an embed's section name is not a valid section name");

    public static readonly DiagnosticDescriptor EmbedSectionNameTruncated = Warning(
        "SL0710",
        "an embed's section name is longer than a PE image keeps and will be truncated");

    public static readonly DiagnosticDescriptor EmbedSectionIncompatible =
        Error("SL0711", "an embed is placed in a section whose kind or permissions cannot hold it");

    public static readonly DiagnosticDescriptor AsmBlockUnterminated =
        Error("SL0713", "an 'asm' block is never closed");

    public static readonly DiagnosticDescriptor AsmBlockExpected =
        Error("SL0714", "'asm' is not followed by a braced block of instructions");

    public static readonly DiagnosticDescriptor AsmOperandDirectionMissing =
        Error("SL0715", "an 'asm' operand does not say 'in', 'out' or 'inout'");

    public static readonly DiagnosticDescriptor AsmRegisterUnknown =
        Error("SL0716", "an 'asm' operand names a register the target architecture does not have");

    public static readonly DiagnosticDescriptor AsmRegisterNotAllowed =
        Error("SL0717", "an 'asm' operand names a register that cannot be used as an operand");

    public static readonly DiagnosticDescriptor AsmRegisterNamedTwice =
        Error("SL0718", "an 'asm' block names the same register more than once in one direction");

    public static readonly DiagnosticDescriptor AsmOperandTypeNotAllowed =
        Error("SL0719", "an 'asm' operand's type cannot travel in a register");

    public static readonly DiagnosticDescriptor AsmOperandTooWide =
        Error("SL0720", "an 'asm' operand's value is wider than the register named for it");

    public static readonly DiagnosticDescriptor AsmRegisterKindMismatch = Error(
        "SL0721",
        "an 'asm' operand's type belongs in a different kind of register than the one named");

    public static readonly DiagnosticDescriptor AsmOutputToBitField =
        Error("SL0722", "an 'asm' output is written to a bit-field, which has no address");

    public static readonly DiagnosticDescriptor AsmRejectedByAssembler =
        Error("SL0723", "the assembler rejected a line of an 'asm' block");

    public static readonly DiagnosticDescriptor AttributeFieldNotFound =
        Error("SL0724", "an attribute argument names a field the attribute does not have");

    public static readonly DiagnosticDescriptor AttributeFieldGivenTwice =
        Error("SL0725", "an attribute field is given a value more than once");

    public static readonly DiagnosticDescriptor AttributePositionalAfterNamed =
        Error("SL0726", "a positional attribute argument follows a named one");

    public static readonly DiagnosticDescriptor AttributeArgumentUsesColon =
        Error("SL0727", "an attribute field is set with ':' rather than '='");

    public static readonly DiagnosticDescriptor AttributeNotAllowedHere =
        Error("SL0728", "an attribute is written on a declaration that cannot carry it");

    public static readonly DiagnosticDescriptor InvalidEmbedPlacement =
        Error("SL0729", "'[Embed]' is written on something other than a static, or more than once");

    public static readonly DiagnosticDescriptor EmbedStaticNotByteArray =
        Error("SL0730", "a static with '[Embed]' is not declared 'byte[]'");

    public static readonly DiagnosticDescriptor EmbedStaticHasInitializer =
        Error("SL0731", "a static with '[Embed]' also has an initializer");

    public static readonly DiagnosticDescriptor ConstructorInitializerListNotSupported = Error(
        "SL0732",
        "a constructor is followed by something other than ': base(...)' or ': this(...)'");

    public static readonly DiagnosticDescriptor ConstructorChainsTwice = Error(
        "SL0733",
        "a constructor chains to another both after its parameters and in its body");

    public static readonly DiagnosticDescriptor RecordStructNotSupported =
        Error("SL0734", "a 'record struct' is declared, which is not supported");

    public static readonly DiagnosticDescriptor WithOnNonRecord =
        Error("SL0735", "a 'with' expression is applied to a value that is not a record");

    public static readonly DiagnosticDescriptor WithMemberNotFound = Error(
        "SL0736",
        "a 'with' expression assigns a name the record has no parameter or settable property for");

    public static readonly DiagnosticDescriptor WithMemberAssignedTwice =
        Error("SL0737", "a 'with' expression assigns the same member twice");

    public static readonly DiagnosticDescriptor StructParameterlessConstructor =
        Error("SL0738", "a struct declares a constructor taking no arguments");

    public static readonly DiagnosticDescriptor DocumentationTagUnknown =
        Warning("SL0739", "a documentation comment uses a tag that does not exist");

    public static readonly DiagnosticDescriptor DocumentedParameterInvalid = Warning(
        "SL0740",
        "a '@param' tag names a parameter that does not exist or was already documented");

    public static readonly DiagnosticDescriptor DocumentedParametersIncomplete =
        Warning("SL0741", "a documentation comment documents some parameters but not all");

    public static readonly DiagnosticDescriptor DocumentedTypeParameterNotFound =
        Warning("SL0742", "a documentation tag names a type parameter that does not exist");

    public static readonly DiagnosticDescriptor DocumentationTagMisplaced =
        Warning("SL0743", "a documentation tag is written on a declaration it says nothing about");

    public static readonly DiagnosticDescriptor DocumentedFailureInvalid = Warning(
        "SL0744",
        "a '@failure' tag is on a function that cannot fail or does not name a valid error case");

    public static readonly DiagnosticDescriptor DocumentationReferenceUnresolved = Warning(
        "SL0745",
        "a documentation cross-reference names nothing or names something not in scope");

    public static readonly DiagnosticDescriptor RawStringOpeningLineNotEmpty = Error(
        "SL0746",
        "text follows the opening quotes of a multi-line raw string on the same line");

    public static readonly DiagnosticDescriptor RawStringClosingMalformed = Error(
        "SL0747",
        "a multi-line raw string has no content or its closing quotes are not on their own line");

    public static readonly DiagnosticDescriptor RawStringIndentationMismatch =
        Error("SL0748", "a line of a raw string is indented less than its closing quotes");

    public static readonly DiagnosticDescriptor RawStringQuoteRunTooLong =
        Error("SL0749", "a raw string contains a run of quotes as long as its delimiter");

    public static readonly DiagnosticDescriptor InterpolationBraceRunInvalid = Error(
        "SL0750",
        "a run of braces in an interpolated string does not match the hole delimiter");

    public static readonly DiagnosticDescriptor MultipleDollarsOnNonRawString =
        Error("SL0751", "more than one '$' prefixes a string that is not raw");

    public static readonly DiagnosticDescriptor InterpolatedUtf8Literal =
        Error("SL0752", "an interpolated string is given the 'u8' suffix");

    public static readonly DiagnosticDescriptor InterpolationFormatInvalid = Error(
        "SL0753",
        "an interpolation hole's format string is not allowed or not valid for its value");

    public static readonly DiagnosticDescriptor InterpolationAlignmentNotConstant =
        Error("SL0754", "an interpolation's alignment is not a constant integer");

    public static readonly DiagnosticDescriptor InterpolationConditionalNotParenthesized =
        Error("SL0755", "a conditional expression in an interpolation hole is not parenthesized");

    public static readonly DiagnosticDescriptor TargetTypedNewWithoutTarget =
        Error("SL0756", "a 'new(...)' has no target type to take its type from");

    public static readonly DiagnosticDescriptor DefaultLiteralWithoutTarget =
        Error("SL0757", "a bare 'default' has no target type to take its type from");

    public static readonly DiagnosticDescriptor DefaultLiteralAsPattern =
        Error("SL0758", "a bare 'default' is used as a case pattern");

    public static readonly DiagnosticDescriptor TypeArgumentsOnNonGeneric =
        Error("SL0759", "type arguments are written on a function that is not generic");

    public static readonly DiagnosticDescriptor CallTypeArgumentCountMismatch =
        Error("SL0760", "a call writes a number of type arguments no candidate takes");

    public static readonly DiagnosticDescriptor NotUsableAsValue =
        Error("SL0761", "a type or an uninstantiated generic is used where a value is expected");

    public static readonly DiagnosticDescriptor AssignmentThroughConditionalAccess =
        Error("SL0762", "an assignment is made through '?.' or '?['");

    public static readonly DiagnosticDescriptor InvalidParamsParameter =
        Error("SL0763", "a parameter is marked 'params' where it is not allowed");

    public static readonly DiagnosticDescriptor StaticLambdaCaptures =
        Error("SL0764", "a 'static' lambda reads a variable from its enclosing scope");

    public static readonly DiagnosticDescriptor LambdaReturnTypeMismatch =
        Error("SL0765", "a lambda's declared return type differs from its target delegate's");

    public static readonly DiagnosticDescriptor LambdaDefaultNotSeenByTarget = Warning(
        "SL0766",
        "a lambda parameter's default differs from the one its target type gives");

    public static readonly DiagnosticDescriptor StaticLocalFunctionCaptures = Error(
        "SL0767",
        "a 'static' local function reads a variable or 'this' from its enclosing function");

    public static readonly DiagnosticDescriptor LocalFunctionCaptureNotInScope = Error(
        "SL0768",
        "a local function is called where a variable it captures is not in scope or not yet known");

    public static readonly DiagnosticDescriptor LocalFunctionAssignsOuterParameter = Error(
        "SL0769",
        "a local function assigns its enclosing function's parameter, of which it has a copy");

    public static readonly DiagnosticDescriptor StaticLocalVariable =
        Error("SL0770", "a local variable is declared 'static'");

    public static readonly DiagnosticDescriptor DeclarationOutsideDeconstruction = Error(
        "SL0771",
        "a variable is declared inside an expression where no deconstruction statement holds it");

    public static readonly DiagnosticDescriptor ForeachDeconstructionWithoutDeclaration = Error(
        "SL0772",
        "a 'foreach' deconstruction names existing variables rather than declaring new ones");

    public static readonly DiagnosticDescriptor TupleTargetTypeUnknown =
        Error("SL0773", "a tuple has an element that needs a target type and none is available");

    public static readonly DiagnosticDescriptor ListPatternTypeNotIndexable = Error(
        "SL0774",
        "a list pattern is matched against a type that cannot be indexed element by element");

    public static readonly DiagnosticDescriptor InvalidSlicePattern =
        Error("SL0775", "a '..' in a pattern is misplaced, repeated or cannot name what it skips");

    public static readonly DiagnosticDescriptor InvalidPatternMemberName = Error(
        "SL0776",
        "a name in a positional or property pattern does not match a readable member");

    public static readonly DiagnosticDescriptor IndexFromEndWithoutLength =
        Error("SL0777", "'^' or a range is applied to a type with no length");

    public static readonly DiagnosticDescriptor InvalidSpreadElement = Error(
        "SL0778",
        "a '..' spread in a collection expression cannot be spread into its target");

    public static readonly DiagnosticDescriptor SpreadIntoFixedLengthUnknown =
        Error("SL0779", "a spread of unknown length fills a fixed-length inline array");

    public static readonly DiagnosticDescriptor InitAccessorOnStatic =
        Error("SL0780", "a static property declares an 'init' accessor");

    public static readonly DiagnosticDescriptor InitPropertyAssignedAfterConstruction =
        Error("SL0781", "an 'init' property is assigned outside of the object's construction");

    public static readonly DiagnosticDescriptor InitSetAccessorMismatch = Error(
        "SL0782",
        "a property's 'init' or 'set' differs from that of the member it implements or overrides");

    public static readonly DiagnosticDescriptor InvalidRequiredMember =
        Error("SL0783", "a member is marked 'required' where that is not allowed");

    public static readonly DiagnosticDescriptor RequiredMembersNotSet =
        Error("SL0784", "a construction does not set every required member");

    public static readonly DiagnosticDescriptor ConstructorMustChainToPrimary =
        Error("SL0785", "a constructor of a type with a primary constructor does not chain to it");

    public static readonly DiagnosticDescriptor InvalidPrimaryConstructorSyntax = Error(
        "SL0786",
        "a primary constructor parameter list or base arguments are written where not allowed");

    public static readonly DiagnosticDescriptor PrimaryConstructorRefParameterCaptured =
        Error("SL0787", "a by-reference primary constructor parameter is used by a member body");

    public static readonly DiagnosticDescriptor DuplicateWhereClause =
        Error("SL0788", "a type parameter has more than one 'where' clause");

    public static readonly DiagnosticDescriptor DuplicateConstraint =
        Error("SL0789", "a type parameter is given the same constraint twice");

    public static readonly DiagnosticDescriptor MultipleBaseClassConstraints =
        Error("SL0790", "a type parameter is constrained to derive from more than one class");

    public static readonly DiagnosticDescriptor CircularConstraint =
        Error("SL0791", "type parameter constraints refer to each other in a cycle");

    public static readonly DiagnosticDescriptor DefaultConstraintNotOnOverride = Error(
        "SL0792",
        "a 'default' constraint is written outside an override, where it means nothing");

    public static readonly DiagnosticDescriptor InvalidExplicitInterfaceMember =
        Error("SL0793", "an explicit interface member is a field or an automatic property");

    public static readonly DiagnosticDescriptor ExplicitInterfaceTargetInvalid = Error(
        "SL0794",
        "an explicit interface member names something that is not an implemented interface slot");

    public static readonly DiagnosticDescriptor ExplicitInterfaceMemberHasModifier =
        Error("SL0795", "an explicit interface member is declared with a modifier");

    public static readonly DiagnosticDescriptor AmbiguousDefaultInterfaceMember = Error(
        "SL0796",
        "two interfaces give equally specific defaults for a member a class does not define");

    public static readonly DiagnosticDescriptor StaticAbstractReachedThroughInterface = Error(
        "SL0797",
        "a static abstract or virtual interface member is reached through the interface itself");

    public static readonly DiagnosticDescriptor GenericInstantiationTooDeep = Error(
        "SL0798",
        "a generic instantiates itself with ever-larger type arguments without end");

    public static readonly DiagnosticDescriptor GenericVirtualExcludedFromMetadata = Warning(
        "SL0799",
        "a type with a generic virtual method is left out of the library's metadata");

    // ---------------------------------------------------------- SL08xx

    public static readonly DiagnosticDescriptor VarianceOnInvariantParameter = Error(
        "SL0800",
        "'in' or 'out' is written on a type parameter that is not an interface's or a delegate's");

    public static readonly DiagnosticDescriptor VarianceViolatedByPosition =
        Error("SL0801", "a variant type parameter is used in a position its variance forbids");

    public static readonly DiagnosticDescriptor GotoCaseOutsideSwitch =
        Error("SL0802", "'goto case' or 'goto default' is written outside a switch statement");

    public static readonly DiagnosticDescriptor GotoCaseTargetInvalid =
        Error("SL0803", "'goto case' or 'goto default' names no section the switch can run");

    public static readonly DiagnosticDescriptor NonRecordDerivesFromRecord =
        Error("SL0804", "a class that is not a record derives from a record");

    public static readonly DiagnosticDescriptor UnsettledArgumentToVariadic =
        Error("SL0805", "an argument of no settled type is passed to a C variadic parameter list");

    public static readonly DiagnosticDescriptor BaseCallToAbstractMember =
        Error("SL0806", "a 'base' call names a member that is abstract in the base");

    public static readonly DiagnosticDescriptor SliceSyntaxInType =
        Error("SL0807", "'[:]' is written in a type where 'Span<T>' or 'ReadOnlySpan<T>' is meant");

    public static readonly DiagnosticDescriptor ReadOnlySpanElementWritten =
        Error("SL0808", "an element of a read-only span is written");

    public static readonly DiagnosticDescriptor MutatingMemberOnReadOnlyStruct = Error(
        "SL0809",
        "a setter or method that writes a struct is used on a read-only struct value");

    public static readonly DiagnosticDescriptor DefaultOfTypeWithoutZero =
        Error("SL0810", "'default' is taken of a type that has no zero value");

    public static readonly DiagnosticDescriptor LocalWithoutZeroUnassigned = Error(
        "SL0811",
        "a local whose type has no zero value is read before it is assigned on every path");

    public static readonly DiagnosticDescriptor ArrayOfTypeWithoutZero =
        Error("SL0812", "'new T[n]' is written for an element type that has no zero value");

    public static readonly DiagnosticDescriptor FieldWithoutZeroUnassigned = Error(
        "SL0813",
        "a field whose type has no zero value can be left unassigned by construction");

    public static readonly DiagnosticDescriptor StaticWithoutZeroUninitialized =
        Error("SL0814", "a static or global whose type has no zero value has no initializer");

    public static readonly DiagnosticDescriptor ZeroableConstraintUnmet = Error(
        "SL0815",
        "a type argument with no zero value is given for a 'zeroable' type parameter");

    public static readonly DiagnosticDescriptor MemberUnavailableForTypeArguments = Error(
        "SL0816",
        "a member is called that its type's constraint-dependent arguments leave out");

    public static readonly DiagnosticDescriptor EventGivenInitializer =
        Error("SL0817", "an event is declared with an initial value");

    public static readonly DiagnosticDescriptor EventTypeNotClosure =
        Error("SL0818", "an event is declared with a type that is not a closure");

    public static readonly DiagnosticDescriptor EventHandlerReturnsValue =
        Error("SL0819", "an event's closure type returns a value rather than void");

    public static readonly DiagnosticDescriptor StaticEventNotSupported =
        Error("SL0820", "an event is declared static");

    public static readonly DiagnosticDescriptor EventAccessorNameTaken = Error(
        "SL0821",
        "a method already declared takes the name and signature an event's generated method needs");

    public static readonly DiagnosticDescriptor InstanceEventFromStatic = Error(
        "SL0822",
        "an instance event is raised, cleared or subscribed to from a static method");

    public static readonly DiagnosticDescriptor EventRaisedOutsideDeclarer =
        Error("SL0823", "an event is raised from outside the type that declares it");

    public static readonly DiagnosticDescriptor EventReadAsValue =
        Error("SL0824", "an event is read as a value from outside its declaring type");

    public static readonly DiagnosticDescriptor EventAssignedWithWrongOperator =
        Error("SL0825", "an event is assigned with an operator other than '+=' or '-='");

    public static readonly DiagnosticDescriptor MetadataInconsistentWithLibrary = Error(
        "SL0826",
        "a library's metadata describes a slot or event incompletely, as if edited");

    public static readonly DiagnosticDescriptor CallingConventionMisplaced = Error(
        "SL0827",
        "a calling convention is written on something that is not a function or delegate");

    public static readonly DiagnosticDescriptor StorageModifierMisplaced =
        Error("SL0828", "'readonly' or 'static' is written on a declaration it cannot apply to");

    public static readonly DiagnosticDescriptor CapturedCopyWrittenInLambda = Warning(
        "SL0829",
        "a lambda assigns its own copy of a captured variable or member, changing nothing");

    public static readonly DiagnosticDescriptor SectionNameInvalidForTarget =
        Error("SL0830", "an embed names a section the target's object format cannot have");

    public static readonly DiagnosticDescriptor Int128OnThirtyTwoBitTarget =
        Error("SL0831", "a 128-bit integer type is used on a 32-bit target");

    // ---------------------------------------------------------- SL09xx

    public static readonly DiagnosticDescriptor ObjCModifierMisplaced =
        Error("SL0900", "'objc' is written on a declaration that cannot be an Objective-C type");

    public static readonly DiagnosticDescriptor ExternObjCTypeMisdeclared =
        Error("SL0901", "'extern' is written on an Objective-C type that cannot take it");

    public static readonly DiagnosticDescriptor ObjCMemberMissingSelector =
        Error("SL0902", "a member of an Objective-C class or protocol has no '[Selector]'");

    public static readonly DiagnosticDescriptor ObjCMessageMemberHasBody =
        Error("SL0903", "a protocol member or an existing class's selector member is given a body");

    public static readonly DiagnosticDescriptor SelectorAttributeMalformed = Error(
        "SL0904",
        "a '[Selector]' attribute is repeated, malformed or names an invalid selector");

    public static readonly DiagnosticDescriptor SelectorArgumentCountMismatch =
        Error("SL0905", "a selector's colon count disagrees with the member's parameter count");

    public static readonly DiagnosticDescriptor ObjCMemberAttributeMisplaced =
        Error("SL0906", "an attribute is written on an Objective-C member it does not apply to");

    public static readonly DiagnosticDescriptor ObjCSignatureCannotCross = Error(
        "SL0907",
        "a parameter or return type cannot be carried by an Objective-C message or block");

    public static readonly DiagnosticDescriptor ObjCTypeAttributeMisplaced =
        Error("SL0908", "an Objective-C type attribute is on the wrong type or malformed");

    public static readonly DiagnosticDescriptor ExternObjCClassDeclaresStorage =
        Error("SL0909", "an 'extern objc class' declares a member it cannot have, such as a field");

    public static readonly DiagnosticDescriptor ObjCInheritanceListInvalid = Error(
        "SL0910",
        "an Objective-C type's base or protocol list is cyclic, misordered or names a wrong kind");

    public static readonly DiagnosticDescriptor ObjCClassRootInvalid =
        Error("SL0911", "an Objective-C class does not reach exactly one '[ObjCRoot]' root class");

    public static readonly DiagnosticDescriptor ObjCMemberHeldWithoutCall =
        Error("SL0913", "a member of an Objective-C type is taken as a value without being called");

    public static readonly DiagnosticDescriptor ExternObjCClassConstructedWithNew =
        Error("SL0914", "'new' is used on an 'extern objc class'");

    public static readonly DiagnosticDescriptor ObjCOnNonAppleTarget =
        Error("SL0915", "an Objective-C message is sent on a target that is not macOS");

    public static readonly DiagnosticDescriptor ObjCObjectAcrossCLinkage =
        Error("SL0916", "an Objective-C object crosses a C++ or exported C boundary");

    public static readonly DiagnosticDescriptor InjectedTypeNotConstructible =
        Error("SL0917", "a dependency container is asked for a type it cannot construct");

    public static readonly DiagnosticDescriptor InjectedConstructorAmbiguous = Error(
        "SL0918",
        "a dependency container cannot choose between equally wide public constructors");

    public static readonly DiagnosticDescriptor InjectedParameterUnresolvable = Error(
        "SL0919",
        "a constructor parameter is of a kind a dependency container cannot supply");

    public static readonly DiagnosticDescriptor DefaultImplementationInvalid = Error(
        "SL0920",
        "a default implementation named for a contract is not a matching generic class");

    public static readonly DiagnosticDescriptor ObjCOverrideInvalid = Error(
        "SL0921",
        "an Objective-C class method's override, selector or modifier is inconsistent");

    public static readonly DiagnosticDescriptor ObjCProtocolMemberUnimplemented =
        Error("SL0922", "a class adopting a protocol does not answer one of its required messages");

    public static readonly DiagnosticDescriptor ObjCClassShapeUnsupported = Error(
        "SL0923",
        "an Objective-C type is used or declared in a way the runtime cannot support");

    public static readonly DiagnosticDescriptor ObjCInitializerInvalid =
        Error("SL0924", "an Objective-C class's constructor has no valid init message to run");

    public static readonly DiagnosticDescriptor ObjCFieldWithoutZero =
        Error("SL0925", "a field of an Objective-C class has no zero value and no initializer");

    public static readonly DiagnosticDescriptor ForeignObjCObjectWritten =
        Error("SL0926", "an Objective-C object owned by a C library is written to");

    public static readonly DiagnosticDescriptor CFTypeMisused = Error(
        "SL0927",
        "'[CFType]' is misplaced or malformed, or a Core Foundation type is misused");

    public static readonly DiagnosticDescriptor ProtocolClassMemberSentToProtocol =
        Error("SL0928", "a class member of a protocol is sent to the protocol rather than a class");

    public static readonly DiagnosticDescriptor VectorConstructionInvalid =
        Error("SL0929", "a vector is constructed with wrong arguments");

    public static readonly DiagnosticDescriptor VectorLaneNameUnknown =
        Error("SL0930", "a vector member access names no lane or swizzle");

    public static readonly DiagnosticDescriptor VectorLaneWriteInvalid = Error(
        "SL0931",
        "a lane write repeats a lane or writes back to a non-repeatable vector expression");

    public static readonly DiagnosticDescriptor VectorOperandsMismatch =
        Error("SL0932", "a binary operator is applied to vectors it does not accept");

    public static readonly DiagnosticDescriptor TooManyVectorsAcrossX86Windows =
        Error("SL0933", "more than three vectors cross a foreign boundary on 32-bit Windows");

    public static readonly DiagnosticDescriptor VectorFunctionInvalid =
        Error("SL0934", "a vector type's static member or function is unknown or wrongly applied");

    public static readonly DiagnosticDescriptor VaListMisused =
        Error("SL0935", "'VaList.Start' or 'Next<T>' is used where or how it cannot be");

    public static readonly DiagnosticDescriptor VariableNamedFieldInAccessor =
        Error("SL0936", "a variable named 'field' is declared inside a property accessor");

    public static readonly DiagnosticDescriptor ObjectReachedBeforeBase =
        Error("SL0937", "a constructor reaches the object or returns before 'base(...)' has run");

    public static readonly DiagnosticDescriptor FieldWithoutZeroUnsetAtBase = Error(
        "SL0938",
        "a field with no zero value is still unset when the object becomes reachable");

    public static readonly DiagnosticDescriptor FieldWithoutZeroReadBeforeSet = Error(
        "SL0939",
        "a field with no zero value is read in a constructor before it is assigned");

    public static readonly DiagnosticDescriptor LateFieldNotAllowed =
        Error("SL0940", "'late' is written on a field that cannot be late");

    public static readonly DiagnosticDescriptor ThrowsAttributeMisplaced =
        Error("SL0941", "'[Throws]' is written where it cannot apply");
}
