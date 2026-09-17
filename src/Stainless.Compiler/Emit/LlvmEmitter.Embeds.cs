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

namespace Stainless.Emit;

/// <summary>
/// Embedded files: the objects <c>embed</c> names, written as assembly.
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>
    /// The IR name of an embedded file's object.
    ///
    /// The <c>\01</c> tells LLVM to write the name exactly as it is. Without
    /// it i686 Windows puts the C underscore in front, and the label the
    /// assembly defines would no longer be the symbol the IR refers to.
    /// </summary>
    private static string EmbedSymbol(EmbeddedFile file) => $"@\"\\01{file.Label}\"";

    /// <summary>
    /// Every embedded file, as <c>module asm</c> that defines the object and a
    /// declaration the rest of the module refers to it through.
    ///
    /// <para>
    /// <b>The bytes are assembly and not an IR global.</b> An IR global can be
    /// given a section but not a section's flags, and on ELF one in a section
    /// a directive also named becomes a second section of the same name, with
    /// the flags LLVM chose. <see cref="EmbeddedFile.Assembly"/> has the rest.
    /// </para>
    ///
    /// <para>
    /// <b>The declaration is <c>external hidden</c>, and a <c>global</c>, not a
    /// <c>constant</c>.</b> Hidden, because the definition is in this very
    /// object: the code then reaches it directly rather than through a table
    /// of addresses. Not constant, even for read-only data, because a
    /// constant is a promise to the optimiser that nothing writes, and a
    /// program that writes to a read-only embed should get the fault the
    /// section's permissions give it rather than having the store deleted as
    /// something that cannot happen. Its type is the whole object, header and
    /// bytes, so the optimiser knows how large it is.
    /// </para>
    /// </summary>
    private void EmbeddedData(BoundProgram program)
    {
        if (program.Embeds.Count == 0) return;

        var target = TargetPlatform.Current;

        _module.AppendLine();
        foreach (var file in program.Embeds)
        {
            foreach (string line in file.Assembly(target))
                _module.AppendLine($"module asm \"{EmbeddedFile.IrString(line)}\"");

            _module.AppendLine(
                $"{EmbedSymbol(file)} = external hidden global " +
                $"{{ {Word}, {Word}, ptr, {Word}, [{file.Length} x i8] }}, " +
                $"align {target.PointerWidth}");
        }
    }
}
