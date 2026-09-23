// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Collections;

// ------------------------------------------------------------------- stack

/// Last in, first out. The top is the end of the array, so nothing moves.
///
/// @typeparam T  what the stack holds; nothing is asked of it
public class Stack<T> : IEnumerable<T>
{
    T[] _items;
    T[] _blank;
    nuint _count;

    /// An empty stack with room for a few items before it first grows.
    public Stack()
    {
        _items = new T[8];
        _blank = new T[1];
        _count = 0;
    }

    /// How many items are on the stack. O(1).
    public nuint Count => _count;

    /// True when there is nothing to pop. Check this before `Pop` or `Peek`,
    /// both of which abort on an empty stack.
    ///
    /// @see Stack.Pop
    /// @seealso Stack.Peek
    public bool IsEmpty => _count == 0;

    /// The number of slots the backing array has.
    public nuint Capacity => _items.Length;

    /// Pushes onto the top, growing when full. Amortised constant time.
    ///
    /// @see Stack.Pop
    public void Push(T item)
    {
        if (_count == _items.Length)
            GrowStorage();
        _items[_count] = item;
        _count++;
    }

    /// Removes and returns the top. Aborts when the stack is empty.
    ///
    /// @see Stack.Push
    /// @seealso Stack.Peek
    public T Pop()
    {
        if (_count == 0)
            sl_fail("Stack.Pop: the stack is empty");

        _count--;
        var item = _items[_count];
        _items[_count] = _blank[0];
        return item;
    }

    /// The top, without removing it. Aborts when the stack is empty.
    ///
    /// @see Stack.Pop
    public T Peek()
    {
        if (_count == 0)
            sl_fail("Stack.Peek: the stack is empty");
        return _items[_count - 1];
    }

    /// Drops everything. The array is replaced rather than blanked, so
    /// anything it held is released now.
    public void Clear()
    {
        _items = new T[8];
        _count = 0;
    }

    /// The items, top first, which is the order they would be popped in.
    ///
    /// @see Stack.GetEnumerator
    public List<T> ToList()
    {
        var result = new List<T>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_items[_count - 1 - i]);
        return result;
    }

    /// The item `depth` places below the top, counting from zero.
    T GetItemFromTop(nuint depth) => _items[_count - 1 - depth];

    /// A cursor over the items, top first -- the order `Pop` would give them
    /// back in. Pushing or popping during a walk invalidates it.
    ///
    /// @see StackEnumerator
    /// @seealso Stack.ToList
    public IEnumerator<T> GetEnumerator() => new StackEnumerator<T>(this);

    void GrowStorage()
    {
        var bigger = new T[_items.Length * 2];
        for (nuint i = 0; i < _count; i++)
            bigger[i] = _items[i];
        _items = bigger;
    }
}
