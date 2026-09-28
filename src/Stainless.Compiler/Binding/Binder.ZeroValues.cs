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

using Stainless.Source;

namespace Stainless.Binding;

/// <summary>
/// The rule that a type whose zero would hold a null in a never-null
/// reference has no zero value (§2.16 of the specification): no
/// <c>default</c> of one, no local of one read before it is assigned, no
/// <c>new T[n]</c> of one, and no constructor that can leave a field of one
/// unwritten.
///
/// A generic body is judged per instantiation, as everything in a template
/// is, so <c>default(T)</c> is an error in <c>Box&lt;String&gt;</c> and
/// nothing in <c>Box&lt;int&gt;</c>. <c>Standard.Unchecked</c> is the one
/// module the rule does not reach: its two functions are how a collection
/// holds room for elements it does not have yet.
/// </summary>
public sealed partial class Binder
{
    private const string UncheckedModuleName = "Standard.Unchecked";

    /// <summary>Whether the body being bound is one the rule does not reach.</summary>
    private bool InUncheckedModule => _context.Function?.ModuleName == UncheckedModuleName;

    /// <summary>
    /// <c>default(T)</c>, or a bare <c>default</c> going to
    /// <paramref name="type"/>.
    /// </summary>
    private void CheckDefaultHasZero(SourceSpan span, TypeSymbol type)
    {
        if (InUncheckedModule || ZeroValues.FindNullInZero(type) is not { } found) return;

        ReportNoZeroValue("SL0810", span,
            $"'{type.Name}' has no zero value: {ExplainNullInZero(found)}, so 'default' would " +
            "hand out a null where the type says there is none. Build the value with a " +
            "constructor, or make the reference nullable",
            type);
    }

    /// <summary>
    /// <c>new T[n]</c>, whose elements start as the zero of <c>T</c>. A length
    /// that is the constant zero makes no element to be one.
    /// </summary>
    private void CheckArrayElementHasZero(
        SourceSpan span, TypeSymbol element, BoundExpression length)
    {
        if (InUncheckedModule || FoldSwitchLabel(length) == 0) return;
        if (ZeroValues.FindNullInZero(element) is not { } found) return;

        ReportNoZeroValue("SL0812", span,
            $"'new {element.Name}[n]' would start every element as a zero, and " +
            $"'{element.Name}' has none: {ExplainNullInZero(found)}. Write the elements out, " +
            "as '[a, b, c]', make them with 'Array.Create(n, (i) => ...)', or collect them " +
            "in a 'List'",
            element);
    }

    // ------------------------------------------------------------ locals

    /// <summary>Locals declared with no value and no zero value, waiting for their body.</summary>
    private readonly List<LocalSymbol> _unsetLocals = [];

    /// <summary>A local declared with no value, judged once its body has been bound.</summary>
    private void NoteUnsetLocal(LocalSymbol local)
    {
        if (local.Type.IsError() || ZeroValues.HasZeroValue(local.Type)) return;
        Remember(_unsetLocals, local);
    }

    /// <summary>
    /// Every unset local this body declares is read only once each slot of it
    /// that has no zero value has been written, on every path: C#'s definite
    /// assignment, a field at a time. The walk covers the block that declares
    /// the local, which is everywhere its name can be read.
    /// </summary>
    private void SettleUnsetLocals(BoundBlock body)
    {
        if (_unsetLocals.Count == 0) return;

        // A `goto` reaches a statement from where the walk does not look, so
        // it stands down, as it does for `out`.
        bool jumps = _context.Jumps.Labels.Count > 0 || _context.Jumps.Jumps.Count > 0;

        foreach (var local in _unsetLocals.ToList())
        {
            if (DeclaringBlockFinder.Find(body, local) is not { } block) continue;
            _unsetLocals.Remove(local);
            if (jumps) continue;

            var reported = new HashSet<int>();
            foreach (var slot in SlotsWithoutZero(local.Type))
                Assigns(block, new UnsetLocalPlace(this, local, slot, reported), false);
        }
    }

    /// <summary>
    /// The paths through a type's fields to each slot that has no zero value:
    /// a struct's or a tuple's by field, and anything else as one slot.
    /// </summary>
    private static List<FieldSymbol[]> SlotsWithoutZero(TypeSymbol type)
    {
        var slots = new List<FieldSymbol[]>();
        CollectSlotsWithoutZero(type, [], slots, []);
        return slots;
    }

    private static void CollectSlotsWithoutZero(
        TypeSymbol type, List<FieldSymbol> path, List<FieldSymbol[]> into,
        HashSet<TypeSymbol> walked)
    {
        if (type is not StructTypeSymbol composite ||
            type is VariantTypeSymbol or ClosureTypeSymbol or UnionTypeSymbol ||
            !walked.Add(type))
        {
            into.Add([.. path]);
            return;
        }

        foreach (var field in composite.Fields.Where(f => !ZeroValues.HasZeroValue(f.Type)))
        {
            path.Add(field);
            CollectSlotsWithoutZero(field.Type, path, into, walked);
            path.RemoveAt(path.Count - 1);
        }

        walked.Remove(type);
    }

    private void ReportUnsetLocalRead(LocalSymbol local, FieldSymbol[] slot, SourceSpan span)
    {
        var slotType = slot.Length == 0 ? local.Type : slot[^1].Type;
        var found = ZeroValues.FindNullInZero(slotType)!.Value;
        string what = slot.Length == 0
            ? $"'{local.Name}' is read here before it has been assigned"
            : $"'{local.Name}' is read here before '{local.Name}." +
              $"{string.Join('.', slot.Select(f => f.Name))}' has been assigned";

        ReportNoZeroValue("SL0811", span,
            $"{what}, and '{slotType.Name}' has no zero value: {ExplainNullInZero(found)}. " +
            "Assign it on every path before this, or give it a value where it is declared",
            local.Type);
    }

    /// <summary>
    /// One slot of a local declared without a value, as definite assignment
    /// asks about it.
    /// </summary>
    private sealed class UnsetLocalPlace(
        Binder binder, LocalSymbol local, FieldSymbol[] slot, HashSet<int> reported) : AssignedPlace
    {
        public override bool ChecksReads => true;

        public override bool IsDeclaredBy(LocalSymbol declared) => ReferenceEquals(declared, local);

        // Writing the local, or a field on the way to the slot, writes the slot.
        public override bool IsPlace(BoundExpression expression) =>
            PathOf(expression) is { } path && IsOnTheWay(path);

        // So does an automatic property's setter, which writes its storage.
        public override bool IsWrittenBy(BoundExpression write) => write switch
        {
            BoundPropertyAssignment
                {
                    Property.BackingField: { } backing, Receiver: { } receiver,
                } => PathOf(receiver) is { } path && IsOnTheWay([.. path, backing]),
            BoundCall
                {
                    Function.Accessor.BackingField: { } backing, Receiver: { } receiver,
                } call => call.Function.ReturnType.IsVoid() && PathOf(receiver) is { } path &&
                          IsOnTheWay([.. path, backing]),
            _ => false,
        };

        public override PlaceUse UseOf(BoundExpression expression)
        {
            if (PathOf(expression) is not { } path) return PlaceUse.Other;
            return IsOnTheWay(path) || GoesThrough(path) ? PlaceUse.Read : PlaceUse.Beside;
        }

        public override void ReportRead(SourceSpan span)
        {
            if (reported.Add(span.Start))
                binder.ReportUnsetLocalRead(local, slot, span);
        }

        public override void ReportReturn(SourceSpan span)
        {
        }

        public override void ReportEarlyReturn(SourceSpan span)
        {
        }

        /// <summary>
        /// The fields from the local to this expression, or null when it is not
        /// one of them.
        /// </summary>
        private List<FieldSymbol>? PathOf(BoundExpression expression)
        {
            switch (expression)
            {
                case BoundLocalAccess named when ReferenceEquals(named.Local, local):
                    return [];

                case BoundFieldAccess { Receiver: { } receiver } access
                    when PathOf(receiver) is { } path:
                    path.Add(access.Field);
                    return path;

                case BoundAddressOf { FromOutKeyword: false } address:
                    return PathOf(address.Operand);

                case BoundDereference dereference:
                    return PathOf(dereference.Operand);

                default:
                    return null;
            }
        }

        /// <summary>The path is the slot or leads to it.</summary>
        private bool IsOnTheWay(List<FieldSymbol> path) =>
            path.Count <= slot.Length &&
            path.Select((f, i) => ReferenceEquals(f, slot[i])).All(b => b);

        /// <summary>The path passes through the slot to something it holds.</summary>
        private bool GoesThrough(List<FieldSymbol> path) =>
            path.Count > slot.Length &&
            slot.Select((f, i) => ReferenceEquals(f, path[i])).All(b => b);
    }

    /// <summary>The block whose statements declare a local, however deep in a body it is.</summary>
    private sealed class DeclaringBlockFinder(LocalSymbol local) : BoundTreeWalker
    {
        private BoundBlock? _found;

        public static BoundBlock? Find(BoundStatement body, LocalSymbol local)
        {
            var finder = new DeclaringBlockFinder(local);
            finder.Visit(body);
            return finder._found;
        }

        public override void Visit(BoundStatement? statement)
        {
            if (_found is not null) return;

            if (statement is BoundBlock block &&
                block.Statements.Any(s => s is BoundLocalDeclaration declared &&
                                          ReferenceEquals(declared.Local, local)))
            {
                _found = block;
                return;
            }

            base.Visit(statement);
        }
    }

    // ------------------------------------------------------------ fields

    /// <summary>
    /// Every constructor writes each field whose type has no zero value, on
    /// every path, unless an initializer, <c>required</c> or <c>: this(...)</c>
    /// already does. Asked once every body is bound, because a call to one of
    /// the type's own private methods is followed into its body.
    /// </summary>
    private void CheckConstructorsAssignFields()
    {
        _boundBodies = [];
        foreach (var bound in _functions)
            _boundBodies[bound.Symbol] = bound.Body;

        foreach (var bound in _functions.ToList())
        {
            if (bound.Symbol.Kind != FunctionKind.Constructor) continue;
            if (bound.Symbol.ContainingType is not { } type) continue;
            if (_delegated.ContainsKey(bound.Symbol)) continue;
            if (JumpFinder.Contains(bound.Body)) continue;

            // A field of a struct with no zero value may be written whole, or
            // a field at a time as a local is.
            foreach (var field in FieldsNeedingValues(type, bound.Symbol.SetsRequiredMembers))
            {
                foreach (var slot in SlotsWithoutZero(field.Type))
                {
                    var place = new ConstructorFieldPlace(this, [field, .. slot], bound.Symbol);
                    if (!Assigns(bound.Body, place, false) && EndIsReachable(bound.Body))
                        place.ReportReturn(bound.Symbol.Span);
                }
            }
        }

        _boundBodies = null;
        _helperWrites.Clear();
    }

    /// <summary>Each bound body by its function, while constructors are being checked.</summary>
    private Dictionary<FunctionSymbol, BoundBlock>? _boundBodies;

    /// <summary>Whether a helper writes a field on every path, as far as asked.</summary>
    private readonly Dictionary<(FunctionSymbol, string), bool> _helperWrites = [];

    /// <summary>
    /// Whether a call to one of the type's own private methods writes the
    /// field on every path through it. A private method has one body, so this
    /// is exact; a method that is still being asked about, because it calls
    /// itself, answers no.
    /// </summary>
    private bool HelperWrites(FunctionSymbol helper, FieldSymbol[] path)
    {
        var key = (helper, string.Join('.', path.Select(f => f.Name)));
        if (_helperWrites.TryGetValue(key, out bool known)) return known;
        if (_boundBodies?.GetValueOrDefault(helper) is not { } body) return false;

        _helperWrites[key] = false;
        var place = new ConstructorFieldPlace(this, path, owner: null);
        bool writes = Assigns(body, place, false) && !place.LeftEarly;
        _helperWrites[key] = writes;
        return writes;
    }

    /// <summary>A class with no constructor at all: nothing writes any field it has.</summary>
    private void CheckClassesWithoutConstructors()
    {
        foreach (var type in _classes.ToList())
        {
            // A lambda's environment is filled by the code that makes it.
            if (type.Constructors.Count > 0 || type.Span is not { } span ||
                _generated.Contains(type))
                continue;

            foreach (var field in FieldsNeedingValues(type, setsRequired: false))
            {
                var found = FindNullInField(type, field);
                ReportNoZeroValue("SL0813", span,
                    $"'{type.Name}' has no constructor, so nothing gives '{field.Name}' a value, " +
                    $"and '{field.Type.Name}' has no zero value: " +
                    $"{ExplainNullInZero(found)}. Give the field an initializer, mark it " +
                    "'required', or write a constructor that assigns it",
                    field.Type);
            }
        }
    }

    /// <summary>
    /// The fields of a type a constructor has to write: those whose type has
    /// no zero value, less those an initializer writes, those a <c>new</c> has
    /// to name, and an event's storage, which the allocation fills.
    /// </summary>
    /// <param name="setsRequired">
    /// For a <c>[SetsRequiredMembers]</c> constructor, which takes back what
    /// <c>required</c> gave to every <c>new</c>.
    /// </param>
    private static IEnumerable<FieldSymbol> FieldsNeedingValues(
        NamedTypeSymbol type, bool setsRequired)
    {
        var required = type.Properties
            .Where(p => p.IsRequired && p.BackingField is not null)
            .Select(p => p.BackingField!)
            .ToHashSet();
        var events = type.Events.Select(e => e.BackingField).OfType<FieldSymbol>().ToHashSet();

        return type.Fields.Where(f =>
            f.InitializerSyntax is null && !events.Contains(f) && !f.IsFilledOnFirstUse &&
            (setsRequired || !f.IsRequired && !required.Contains(f)) &&
            !f.Type.IsError() && !ZeroValues.HasZeroValue(f.Type));
    }

    /// <summary>
    /// A field a constructor has to write, or one slot of a struct field, as
    /// definite assignment asks about it.
    /// </summary>
    /// <param name="path">The field, then the fields inside it on the way to the slot.</param>
    /// <param name="owner">
    /// The constructor, or null when a helper is being asked on its behalf.
    /// </param>
    private sealed class ConstructorFieldPlace(
        Binder binder, FieldSymbol[] path, FunctionSymbol? owner) : AssignedPlace
    {
        /// <summary>A path through a helper that returned before writing the field.</summary>
        public bool LeftEarly { get; private set; }

        private FieldSymbol Field => path[0];

        // Writing the field, or a field inside it on the way to the slot.
        public override bool IsPlace(BoundExpression expression) =>
            PathOf(expression) is { } written && written.Count <= path.Length &&
            written.Select((f, i) => ReferenceEquals(f, path[i])).All(b => b);

        public override bool IsWrittenBy(BoundExpression write) => write switch
        {
            BoundPropertyAssignment assigned =>
                path.Length == 1 && ReferenceEquals(assigned.Property.BackingField, Field) &&
                IsSelf(assigned.Receiver),
            BoundCall { Function.Accessor: { BackingField: { } backing } } call =>
                path.Length == 1 && ReferenceEquals(backing, Field) &&
                call.Function.ReturnType.IsVoid() && IsSelf(call.Receiver),
            BoundCall call => IsHelper(call.Function) && IsSelf(call.Receiver) &&
                              binder.HelperWrites(call.Function, path),
            _ => false,
        };

        public override void ReportReturn(SourceSpan span)
        {
            if (owner is null)
            {
                LeftEarly = true;
                return;
            }

            var slot = path[^1];
            var found = FindNullInField(slot.ContainingType, slot);
            string named = string.Join('.', path.Select(f => f.Name));
            binder.ReportNoZeroValue("SL0813", span,
                $"'{Field.ContainingType.Name}' can be made without '{named}' being written, " +
                $"and '{slot.Type.Name}' has no zero value: {ExplainNullInZero(found)}. Assign " +
                "it on every path through the constructor, or give it an initializer",
                slot.Type);
        }

        public override void ReportEarlyReturn(SourceSpan span) => ReportReturn(span);

        /// <summary>
        /// The fields from this object to the expression, or null when it is
        /// not one of them.
        /// </summary>
        private static List<FieldSymbol>? PathOf(BoundExpression expression) => expression switch
        {
            BoundFieldAccess { Receiver: { } receiver } access when IsSelf(receiver) =>
                [access.Field],
            BoundFieldAccess { Receiver: { } receiver } access when PathOf(receiver) is { } inner =>
                [.. inner, access.Field],
            _ => null,
        };

        /// <summary>
        /// A method of the field's own type with one body: not public,
        /// protected or dispatched.
        /// </summary>
        private bool IsHelper(FunctionSymbol method) =>
            method.Kind == FunctionKind.Method && !method.IsStatic && !method.IsPublic &&
            !method.IsProtected && !method.IsVirtual && method.Body is not null &&
            ReferenceEquals(method.ContainingType, Field.ContainingType);

        private static bool IsSelf(BoundExpression? receiver) => receiver switch
        {
            BoundThis => true,
            BoundParameterAccess { Parameter.IsThis: true } => true,
            BoundDereference inner => IsSelf(inner.Operand),
            BoundAddressOf inner => IsSelf(inner.Operand),
            BoundConversion inner => IsSelf(inner.Operand),
            _ => false,
        };
    }

    /// <summary>Whether a body holds a label or a jump to one.</summary>
    private sealed class JumpFinder : BoundTreeWalker
    {
        private bool _found;

        public static bool Contains(BoundStatement body)
        {
            var finder = new JumpFinder();
            finder.Visit(body);
            return finder._found;
        }

        public override void Visit(BoundStatement? statement)
        {
            if (_found) return;

            if (statement is BoundLabel or BoundGoto)
            {
                _found = true;
                return;
            }

            base.Visit(statement);
        }
    }

    // ------------------------------------------------------------ statics

    /// <summary>
    /// Whether a static property with no <c>= value</c> starts as a zero its
    /// type does not have. That is reported, unless its accessors read the
    /// storage only to fill it on first use; either way there is nothing to
    /// bind.
    /// </summary>
    private bool StaticPropertyStartsWithoutValue(
        StaticSymbol symbol, Syntax.StaticDeclSyntax declaration)
    {
        if (!symbol.IsPropertyStorage) return false;
        if (declaration.Value is not Syntax.DefaultSyntax { Type: null } made ||
            made.Span != declaration.Span)
            return false;
        if (ZeroValues.FindNullInZero(symbol.Type) is not { } found) return false;

        if (!symbol.IsFilledOnFirstUse)
            ReportNoZeroValue("SL0814", declaration.Span,
                $"'{symbol.DisplayName}' has no '= value', so it would start as the zero of " +
                $"'{symbol.Type.Name}', which has none: {ExplainNullInZero(found)}. Give it an " +
                "initializer",
                symbol.Type);
        return true;
    }

    // ------------------------------------------------------------ saying so

    /// <summary>Where a field's zero breaks a promise, named from the type that holds it.</summary>
    private static (string Path, TypeSymbol Slot) FindNullInField(
        NamedTypeSymbol type, FieldSymbol field)
    {
        var found = ZeroValues.FindNullInZero(field.Type)!.Value;
        return ($"{type.Name}.{field.Name}{found.Path[field.Type.Name.Length..]}", found.Slot);
    }

    private static string ExplainNullInZero((string Path, TypeSymbol Slot) found)
    {
        bool itself = found.Path == found.Slot.Name;
        return found.Slot is ClosureTypeSymbol
            ? itself
                ? $"the zero of the closure '{found.Slot.Name}' has no function to call"
                : $"'{found.Path}' is the closure '{found.Slot.Name}', whose zero has no " +
                  "function to call"
            : itself
                ? $"a '{found.Slot.Name}' is never null"
                : $"'{found.Path}' is a '{found.Slot.Name}', which is never null";
    }

    private void ReportNoZeroValue(
        string code, SourceSpan span, string message, TypeSymbol about) =>
        diagnostics.Error(code, span, message, about);
}
