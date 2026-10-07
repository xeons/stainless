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
/// Where binding is: the function, the file, the type arguments, the locals
/// and everything else that belongs to one body rather than to the program.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// One body's binding state. A body bound inside another -- a lambda, a
    /// local function, an instantiation's signature -- is bound in a context of
    /// its own, entered with <see cref="Enter"/>, and the one it interrupted is
    /// back when it is disposed.
    /// </summary>
    private sealed record BinderContext
    {
        public FunctionSymbol? Function { get; set; }

        /// <summary>
        /// The file being bound. Imports are per-file, so this is the unit of
        /// lookup.
        /// </summary>
        public FileScope? File { get; set; }

        /// <summary>
        /// The type a constant being folded is declared in, whose constants its
        /// initializer names without the type in front.
        /// </summary>
        public NamedTypeSymbol? ConstantOwner { get; set; }

        /// <summary>
        /// The enum whose member values are being folded, and how many of its
        /// members have one: those the next value may name without the enum.
        /// </summary>
        public EnumTypeSymbol? FoldingEnum { get; set; }
        public int FoldedEnumMembers { get; set; }

        /// <summary>The type arguments in force while binding inside an instantiation.</summary>
        public Dictionary<string, TypeSymbol> Substitution { get; set; } =
            new(StringComparer.Ordinal);

        /// <summary>The locals in scope, innermost block last.</summary>
        public List<Dictionary<string, LocalSymbol>> Locals { get; init; } = [];

        public int LoopDepth { get; set; }

        /// <summary>
        /// How many <c>switch</c> statements enclose what is being bound. Separate
        /// from the loop depth because a switch is a target for <c>break</c> but not
        /// for <c>continue</c>, which passes straight through it to the loop.
        /// </summary>
        public int SwitchDepth { get; set; }

        /// <summary>How many 'parallel' scopes enclose what is being bound.</summary>
        public int ParallelDepth { get; set; }

        /// <summary>
        /// Which case each variant in scope is known to be holding. A fact is put
        /// here by a condition that tested one, and taken away by anything that
        /// could have changed it.
        /// </summary>
        public Dictionary<object, Fact> VariantFacts { get; set; } = [];

        /// <summary>The labels and jumps of the function being bound.</summary>
        public JumpState Jumps { get; set; } = new();

        /// <summary>
        /// Whether <c>+</c>, <c>-</c> and <c>*</c> on integers are being asked to
        /// notice that they overflowed. False everywhere but inside
        /// <c>checked</c>: wrapping is the language's defined default (§9).
        /// </summary>
        public bool CheckedArithmetic { get; set; }

        /// <summary>
        /// The one <c>base(...)</c> a constructor may contain, or null. Compared by
        /// reference, so a second one anywhere else is not it.
        /// </summary>
        public CallSyntax? ConstructorChain { get; set; }

        /// <summary>The lambdas being bound, outermost first.</summary>
        public List<ClosureContext> Closures { get; init; } = [];

        /// <summary>The local functions in scope, innermost last; a lambda sees them too.</summary>
        public List<Dictionary<string, LocalFunction>> LocalFunctionScopes { get; set; } = [];

        /// <summary>
        /// Set while a field initializer is being bound, which is the one place
        /// <c>this</c> is out of reach inside a constructor.
        /// </summary>
        public bool InitializingField { get; set; }

        /// <summary>
        /// The function whose <c>return</c>s are being collected rather than
        /// checked, while a block-bodied lambda's result is worked out.
        /// </summary>
        public FunctionSymbol? InferringReturnsOf { get; set; }

        /// <summary>What each <c>return</c> there gave back; null for a bare one.</summary>
        public List<BoundExpression?> ReturnsFound { get; set; } = [];

        /// <summary>
        /// A context for a body bound in the middle of this one: its own locals,
        /// loops, jumps and facts, and this one's file, type arguments and local
        /// functions until the caller says otherwise.
        /// </summary>
        public BinderContext ForBody(FunctionSymbol? function) => this with
        {
            Function = function,
            Locals = [],
            LoopDepth = 0,
            SwitchDepth = 0,
            ParallelDepth = 0,
            VariantFacts = new Dictionary<object, Fact>(VariantFacts),
            Jumps = new JumpState(),
            Closures = [.. Closures],
            ReturnsFound = [],
            InferringReturnsOf = null,
        };
    }

    private BinderContext _context = new();

    private ModuleSymbol? _currentModule => _context.File?.Module;

    /// <summary>Makes <paramref name="context"/> current until the result is disposed.</summary>
    private ContextScope Enter(BinderContext context)
    {
        var outer = _context;
        _context = context;
        return new ContextScope(this, outer);
    }

    private readonly struct ContextScope(Binder binder, BinderContext outer) : IDisposable
    {
        public void Dispose() => binder._context = outer;
    }
}
