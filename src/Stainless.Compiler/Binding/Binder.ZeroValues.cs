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
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// The rule that a type whose zero would hold a null in a never-null
/// reference has no zero value, and so no <c>default</c>, no unassigned
/// local, no <c>new T[n]</c> and no constructor that leaves such a field
/// unwritten. See docs/design/zero-values.md.
///
/// A prototype, off unless <c>STAINLESS_ZERO_VALUES</c> is <c>warn</c>,
/// <c>error</c> or <c>log</c>; the last reports nothing and only writes the
/// log. <c>STAINLESS_ZERO_VALUES_LOG</c> names a file each finding is appended
/// to as a tab-separated line, which is how the tree was surveyed, together
/// with every site in a generic body whose type names a type parameter,
/// whatever it was instantiated with. Off, it costs one test per site.
/// </summary>
public sealed partial class Binder
{
    private enum ZeroValueMode { Off, Log, Warn, Error }

    private static readonly ZeroValueMode s_zeroValueMode =
        Environment.GetEnvironmentVariable("STAINLESS_ZERO_VALUES") switch
        {
            "log" => ZeroValueMode.Log,
            "warn" => ZeroValueMode.Warn,
            "error" or "1" => ZeroValueMode.Error,
            _ => ZeroValueMode.Off,
        };

    private static readonly string? s_zeroValueLog =
        Environment.GetEnvironmentVariable("STAINLESS_ZERO_VALUES_LOG") is { Length: > 0 } log
            ? log
            : null;

    private static bool ChecksZeroValues => s_zeroValueMode != ZeroValueMode.Off;

    private static readonly object s_zeroValueLogLock = new();

    private static void AppendToZeroValueLog(string line)
    {
        lock (s_zeroValueLogLock)
            System.IO.File.AppendAllText(s_zeroValueLog!, line);
    }

    /// <summary>One finding per place, however many instantiations or rebinds reach it.</summary>
    private readonly HashSet<(string File, int Start, string Path)> _zeroValueReported = [];

    /// <summary>Locals declared without a value, waiting for their body to be bound.</summary>
    private readonly List<(LocalSymbol Local, SourceSpan Span, bool Generic)> _unsetLocals = [];

    /// <summary><c>default(T)</c>, or a bare <c>default</c> going to <paramref name="type"/>.</summary>
    private void CheckDefaultHasZero(SourceSpan span, TypeSymbol type, TypeSyntax? written)
    {
        if (!ChecksZeroValues) return;
        NoteTemplateSite("default", span, written);
        if (ZeroValues.FindNullInZero(type) is not { } found) return;

        ReportNoZeroValue("SL0810", span, "default", MentionsTypeArgument(written), type, found,
            $"'{type.Name}' has no zero value: {Explain(found)}, so 'default' would hand out a " +
            "null where the type says there is none. Build the value with a constructor, or " +
            "make the reference nullable");
    }

    /// <summary><c>new T[n]</c>, whose elements start as the zero of <c>T</c>.</summary>
    private void CheckArrayElementHasZero(SourceSpan span, TypeSymbol element, TypeSyntax written)
    {
        if (!ChecksZeroValues) return;
        NoteTemplateSite("new-array", span, written);
        if (ZeroValues.FindNullInZero(element) is not { } found) return;

        ReportNoZeroValue("SL0812", span, "new-array", MentionsTypeArgument(written), element, found,
            $"'new {element.Name}[n]' would start every element as a zero, and '{element.Name}' " +
            $"has none: {Explain(found)}. Write the elements out, as '[a, b, c]', fill it with " +
            "'Array.Create(n, i => ...)', or collect them in a 'List'");
    }

    /// <summary>A local declared with no value, judged once its body has been bound.</summary>
    private void NoteUnsetLocal(LocalSymbol local, SourceSpan span, TypeSyntax written)
    {
        if (!ChecksZeroValues) return;
        NoteTemplateSite("local", span, written);
        if (local.Type.IsError() || ZeroValues.HasZeroValue(local.Type)) return;
        _unsetLocals.Add((local, span, MentionsTypeArgument(written)));
    }

    /// <summary>
    /// Settles each unset local this body declares by what first touches it:
    /// the whole of it written, a field of it written, or a read. Only the
    /// first is what definite assignment would accept, and only when every
    /// path does it; this looks at the first touch alone, so it is a lower
    /// bound on what the rule refuses.
    /// </summary>
    private void SettleUnsetLocals(BoundBlock body)
    {
        if (_unsetLocals.Count == 0) return;

        foreach (var pending in _unsetLocals.ToList())
        {
            var finder = new FirstTouchFinder(pending.Local);
            finder.Visit(body);
            if (!finder.Declared) continue;

            _unsetLocals.Remove(pending);
            var found = ZeroValues.FindNullInZero(pending.Local.Type)!.Value;
            string category = finder.Touch switch
            {
                LocalTouch.Whole => "local-assigned",
                LocalTouch.Fields => "local-fields",
                LocalTouch.Read => "local-read",
                _ => "local-unused",
            };

            ReportNoZeroValue("SL0811", pending.Span, category, pending.Generic,
                pending.Local.Type, found,
                $"'{pending.Local.Name}' is declared without a value, and '{pending.Local.Type.Name}' " +
                $"has no zero value: {Explain(found)}. Give it one where it is declared, or " +
                "assign the whole of it on every path before it is read",
                quiet: finder.Touch == LocalTouch.Whole);
        }
    }

    /// <summary>
    /// Every field a constructor's type cannot leave as zero is written on
    /// every path through it. One that delegates with <c>this(...)</c> is held
    /// to nothing, because the one it delegates to is held to all of it.
    /// </summary>
    private void CheckConstructorAssignsFields(FunctionSymbol constructor, BoundBlock body)
    {
        if (!ChecksZeroValues) return;
        if (constructor.ContainingType is not { } type) return;
        if (_delegated.ContainsKey(constructor)) return;
        if (_context.Jumps.Labels.Count > 0 || _context.Jumps.Jumps.Count > 0) return;

        bool generic = type.Template is not null;
        foreach (var field in FieldsNeedingValues(type))
        {
            var found = FindNullInField(type, field);
            var place = new ConstructorFieldPlace(field, this, constructor, generic, found);
            if (!Assigns(body, place, false) && EndIsReachable(body))
                place.ReportReturn(constructor.Span);
        }
    }

    /// <summary>A class with no constructor at all: nothing writes any field it has.</summary>
    private void CheckClassesWithoutConstructors()
    {
        if (!ChecksZeroValues) return;

        foreach (var type in _classes.ToList())
        {
            // A lambda's environment is filled by the code that makes it.
            if (type.Constructors.Count > 0 || type.Span is not { } span || _generated.Contains(type))
                continue;

            foreach (var field in FieldsNeedingValues(type))
            {
                var found = FindNullInField(type, field);
                ReportNoZeroValue("SL0813", span, "field-no-constructor", type.Template is not null,
                    field.Type, found,
                    $"'{type.Name}' has no constructor, so nothing gives '{field.Name}' a value, and " +
                    $"'{field.Type.Name}' has no zero value: {Explain(found)}. Give the field an " +
                    "initializer, mark it 'required', or write a constructor that assigns it");
            }
        }
    }

    /// <summary>A static property with no <c>= value</c>, which would start as the zero.</summary>
    private void CheckStaticPropertyHasValue(StaticSymbol symbol, StaticDeclSyntax declaration)
    {
        if (!ChecksZeroValues || !symbol.IsPropertyStorage) return;
        if (declaration.Value is not DefaultSyntax { Type: null } made || made.Span != declaration.Span) return;
        if (ZeroValues.FindNullInZero(symbol.Type) is not { } found) return;

        ReportNoZeroValue("SL0814", declaration.Span, "static-property",
            _context.Substitution.Count > 0, symbol.Type, found,
            $"'{symbol.DisplayName}' has no '= value', so it would start as the zero of " +
            $"'{symbol.Type.Name}', which has none: {Explain(found)}. Give it an initializer");
    }

    /// <summary>
    /// The fields of a type that a constructor has to write: those whose type
    /// has no zero, less those an initializer writes, those a <c>new</c> has
    /// to name, and an event's storage, which the allocation fills.
    /// </summary>
    private static IEnumerable<FieldSymbol> FieldsNeedingValues(NamedTypeSymbol type)
    {
        var required = type.Properties
            .Where(p => p.IsRequired && p.BackingField is not null)
            .Select(p => p.BackingField!)
            .Concat(type.Events.Select(e => e.BackingField).OfType<FieldSymbol>())
            .ToHashSet();

        return type.Fields.Where(f =>
            f.InitializerSyntax is null && !f.IsRequired && !required.Contains(f) &&
            !f.Type.IsError() && !ZeroValues.HasZeroValue(f.Type));
    }

    /// <summary>Generic sites already logged, whatever they were instantiated with.</summary>
    private readonly HashSet<(string File, int Start)> _templateSitesLogged = [];

    /// <summary>
    /// Logs a site in a generic body whose type is a type parameter's, which
    /// a rule judged at the declaration rather than per instantiation would
    /// have to answer for every argument.
    /// </summary>
    private void NoteTemplateSite(string category, SourceSpan span, TypeSyntax? written)
    {
        if (s_zeroValueLog is null || diagnostics.IsMuted || !MentionsTypeArgument(written)) return;
        if (!_templateSitesLogged.Add((span.File.Path, span.Start))) return;

        var (line, column) = span.File.GetLineColumn(span.Start);
        AppendToZeroValueLog(
            $"template\t{category}\tgeneric\t{span.File.Path}\t{line}\t{column}\t\t\t\t" +
            $"{_context.Function?.Name ?? ""}\n");
    }

    /// <summary>Where a field's zero breaks a promise, named from the type that holds it.</summary>
    private static (string Path, TypeSymbol Slot) FindNullInField(NamedTypeSymbol type, FieldSymbol field)
    {
        var found = ZeroValues.FindNullInZero(field.Type)!.Value;
        return ($"{type.Name}.{field.Name}{found.Path[field.Type.Name.Length..]}", found.Slot);
    }

    private bool MentionsTypeArgument(TypeSyntax? written) =>
        _context.Substitution.Count > 0 &&
        (written is null || MentionsUnknown(written, _context.Substitution.Keys.ToHashSet(), []));

    private static string Explain((string Path, TypeSymbol Slot) found) =>
        found.Slot is ClosureTypeSymbol
            ? $"'{found.Path}' is the closure '{found.Slot.Name}', whose zero has no function to call"
            : $"'{found.Path}' is a '{found.Slot.Name}', which is never null";

    private void ReportNoZeroValue(
        string code, SourceSpan span, string category, bool generic, TypeSymbol type,
        (string Path, TypeSymbol Slot) found, string message, bool quiet = false)
    {
        if (diagnostics.IsMuted) return;
        if (!_zeroValueReported.Add((span.File.Path, span.Start, found.Path))) return;

        if (s_zeroValueLog is not null)
        {
            var (line, column) = span.File.GetLineColumn(span.Start);
            string function = _context.Function?.Name ?? "";
            AppendToZeroValueLog(
                $"{code}\t{category}\t{(generic ? "generic" : "concrete")}\t{span.File.Path}\t" +
                $"{line}\t{column}\t{type.Name}\t{found.Path}\t{found.Slot.Name}\t{function}\n");
        }

        if (quiet || s_zeroValueMode == ZeroValueMode.Log) return;

        if (s_zeroValueMode == ZeroValueMode.Error)
            diagnostics.Error(code, span, message, type);
        else
            diagnostics.Warning(code, span, message, type);
    }

    /// <summary>A field a constructor has to write, as definite assignment asks about it.</summary>
    private sealed class ConstructorFieldPlace(
        FieldSymbol field, Binder binder, FunctionSymbol constructor, bool generic,
        (string Path, TypeSymbol Slot) found) : AssignedPlace
    {
        public override bool IsPlace(BoundExpression expression) =>
            expression is BoundFieldAccess access && ReferenceEquals(access.Field, field) &&
            IsSelf(access.Receiver);

        public override bool IsWrittenBy(BoundExpression write) => write switch
        {
            BoundPropertyAssignment assigned =>
                ReferenceEquals(assigned.Property.BackingField, field) && IsSelf(assigned.Receiver),
            BoundCall call =>
                call.Function.Accessor is { BackingField: { } backing } &&
                ReferenceEquals(backing, field) && call.Function.ReturnType.IsVoid() &&
                IsSelf(call.Receiver),
            _ => false,
        };

        public override void ReportReturn(SourceSpan span) =>
            binder.ReportNoZeroValue("SL0813", span, "field", generic, field.Type, found,
                $"'{constructor.ContainingType!.Name}' can be made without '{field.Name}' being " +
                $"written, and '{field.Type.Name}' has no zero value: {Explain(found)}. Assign it " +
                "on every path through the constructor, or give it an initializer");

        public override void ReportEarlyReturn(SourceSpan span) => ReportReturn(span);

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

    private enum LocalTouch { None, Whole, Fields, Read }

    /// <summary>What first reaches a local, in evaluation order: a write of all of it, of a field, or a read.</summary>
    private sealed class FirstTouchFinder(LocalSymbol local) : BoundTreeWalker
    {
        public bool Declared { get; private set; }
        public LocalTouch Touch { get; private set; }

        public override void Visit(BoundStatement? statement)
        {
            if (statement is BoundLocalDeclaration declaration && ReferenceEquals(declaration.Local, local))
                Declared = true;

            base.Visit(statement);
        }

        public override void Visit(BoundExpression? expression)
        {
            if (Touch != LocalTouch.None)
                return;

            switch (Declared ? expression : null)
            {
                case BoundAssignment { Target: BoundLocalAccess named } whole
                    when ReferenceEquals(named.Local, local):
                    Visit(whole.Value);
                    Settle(LocalTouch.Whole);
                    return;

                case BoundAssignment { Target: BoundFieldAccess field } when Root(field) == local:
                    Settle(LocalTouch.Fields);
                    return;

                case BoundMemberAssignment { Target: BoundFieldAccess field } when Root(field) == local:
                    Settle(LocalTouch.Fields);
                    return;

                case BoundAddressOf { FromOutKeyword: true, Operand: BoundLocalAccess named }
                    when ReferenceEquals(named.Local, local):
                    Settle(LocalTouch.Whole);
                    return;

                case BoundDeconstruction taken
                    when taken.Target.WrittenPlaces.Any(p => p is BoundLocalAccess named &&
                                                             ReferenceEquals(named.Local, local)):
                    Settle(LocalTouch.Whole);
                    return;

                case BoundLocalAccess named when ReferenceEquals(named.Local, local):
                    Settle(LocalTouch.Read);
                    return;
            }

            base.Visit(expression);
        }

        private void Settle(LocalTouch touch)
        {
            if (Touch == LocalTouch.None)
                Touch = touch;
        }

        private static LocalSymbol? Root(BoundExpression place) => place switch
        {
            BoundLocalAccess named => named.Local,
            BoundFieldAccess { Receiver: { } receiver } => Root(receiver),
            BoundAddressOf inner => Root(inner.Operand),
            _ => null,
        };
    }
}
