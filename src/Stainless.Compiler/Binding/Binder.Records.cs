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

using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// The one member of a record that cannot be written as source: the copy
/// <c>with</c> starts from.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// <c>Root $Clone()</c>: dispatched, so that a derived record reached
    /// through its base is copied whole. It answers with the root record's
    /// type so that every level overrides the one signature.
    /// </summary>
    private void DeclareRecordClone(ClassTypeSymbol record)
    {
        var root = record;
        while (root.BaseClass is { RecordParameters.Count: > 0 } above) root = above;

        var clone = new FunctionSymbol
        {
            Name = Records.CloneName,
            ModuleName = record.ModuleName,
            ReturnType = root,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = record,
            Span = record.Span ?? default,
            IsPublic = true,
            IsVirtual = true,
            IsOverride = !ReferenceEquals(root, record),
            IsRecordClone = true,
        };

        clone.Parameters.Add(new ParameterSymbol("this", record, 0) { IsThis = true });
        record.Methods.Add(clone);
        if (_modules.TryGetValue(record.ModuleName, out var module)) module.Functions.Add(clone);
    }

    /// <summary>
    /// A new object of the record's own type, with every field of it and of
    /// its bases copied across -- what C#'s copy constructor does. No
    /// constructor runs: the values are the ones the original already has.
    /// </summary>
    private void BindRecordClone(FunctionSymbol clone)
    {
        if (!_boundFunctions.Add(clone)) return;

        var span = clone.Span;
        var record = (ClassTypeSymbol)clone.ContainingType!;
        var self = Receiver(span, clone.Parameters[0]);

        var made = new LocalSymbol("made", record, isConst: false);
        var copy = new BoundLocalAccess(span, made);

        var statements = new List<BoundStatement>
        {
            new BoundLocalDeclaration(span, made, new BoundNew(span, record, constructor: null, [])),
        };

        for (ClassTypeSymbol? level = record; level is not null; level = level.BaseClass)
            foreach (var field in level.Fields)
                statements.Add(new BoundExpressionStatement(span, new BoundAssignment(span,
                    new BoundFieldAccess(span, copy, field),
                    new BoundFieldAccess(span, self, field))));

        BoundExpression answer = ReferenceEquals(clone.ReturnType, record)
            ? copy
            : new BoundConversion(span, clone.ReturnType, copy, ConversionKind.Upcast);
        statements.Add(new BoundReturn(span, answer));

        var block = new BoundBlock(span, statements);
        block.Locals.Add(made);
        _functions.Add(new BoundFunction(clone, block));
    }

    /// <summary>The record's <c>$Clone</c>, its own or inherited.</summary>
    private static FunctionSymbol? RecordClone(ClassTypeSymbol record)
    {
        for (ClassTypeSymbol? level = record; level is not null; level = level.BaseClass)
            if (level.Methods.FirstOrDefault(m => m.IsRecordClone) is { } clone)
                return clone;

        return null;
    }
}
