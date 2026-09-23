// SPDX-License-Identifier: 0BSD
module ConcurrentContainers;

import Standard.Collections;
import Standard.Concurrent;
import Standard.Threading;
import Standard.Console;

extern "C" int printf(byte* format, ...);

// Enough work per job, and enough jobs, that the threads really do overlap.
// A container that only looked thread safe would lose items here.
void Produce(ConcurrentQueue<int> queue, int from, int upto)
{
    for (int i = from; i < upto; i = i + 1)
        queue.Enqueue(i);
}

void Record(ConcurrentDictionary<int, int> map, int from, int upto)
{
    for (int i = from; i < upto; i = i + 1)
        map.SetValue(i, i * 2);
}

void Stack(ConcurrentStack<int> stack, int from, int upto)
{
    for (int i = from; i < upto; i = i + 1)
        stack.Push(i);
}

// Every consumer takes until the channel is closed and drained, so between
// them they see each item exactly once.
void Consume(Channel<int> channel, AtomicLong total, AtomicLong seen)
{
    while (channel.Take() is Some item)
    {
        total.Add((long)item.Value);
        seen.Add(1);
    }
}

int Main()
{
    // ------------------------------------------------------------ queue
    var queue = new ConcurrentQueue<int>();
    parallel
    {
        spawn Produce(queue, 0, 1000);
        spawn Produce(queue, 1000, 2000);
        spawn Produce(queue, 2000, 3000);
        spawn Produce(queue, 3000, 4000);
    }
    printf("queued=%llu\n", queue.Count);

    long sum = 0;
    while (queue.TryDequeue() is Some got)
        sum = sum + (long)got.Value;
    // 0 + 1 + ... + 3999
    printf("drained=%lld empty=%d again=%d\n",
        sum, queue.IsEmpty ? 1 : 0, queue.TryDequeue().HasValue ? 1 : 0);
    printf("fallback=%d\n", queue.DequeueOrDefault(-1));

    // ------------------------------------------------------------ stack
    var stack = new ConcurrentStack<int>();
    parallel
    {
        spawn Stack(stack, 0, 500);
        spawn Stack(stack, 500, 1000);
    }

    long stacked = 0;
    while (stack.TryPop() is Some popped)
        stacked = stacked + (long)popped.Value;
    printf("stacked=%lld empty=%d or=%d\n", stacked, stack.IsEmpty ? 1 : 0, stack.PopOrDefault(-7));

    // ------------------------------------------------------- dictionary
    var map = new ConcurrentDictionary<int, int>();
    parallel
    {
        spawn Record(map, 0, 500);
        spawn Record(map, 500, 1000);
        spawn Record(map, 1000, 1500);
        spawn Record(map, 1500, 2000);
    }
    printf("mapped=%llu at777=%d\n", map.Count, map.GetValueOrDefault(777, -1));

    // TryAdd is the operation ContainsKey-then-Set cannot be, since another
    // thread can insert between the two.
    printf("add=%d dup=%d\n",
        map.TryAdd(9999, 1) ? 1 : 0, map.TryAdd(777, 1) ? 1 : 0);

    var found = map.TryGetValue(1234);
    printf("get=%d %d absent=%d\n",
        found.HasValue ? 1 : 0, found.GetValueOrDefault(0),
        map.TryGetValue(-1).HasValue ? 1 : 0);
    printf("remove=%d gone=%d keys=%llu\n",
        map.TryRemove(9999) ? 1 : 0, map.TryRemove(9999) ? 1 : 0,
        map.GetKeys().Count);

    // ---------------------------------------------------------- channel
    // One producer, three consumers, and a close that wakes all of them.
    var channel = new Channel<int>();
    for (int i = 1; i <= 600; i = i + 1)
        channel.Add(i);
    channel.Close();

    var total = new AtomicLong(0);
    var seen = new AtomicLong(0);
    parallel
    {
        spawn Consume(channel, total, seen);
        spawn Consume(channel, total, seen);
        spawn Consume(channel, total, seen);
    }
    // 1 + 2 + ... + 600, and each item taken exactly once.
    printf("channel=%lld items=%lld closed=%d\n",
        total.Read(), seen.Read(), channel.IsClosed ? 1 : 0);
    printf("after-close=%d drained=%d\n",
        channel.Add(1) ? 1 : 0, channel.Take().HasValue ? 1 : 0);

    printf("done\n");
    return 0;
}
