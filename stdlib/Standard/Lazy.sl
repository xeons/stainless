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

module Standard;

extern "C"
{
    byte* sl_mutex_new();
    void sl_mutex_free(byte* mutex);
    void sl_mutex_lock(byte* mutex);
    void sl_mutex_unlock(byte* mutex);
    nuint sl_thread_current_id();
}

/// A value made the first time it is asked for: C#'s `System.Lazy<T>`.
///
///     var table = new Lazy<Dictionary<String, int>>(() => LoadTable());
///     int n = table.Value.GetValue("key");     // loaded here, once
///
/// By default the factory runs once however many threads ask at once, and the
/// others wait for it; `LazyThreadSafetyMode` says otherwise. A factory that
/// reads the `Value` it is making aborts, where C#'s throws.
///
/// @typeparam T  what is made; nothing is asked of it
public threadsafe class Lazy<T>
{
    Func<T> _factory;
    T _value;
    bool _created;
    LazyThreadSafetyMode _mode;

    // Null for a Lazy that is not thread-safe.
    byte* _lock;

    // The thread running the factory, and zero when none is.
    nuint _makingOn;

    /// Made by `factory`, once, however many threads ask.
    public Lazy(Func<T> factory) : this(factory, LazyThreadSafetyMode.ExecutionAndPublication) { }

    /// Made by `factory`, once, and safe to share between threads only when
    /// `isThreadSafe` is.
    public Lazy(Func<T> factory, bool isThreadSafe)
        : this(factory, isThreadSafe ? LazyThreadSafetyMode.ExecutionAndPublication : LazyThreadSafetyMode.None) { }

    /// Made by `factory`, as `mode` says it may be made.
    public Lazy(Func<T> factory, LazyThreadSafetyMode mode)
    {
        _factory = factory;
        _mode = mode;
        _lock = mode == LazyThreadSafetyMode.None ? null : sl_mutex_new();
    }

    /// Already made.
    public Lazy(T value)
    {
        _value = value;
        _created = true;
        _factory = () => value;
        _mode = LazyThreadSafetyMode.None;
        _lock = null;
    }

    ~Lazy()
    {
        if (_lock != null)
            sl_mutex_free(_lock);
    }

    /// Whether the value has been made yet.
    public bool IsValueCreated
    {
        get
        {
            if (_lock == null)
                return _created;

            sl_mutex_lock(_lock);
            bool created = _created;
            sl_mutex_unlock(_lock);
            return created;
        }
    }

    /// The value, made now if it has not been.
    public T Value
    {
        get
        {
            switch (_mode)
            {
                case LazyThreadSafetyMode.None:
                    return MadeAlone();
                case LazyThreadSafetyMode.PublicationOnly:
                    return MadeByTheFirstToFinish();
                default:
                    return MadeOnce();
            }
        }
    }

    /// With no other thread to fear.
    T MadeAlone()
    {
        if (_created)
            return _value;
        if (_makingOn != 0u)
            sl_fail("Lazy.Value: the factory read the value it is making");

        _makingOn = 1u;
        _value = _factory();
        _created = true;
        _makingOn = 0u;
        return _value;
    }

    /// Run by whoever asks, kept by the first to finish.
    T MadeByTheFirstToFinish()
    {
        sl_mutex_lock(_lock);
        bool created = _created;
        sl_mutex_unlock(_lock);
        if (created)
            return _value;

        T made = _factory();

        sl_mutex_lock(_lock);
        if (!_created)
        {
            _value = made;
            _created = true;
        }
        sl_mutex_unlock(_lock);
        return _value;
    }

    /// Run once, under the lock, while any other thread asking waits.
    T MadeOnce()
    {
        // Read before the lock, which the factory's own thread already holds:
        // only that thread can find its own id here, so a stale read is only
        // ever a different thread's, and that one waits at the lock instead.
        nuint self = sl_thread_current_id();
        if (_makingOn == self)
            sl_fail("Lazy.Value: the factory read the value it is making");

        sl_mutex_lock(_lock);
        if (!_created)
        {
            _makingOn = self;
            _value = _factory();
            _created = true;
            _makingOn = 0u;
        }
        sl_mutex_unlock(_lock);
        return _value;
    }
}
