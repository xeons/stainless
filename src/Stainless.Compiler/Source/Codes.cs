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
/// A code is `SL`, the letter of its category, and a number within it:
/// SLT0042 is a rule about types. The categories are <see cref="Categories"/>.
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

    /// <summary>What each letter after `SL` covers, in inventory order.</summary>
    public static IReadOnlyList<DiagnosticCategory> Categories { get; } =
    [
        new('P', "Parsing", "lexing, tokens, literals, preprocessor directives and grammar"),
        new('N', "Names",
            "name lookup, modules and imports, duplicate declarations, visibility and receivers"),
        new('T', "Types",
            "expression typing, operators, calls and arguments, conversions, " +
            "casts, arrays, ranges, vectors and constants"),
        new('G', "Generics",
            "type parameters and arguments, inference, constraints, variance and " +
            "static abstract members"),
        new('C', "Classes and members",
            "type and member declarations: inheritance, interfaces, overrides, " +
            "constructors, properties, events, operators, enums, variants, records and attributes"),
        new('F', "Flow and patterns",
            "statements and jumps, returns, switch, patterns, try, deconstruction, " +
            "lambdas and local functions"),
        new('O', "Ownership and safety",
            "ARC and weak references, null safety, zero values and definite " +
            "initialisation, late, statics, parallel and thread safety"),
        new('I', "Interop",
            "C and C++ linkage, foreign signatures, layout attributes and " +
            "bit-fields, inline assembly, COM and Objective-C"),
        new('L', "Lint", "warnings about legal but suspicious code, and documentation comments"),
        new('D', "Driver and build",
            "entry point, libraries and their metadata, embedded files and " +
            "sections, target-specific build output"),
    ];

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

    // ----------------------------------------------------------- P: Parsing

    public static readonly DiagnosticDescriptor UnexpectedCharacter =
        Error("SLP0001", "a character in the source begins no token");

    public static readonly DiagnosticDescriptor UnterminatedBlockComment =
        Error("SLP0002", "a block comment is never closed");

    public static readonly DiagnosticDescriptor NumericLiteralWithoutDigits =
        Error("SLP0003", "a numeric literal has a prefix but no digits");

    public static readonly DiagnosticDescriptor InvalidNumericSuffix =
        Error("SLP0004", "a numeric literal has a suffix it cannot take");

    public static readonly DiagnosticDescriptor IntegerLiteralTooLarge =
        Error("SLP0005", "an integer literal does not fit in 64 bits");

    public static readonly DiagnosticDescriptor UnterminatedStringLiteral =
        Error("SLP0006", "a string literal, raw or interpolated, is never closed");

    public static readonly DiagnosticDescriptor UnterminatedCharacterLiteral =
        Error("SLP0007", "a character literal is never closed");

    public static readonly DiagnosticDescriptor HexEscapeDigitCount =
        Error("SLP0008", "a hex escape has too few or the wrong number of hex digits");

    public static readonly DiagnosticDescriptor UnrecognizedEscapeSequence =
        Error("SLP0009", "a backslash escape is not one the language defines");

    public static readonly DiagnosticDescriptor EmptyCharacterLiteral =
        Error("SLP0010", "a character literal holds no character");

    public static readonly DiagnosticDescriptor InvalidFloatLiteral =
        Error("SLP0011", "a floating-point literal is malformed");

    public static readonly DiagnosticDescriptor ExpectedToken =
        Error("SLP0012", "the parser expected something other than what it found");

    public static readonly DiagnosticDescriptor UnsupportedLinkageConvention =
        Error("SLP0013", "an extern or export names a linkage convention other than C or C++");

    public static readonly DiagnosticDescriptor MissingLinkageConvention =
        Error("SLP0014", "extern or export is not followed by a linkage convention string");

    public static readonly DiagnosticDescriptor DestructorNameMismatch =
        Error("SLP0015", "a destructor's name is not the name of its enclosing type");

    public static readonly DiagnosticDescriptor NestingTooDeep =
        Error("SLP0016", "source is nested deeper than the compiler can process");

    public static readonly DiagnosticDescriptor PropertyAccessorExpected =
        Error("SLP0017", "a property body contains something other than 'get', 'set' or 'init'");

    public static readonly DiagnosticDescriptor SwitchStatementOutsideSection =
        Error("SLP0018", "a statement in a switch is not under a 'case' or 'default' label");

    public static readonly DiagnosticDescriptor IndexMissing =
        Error("SLP0019", "an indexing expression has no index");

    public static readonly DiagnosticDescriptor UnclosedConditionalDirective =
        Error("SLP0020", "an '#if' is never closed by '#endif'");

    public static readonly DiagnosticDescriptor DirectiveAfterElse =
        Error("SLP0021", "an '#elif' or second '#else' follows an '#else'");

    public static readonly DiagnosticDescriptor DefineAfterDeclaration =
        Error("SLP0022", "a '#define' or '#undef' comes after the first declaration in the file");

    public static readonly DiagnosticDescriptor DefineArgumentNotName =
        Error("SLP0023", "a '#define' or '#undef' is given something other than one name");

    public static readonly DiagnosticDescriptor ErrorDirective =
        Error("SLP0024", "an '#error' directive is reached");

    public static readonly DiagnosticDescriptor WarningDirective =
        Warning("SLP0025", "a '#warning' directive is reached");

    public static readonly DiagnosticDescriptor UnknownDirective =
        Error("SLP0026", "a '#' line names no directive the language has");

    public static readonly DiagnosticDescriptor DirectiveWithoutIf =
        Error("SLP0027", "an '#elif', '#else' or '#endif' has no '#if' to belong to");

    public static readonly DiagnosticDescriptor MalformedDirectiveCondition =
        Error("SLP0028", "a conditional directive's condition is missing or malformed");

    public static readonly DiagnosticDescriptor UnknownPragma =
        Error("SLP0029", "a '#pragma' is not 'comment(lib, ...)' or 'comment(framework, ...)'");

    public static readonly DiagnosticDescriptor PragmaLibraryNameInvalid =
        Error("SLP0030", "a '#pragma comment(lib, ...)' library name is missing or not quoted");

    public static readonly DiagnosticDescriptor EscapeNotUnicodeScalar =
        Error("SLP0031", "a Unicode escape names a value that is not a Unicode scalar");

    public static readonly DiagnosticDescriptor UnmatchedInterpolationBrace =
        Error("SLP0032", "an interpolated string has a '}' that closes nothing");

    public static readonly DiagnosticDescriptor EmptyInterpolation =
        Error("SLP0033", "an interpolated string has an empty '{}' hole");

    public static readonly DiagnosticDescriptor InterpolationHasExtraTokens =
        Error("SLP0034", "an interpolation hole holds more than one expression");

    public static readonly DiagnosticDescriptor OperatorNotOverloadable =
        Error("SLP0035", "an operator that cannot be overloaded is declared");

    public static readonly DiagnosticDescriptor IndexerWithoutParameters =
        Error("SLP0036", "an indexer declares no index parameters");

    public static readonly DiagnosticDescriptor TupleTypeTooFewElements =
        Error("SLP0037", "a tuple type is written with fewer than two elements");

    public static readonly DiagnosticDescriptor AsmBlockUnterminated =
        Error("SLP0038", "an 'asm' block is never closed");

    public static readonly DiagnosticDescriptor AsmBlockExpected =
        Error("SLP0039", "'asm' is not followed by a braced block of instructions");

    public static readonly DiagnosticDescriptor AsmOperandDirectionMissing =
        Error("SLP0040", "an 'asm' operand does not say 'in', 'out' or 'inout'");

    public static readonly DiagnosticDescriptor ConstructorInitializerListNotSupported = Error(
        "SLP0041",
        "a constructor is followed by something other than ': base(...)' or ': this(...)'");

    public static readonly DiagnosticDescriptor ConstructorChainsTwice = Error(
        "SLP0042",
        "a constructor chains to another both after its parameters and in its body");

    public static readonly DiagnosticDescriptor RawStringOpeningLineNotEmpty = Error(
        "SLP0043",
        "text follows the opening quotes of a multi-line raw string on the same line");

    public static readonly DiagnosticDescriptor RawStringClosingMalformed = Error(
        "SLP0044",
        "a multi-line raw string has no content or its closing quotes are not on their own line");

    public static readonly DiagnosticDescriptor RawStringIndentationMismatch =
        Error("SLP0045", "a line of a raw string is indented less than its closing quotes");

    public static readonly DiagnosticDescriptor RawStringQuoteRunTooLong =
        Error("SLP0046", "a raw string contains a run of quotes as long as its delimiter");

    public static readonly DiagnosticDescriptor InterpolationBraceRunInvalid = Error(
        "SLP0047",
        "a run of braces in an interpolated string does not match the hole delimiter");

    public static readonly DiagnosticDescriptor MultipleDollarsOnNonRawString =
        Error("SLP0048", "more than one '$' prefixes a string that is not raw");

    public static readonly DiagnosticDescriptor InterpolatedUtf8Literal =
        Error("SLP0049", "an interpolated string is given the 'u8' suffix");

    public static readonly DiagnosticDescriptor InterpolationConditionalNotParenthesized =
        Error("SLP0050", "a conditional expression in an interpolation hole is not parenthesized");

    public static readonly DiagnosticDescriptor DefaultLiteralAsPattern =
        Error("SLP0051", "a bare 'default' is used as a case pattern");

    public static readonly DiagnosticDescriptor SliceSyntaxInType = Error(
        "SLP0052",
        "'[:]' is written in a type where 'Span<T>' or 'ReadOnlySpan<T>' is meant");

    public static readonly DiagnosticDescriptor VariableNamedFieldInAccessor =
        Error("SLP0053", "a variable named 'field' is declared inside a property accessor");

    // ------------------------------------------------------------- N: Names

    public static readonly DiagnosticDescriptor DuplicateModuleMember =
        Error("SLN0001", "a name is declared twice in one module");

    public static readonly DiagnosticDescriptor ImportedModuleNotFound =
        Error("SLN0002", "an import names a module that is not among the compiled sources");

    public static readonly DiagnosticDescriptor ImportOfOwnModule =
        Warning("SLN0003", "a file imports the module it belongs to");

    public static readonly DiagnosticDescriptor ModuleLevelVariable = Error(
        "SLN0004",
        "a variable is declared at module scope, where only constants are allowed");

    public static readonly DiagnosticDescriptor DuplicateMember =
        Error("SLN0005", "a type declares two members of one name");

    public static readonly DiagnosticDescriptor DuplicateOverload = Error(
        "SLN0006",
        "two overloads of one function, operator, constructor or conversion share a signature");

    public static readonly DiagnosticDescriptor DuplicateParameterName =
        Error("SLN0007", "two parameters of one function share a name");

    public static readonly DiagnosticDescriptor DuplicateLocalName =
        Error("SLN0008", "a local name is declared twice in one scope");

    public static readonly DiagnosticDescriptor LocalShadowsParameter =
        Error("SLN0009", "a local takes the name of a parameter");

    public static readonly DiagnosticDescriptor ThisOutsideInstanceMember =
        Error("SLN0010", "this is used outside an instance method, constructor or destructor");

    public static readonly DiagnosticDescriptor NameNotFound =
        Error("SLN0011", "a name matches nothing in scope");

    public static readonly DiagnosticDescriptor ModuleMemberNotFound =
        Error("SLN0012", "a module has no public member with the name accessed");

    public static readonly DiagnosticDescriptor MemberNotFound =
        Error("SLN0013", "a type has no member of the name used");

    public static readonly DiagnosticDescriptor NotVisible =
        Error("SLN0014", "a declaration is not visible from where it is used");

    public static readonly DiagnosticDescriptor AmbiguousTypeName =
        Error("SLN0015", "an unqualified type name matches types in more than one module");

    public static readonly DiagnosticDescriptor ModuleTypeNotFound =
        Error("SLN0016", "a qualified type name names a module that declares no such type");

    public static readonly DiagnosticDescriptor TypeNotFound =
        Error("SLN0017", "a type name matches nothing in scope");

    public static readonly DiagnosticDescriptor ModuleDeclarationMissing =
        Error("SLN0018", "a file does not declare which module it belongs to");

    public static readonly DiagnosticDescriptor FunctionNamedAfterVariantCase = Error(
        "SLN0019",
        "a module-level function has the name of a variant case, which a bare call would build");

    public static readonly DiagnosticDescriptor AmbiguousNamelessMember =
        Error("SLN0020", "a member name is declared by more than one nameless member of a type");

    public static readonly DiagnosticDescriptor ConstructorNotAccessible = Error(
        "SLN0021",
        "a type is constructed from outside the module that owns its constructors");

    public static readonly DiagnosticDescriptor InstanceMemberWithoutInstance =
        Error("SLN0022", "an instance member is reached without an instance");

    public static readonly DiagnosticDescriptor StaticMemberThroughValue =
        Error("SLN0023", "a static method is called through a value rather than its type");

    // ------------------------------------------------------------- T: Types

    public static readonly DiagnosticDescriptor InvalidConstantInitializer =
        Error("SLT0001", "a constant is initialized with something other than a literal");

    public static readonly DiagnosticDescriptor VarWithoutInitializer =
        Error("SLT0002", "a var declaration has no initializer to infer its type from");

    public static readonly DiagnosticDescriptor ConditionNotBool =
        Error("SLT0003", "a condition is not of type bool");

    public static readonly DiagnosticDescriptor AddressOfNoStorage =
        Error("SLT0004", "the address of something with no storage is taken");

    public static readonly DiagnosticDescriptor DereferenceOfNonPointer =
        Error("SLT0005", "something other than a pointer is dereferenced");

    public static readonly DiagnosticDescriptor OperatorNotApplicable =
        Error("SLT0006", "an operator cannot be applied to the operands' types");

    public static readonly DiagnosticDescriptor NoCommonOperandType =
        Error("SLT0007", "two operands have no common type for a binary operator");

    public static readonly DiagnosticDescriptor AssignmentTargetNotAssignable = Error(
        "SLT0008",
        "an assignment or update targets a constant or something that is not a location");

    public static readonly DiagnosticDescriptor TypeNotIndexable =
        Error("SLT0009", "a value is indexed by a type with no matching indexer");

    public static readonly DiagnosticDescriptor IndexNotInteger =
        Error("SLT0010", "an index, slice bound, from-end count or range bound is not an integer");

    public static readonly DiagnosticDescriptor InvalidCast =
        Error("SLT0011", "an explicit cast names a conversion that does not exist");

    public static readonly DiagnosticDescriptor MethodUsedAsValue =
        Error("SLT0012", "a method is used as a value without being called");

    public static readonly DiagnosticDescriptor ExpressionNotCallable =
        Error("SLT0013", "a call is made through a value that is not a delegate or closure");

    public static readonly DiagnosticDescriptor ArgumentCountMismatch =
        Error("SLT0014", "a call passes the wrong number of arguments");

    public static readonly DiagnosticDescriptor ArgumentTypeMismatch =
        Error("SLT0015", "an argument's type does not match its parameter's type");

    public static readonly DiagnosticDescriptor NoMatchingOverload =
        Error("SLT0016", "no overload accepts the arguments of a call");

    public static readonly DiagnosticDescriptor AmbiguousCall =
        Error("SLT0017", "more than one overload matches a call equally well");

    public static readonly DiagnosticDescriptor NoImplicitConversion =
        Error("SLT0018", "a value cannot be implicitly converted to the type required");

    public static readonly DiagnosticDescriptor ConstantOutOfRange =
        Error("SLT0019", "a constant value lies outside the range of its target type");

    public static readonly DiagnosticDescriptor PointerToReferenceType =
        Error("SLT0020", "a raw pointer type is formed over a reference type");

    public static readonly DiagnosticDescriptor OptionalOfValueType =
        Error("SLT0021", "an optional type is formed over a type that cannot be null");

    public static readonly DiagnosticDescriptor VariantCaseArgumentCount =
        Error("SLT0022", "a variant case is constructed with the wrong number of fields");

    public static readonly DiagnosticDescriptor StringOperandTypeMismatch =
        Error("SLT0023", "a string operator is applied to a string and a value of another type");

    public static readonly DiagnosticDescriptor VoidUsedAsValue =
        Error("SLT0024", "'void' is used where a value or its type is needed");

    public static readonly DiagnosticDescriptor ArrayLengthNotInteger =
        Error("SLT0025", "an array length is not an integer");

    public static readonly DiagnosticDescriptor TypeofWithoutReflect = Error(
        "SLT0026",
        "'typeof' names a type that carries no metadata because it lacks '[Reflect]'");

    public static readonly DiagnosticDescriptor TypeofWithoutReflection =
        Error("SLT0027", "'typeof' is used without Standard.Reflection in the compilation");

    public static readonly DiagnosticDescriptor ConditionalArmIsVoid =
        Error("SLT0028", "an arm of a conditional expression produces no value");

    public static readonly DiagnosticDescriptor ConditionalArmsNoCommonType =
        Error("SLT0029", "the arms of a conditional expression have no common type");

    public static readonly DiagnosticDescriptor EnumComparisonTypeMismatch =
        Error("SLT0030", "an enum is compared with a value of a different type");

    public static readonly DiagnosticDescriptor FunctionConvertedToNonDelegate =
        Error("SLT0031", "a function is converted to a type that is not a delegate or closure");

    public static readonly DiagnosticDescriptor NoOverloadMatchesDelegate =
        Error("SLT0032", "no overload of a method group matches the delegate or closure type");

    public static readonly DiagnosticDescriptor AmbiguousDelegateConversion = Error(
        "SLT0033",
        "a method group matches a delegate or closure type through more than one overload");

    public static readonly DiagnosticDescriptor CapturingFunctionToDelegate =
        Error("SLT0034", "a function that carries state is converted to a delegate");

    public static readonly DiagnosticDescriptor WriteToTemporaryStruct = Error(
        "SLT0035",
        "a field or property of a temporary struct is written, so the write is lost");

    public static readonly DiagnosticDescriptor FlagOperationOnNonFlagsEnum =
        Error("SLT0036", "a flag operation is used on an enum that is not marked '[Flags]'");

    public static readonly DiagnosticDescriptor HasFlagArgumentMismatch =
        Error("SLT0037", "'HasFlag' is not given exactly one argument of the enum's own type");

    public static readonly DiagnosticDescriptor FlagTestedAgainstItself = Error(
        "SLT0038",
        "a flag test reads the same expression twice; it must be put in a variable first");

    public static readonly DiagnosticDescriptor VariantCaseWhereOtherTypeExpected =
        Error("SLT0039", "a variant's case is named where a value of another type is expected");

    public static readonly DiagnosticDescriptor ConstantDivisionByZero =
        Error("SLT0040", "a division or remainder has a constant zero divisor");

    public static readonly DiagnosticDescriptor ArgumentHasNoStorage =
        Error("SLT0041", "an expression with no storage is passed by 'ref' or 'out'");

    public static readonly DiagnosticDescriptor ReadOnlyPassedByReference =
        Error("SLT0042", "a read-only location is passed as 'ref' or 'out'");

    public static readonly DiagnosticDescriptor RefArgumentWithoutKeyword =
        Error("SLT0043", "an argument for a ref or out parameter omits the keyword");

    public static readonly DiagnosticDescriptor RefKeywordOnPlainParameter =
        Error("SLT0044", "'ref' or 'out' is written for a parameter of another mode");

    public static readonly DiagnosticDescriptor RefArgumentTypeMismatch =
        Error("SLT0045", "a 'ref' or 'out' argument's type does not exactly match the parameter's");

    public static readonly DiagnosticDescriptor InParameterWritten =
        Error("SLT0046", "an 'in' parameter is written to");

    public static readonly DiagnosticDescriptor TypeCannotBeSliced =
        Error("SLT0047", "a slice is taken of a value that cannot be sliced");

    public static readonly DiagnosticDescriptor ConstTypeNotInlinable =
        Error("SLT0048", "a 'const' is declared with a type a constant cannot hold");

    public static readonly DiagnosticDescriptor ConstValueTypeMismatch =
        Error("SLT0049", "a 'const' is given a literal of the wrong kind for its declared type");

    public static readonly DiagnosticDescriptor InlineArrayLengthNotConstant =
        Error("SLT0050", "an inline array's length is not a constant");

    public static readonly DiagnosticDescriptor InlineArrayLengthNotPositive =
        Error("SLT0051", "an inline array asks for fewer than one element");

    public static readonly DiagnosticDescriptor InlineArrayTooLarge =
        Error("SLT0052", "an inline array would be larger than a value can be");

    public static readonly DiagnosticDescriptor ConstantIndexOutOfRange =
        Error("SLT0053", "a constant index is outside a fixed-length array or vector");

    public static readonly DiagnosticDescriptor InlineArrayParameterByValue =
        Error("SLT0054", "a parameter takes an inline array by value rather than by 'ref' or 'in'");

    public static readonly DiagnosticDescriptor ArrowOnNonPointer = Error(
        "SLT0055",
        "'->' is applied to a non-pointer, or a pointer to a type with no members");

    public static readonly DiagnosticDescriptor CodeUnitConversionInvalid = Error(
        "SLT0056",
        "a character value converts implicitly between encodings or does not fit one code unit");

    public static readonly DiagnosticDescriptor ArrayLiteralTargetInvalid =
        Error("SLT0057", "an array literal targets a type that cannot be built from elements");

    public static readonly DiagnosticDescriptor InlineArrayLengthMismatch = Error(
        "SLT0058",
        "an array literal has a different number of elements than its inline array type");

    public static readonly DiagnosticDescriptor EmptyArrayLiteralUntyped =
        Error("SLT0059", "an empty array literal has no element type to infer");

    public static readonly DiagnosticDescriptor ArrayLiteralElementTypesDisagree =
        Error("SLT0060", "the elements of an array literal do not share one type");

    public static readonly DiagnosticDescriptor VarCannotInfer =
        Error("SLT0061", "'var' is given an initializer whose type cannot be inferred");

    public static readonly DiagnosticDescriptor InterpolatedValueNotWritable =
        Error("SLT0062", "an interpolation hole holds a value with no defined text form");

    public static readonly DiagnosticDescriptor OperatorOverloadNotFound =
        Error("SLT0063", "no declared operator overload accepts the operand types");

    public static readonly DiagnosticDescriptor OperatorOverloadAmbiguous =
        Error("SLT0064", "more than one operator overload accepts the operand types");

    public static readonly DiagnosticDescriptor NameofOperandUnnamed =
        Error("SLT0065", "'nameof' is given an expression that is not a name");

    public static readonly DiagnosticDescriptor IncrementOperandInvalid = Error(
        "SLT0066",
        "an increment or decrement is applied to a type that is not a number or pointer");

    public static readonly DiagnosticDescriptor CallArgumentsDoNotFit = Error(
        "SLT0067",
        "a call's arguments do not fit the parameters of the function or constructor it names");

    public static readonly DiagnosticDescriptor NamedArgumentNotAllowed = Error(
        "SLT0068",
        "a named argument is passed to something that takes its arguments only by position");

    public static readonly DiagnosticDescriptor TupleElementHasNoValue =
        Error("SLT0069", "an element of a tuple is an expression that produces no value");

    public static readonly DiagnosticDescriptor AsNotApplicable =
        Error("SLT0070", "'as' is applied to a value or a type it cannot ask about");

    public static readonly DiagnosticDescriptor AmbiguousConversion =
        Error("SLT0071", "two user-defined conversions apply and nothing chooses between them");

    public static readonly DiagnosticDescriptor AsAlwaysNull =
        Error("SLT0072", "an 'as' can never succeed, because no object is both types");

    public static readonly DiagnosticDescriptor AsTypeRedundantlyOptional =
        Error("SLT0073", "the type after 'as' is written optional, which 'as' already makes it");

    public static readonly DiagnosticDescriptor InterpolationFormatInvalid = Error(
        "SLT0074",
        "an interpolation hole's format string is not allowed or not valid for its value");

    public static readonly DiagnosticDescriptor InterpolationAlignmentNotConstant =
        Error("SLT0075", "an interpolation's alignment is not a constant integer");

    public static readonly DiagnosticDescriptor TargetTypedWithoutTarget =
        Error("SLT0076", "a target-typed expression has no type to take");

    public static readonly DiagnosticDescriptor TypeUsedAsValue =
        Error("SLT0077", "a type name stands where a value is expected");

    public static readonly DiagnosticDescriptor AssignmentThroughConditionalAccess =
        Error("SLT0078", "an assignment is made through '?.' or '?['");

    public static readonly DiagnosticDescriptor IndexFromEndWithoutLength =
        Error("SLT0079", "'^' or a range is applied to a type with no length");

    public static readonly DiagnosticDescriptor SpreadSourceNotEnumerable =
        Error("SLT0080", "a '..' spread names a value that is not an array, slice or enumerable");

    public static readonly DiagnosticDescriptor SpreadIntoFixedLengthUnknown =
        Error("SLT0081", "a spread of unknown length fills a fixed-length inline array");

    public static readonly DiagnosticDescriptor ReadOnlySpanElementWritten =
        Error("SLT0082", "an element of a read-only span is written");

    public static readonly DiagnosticDescriptor MutatingMemberOnReadOnlyStruct = Error(
        "SLT0083",
        "a setter or method that writes a struct is used on a read-only struct value");

    public static readonly DiagnosticDescriptor Int128OnThirtyTwoBitTarget =
        Error("SLT0084", "a 128-bit integer type is used on a 32-bit target");

    public static readonly DiagnosticDescriptor GenericFunctionUsedAsValue =
        Error("SLT0085", "a generic function is used as a value rather than called");

    public static readonly DiagnosticDescriptor SpreadElementTypeMismatch =
        Error("SLT0086", "a '..' spread yields elements that do not convert to the target's");

    public static readonly DiagnosticDescriptor VectorArgumentNamedOrByReference =
        Error("SLT0087", "a vector constructor argument is named or passed by 'ref' or 'out'");

    public static readonly DiagnosticDescriptor VectorLaneRepeated =
        Error("SLT0088", "a lane write names one lane twice");

    public static readonly DiagnosticDescriptor VectorFunctionWrongElement = Error(
        "SLT0089",
        "a vector function is applied to a vector of an element kind it does not take");

    public static readonly DiagnosticDescriptor VectorElementTypeMismatch =
        Error("SLT0090", "a vector is made from a vector with a different element type");

    public static readonly DiagnosticDescriptor VectorLaneCountMismatch =
        Error("SLT0091", "a vector is made from values that do not fill its lanes");

    public static readonly DiagnosticDescriptor VectorLaneTargetUnstable =
        Error("SLT0092", "a compound lane write targets a vector that is not a stable location");

    // ---------------------------------------------------------- G: Generics

    public static readonly DiagnosticDescriptor TypeParametersOnNonMethod =
        Error("SLG0001", "a property or field declares type parameters");

    public static readonly DiagnosticDescriptor GenericStaticInterfaceMember =
        Error("SLG0002", "a 'static abstract' or 'static virtual' interface member is generic");

    public static readonly DiagnosticDescriptor TypeArgumentCountMismatch =
        Error("SLG0003", "a generic is given the wrong number of type arguments");

    public static readonly DiagnosticDescriptor GenericTypeMissingArguments =
        Error("SLG0004", "a generic type is named without its type arguments");

    public static readonly DiagnosticDescriptor TypeArgumentNotInferred =
        Error("SLG0005", "type arguments for a generic cannot be inferred from the values passed");

    public static readonly DiagnosticDescriptor ConstraintNotMet =
        Error("SLG0006", "a type argument does not meet its parameter's constraint");

    public static readonly DiagnosticDescriptor InvalidConstraintType = Error(
        "SLG0007",
        "a type cannot be used as a constraint because it is sealed or cannot be derived from");

    public static readonly DiagnosticDescriptor ConstraintOnUnknownTypeParameter = Error(
        "SLG0008",
        "a 'where' clause names something that is not a type parameter of its declaration");

    public static readonly DiagnosticDescriptor WhereOnNonGeneric =
        Error("SLG0009", "a 'where' clause is written on a declaration that is not generic");

    public static readonly DiagnosticDescriptor WhereOnRequiredMember = Error(
        "SLG0010",
        "a dispatched or interface-implementing member of a generic type has its own 'where'");

    public static readonly DiagnosticDescriptor AmbiguousGenericType =
        Error("SLG0011", "a generic type name matches more than one template for its arguments");

    public static readonly DiagnosticDescriptor NewConstraintWithParameters =
        Error("SLG0012", "a 'new()' constraint lists parameters");

    public static readonly DiagnosticDescriptor ConstraintOrderInvalid =
        Error("SLG0013", "a constraint is out of order in a type parameter's clause");

    public static readonly DiagnosticDescriptor ConstraintsContradict =
        Error("SLG0014", "a type parameter's constraints contradict each other");

    public static readonly DiagnosticDescriptor DuplicateWhereClause =
        Error("SLG0015", "a type parameter has more than one 'where' clause");

    public static readonly DiagnosticDescriptor DuplicateConstraint =
        Error("SLG0016", "a type parameter is given the same constraint twice");

    public static readonly DiagnosticDescriptor MultipleBaseClassConstraints =
        Error("SLG0017", "a type parameter is constrained to derive from more than one class");

    public static readonly DiagnosticDescriptor CircularConstraint =
        Error("SLG0018", "type parameter constraints refer to each other in a cycle");

    public static readonly DiagnosticDescriptor DefaultConstraintNotOnOverride = Error(
        "SLG0019",
        "a 'default' constraint is written outside an override, where it means nothing");

    public static readonly DiagnosticDescriptor StaticAbstractReachedThroughInterface = Error(
        "SLG0020",
        "a static abstract or virtual interface member is reached through the interface itself");

    public static readonly DiagnosticDescriptor GenericInstantiationTooDeep = Error(
        "SLG0021",
        "a generic instantiates itself with ever-larger type arguments without end");

    public static readonly DiagnosticDescriptor VarianceOnInvariantParameter = Error(
        "SLG0022",
        "'in' or 'out' is written on a type parameter that is not an interface's or a delegate's");

    public static readonly DiagnosticDescriptor VarianceViolatedByPosition =
        Error("SLG0023", "a variant type parameter is used in a position its variance forbids");

    public static readonly DiagnosticDescriptor MemberUnavailableForTypeArguments = Error(
        "SLG0024",
        "a member is called that its type's constraint-dependent arguments leave out");

    // ----------------------------------------------- C: Classes and members

    public static readonly DiagnosticDescriptor DuplicateModifier =
        Error("SLC0001", "a modifier is written twice on one declaration");

    public static readonly DiagnosticDescriptor ConstructorOnNonConstructibleType = Error(
        "SLC0002",
        "a constructor is declared on a type that is neither a class nor a struct");

    public static readonly DiagnosticDescriptor DestructorOnStruct =
        Error("SLC0003", "a struct declares a destructor, which only a class can have");

    public static readonly DiagnosticDescriptor DuplicateDestructorOrStaticConstructor =
        Error("SLC0004", "a type declares more than one destructor or static constructor");

    public static readonly DiagnosticDescriptor FunctionWithoutBody =
        Error("SLC0005", "a function that needs a body has none");

    public static readonly DiagnosticDescriptor StructContainsItself =
        Error("SLC0006", "a struct contains itself by value and so has no finite size");

    public static readonly DiagnosticDescriptor NewOfNonConstructibleType =
        Error("SLC0007", "new is applied to a type that is neither a class nor a struct");

    public static readonly DiagnosticDescriptor NoConstructorTakesArguments =
        Error("SLC0008", "arguments are passed to a class with no constructor that takes any");

    public static readonly DiagnosticDescriptor InterfaceMemberHasState = Error(
        "SLC0009",
        "an interface declares state, a constructor or a destructor, or a property naming storage");

    public static readonly DiagnosticDescriptor StructConvertedToInterface =
        Error("SLC0010", "a struct is converted to an interface reference");

    public static readonly DiagnosticDescriptor ExtendsNonInterface =
        Error("SLC0011", "a type extends something that is not an interface");

    public static readonly DiagnosticDescriptor InterfaceListedTwice = Warning(
        "SLC0012",
        "a type lists the same interface, COM interface or protocol more than once");

    public static readonly DiagnosticDescriptor InterfaceMemberNotImplemented =
        Error("SLC0013", "a type does not provide a member its interface requires");

    public static readonly DiagnosticDescriptor ImplementationNotPublic =
        Error("SLC0014", "a member implementing an interface member is not public");

    public static readonly DiagnosticDescriptor ImplementationSignatureMismatch =
        Error("SLC0015", "a member implementing an interface member does not match its signature");

    public static readonly DiagnosticDescriptor ValueTypeImplementsInterface =
        Error("SLC0016", "a variant or union lists an interface to implement");

    public static readonly DiagnosticDescriptor AttributeMemberNotField =
        Error("SLC0017", "an attribute type declares a member that is not a field");

    public static readonly DiagnosticDescriptor NotAnAttribute =
        Error("SLC0018", "a type that is not an attribute is written as an attribute");

    public static readonly DiagnosticDescriptor AttributeArgumentCountMismatch = Error(
        "SLC0019",
        "an attribute is given a number of arguments different from its field count");

    public static readonly DiagnosticDescriptor AttributeArgumentNotConstant =
        Error("SLC0020", "an attribute argument is not a constant of its field's type");

    public static readonly DiagnosticDescriptor AttributeUsedAsType =
        Error("SLC0021", "an attribute is used as a type");

    public static readonly DiagnosticDescriptor EnumUnderlyingTypeNotInteger =
        Error("SLC0022", "an enum is built on a type that is not an integer");

    public static readonly DiagnosticDescriptor EnumValueNotConstant =
        Error("SLC0023", "an enum member's value is not an integer constant");

    public static readonly DiagnosticDescriptor DuplicatePropertyAccessor =
        Error("SLC0024", "a property declares the same accessor twice");

    public static readonly DiagnosticDescriptor PropertyGetterMissing =
        Error("SLC0025", "a property declares no getter");

    public static readonly DiagnosticDescriptor MixedAutoAndWrittenAccessors =
        Error("SLC0026", "a property mixes an automatic accessor with a written one");

    public static readonly DiagnosticDescriptor AccessorNameTaken =
        Error("SLC0027", "a declared method already has the name a generated accessor needs");

    public static readonly DiagnosticDescriptor GetterAccessibilityNarrowed =
        Error("SLC0028", "a property getter is given narrower accessibility than its property");

    public static readonly DiagnosticDescriptor PropertyHasNoSetter =
        Error("SLC0029", "a property without a setter is assigned");

    public static readonly DiagnosticDescriptor AccessorCalledDirectly = Error(
        "SLC0030",
        "a property's getter or setter method is called by name instead of the property");

    public static readonly DiagnosticDescriptor PropertyAtModuleLevel = Error(
        "SLC0031",
        "a property is declared at module level, where there is no instance for it");

    public static readonly DiagnosticDescriptor AutoPropertyNeverAssigned = Error(
        "SLC0032",
        "an automatic property has no setter and its type has no constructor to fill it");

    public static readonly DiagnosticDescriptor VariantHasNoCases =
        Error("SLC0033", "a variant declares no cases");

    public static readonly DiagnosticDescriptor TooManyVariantCases =
        Error("SLC0034", "a variant has more cases than its one-byte tag can number");

    public static readonly DiagnosticDescriptor DuplicateVariantCaseField =
        Error("SLC0035", "a variant case declares two fields with the same name");

    public static readonly DiagnosticDescriptor AbstractOrSealedNonClass =
        Error("SLC0036", "'abstract' or 'sealed' is applied to a type that is not a class");

    public static readonly DiagnosticDescriptor DispatchModifierOnField =
        Error("SLC0037", "a field is given a dispatch modifier such as 'virtual' or 'override'");

    public static readonly DiagnosticDescriptor AbstractMemberHasBody =
        Error("SLC0038", "an abstract member has a body");

    public static readonly DiagnosticDescriptor OverrideHasNoBase =
        Error("SLC0039", "a member marked 'override' matches nothing it inherits");

    public static readonly DiagnosticDescriptor OverriddenMethodNotVirtual =
        Error("SLC0040", "a method overrides one that is not virtual or abstract");

    public static readonly DiagnosticDescriptor OverriddenMethodSealed =
        Error("SLC0041", "a method overrides a sealed override");

    public static readonly DiagnosticDescriptor OverrideSignatureMismatch =
        Error("SLC0042", "an override does not match the signature of what it overrides");

    public static readonly DiagnosticDescriptor InheritedMemberHiddenWithoutOverride = Error(
        "SLC0043",
        "a member has the same signature as an inherited one and is not marked 'override'");

    public static readonly DiagnosticDescriptor AbstractMemberNotImplemented =
        Error("SLC0044", "a concrete class does not implement an inherited abstract method");

    public static readonly DiagnosticDescriptor AbstractMemberInConcreteClass =
        Error("SLC0045", "an abstract method is declared in a class that is not abstract");

    public static readonly DiagnosticDescriptor DispatchedMemberNotAccessible =
        Error("SLC0046", "a virtual, abstract or override method is neither public nor protected");

    public static readonly DiagnosticDescriptor ModifiersConflict =
        Error("SLC0047", "two modifiers on one declaration contradict each other");

    public static readonly DiagnosticDescriptor BaseClassNotFirst =
        Error("SLC0048", "a base class is listed after an interface in a base list");

    public static readonly DiagnosticDescriptor BaseClassSealed =
        Error("SLC0049", "a class derives from a sealed class");

    public static readonly DiagnosticDescriptor SingleInheritance =
        Error("SLC0050", "a type derives from a second base where only one is allowed");

    public static readonly DiagnosticDescriptor InheritanceCycle =
        Error("SLC0051", "a type inherits from itself, directly or through others");

    public static readonly DiagnosticDescriptor BaseClassProvidedByRuntime = Error(
        "SLC0052",
        "a class derives from a type the runtime provides rather than this compilation");

    public static readonly DiagnosticDescriptor AbstractClassInstantiated =
        Error("SLC0053", "an abstract class is constructed with 'new'");

    public static readonly DiagnosticDescriptor NoBaseToReach =
        Error("SLC0054", "'base' is used where there is no base class to reach");

    public static readonly DiagnosticDescriptor ConstructorCallMisplaced = Error(
        "SLC0055",
        "a 'base(...)' or 'this(...)' call is outside a constructor or in the wrong place in one");

    public static readonly DiagnosticDescriptor BaseConstructorCallRequired =
        Error("SLC0056", "a base has no parameterless constructor and no 'base(...)' says which");

    public static readonly DiagnosticDescriptor ClassOnlyModifierOutsideClass =
        Error("SLC0057", "a dispatch modifier or 'protected' is used on a member outside a class");

    public static readonly DiagnosticDescriptor CircularConstructorDelegation =
        Error("SLC0058", "constructors delegate to themselves or to each other in a cycle");

    public static readonly DiagnosticDescriptor CircularTypeAlias =
        Error("SLC0059", "a type alias is defined in terms of itself");

    public static readonly DiagnosticDescriptor TypeAliasInsideType =
        Error("SLC0060", "a type alias is declared inside a type rather than at module level");

    public static readonly DiagnosticDescriptor AttributeRepeated =
        Error("SLC0061", "an attribute is written more than once on one declaration");

    public static readonly DiagnosticDescriptor TypeRedeclaredAsOtherKind =
        Error("SLC0062", "a type is declared again in its module as a different kind of type");

    public static readonly DiagnosticDescriptor OnlyFirstDeclarationMay =
        Error("SLC0063", "a further declaration of a type says what only the first may");

    public static readonly DiagnosticDescriptor OperatorAtModuleLevel =
        Error("SLC0064", "an operator is declared at module level rather than in a type");

    public static readonly DiagnosticDescriptor OperatorNotPublic =
        Error("SLC0065", "an operator is not declared 'public'");

    public static readonly DiagnosticDescriptor OperatorOperandCountMismatch =
        Error("SLC0066", "an operator declares the wrong number of operands");

    public static readonly DiagnosticDescriptor OperatorOperandNotContainingType =
        Error("SLC0067", "no operand of an operator is the type that declares it");

    public static readonly DiagnosticDescriptor ComparisonOperatorNotBool =
        Error("SLC0068", "a comparison operator does not return 'bool'");

    public static readonly DiagnosticDescriptor OperatorPairIncomplete =
        Error("SLC0069", "a type declares one operator of a pair without its counterpart");

    public static readonly DiagnosticDescriptor StaticInterfaceMemberModifiersInvalid = Error(
        "SLC0070",
        "a static interface member has an invalid combination of body and modifiers");

    public static readonly DiagnosticDescriptor StaticClassConstructed =
        Error("SLC0071", "a static class is constructed with 'new'");

    public static readonly DiagnosticDescriptor ParameterDefaultNotConstant =
        Error("SLC0072", "a parameter's default value is not a constant");

    public static readonly DiagnosticDescriptor RequiredParameterAfterOptional =
        Error("SLC0073", "a parameter without a default follows one with a default");

    public static readonly DiagnosticDescriptor ConversionNotOnItsType =
        Error("SLC0074", "a conversion is declared outside both types it converts between");

    public static readonly DiagnosticDescriptor InitializerOutsideClass =
        Error("SLC0075", "a field or property of a type that is not a class has an initializer");

    public static readonly DiagnosticDescriptor BraceListMixesMembersAndElements =
        Error("SLC0076", "a brace initializer mixes member entries and element entries");

    public static readonly DiagnosticDescriptor ParameterDefaultNotAllowed = Error(
        "SLC0077",
        "a 'ref', 'out' or 'in' parameter, or one of a variadic function, has a default");

    public static readonly DiagnosticDescriptor ParameterDefaultRestated =
        Error("SLC0078", "an override or interface implementation gives a parameter a default");

    public static readonly DiagnosticDescriptor ConversionNotPublic =
        Error("SLC0079", "a conversion operator is not 'public'");

    public static readonly DiagnosticDescriptor ConversionParameterCount =
        Error("SLC0080", "a conversion does not take exactly one non-variadic parameter");

    public static readonly DiagnosticDescriptor ConversionToItself =
        Error("SLC0081", "a conversion converts a type to itself");

    public static readonly DiagnosticDescriptor ConversionInvolvesInterface =
        Error("SLC0082", "a conversion is to or from an interface");

    public static readonly DiagnosticDescriptor DuplicateConversion =
        Error("SLC0083", "a conversion between two types is declared twice");

    public static readonly DiagnosticDescriptor FieldInitializerReadsObject =
        Error("SLC0084", "a field initializer reads the object it belongs to");

    public static readonly DiagnosticDescriptor InitializerOnComputedProperty =
        Error("SLC0085", "a computed property has an initializer");

    public static readonly DiagnosticDescriptor CollectionInitializerWithoutAdd =
        Error("SLC0086", "a brace list of elements initializes a type with no 'Add' method");

    public static readonly DiagnosticDescriptor InstanceMemberInStaticClass =
        Error("SLC0087", "a static class declares an instance member");

    public static readonly DiagnosticDescriptor BaseUsedAsValue =
        Error("SLC0088", "'base' is used as a value rather than as 'base.Member' or 'base(...)'");

    public static readonly DiagnosticDescriptor BaseConstructorCallUnneeded =
        Error("SLC0089", "'base(...)' is written and nothing derived from declares a constructor");

    public static readonly DiagnosticDescriptor TypeRedeclaredWithoutBody =
        Error("SLC0090", "a type already declared in the module is declared again with no body");

    public static readonly DiagnosticDescriptor InterfaceOperatorNotStaticAbstract = Error(
        "SLC0091",
        "an interface declares an operator that is not 'static abstract' or 'static virtual'");

    public static readonly DiagnosticDescriptor AttributeFieldNotFound =
        Error("SLC0092", "an attribute argument names a field the attribute does not have");

    public static readonly DiagnosticDescriptor MemberGivenTwice =
        Error("SLC0093", "a member is given a value twice in one list");

    public static readonly DiagnosticDescriptor AttributePositionalAfterNamed =
        Error("SLC0094", "a positional attribute argument follows a named one");

    public static readonly DiagnosticDescriptor AttributeArgumentUsesColon =
        Error("SLC0095", "an attribute field is set with ':' rather than '='");

    public static readonly DiagnosticDescriptor AttributeNotAllowedHere =
        Error("SLC0096", "an attribute is written on a declaration it does not apply to");

    public static readonly DiagnosticDescriptor RecordStructNotSupported =
        Error("SLC0097", "a 'record struct' is declared, which is not supported");

    public static readonly DiagnosticDescriptor WithOnNonRecord =
        Error("SLC0098", "a 'with' expression is applied to a value that is not a record");

    public static readonly DiagnosticDescriptor WithMemberNotFound = Error(
        "SLC0099",
        "a 'with' expression assigns a name the record has no parameter or settable property for");

    public static readonly DiagnosticDescriptor StructParameterlessConstructor =
        Error("SLC0100", "a struct declares a constructor taking no arguments");

    public static readonly DiagnosticDescriptor InvalidParamsParameter =
        Error("SLC0101", "a parameter is marked 'params' where it is not allowed");

    public static readonly DiagnosticDescriptor InitAccessorOnStatic =
        Error("SLC0102", "a static property declares an 'init' accessor");

    public static readonly DiagnosticDescriptor InitPropertyAssignedAfterConstruction =
        Error("SLC0103", "an 'init' property is assigned outside of the object's construction");

    public static readonly DiagnosticDescriptor InitSetAccessorMismatch = Error(
        "SLC0104",
        "a property's 'init' or 'set' differs from that of the member it implements or overrides");

    public static readonly DiagnosticDescriptor InvalidRequiredMember =
        Error("SLC0105", "a member is marked 'required' that cannot be");

    public static readonly DiagnosticDescriptor RequiredMembersNotSet =
        Error("SLC0106", "a construction does not set every required member");

    public static readonly DiagnosticDescriptor ConstructorMustChainToPrimary =
        Error("SLC0107", "a constructor of a type with a primary constructor does not chain to it");

    public static readonly DiagnosticDescriptor PrimaryConstructorOnWrongKind = Error(
        "SLC0108",
        "a parameter list follows the name of a type that is not a class or struct");

    public static readonly DiagnosticDescriptor PrimaryConstructorRefParameterCaptured =
        Error("SLC0109", "a by-reference primary constructor parameter is used by a member body");

    public static readonly DiagnosticDescriptor InvalidExplicitInterfaceMember =
        Error("SLC0110", "an explicit interface member is a field or an automatic property");

    public static readonly DiagnosticDescriptor ExplicitInterfaceTargetInvalid = Error(
        "SLC0111",
        "an explicit interface member names something that is not an implemented interface slot");

    public static readonly DiagnosticDescriptor ExplicitInterfaceMemberHasModifier =
        Error("SLC0112", "an explicit interface member is declared with a modifier");

    public static readonly DiagnosticDescriptor AmbiguousDefaultInterfaceMember = Error(
        "SLC0113",
        "two interfaces give equally specific defaults for a member a class does not define");

    public static readonly DiagnosticDescriptor NonRecordDerivesFromRecord =
        Error("SLC0114", "a class that is not a record derives from a record");

    public static readonly DiagnosticDescriptor BaseCallToAbstractMember =
        Error("SLC0115", "a 'base' call names a member that is abstract in the base");

    public static readonly DiagnosticDescriptor EventGivenInitializer =
        Error("SLC0116", "an event is declared with an initial value");

    public static readonly DiagnosticDescriptor EventTypeNotClosure =
        Error("SLC0117", "an event is declared with a type that is not a closure");

    public static readonly DiagnosticDescriptor EventHandlerReturnsValue =
        Error("SLC0118", "an event's closure type returns a value rather than void");

    public static readonly DiagnosticDescriptor StaticEventNotSupported =
        Error("SLC0119", "an event is declared static");

    public static readonly DiagnosticDescriptor EventRaisedOutsideDeclarer =
        Error("SLC0120", "an event is raised from outside the type that declares it");

    public static readonly DiagnosticDescriptor EventReadAsValue =
        Error("SLC0121", "an event is read as a value from outside its declaring type");

    public static readonly DiagnosticDescriptor EventAssignedWithWrongOperator =
        Error("SLC0122", "an event is assigned with an operator other than '+=' or '-='");

    public static readonly DiagnosticDescriptor ModifierNotAllowedHere =
        Error("SLC0123", "a modifier is written on a declaration it does not apply to");

    public static readonly DiagnosticDescriptor RequiredMemberNotPublic =
        Error("SLC0124", "a required member of a public type, or its setter, is not public");

    public static readonly DiagnosticDescriptor BaseArgumentsMisplaced = Error(
        "SLC0125",
        "base constructor arguments follow a base type other than the first in the list");

    public static readonly DiagnosticDescriptor InjectedTypeNotConstructible =
        Error("SLC0126", "a dependency container is asked for a type it cannot construct");

    public static readonly DiagnosticDescriptor InjectedConstructorAmbiguous = Error(
        "SLC0127",
        "a dependency container cannot choose between equally wide public constructors");

    public static readonly DiagnosticDescriptor InjectedParameterUnresolvable = Error(
        "SLC0128",
        "a constructor parameter is of a kind a dependency container cannot supply");

    public static readonly DiagnosticDescriptor DefaultImplementationInvalid = Error(
        "SLC0129",
        "a default implementation named for a contract is not a matching generic class");

    // ------------------------------------------------- F: Flow and patterns

    public static readonly DiagnosticDescriptor NotAllPathsReturn =
        Error("SLF0001", "some path through a function or lambda ends without returning a value");

    public static readonly DiagnosticDescriptor ReturnMissingValue =
        Error("SLF0002", "a return in a function that returns a value has no value");

    public static readonly DiagnosticDescriptor ReturnValueFromVoid =
        Error("SLF0003", "a return in a void function carries a value");

    public static readonly DiagnosticDescriptor BreakOutsideLoopOrSwitch =
        Error("SLF0004", "break appears outside a loop or a switch");

    public static readonly DiagnosticDescriptor ContinueOutsideLoop =
        Error("SLF0005", "continue appears outside a loop");

    public static readonly DiagnosticDescriptor CaseFieldReadWithoutCheck =
        Error("SLF0006", "a variant case's field is read where no check established the case");

    public static readonly DiagnosticDescriptor ForEachNotEnumerable = Error(
        "SLF0007",
        "'foreach' iterates something that is not an array and has no 'GetEnumerator()'");

    public static readonly DiagnosticDescriptor GetEnumeratorReturnsNonEnumerator =
        Error("SLF0008", "'GetEnumerator()' returns a type lacking 'MoveNext()' and 'Current'");

    public static readonly DiagnosticDescriptor LambdaTargetInvalid = Error(
        "SLF0009",
        "a lambda is converted to a type that is not a delegate or single-method interface");

    public static readonly DiagnosticDescriptor LambdaParameterCountMismatch =
        Error("SLF0010", "a lambda declares a parameter count different from its target type");

    public static readonly DiagnosticDescriptor LambdaParameterTypeMismatch =
        Error("SLF0011", "a lambda parameter's written type differs from what its target expects");

    public static readonly DiagnosticDescriptor SwitchValueTypeNotSwitchable =
        Error("SLF0012", "a switch is over a type that cannot have constant labels");

    public static readonly DiagnosticDescriptor CaseLabelNotConstant =
        Error("SLF0013", "a 'case' label is not a constant of the switched type");

    public static readonly DiagnosticDescriptor DuplicateSwitchCase =
        Error("SLF0014", "a switch has two cases or arms for the same value");

    public static readonly DiagnosticDescriptor DuplicateSwitchDefault =
        Error("SLF0015", "a switch has more than one 'default' section");

    public static readonly DiagnosticDescriptor SwitchSectionFallsThrough = Error(
        "SLF0016",
        "a switch section runs off its end without 'break', 'return', 'continue' or 'goto'");

    public static readonly DiagnosticDescriptor VariantSwitchNotExhaustive =
        Error("SLF0017", "a switch over a variant leaves cases uncovered and has no 'default'");

    public static readonly DiagnosticDescriptor CasePatternOnNonVariant = Error(
        "SLF0018",
        "a case or class pattern is matched against something neither a variant nor an object");

    public static readonly DiagnosticDescriptor MultipleBoundCasesInSection =
        Error("SLF0019", "a switch section binds more than one variant case");

    public static readonly DiagnosticDescriptor PatternTypeNotApplicable =
        Error("SLF0020", "a pattern asks about a type its subject's type cannot answer");

    public static readonly DiagnosticDescriptor TryOperandNotResult =
        Error("SLF0021", "'try' is applied to a value that is not a 'Result'");

    public static readonly DiagnosticDescriptor TryOutsideResultFunction =
        Error("SLF0022", "'try' is used where the enclosing code does not return a 'Result'");

    public static readonly DiagnosticDescriptor TryErrorTypeMismatch =
        Error("SLF0023", "'try' passes on a failure type that differs from the function's");

    public static readonly DiagnosticDescriptor PatternVariableNotDefinitelyMatched =
        Error("SLF0024", "a pattern variable is used where its pattern may not have matched");

    public static readonly DiagnosticDescriptor EmptyCaseBound =
        Error("SLF0025", "a name is bound to a variant case that carries nothing");

    public static readonly DiagnosticDescriptor PatternBindsInterface =
        Error("SLF0026", "a pattern names or deconstructs a value tested against an interface");

    public static readonly DiagnosticDescriptor DuplicateLabel =
        Error("SLF0027", "a label is declared twice in one function");

    public static readonly DiagnosticDescriptor LabelNotFound =
        Error("SLF0028", "a 'goto' names a label that does not exist in its function");

    public static readonly DiagnosticDescriptor JumpIntoBlock =
        Error("SLF0029", "a jump enters a block it is not already in");

    public static readonly DiagnosticDescriptor ValueCannotBeDeconstructed =
        Error("SLF0030", "a value is neither a tuple nor has a 'Deconstruct' of the needed arity");

    public static readonly DiagnosticDescriptor DeconstructionArityMismatch = Error(
        "SLF0031",
        "a positional pattern or deconstruction names the wrong number of elements");

    public static readonly DiagnosticDescriptor PatternNameNotAssigned = Error(
        "SLF0032",
        "a pattern names a variable that is not assigned wherever it would be used");

    public static readonly DiagnosticDescriptor SwitchExpressionNotExhaustive =
        Error("SLF0033", "a switch expression has no arm for some input");

    public static readonly DiagnosticDescriptor SwitchArmHasNoValue =
        Error("SLF0034", "an arm of a switch expression produces no value");

    public static readonly DiagnosticDescriptor VariantDeconstructedWithoutCase =
        Error("SLF0035", "a variant is taken apart by a pattern that does not name its case");

    public static readonly DiagnosticDescriptor StaticBodyCaptures =
        Error("SLF0036", "a static lambda or local function reads from around it");

    public static readonly DiagnosticDescriptor LambdaReturnTypeMismatch =
        Error("SLF0037", "a lambda's declared return type differs from its target delegate's");

    public static readonly DiagnosticDescriptor LocalFunctionCaptureNotInScope = Error(
        "SLF0038",
        "a local function is called where a variable it captures is not in scope or not yet known");

    public static readonly DiagnosticDescriptor LocalFunctionAssignsOuterParameter = Error(
        "SLF0039",
        "a local function assigns its enclosing function's parameter, of which it has a copy");

    public static readonly DiagnosticDescriptor DeclarationOutsideDeconstruction = Error(
        "SLF0040",
        "a variable is declared inside an expression where no deconstruction statement holds it");

    public static readonly DiagnosticDescriptor ForeachDeconstructionWithoutDeclaration = Error(
        "SLF0041",
        "a 'foreach' deconstruction names existing variables rather than declaring new ones");

    public static readonly DiagnosticDescriptor ListPatternTypeNotIndexable = Error(
        "SLF0042",
        "a list pattern is matched against a type that cannot be indexed element by element");

    public static readonly DiagnosticDescriptor SlicePatternMisplaced =
        Error("SLF0043", "a '..' stands outside a list pattern, or a list pattern has two");

    public static readonly DiagnosticDescriptor PositionalPatternNameMismatch =
        Error("SLF0044", "a name in a positional pattern is not that position's name");

    public static readonly DiagnosticDescriptor GotoCaseOutsideSwitch =
        Error("SLF0045", "'goto case' or 'goto default' is written outside a switch statement");

    public static readonly DiagnosticDescriptor GotoCaseTargetNotFound =
        Error("SLF0046", "'goto case' or 'goto default' has no section to run");

    public static readonly DiagnosticDescriptor SlicePatternNotSliceable =
        Error("SLF0047", "a '..' names what it skips on a type that cannot be sliced");

    public static readonly DiagnosticDescriptor PropertyPatternNamesMethod =
        Error("SLF0048", "a property pattern names a method rather than a field or property");

    public static readonly DiagnosticDescriptor GotoCaseNotConstant =
        Error("SLF0049", "'goto case' names a value that is not a constant");

    // ---------------------------------------------- O: Ownership and safety

    public static readonly DiagnosticDescriptor MaybeNullUsedWithoutCheck =
        Error("SLO0001", "a value that may be null is used without a check");

    public static readonly DiagnosticDescriptor WeakOfNonReference =
        Error("SLO0002", "weak is applied to a type that is not a class or interface reference");

    public static readonly DiagnosticDescriptor SpawnOutsideParallel =
        Error("SLO0003", "'spawn' is used outside a 'parallel' block");

    public static readonly DiagnosticDescriptor SpawnTargetNotCall =
        Error("SLO0004", "'spawn' is given something other than a function or method call");

    public static readonly DiagnosticDescriptor SpawnResultNotStorable = Error(
        "SLO0005",
        "a spawned result is assigned to something other than a variable, field or element");

    public static readonly DiagnosticDescriptor SpawnResultIsVoid =
        Error("SLO0006", "a spawned call returning nothing is assigned to a target");

    public static readonly DiagnosticDescriptor SpawnResultNeedsConversion =
        Error("SLO0007", "a spawned result needs a conversion to the type it is stored into");

    public static readonly DiagnosticDescriptor ParallelForVariableMissing =
        Error("SLO0008", "a 'for parallel' does not start by declaring an integer loop variable");

    public static readonly DiagnosticDescriptor ParallelForConditionInvalid = Error(
        "SLO0009",
        "a 'for parallel' condition is not a '<' or '<=' bound on its loop variable");

    public static readonly DiagnosticDescriptor ParallelForStepInvalid =
        Error("SLO0010", "a 'for parallel' step is not an increment of its loop variable");

    public static readonly DiagnosticDescriptor ParallelForStrideNotLiteral =
        Error("SLO0011", "a 'for parallel' stride is not a positive integer literal");

    public static readonly DiagnosticDescriptor ParallelForOuterAssignment =
        Error("SLO0012", "a 'for parallel' body assigns a variable declared outside it");

    public static readonly DiagnosticDescriptor SpawnBorrowsTemporary = Error(
        "SLO0013",
        "a spawned call's receiver or argument is a temporary rather than a held value");

    public static readonly DiagnosticDescriptor StaticWithoutInitializer =
        Error("SLO0014", "a static is declared without an initial value");

    public static readonly DiagnosticDescriptor SharedStateNotThreadSafe =
        Warning("SLO0015", "a value reached by more than one thread has no declared thread safety");

    public static readonly DiagnosticDescriptor StaticInitializationCycle = Error(
        "SLO0016",
        "a static initializer or static constructor depends on itself through other statics");

    public static readonly DiagnosticDescriptor StaticReadonlyAssigned = Error(
        "SLO0017",
        "a 'static readonly' or a field of the struct it holds is written after initialization");

    public static readonly DiagnosticDescriptor SpawnUsedAsValue =
        Error("SLO0018", "'spawn' is used as a value inside a larger expression");

    public static readonly DiagnosticDescriptor SpawnedCallTakesReference = Error(
        "SLO0019",
        "a spawned call passes a 'ref', 'out' or 'in' parameter, sharing the caller's storage");

    public static readonly DiagnosticDescriptor InlineArrayOfCounted =
        Error("SLO0020", "an inline array's element type holds a counted reference");

    public static readonly DiagnosticDescriptor ThreadsafeOnWrongKind =
        Error("SLO0021", "'threadsafe' is written on a kind of type that cannot claim it");

    public static readonly DiagnosticDescriptor JumpOutOfParallelBlock =
        Error("SLO0022", "a jump leaves a parallel block");

    public static readonly DiagnosticDescriptor OutParameterNotAssigned =
        Error("SLO0023", "a function can return without assigning one of its 'out' parameters");

    public static readonly DiagnosticDescriptor NullOperatorOnNonNullable =
        Error("SLO0024", "a null-testing operator is applied to a type that cannot be null");

    public static readonly DiagnosticDescriptor ConditionalAccessResultNotNullable =
        Error("SLO0025", "a '?.' reaches a type with no null to stand for a missing receiver");

    public static readonly DiagnosticDescriptor WeakReferenceUsedDirectly = Error(
        "SLO0026",
        "a weak reference is used or tested without first being read into an optional");

    public static readonly DiagnosticDescriptor DefaultOfTypeWithoutZero =
        Error("SLO0027", "'default' is taken of a type that has no zero value");

    public static readonly DiagnosticDescriptor ReadBeforeAssigned =
        Error("SLO0028", "a slot with no zero value is read before it is assigned");

    public static readonly DiagnosticDescriptor ArrayOfTypeWithoutZero =
        Error("SLO0029", "'new T[n]' is written for an element type that has no zero value");

    public static readonly DiagnosticDescriptor FieldMayBeUnassigned =
        Error("SLO0030", "a field with no zero value may be left unassigned by construction");

    public static readonly DiagnosticDescriptor StaticWithoutZeroUninitialized =
        Error("SLO0031", "a static or global whose type has no zero value has no initializer");

    public static readonly DiagnosticDescriptor ObjectReachedBeforeBase =
        Error("SLO0032", "a constructor reaches the object or returns before 'base(...)' has run");

    public static readonly DiagnosticDescriptor FieldWithoutZeroUnsetAtBase = Error(
        "SLO0033",
        "a field with no zero value is still unset when the object becomes reachable");

    public static readonly DiagnosticDescriptor LateFieldNotAllowed =
        Error("SLO0034", "'late' is written on a field that cannot be late");

    // ----------------------------------------------------------- I: Interop

    public static readonly DiagnosticDescriptor ExternFunctionHasBody =
        Error("SLI0001", "a function declared extern has a body");

    public static readonly DiagnosticDescriptor TypeCannotCrossBoundary =
        Error("SLI0002", "a parameter or return type cannot cross a foreign boundary");

    public static readonly DiagnosticDescriptor StringIsNotBytePointer =
        Error("SLI0003", "a String is passed where a byte pointer is expected");

    public static readonly DiagnosticDescriptor DuplicateForeignSymbol = Error(
        "SLI0004",
        "two declarations, or a declaration and the runtime, claim one C symbol name");

    public static readonly DiagnosticDescriptor PackOnPackedType =
        Error("SLI0005", "'[Pack(N)]' is written on a type already marked '[Packed]'");

    public static readonly DiagnosticDescriptor PackedFieldInvalid =
        Error("SLI0006", "'[Packed]' is on a field that cannot be packed");

    public static readonly DiagnosticDescriptor AlignmentNotPowerOfTwo = Error(
        "SLI0007",
        "'[Pack(N)]' or '[Align(N)]' asks for an alignment that is not a power of two");

    public static readonly DiagnosticDescriptor AlignmentTooLarge = Error(
        "SLI0008",
        "'[Pack(N)]' or '[Align(N)]' asks for more than the largest alignment allowed");

    public static readonly DiagnosticDescriptor UnionHasNoMembers =
        Error("SLI0009", "a union declares no members");

    public static readonly DiagnosticDescriptor UnionMemberCounted =
        Error("SLI0010", "a union member holds a counted reference");

    public static readonly DiagnosticDescriptor BitFieldOutsideStruct =
        Error("SLI0011", "a bit-field is declared in a type that is not a struct or union");

    public static readonly DiagnosticDescriptor PackedWithBitFields =
        Error("SLI0012", "a packed type has bit-fields, whose layout C compilers disagree on");

    public static readonly DiagnosticDescriptor BitFieldTypeInvalid =
        Error("SLI0013", "a bit-field's type is not an integer or a bool");

    public static readonly DiagnosticDescriptor BitFieldWidthNotConstant =
        Error("SLI0014", "a bit-field's width is not a constant");

    public static readonly DiagnosticDescriptor BitFieldWidthZero =
        Error("SLI0015", "a bit-field's width is less than one bit");

    public static readonly DiagnosticDescriptor BitFieldWidthTooLarge =
        Error("SLI0016", "a bit-field asks for more bits than its type has");

    public static readonly DiagnosticDescriptor ReflectWithBitFields = Error(
        "SLI0017",
        "'[Reflect]' is applied to a type with bit-fields, which have no byte offset");

    public static readonly DiagnosticDescriptor OffsetOfInvalidType =
        Error("SLI0018", "'offsetof' names a type that has no fixed field offsets");

    public static readonly DiagnosticDescriptor OffsetOfFieldNotFound =
        Error("SLI0019", "'offsetof' names a field the type does not have");

    public static readonly DiagnosticDescriptor OffsetOfBitField =
        Error("SLI0020", "'offsetof' names a bit-field, which has no byte offset");

    public static readonly DiagnosticDescriptor VariadicNotAllowed =
        Error("SLI0021", "'...' is written on a declaration that cannot be variadic");

    public static readonly DiagnosticDescriptor BodilessTypeNotAllowed = Error(
        "SLI0022",
        "a type is declared without a body where only a non-generic struct may be");

    public static readonly DiagnosticDescriptor IncompleteTypeUsedByValue = Error(
        "SLI0023",
        "a type declared without a body is used by value rather than through a pointer");

    public static readonly DiagnosticDescriptor ComModifierOnWrongKind =
        Error("SLI0024", "'com' is written on a type that is neither an interface nor a class");

    public static readonly DiagnosticDescriptor ComInterfaceExtendsNonCom =
        Error("SLI0025", "a com interface extends an interface that is not com");

    public static readonly DiagnosticDescriptor ComInterfaceOnNonClass =
        Error("SLI0026", "a type other than a class implements a com interface");

    public static readonly DiagnosticDescriptor ComInterfaceOnNonComClass =
        Error("SLI0027", "a class implements a com interface without being declared 'com class'");

    public static readonly DiagnosticDescriptor ComInterfaceEmpty =
        Warning("SLI0028", "a com interface declares no methods, so it is just IUnknown");

    public static readonly DiagnosticDescriptor ComClassWithoutComInterface =
        Error("SLI0029", "a com class implements no com interface");

    public static readonly DiagnosticDescriptor ComClassWithBaseClass =
        Error("SLI0030", "a com class derives from a base class");

    public static readonly DiagnosticDescriptor ComInterfaceMissingGuid =
        Error("SLI0031", "a com interface has no '[Guid]' attribute");

    public static readonly DiagnosticDescriptor GuidArgumentInvalid =
        Error("SLI0032", "'[Guid]' is not given exactly one string literal");

    public static readonly DiagnosticDescriptor GuidFormatInvalid =
        Error("SLI0033", "a '[Guid]' string is not in GUID form");

    public static readonly DiagnosticDescriptor IidOfNonComInterface =
        Error("SLI0034", "'iidof' names a type that is not a com interface");

    public static readonly DiagnosticDescriptor GuidClassNotFactoryConstructible = Error(
        "SLI0035",
        "a class with '[Guid]' cannot be made by a class factory with no arguments");

    public static readonly DiagnosticDescriptor ComInterfaceUnknownMismatch =
        Error("SLI0036", "a COM interface and the one it extends disagree about '[NoUnknown]'");

    public static readonly DiagnosticDescriptor GuidOnNoUnknownInterface = Error(
        "SLI0037",
        "a '[NoUnknown]' com interface also has a '[Guid]' nothing could query for");

    public static readonly DiagnosticDescriptor ObjCCategoryClassUnresolved = Error(
        "SLI0038",
        "an Objective-C category names a class no import declares, or one several do");

    public static readonly DiagnosticDescriptor CppVariableNotSupported =
        Error("SLI0039", "an extern C++ variable is declared, whose mangled name is not supported");

    public static readonly DiagnosticDescriptor ExternVariableInitialized =
        Error("SLI0040", "an 'extern \"C\"' variable is given an initializer");

    public static readonly DiagnosticDescriptor AsmRegisterUnknown =
        Error("SLI0041", "an 'asm' operand names a register the target architecture does not have");

    public static readonly DiagnosticDescriptor AsmRegisterNotAllowed =
        Error("SLI0042", "an 'asm' operand names a register that cannot be used as an operand");

    public static readonly DiagnosticDescriptor AsmRegisterNamedTwice =
        Error("SLI0043", "an 'asm' block names the same register more than once in one direction");

    public static readonly DiagnosticDescriptor AsmOperandTypeNotAllowed =
        Error("SLI0044", "an 'asm' operand's type cannot travel in a register");

    public static readonly DiagnosticDescriptor AsmOperandTooWide =
        Error("SLI0045", "an 'asm' operand's value is wider than the register named for it");

    public static readonly DiagnosticDescriptor AsmRegisterKindMismatch = Error(
        "SLI0046",
        "an 'asm' operand's type belongs in a different kind of register than the one named");

    public static readonly DiagnosticDescriptor AsmOutputToBitField =
        Error("SLI0047", "an 'asm' output is written to a bit-field, which has no address");

    public static readonly DiagnosticDescriptor AsmRejectedByAssembler =
        Error("SLI0048", "the assembler rejected a line of an 'asm' block");

    public static readonly DiagnosticDescriptor UnsettledArgumentToVariadic =
        Error("SLI0049", "an argument of no settled type is passed to a C variadic parameter list");

    public static readonly DiagnosticDescriptor ObjCModifierMisplaced = Error(
        "SLI0050",
        "'objc' is written on something other than an interface, class or closure");

    public static readonly DiagnosticDescriptor ExternObjCTypeMisdeclared =
        Error("SLI0051", "'extern' is written on an Objective-C type that cannot take it");

    public static readonly DiagnosticDescriptor ObjCMemberMissingSelector =
        Error("SLI0052", "a member of an Objective-C class or protocol has no '[Selector]'");

    public static readonly DiagnosticDescriptor ObjCMessageMemberHasBody = Error(
        "SLI0053",
        "a protocol member or an existing class's selector member is given a body");

    public static readonly DiagnosticDescriptor SelectorAttributeMalformed =
        Error("SLI0054", "a '[Selector]' has the wrong arguments or names an invalid selector");

    public static readonly DiagnosticDescriptor SelectorArgumentCountMismatch =
        Error("SLI0055", "a selector's colon count disagrees with the member's parameter count");

    public static readonly DiagnosticDescriptor ObjCSignatureCannotCross = Error(
        "SLI0056",
        "a parameter or return type cannot be carried by an Objective-C message or block");

    public static readonly DiagnosticDescriptor ObjCTypeAttributeMalformed =
        Error("SLI0057", "'[ObjCRoot]' or '[ObjCName]' has the wrong arguments");

    public static readonly DiagnosticDescriptor ExternObjCClassDeclaresStorage = Error(
        "SLI0058",
        "an 'extern objc class' declares a member it cannot have, such as a field");

    public static readonly DiagnosticDescriptor ObjCBaseWrongKind =
        Error("SLI0059", "an Objective-C type names a base or protocol of a kind it cannot take");

    public static readonly DiagnosticDescriptor ObjCClassRootInvalid =
        Error("SLI0060", "an Objective-C class does not reach exactly one '[ObjCRoot]' root class");

    public static readonly DiagnosticDescriptor ExternObjCClassConstructedWithNew =
        Error("SLI0061", "'new' is used on an 'extern objc class'");

    public static readonly DiagnosticDescriptor ObjCOnNonAppleTarget =
        Error("SLI0062", "an Objective-C message is sent on a target that is not macOS");

    public static readonly DiagnosticDescriptor ObjCMethodVirtual =
        Error("SLI0063", "a method of an Objective-C class is marked 'abstract' or 'virtual'");

    public static readonly DiagnosticDescriptor ObjCClassShapeUnsupported =
        Error("SLI0064", "an Objective-C type is declared in a shape the runtime cannot support");

    public static readonly DiagnosticDescriptor ObjCConstructorSelectorNotInit =
        Error("SLI0065", "an Objective-C constructor's selector does not begin with 'init'");

    public static readonly DiagnosticDescriptor ForeignObjCObjectWritten =
        Error("SLI0066", "an Objective-C object owned by a C library is written to");

    public static readonly DiagnosticDescriptor CFTypeMalformed =
        Error("SLI0067", "'[CFType]' has arguments other than one type-ID function name");

    public static readonly DiagnosticDescriptor ProtocolClassMemberSentToProtocol = Error(
        "SLI0068",
        "a class member of a protocol is sent to the protocol rather than a class");

    public static readonly DiagnosticDescriptor TooManyVectorsAcrossX86Windows =
        Error("SLI0069", "more than three vectors cross a foreign boundary on 32-bit Windows");

    public static readonly DiagnosticDescriptor VaListStartOutsideVariadic =
        Error("SLI0070", "'VaList.Start()' is called in a function that is not variadic");

    public static readonly DiagnosticDescriptor CFTypeBaseUnmarked = Error(
        "SLI0071",
        "a class derives from a Core Foundation type without being marked '[CFType]'");

    public static readonly DiagnosticDescriptor VaListArgumentsGiven =
        Error("SLI0072", "'VaList.Start()' or 'Next<T>()' is given arguments");

    public static readonly DiagnosticDescriptor VaListTypeUnreadable =
        Error("SLI0073", "'Next<T>()' names a type a variadic argument cannot be read as");

    public static readonly DiagnosticDescriptor ObjCOverrideSelectorChanged =
        Error("SLI0074", "an override of an Objective-C message names a different selector");

    public static readonly DiagnosticDescriptor ObjCSelectorAnsweredTwice =
        Error("SLI0075", "an Objective-C class answers one selector with two methods");

    public static readonly DiagnosticDescriptor TypeofObjCType =
        Error("SLI0076", "'typeof' is applied to an Objective-C type, which the runtime describes");

    public static readonly DiagnosticDescriptor ObjCInitNotDeclared = Error(
        "SLI0077",
        "an Objective-C class is constructed and nothing it is built on declares 'init'");

    public static readonly DiagnosticDescriptor CFTypeShapeUnsupported = Error(
        "SLI0078",
        "a Core Foundation type has a root, base, protocol or message it cannot have");

    // -------------------------------------------------------------- L: Lint

    public static readonly DiagnosticDescriptor ExpressionHasNoEffect =
        Warning("SLL0001", "an expression statement computes a value and discards it");

    public static readonly DiagnosticDescriptor TypeTestAlwaysTrue = Warning(
        "SLL0002",
        "a type test always succeeds because the subject's type already is the tested type");

    public static readonly DiagnosticDescriptor LabelUnused =
        Warning("SLL0003", "a label is never jumped to");

    public static readonly DiagnosticDescriptor CapturedByValueThenChanged =
        Warning("SLL0004", "a lambda captures a variable by value that is changed afterwards");

    public static readonly DiagnosticDescriptor UnreachableSwitchCase =
        Warning("SLL0005", "a switch label or arm is unreachable because earlier ones cover it");

    public static readonly DiagnosticDescriptor DocumentationTagUnknown =
        Warning("SLL0006", "a documentation comment uses a tag that does not exist");

    public static readonly DiagnosticDescriptor DocumentedParameterNotFound =
        Warning("SLL0007", "a '@param' tag names a parameter the function does not have");

    public static readonly DiagnosticDescriptor DocumentedParametersIncomplete =
        Warning("SLL0008", "a documentation comment documents some parameters but not all");

    public static readonly DiagnosticDescriptor DocumentedTypeParameterNotFound =
        Warning("SLL0009", "a documentation tag names a type parameter that does not exist");

    public static readonly DiagnosticDescriptor DocumentationTagMisplaced =
        Warning("SLL0010", "a documentation tag is written on a declaration it says nothing about");

    public static readonly DiagnosticDescriptor DocumentedFailureCaseInvalid =
        Warning("SLL0011", "a '@failure' tag names no case of the function's error type");

    public static readonly DiagnosticDescriptor DocumentationReferenceUnresolved = Warning(
        "SLL0012",
        "a documentation cross-reference names nothing or names something not in scope");

    public static readonly DiagnosticDescriptor LambdaDefaultNotSeenByTarget = Warning(
        "SLL0013",
        "a lambda parameter's default differs from the one its target type gives");

    public static readonly DiagnosticDescriptor CapturedCopyWrittenInLambda = Warning(
        "SLL0014",
        "a lambda assigns its own copy of a captured variable or member, changing nothing");

    public static readonly DiagnosticDescriptor DocumentedParameterRepeated =
        Warning("SLL0015", "a parameter is documented by more than one '@param' tag");

    public static readonly DiagnosticDescriptor DocumentedFailureOnInfallible =
        Warning("SLL0016", "a '@failure' tag is on a function that reports no failure");

    // -------------------------------------------------- D: Driver and build

    public static readonly DiagnosticDescriptor MultipleEntryPoints =
        Error("SLD0001", "more than one Main is declared in the program");

    public static readonly DiagnosticDescriptor EntryPointReturnType =
        Error("SLD0002", "Main returns something other than int or void");

    public static readonly DiagnosticDescriptor EntryPointParameters =
        Error("SLD0003", "Main takes parameters other than none or one String array");

    public static readonly DiagnosticDescriptor EntryPointNotFound =
        Error("SLD0004", "an executable is built with no Main in any compiled module");

    public static readonly DiagnosticDescriptor ReferencedTypeRedeclared =
        Error("SLD0005", "a type is declared both in the program and in a referenced library");

    public static readonly DiagnosticDescriptor ReferencedSignatureTypeUnknown =
        Error("SLD0006", "a referenced library's member uses a type the program does not know");

    public static readonly DiagnosticDescriptor OmittedFromMetadata =
        Warning("SLD0007", "a public declaration is not described in the library's metadata");

    public static readonly DiagnosticDescriptor LibraryExportsNothing =
        Warning("SLD0008", "a library has no 'export \"C\"' function to export");

    public static readonly DiagnosticDescriptor MetadataReferencesUndescribedType = Warning(
        "SLD0009",
        "a type in a library's metadata refers to a type the metadata does not describe");

    public static readonly DiagnosticDescriptor WindowsResourcesOnOtherTarget = Warning(
        "SLD0010",
        "a program carries Windows-only resources while building for another platform");

    public static readonly DiagnosticDescriptor EmbedPathMissing =
        Error("SLD0011", "'[Embed]' is written without a file path");

    public static readonly DiagnosticDescriptor EmbedArgumentNotLiteral =
        Error("SLD0012", "an '[Embed]' argument is not a string literal");

    public static readonly DiagnosticDescriptor EmbedRelativePathWithoutFile = Error(
        "SLD0013",
        "an embed's relative path cannot be resolved because the source is not a file on disk");

    public static readonly DiagnosticDescriptor EmbedFileUnreadable = Error(
        "SLD0014",
        "the file named by an embed is missing, invalid, a directory, unreadable or too large");

    public static readonly DiagnosticDescriptor EmbedAccessInvalid =
        Error("SLD0015", "an embed's access string is not a valid combination of 'r', 'w' and 'x'");

    public static readonly DiagnosticDescriptor EmbedWritableExecutableSection = Error(
        "SLD0016",
        "an embed asks for writable and executable memory with no section that can hold it");

    public static readonly DiagnosticDescriptor EmbedSectionInvalid =
        Error("SLD0017", "an embed names a section that cannot be one");

    public static readonly DiagnosticDescriptor EmbedSectionNameTruncated = Warning(
        "SLD0018",
        "an embed's section name is longer than a PE image keeps and will be truncated");

    public static readonly DiagnosticDescriptor EmbedSectionIncompatible = Error(
        "SLD0019",
        "an embed is placed in a section whose kind or permissions cannot hold it");

    public static readonly DiagnosticDescriptor EmbedStaticNotByteArray =
        Error("SLD0020", "a static with '[Embed]' is not declared 'byte[]'");

    public static readonly DiagnosticDescriptor EmbedStaticHasInitializer =
        Error("SLD0021", "a static with '[Embed]' also has an initializer");

    public static readonly DiagnosticDescriptor MetadataInconsistentWithLibrary = Error(
        "SLD0022",
        "a library's metadata describes a slot or event incompletely, as if edited");
}
