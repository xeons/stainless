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

namespace Stainless.Binding;

public sealed partial class Binder
{
    /// <summary>
    /// Whether control can run off the end of a statement: C#'s reachability,
    /// with no constant folding beyond a literal <c>true</c> condition.
    ///
    /// It answers both "does every path through this function return" and
    /// "does this switch section fall through", which are the same question.
    /// </summary>
    private static bool EndIsReachable(BoundStatement statement) => Reachability.EndIsReachable(statement);

    /// <summary>
    /// The walk behind <see cref="EndIsReachable"/>. A label is reachable when
    /// a reachable jump names it, and a jump backwards names one the walk has
    /// already passed, so the walk repeats until the set of reached labels
    /// stops growing.
    /// </summary>
    private sealed class Reachability
    {
        private readonly HashSet<LabelSymbol> _reached = [];
        private readonly List<Target> _targets = [];
        private bool _grew;

        /// <summary>Somewhere <c>break</c> lands, and for a loop, somewhere <c>continue</c> does.</summary>
        private sealed class Target(bool isLoop)
        {
            public bool IsLoop { get; } = isLoop;
            public bool Broken { get; set; }
            public bool Continued { get; set; }
        }

        public static bool EndIsReachable(BoundStatement statement)
        {
            var walk = new Reachability();
            bool end;

            do
            {
                walk._grew = false;
                walk._targets.Clear();
                end = walk.Walk(statement, true);
            }
            while (walk._grew);

            return end;
        }

        private bool Walk(BoundStatement statement, bool reachable)
        {
            switch (statement)
            {
                case BoundBlock block:
                    foreach (var inner in block.Statements)
                        reachable = Walk(inner, reachable);
                    return reachable;

                case BoundLabel label:
                    return reachable || _reached.Contains(label.Label);

                case BoundGoto jump:
                    if (reachable && _reached.Add(jump.Label))
                        _grew = true;
                    return false;

                case BoundReturn:
                    return false;

                case BoundBreak:
                    if (reachable && _targets.Count > 0)
                        _targets[^1].Broken = true;
                    return false;

                case BoundContinue:
                    if (reachable && _targets.LastOrDefault(t => t.IsLoop) is { } continued)
                        continued.Continued = true;
                    return false;

                case BoundIf branch:
                {
                    bool then = Walk(branch.Then, reachable);
                    bool otherwise = branch.Else is null ? reachable : Walk(branch.Else, reachable);
                    return then || otherwise;
                }

                case BoundWhile loop:
                {
                    var target = Enter(isLoop: true);
                    bool bodyEnd = Walk(loop.Body, reachable);
                    Leave();

                    bool asked = reachable || bodyEnd || target.Continued;
                    return asked && !IsTrue(loop.Condition) || target.Broken;
                }

                // A collection may be empty, so the body may run no times.
                case BoundForEach loop:
                {
                    Enter(isLoop: true);
                    Walk(loop.Body, reachable);
                    Leave();
                    return reachable;
                }

                case BoundDoWhile loop:
                {
                    var target = Enter(isLoop: true);
                    bool bodyEnd = Walk(loop.Body, reachable);
                    Leave();

                    bool asked = bodyEnd || target.Continued;
                    return asked && !IsTrue(loop.Condition) || target.Broken;
                }

                case BoundFor loop:
                {
                    bool entered = loop.Initializer is null ? reachable : Walk(loop.Initializer, reachable);

                    var target = Enter(isLoop: true);
                    bool bodyEnd = Walk(loop.Body, entered);
                    Leave();

                    bool asked = entered || bodyEnd || target.Continued;
                    bool forever = loop.Condition is null || IsTrue(loop.Condition);
                    return asked && !forever || target.Broken;
                }

                case BoundSwitch chosen:
                {
                    var target = Enter(isLoop: false);
                    bool sectionEnd = false;
                    foreach (var section in chosen.Sections)
                        sectionEnd |= Walk(section.Body, reachable);
                    Leave();

                    bool covered = chosen.IsExhaustive || chosen.Sections.Any(s => s.IsDefault);
                    return reachable && !covered || sectionEnd || target.Broken;
                }

                // `break`, `continue` and a jump out may not cross into either,
                // so a target of its own keeps what is inside from counting.
                case BoundParallel parallel:
                {
                    Enter(isLoop: true);
                    bool end = Walk(parallel.Body, reachable);
                    Leave();
                    return end;
                }

                case BoundParallelFor loop:
                    Enter(isLoop: true);
                    Walk(loop.Body, reachable);
                    Leave();
                    return reachable;

                default:
                    return reachable;
            }
        }

        private Target Enter(bool isLoop)
        {
            var target = new Target(isLoop);
            _targets.Add(target);
            return target;
        }

        private void Leave() => _targets.RemoveAt(_targets.Count - 1);

        private static bool IsTrue(BoundExpression condition) => condition is
            BoundLiteral { Value: true } or BoundConstantAccess { Constant.Value: true };
    }
}
