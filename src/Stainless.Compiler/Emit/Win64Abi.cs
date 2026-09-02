using Stainless.Binding;

namespace Stainless.Emit;

public enum PassStyle
{
    /// <summary>Passed directly in a register as its natural LLVM type.</summary>
    Direct,
    /// <summary>A small struct reinterpreted as an integer of the same size.</summary>
    CoerceToInteger,
    /// <summary>A large struct passed as a pointer to a caller-allocated copy.</summary>
    Indirect,
}

public sealed record ArgInfo(PassStyle Style, string LlvmType, TypeSymbol Type);

/// <summary>
/// Win64 (Microsoft x64) parameter and return classification.
///
/// LLVM IR does not apply a C ABI on its own — that is a front-end job — so if
/// Stainless is to be genuinely C-compatible, this is where it happens. The
/// rules are short: a struct whose size is exactly 1, 2, 4 or 8 bytes travels in
/// a register as an integer of that width; every other struct travels as a
/// pointer to a copy the caller owns. Returns follow the same split, with large
/// results written through a hidden first pointer argument.
/// </summary>
public static class Win64Abi
{
    public static bool IsRegisterSizedStruct(TypeSymbol type) =>
        type is StructTypeSymbol && type.Size is 1 or 2 or 4 or 8;

    public static ArgInfo ClassifyArgument(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type is not StructTypeSymbol)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        return IsRegisterSizedStruct(type)
            ? new ArgInfo(PassStyle.CoerceToInteger, $"i{type.Size * 8}", type)
            : new ArgInfo(PassStyle.Indirect, "ptr", type);
    }

    public static ArgInfo ClassifyReturn(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type.IsVoid()) return new ArgInfo(PassStyle.Direct, "void", type);
        return ClassifyArgument(type, llvmTypeOf);
    }
}
