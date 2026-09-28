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

using Stainless.Binding;
using Stainless.Source;

namespace Stainless.Emit;

/// <summary>
/// Built-in functions written inline because no LLVM intrinsic answers them.
/// See <see cref="Builtins.InlineIntrinsics"/>.
/// </summary>
public sealed partial class LlvmEmitter
{
    private bool TryEmitInlineIntrinsic(BoundCall call, out Val result)
    {
        result = Val.Void;
        if (call.Function.RuntimeSymbol is not { } symbol || !Builtins.InlineIntrinsics.Contains(symbol))
            return false;

        var arguments = call.Arguments.Select(EmitExpression).ToList();

        switch (symbol)
        {
            case Builtins.MultiplyHighIntrinsic:
            {
                // Every target lowers this without a library call, including
                // 32-bit x86, which expands it into four 32-bit multiplies.
                string left = Emit("i128", $"zext i64 {arguments[0].Ref} to i128");
                string right = Emit("i128", $"zext i64 {arguments[1].Ref} to i128");
                string product = Emit("i128", $"mul i128 {left}, {right}");
                string high = Emit("i128", $"lshr i128 {product}, 64");
                result = new Val(Emit("i64", $"trunc i128 {high} to i64"), "i64", call.Function.ReturnType);
                return true;
            }

            case Builtins.OpaqueIntrinsic32:
            case Builtins.OpaqueIntrinsic64:
            {
                string type = symbol == Builtins.OpaqueIntrinsic32 ? "i32" : "i64";
                string value = arguments[0].Ref;

                // A 32-bit target has no register an i64 fits in, so each half
                // goes through one of its own.
                if (type == "i64" && TargetPlatform.Current.PointerWidth == 4)
                {
                    string low = OpaqueRegister("i32", Emit("i32", $"trunc i64 {value} to i32"));
                    string shifted = Emit("i64", $"lshr i64 {value}, 32");
                    string high = OpaqueRegister("i32", Emit("i32", $"trunc i64 {shifted} to i32"));
                    string wideLow = Emit("i64", $"zext i32 {low} to i64");
                    string wideHigh = Emit("i64", $"zext i32 {high} to i64");
                    string placed = Emit("i64", $"shl i64 {wideHigh}, 32");
                    result = new Val(Emit("i64", $"or i64 {placed}, {wideLow}"), "i64", call.Function.ReturnType);
                    return true;
                }

                result = new Val(OpaqueRegister(type, value), type, call.Function.ReturnType);
                return true;
            }

            default:
                throw new InternalCompilerError($"no inline form for '{symbol}'");
        }
    }

    /// <summary>The value through an empty asm block that ties its output to its input register.</summary>
    private string OpaqueRegister(string type, string value) =>
        Emit(type, $"call {type} asm \"\", \"=r,0\"({type} {value})");
}
