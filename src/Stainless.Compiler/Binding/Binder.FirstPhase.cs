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
/// A constructor's first phase: what it does before the object can be reached.
///
/// <para>
/// <b>An object is reachable only once every field it has holds a value</b>,
/// as Swift's two-phase initialization has it. Until then a constructor may
/// give this class's own fields their values and read back the ones it has
/// given, and nothing else: no method, no property, no <c>this</c> handed on,
/// and for a derived class no base, which is a method run over the object
/// like any other. The base's constructor runs after the derived fields are
/// set, so a virtual method it calls finds them set.
/// </para>
///
/// <para>
/// The first phase ends at an explicit <c>base(...)</c>; or, where the base is
/// left implicit, at the first statement that reaches the object or returns,
/// which is where the implicit base is put; or, for a class with no base and
/// for a struct, at that same statement. Every field with no zero value MUST
/// have its value by then.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>Each constructor's first phase, and where it ends.</summary>
    private readonly Dictionary<FunctionSymbol, (BoundBlock Phase, SourceSpan End, bool Explicit)> _firstPhases = [];

    /// <summary>The <c>base(...)</c> written in the constructor being bound.</summary>
    private BoundExpression? _writtenBaseCall;

    /// <summary>The <c>base()</c> the compiler put in the constructor being bound.</summary>
    private BoundStatement? _implicitBaseCall;

    /// <summary>
    /// The index of the first statement that reaches the object or returns,
    /// or the count when none does.
    /// </summary>
    private static int FindFirstReach(FunctionSymbol constructor, IReadOnlyList<BoundStatement> statements)
    {
        for (int i = 0; i < statements.Count; i++)
        {
            var finder = new ObjectReachFinder(constructor);
            finder.Visit(statements[i]);
            if (finder.Reach is not null || finder.Returns)
                return i;
        }
        return statements.Count;
    }

    /// <summary>
    /// Moves a <c>: base(...)</c> written after the parameters to where the
    /// first phase ends, as the implicit base is put: the clause names which
    /// base constructor to run, and the body before the first statement that
    /// reaches the object gives the fields their values.
    /// </summary>
    private BoundBlock WithClauseBaseAtFirstReach(FunctionSymbol constructor, BoundBlock body)
    {
        // Objective-C's `[super init...]` answers the object, which may not be
        // the one it was sent to, so it stays first.
        if (constructor.ContainingType is ClassTypeSymbol { IsObjC: true }) return body;

        var statements = body.Statements.ToList();
        int at = statements.FindIndex(s =>
            s is BoundExpressionStatement { Expression: var call } && ReferenceEquals(call, _writtenBaseCall));
        if (at < 0) return body;

        var chain = statements[at];
        statements.RemoveAt(at);
        int end = FindFirstReach(constructor, statements);
        statements.Insert(end, chain);
        return new BoundBlock(body.Span, statements);
    }

    /// <summary>
    /// Records where a constructor's first phase ends, and refuses what a
    /// written <c>base(...)</c> has before it that reaches the object.
    /// </summary>
    private void RecordFirstPhase(FunctionSymbol constructor, BoundBlock body)
    {
        var written = _writtenBaseCall;
        var implicitCall = _implicitBaseCall;
        _writtenBaseCall = null;
        _implicitBaseCall = null;

        if (constructor.ContainingType is not { } type) return;
        if (type is ClassTypeSymbol { IsObjC: true }) return;
        if (_delegated.ContainsKey(constructor)) return;

        var statements = body.Statements;
        int end;
        if (written is not null)
        {
            end = -1;
            for (int i = 0; i < statements.Count && end < 0; i++)
                if (statements[i] is BoundExpressionStatement { Expression: var call } &&
                    ReferenceEquals(call, written))
                    end = i;
            if (end < 0) return;

            for (int i = 0; i < end; i++)
                ReportReachBeforeBase(constructor, statements[i]);
            if (written is BoundCall { Arguments: var arguments })
                foreach (var argument in arguments)
                    ReportReachBeforeBase(constructor, argument);
        }
        else if (implicitCall is not null)
        {
            end = statements.ToList().IndexOf(implicitCall);
            if (end < 0) return;
        }
        else
        {
            end = FindFirstReach(constructor, statements);
        }

        var phase = new BoundBlock(body.Span, [.. statements.Take(end)]);
        var span = end < statements.Count ? statements[end].Span : constructor.Span;
        _firstPhases[constructor] = (phase, span, written is not null);
    }

    private void ReportReachBeforeBase(FunctionSymbol constructor, object node)
    {
        var finder = new ObjectReachFinder(constructor);
        if (node is BoundStatement statement) finder.Visit(statement);
        else finder.Visit((BoundExpression)node);

        if (finder.Reach is { } reach)
            diagnostics.Report(Codes.ObjectReachedBeforeBase, reach,
                "this reaches the object before 'base(...)' has run; until then a constructor " +
                "may only give this class's own fields their values and read them back, " +
                "because the object is not whole");
        else if (finder.ReturnSpan is { } returned)
            diagnostics.Report(Codes.ObjectReachedBeforeBase, returned,
                "this returns before 'base(...)' has run, which would leave the base unbuilt");
    }

    /// <summary>
    /// Every field with no zero value has its value by the end of the first
    /// phase, and none is read before it has one.
    /// </summary>
    private void CheckFirstPhase(FunctionSymbol constructor, BoundBlock body)
    {
        if (!_firstPhases.TryGetValue(constructor, out var first)) return;
        var type = constructor.ContainingType!;

        foreach (var field in FieldsNeedingValues(type, constructor.SetsRequiredMembers))
        {
            foreach (var slot in SlotsWithoutZero(field.Type))
            {
                var path = new[] { field }.Concat(slot).ToArray();
                var place = new FirstPhaseFieldPlace(this, path);
                if (Assigns(first.Phase, place, false))
                    continue;

                // Never written at all is SL0813's to say.
                if (!Assigns(body, new ConstructorFieldPlace(this, path, null), false))
                    continue;

                var leaf = path[^1];
                string named = string.Join('.', path.Select(f => f.Name));
                string where = first.Explicit
                    ? "'base(...)' runs"
                    : "the object is first reached here -- a method called, a property read, " +
                      "'this' handed on, or the base built";
                ReportNoZeroValue(Codes.FieldWithoutZeroUnsetAtBase, first.End,
                    $"'{type.Name}.{named}' has no value yet when {where}, and '{leaf.Type.Name}' " +
                    $"has no zero value: {ExplainNullInZero(FindNullInField(leaf.ContainingType, leaf))}. " +
                    "Give it its value before this, so that nothing can find the object without it",
                    leaf.Type);
            }
        }
    }

    /// <summary>
    /// Whether a field may be <c>late</c>: a class's field whose type is a
    /// reference with no zero value, which is what the check on a read is a
    /// null test for. Reports why not when it may not.
    /// </summary>
    private bool CheckLateField(NamedTypeSymbol type, Syntax.FieldDeclSyntax field, TypeSymbol fieldType, bool required)
    {
        string? refused =
            type is not ClassTypeSymbol ? $"'{type.Name}' is a struct, whose fields are its constructor's alone"
            : required ? "a 'required' field is given its value by every 'new', so it is never late"
            : !IsLateReference(fieldType) || ZeroValues.HasZeroValue(fieldType)
                ? $"'{fieldType.Name}' is not a reference that is never null; a field that may be " +
                  "empty is an optional, and one that is never empty has its value before the " +
                  "object can be reached"
            : null;
        if (refused is null) return true;

        diagnostics.Report(Codes.LateFieldNotAllowed, field.Span,
            $"'{type.Name}.{field.Name}' cannot be 'late': {refused}", type);
        return false;
    }

    private static bool IsLateReference(TypeSymbol type) => type switch
    {
        NamedTypeSymbol { IsReferenceType: true } => true,
        ArrayTypeSymbol or ClosureTypeSymbol => true,
        _ => false,
    };

    /// <summary>
    /// One slot of one of this type's fields during the first phase, read back
    /// only once it has been written.
    /// </summary>
    private sealed class FirstPhaseFieldPlace(Binder binder, FieldSymbol[] path) : AssignedPlace
    {
        private readonly HashSet<int> _reported = [];

        public override bool ChecksReads => true;

        public override bool IsPlace(BoundExpression expression) =>
            PathOf(expression) is { } written && written.Count <= path.Length &&
            written.Select((f, i) => ReferenceEquals(f, path[i])).All(b => b);

        // An automatic property of this type's own writes its storage.
        public override bool IsWrittenBy(BoundExpression write) =>
            path.Length == 1 && write switch
            {
                BoundPropertyAssignment { Receiver: var receiver, Property.Setter: var setter } =>
                    IsSelfReceiver(receiver) && ReferenceEquals(PlainStorage(setter), path[0]),
                BoundCall { Receiver: var receiver, Function: var setter } when setter.ReturnType.IsVoid() =>
                    IsSelfReceiver(receiver) && ReferenceEquals(PlainStorage(setter), path[0]),
                _ => false,
            };

        public override PlaceUse UseOf(BoundExpression expression)
        {
            if (expression is BoundCall { Receiver: var receiver, Function: var getter } &&
                IsSelfReceiver(receiver) && PlainStorage(getter) is { } storage &&
                !getter.ReturnType.IsVoid())
                return ReferenceEquals(storage, path[0]) ? PlaceUse.Read : PlaceUse.Beside;

            if (PathOf(expression) is not { } used)
                return PlaceUse.Other;
            bool onTheWay = used.Count <= path.Length &&
                            used.Select((f, i) => ReferenceEquals(f, path[i])).All(b => b);
            bool through = used.Count > path.Length &&
                           path.Select((f, i) => ReferenceEquals(f, used[i])).All(b => b);
            return onTheWay || through ? PlaceUse.Read : PlaceUse.Beside;
        }

        public override void ReportRead(SourceSpan span)
        {
            if (!_reported.Add(span.Start))
                return;
            var leaf = path[^1];
            binder.ReportNoZeroValue(Codes.ReadBeforeAssigned, span,
                $"'{string.Join('.', path.Select(f => f.Name))}' is read here before the constructor " +
                $"has given it a value, and '{leaf.Type.Name}' has no zero value: " +
                $"{ExplainNullInZero(FindNullInField(leaf.ContainingType, leaf))}",
                leaf.Type);
        }

        public override void ReportReturn(SourceSpan span)
        {
        }

        public override void ReportEarlyReturn(SourceSpan span)
        {
        }

        private static List<FieldSymbol>? PathOf(BoundExpression expression) => expression switch
        {
            BoundFieldAccess { Receiver: { } receiver } access when IsSelfReceiver(receiver) => [access.Field],
            BoundFieldAccess { Receiver: { } receiver } access when PathOf(receiver) is { } inner =>
                [.. inner, access.Field],
            BoundAddressOf { FromOutKeyword: false } address => PathOf(address.Operand),
            BoundDereference dereference when !IsSelfReceiver(dereference) => PathOf(dereference.Operand),
            _ => null,
        };
    }

    /// <summary>
    /// The storage an automatic accessor reads or writes and does nothing
    /// else with, or null for any other function: one that is virtual may be
    /// replaced by code that reaches the object.
    /// </summary>
    private static FieldSymbol? PlainStorage(FunctionSymbol? accessor) =>
        accessor is { IsAutoAccessor: true, IsVirtual: false, IsOverride: false, Accessor.BackingField: { } backing }
            ? backing
            : null;

    /// <summary><c>this</c>, as a class sees it or as a struct's pointer does.</summary>
    private static bool IsSelfReceiver(BoundExpression? receiver) => receiver switch
    {
        BoundThis => true,
        BoundDereference { Operand: BoundThis } => true,
        _ => false,
    };

    /// <summary>
    /// The first place a tree reaches the object other than through one of its
    /// own type's fields, and whether it returns.
    /// </summary>
    private sealed class ObjectReachFinder(FunctionSymbol constructor) : BoundTreeWalker
    {
        public SourceSpan? Reach { get; private set; }

        public SourceSpan? ReturnSpan { get; private set; }

        public bool Returns => ReturnSpan is not null;

        public override void Visit(BoundStatement? statement)
        {
            if (Reach is not null)
                return;
            if (statement is BoundReturn && ReturnSpan is null)
                ReturnSpan = statement.Span;
            base.Visit(statement);
        }

        public override void Visit(BoundExpression? expression)
        {
            if (Reach is not null || expression is null)
                return;

            switch (expression)
            {
                case BoundFieldAccess access when IsOwnField(access):
                    return;

                case BoundPropertyAssignment { Receiver: var receiver, Property.Setter: var setter } assigned
                    when IsSelfReceiver(receiver) && IsOwnStorage(PlainStorage(setter)):
                    Visit(assigned.Value);
                    return;

                case BoundCall { Receiver: var receiver, Function: var accessor } call
                    when IsSelfReceiver(receiver) && IsOwnStorage(PlainStorage(accessor)):
                    VisitAll(call.Arguments);
                    return;

                case BoundThis self when ReferenceEquals(self.Parameter, constructor.Parameters[0]):
                    Reach = self.Span;
                    return;
            }

            base.Visit(expression);
        }

        private bool IsOwnStorage(FieldSymbol? storage) =>
            storage is not null && constructor.ContainingType!.Fields.Contains(storage);

        /// <summary>A field of this type through <c>this</c>, or one inside it.</summary>
        private bool IsOwnField(BoundFieldAccess access) => access.Receiver switch
        {
            var receiver when IsSelfReceiver(receiver) =>
                constructor.ContainingType!.Fields.Contains(access.Field),
            BoundFieldAccess inner => IsOwnField(inner),
            _ => false,
        };
    }
}
