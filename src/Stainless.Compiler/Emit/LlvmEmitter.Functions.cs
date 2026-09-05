// Stainless - an experimental systems language.
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

using System.Globalization;
using System.Text;
using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Function definitions: the signature, the entry block, the parameters
/// and the prologue that gives each one a slot.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ functions

    private void EmitFunction(BoundFunction function)
    {
        var symbol = function.Symbol;
        ResetFunctionState();

        var returnInfo = ClassifyResult(symbol.ReturnType);
        var parameterInfos = symbol.Parameters
            .Select(p => (Parameter: p, Info: ClassifyParameter(p)))
            .ToList();

        var declaredParameters = new List<string>();
        var incomingNames = new Dictionary<ParameterSymbol, string>();

        if (returnInfo.Style == PassStyle.Indirect)
        {
            _sretSlot = "%sret.result";
            declaredParameters.Add(
                $"ptr sret({StructName((StructTypeSymbol)symbol.ReturnType)}) {_sretSlot}");
        }

        foreach (var (parameter, info) in parameterInfos)
        {
            string name = "%arg." + SanitizeIdentifier(parameter.Name);
            incomingNames[parameter] = name;

            var spellings = Declared(info).ToList();
            if (spellings.Count == 1)
            {
                declaredParameters.Add($"{spellings[0]} {name}");
                continue;
            }

            // Two registers, two names. The body puts them back together.
            for (int piece = 0; piece < spellings.Count; piece++)
                declaredParameters.Add($"{spellings[piece]} {name}.{piece}");
        }

        _returnInfo = returnInfo;
        _nextTemp = 0;

        string returnType = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
        // `public` deliberately does not export: it says which modules may see
        // this, and a C library's surface is stated once with `export "C"`.
        // Asking for module metadata says something different — that another
        // Stainless compilation will bind against this — and that surface is
        // exactly the public declarations the metadata describes.
        bool exported = symbol.Linkage is LinkageKind.ExportC or LinkageKind.ExportCpp
            || (forStainlessConsumers && symbol.Linkage == LinkageKind.Stainless
                && !symbol.IsExternal
                && (symbol.IsPublic || symbol.Kind == FunctionKind.Constructor)
                && symbol.ContainingType is null or { IsPublic: true }
                && symbol.TypeArguments.Count == 0);
        string linkage = exported || symbol.IsPublic ? "" : "internal ";

        // Windows exports only what a binary marks, so a library's declared API
        // has to say so here. Elsewhere default visibility already exports it.
        string storage = forSharedLibrary
                         && exported
                         && OperatingSystem.IsWindows()
            ? "dllexport "
            : "";

        _debugScope = debug?.Subprogram(symbol, symbol.MangledName);
        _debugLocation = _debugScope is { } opening && debug is not null
            ? debug.Location(symbol.Span, opening)
            : null;

        _module.AppendLine(
            $"define {linkage}{storage}{returnType} {Symbol(symbol)}" +
            $"({string.Join(", ", declaredParameters)})" +
            (_debugScope is { } attached ? $" !dbg !{attached}" : "") + " {");
        _body.Clear();
        _blockTerminated = false;

        PushScope();

        // Give every parameter a stack slot so it can be assigned like a local.
        foreach (var (parameter, info) in parameterInfos)
        {
            string incoming = incomingNames[parameter];

            // The caller's storage, so there is nothing to copy and nothing to
            // own: reads and writes go straight through the pointer, which is
            // already the shape every other parameter's slot has. A `ref` is
            // deliberately not adopted the way a written value parameter is —
            // writing to the caller's variable is the point of it.
            if (parameter.IsByReference)
            {
                _parameterSlots[parameter] = incoming;
                continue;
            }

            if (info.Style == PassStyle.Indirect)
            {
                // byval already points at a private copy owned by this call.
                _parameterSlots[parameter] = incoming;
                AdoptWrittenParameter(parameter, incoming);
                continue;
            }

            if (info.Style == PassStyle.Coerce)
            {
                // Back into one object: each register is stored at the eight
                // bytes it covered, which is exactly where the fields expect it.
                string slot = Alloca(LlvmTypeOf(parameter.Type), parameter.Name);

                for (int piece = 0; piece < info.Pieces.Count; piece++)
                {
                    string value = info.Pieces.Count == 1 ? incoming : $"{incoming}.{piece}";
                    Line($"store {info.Pieces[piece]} {value}, ptr {PieceAddress(slot, piece)}");
                }

                _parameterSlots[parameter] = slot;
                AdoptWrittenParameter(parameter, slot);
                continue;
            }

            string plain = Alloca(info.LlvmType, parameter.Name);
            Line($"store {info.LlvmType} {incoming}, ptr {plain}");
            _parameterSlots[parameter] = plain;
            AdoptWrittenParameter(parameter, plain);
        }

        DescribeParameters(symbol);

        EmitStatement(function.Body);

        // Fall off the end: void returns implicitly, everything else was already
        // checked by the binder, so this is only reached for unreachable tails.
        if (!_blockTerminated)
        {
            ReleaseScopes(0);
            Terminator(returnInfo.Style switch
            {
                PassStyle.Indirect => "ret void",
                _ when symbol.ReturnType.IsVoid() => "ret void",
                _ => $"ret {returnInfo.LlvmType} {ZeroOf(returnInfo.LlvmType)}",
            });
        }

        PopScopeWithoutRelease();

        _module.AppendLine("entry:");
        _module.Append(_entryAllocas);
        _module.Append(_body);
        _module.AppendLine("}");
        _module.AppendLine();
    }


    /// <summary>
    /// Names the parameters for a debugger, in the order they were written.
    ///
    /// A parameter has no span of its own, so all of them sit on the line the
    /// function was declared on. That is where a debugger shows arguments
    /// anyway: on entry, before the body has run.
    /// </summary>
    private void DescribeParameters(FunctionSymbol symbol)
    {
        if (debug is null || _debugScope is not { } scope) return;

        int index = 0;
        foreach (var parameter in symbol.Parameters)
        {
            if (!_parameterSlots.TryGetValue(parameter, out string? slot)) { index++; continue; }

            DeclareVariable(slot, debug.Parameter(
                parameter.IsThis ? "this" : parameter.Name,
                parameter.Type, symbol.Span, scope, index++));
        }
    }
}
