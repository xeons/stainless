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
/// A struct method that writes its receiver, called on storage that may not be
/// written: an <c>in</c> parameter, a <c>static readonly</c>, a <c>const</c>,
/// or an element of a <c>ReadOnlySpan&lt;T&gt;</c>.
///
/// <para>
/// A struct method is given its receiver by pointer, so a call is a write
/// exactly when the body is one. Whether it is follows calls on <c>this</c>
/// from one method to the next, and is known only once every body is bound:
/// the writes a body makes itself are noted as it is bound, and the rest is
/// settled here.
/// </para>
///
/// <para>
/// C# copies the receiver instead and calls the method on the copy, which
/// keeps the promise by losing the write without a word. Refusing the call
/// keeps it and says so, and a method that only reads is called in place as
/// before, with no copy.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>Struct methods whose own body writes <c>this</c>.</summary>
    private readonly HashSet<FunctionSymbol> _writesOwnReceiver = [];

    /// <summary>Notes a write to <paramref name="place"/>, which may be the current method's own receiver.</summary>
    private void NoteWriteTo(BoundExpression place)
    {
        if (_context.Function is { } function && IsOwnReceiver(place))
            _writesOwnReceiver.Add(function);
    }

    /// <summary>True for storage in a struct method's own receiver: <c>this</c>, or a field of it.</summary>
    private static bool IsOwnReceiver(BoundExpression place) =>
        BaseOf(place) is BoundDereference { Operand: BoundThis };

    private void ReportReadOnlyReceiversWritten()
    {
        var calls = new ReceiverCallFinder();
        foreach (var function in _functions)
        {
            calls.Caller = function.Symbol;
            calls.Visit(function.Body);
        }

        var writing = new HashSet<FunctionSymbol>(_writesOwnReceiver);
        for (bool grew = true; grew;)
        {
            grew = false;
            foreach (var (caller, callee) in calls.OnOwnReceiver)
                if (writing.Contains(callee) && writing.Add(caller))
                    grew = true;
        }

        foreach (var (callee, receiver, span) in calls.OnOtherReceivers)
        {
            if (!writing.Contains(callee) || IsReadOnlyTarget(receiver) is not { } why) continue;

            diagnostics.Report(Codes.MutatingMemberOnReadOnlyStruct, span,
                $"'{callee.ContainingType!.Name}.{callee.Name}' writes the struct it is called " +
                $"on, and {why}; copy it into a local first if the change is meant to be kept " +
                "there",
                callee.ContainingType);
        }
    }

    /// <summary>Every call a struct method is given its receiver by pointer for.</summary>
    private sealed class ReceiverCallFinder : BoundTreeWalker
    {
        public FunctionSymbol? Caller { get; set; }

        /// <summary>A method calling another on its own <c>this</c>.</summary>
        public List<(FunctionSymbol Caller, FunctionSymbol Callee)> OnOwnReceiver { get; } = [];

        public List<(FunctionSymbol Callee, BoundExpression Receiver, SourceSpan Span)> OnOtherReceivers { get; } = [];

        public override void Visit(BoundExpression? expression)
        {
            // A method's own `this` is passed on as the storage it already is.
            if (expression is BoundCall { Receiver: { } receiver } call &&
                call.Function.ContainingType is StructTypeSymbol)
            {
                if (receiver is BoundThis || IsOwnReceiver(receiver))
                    OnOwnReceiver.Add((Caller!, call.Function));
                else if (receiver is BoundAddressOf { Operand: var place })
                    OnOtherReceivers.Add((call.Function, place, call.Span));
            }

            base.Visit(expression);
        }
    }
}
