// SPDX-License-Identifier: 0BSD
//
// Reference-heavy work, for measuring what retain and release cost: a search
// tree of Strings built, searched and walked, a list of records filled and
// read back, and a chain of short-lived objects passed through conditionals.
// tools/arccount.ps1 builds it, counts its calls and times it.
module ArcBench;

import Standard.Console;
import Standard.Collections;

class TreeNode
{
    public String Key;
    public TreeNode? Left;
    public TreeNode? Right;

    public TreeNode(String key) { Key = key; }
}

class Tree
{
    TreeNode? _root;

    public void Insert(String key)
    {
        if (_root is TreeNode root)
            InsertUnder(root, key);
        else
            _root = new TreeNode(key);
    }

    void InsertUnder(TreeNode node, String key)
    {
        int order = key.CompareTo(node.Key);
        if (order == 0)
            return;

        if (order < 0)
        {
            if (node.Left is TreeNode left)
                InsertUnder(left, key);
            else
                node.Left = new TreeNode(key);
        }
        else
        {
            if (node.Right is TreeNode right)
                InsertUnder(right, key);
            else
                node.Right = new TreeNode(key);
        }
    }

    public bool Contains(String key) => ContainsUnder(_root, key);

    bool ContainsUnder(TreeNode? node, String key)
    {
        if (node is null)
            return false;

        int order = key.CompareTo(node.Key);
        if (order == 0)
            return true;
        return ContainsUnder(order < 0 ? node.Left : node.Right, key);
    }

    public long MeasureKeys() => MeasureKeysUnder(_root);

    long MeasureKeysUnder(TreeNode? node)
    {
        if (node is null)
            return 0;
        return (long)node.Key.ByteLength() + MeasureKeysUnder(node.Left) + MeasureKeysUnder(node.Right);
    }
}

struct Entry
{
    public String Name;
    public String Value;
    public int Weight;

    public Entry(String name, String value, int weight)
    {
        Name = name;
        Value = value;
        Weight = weight;
    }
}

class Link
{
    public Link? Next;
    public String Label;

    public Link(String label, Link? next)
    {
        Label = label;
        Next = next;
    }
}

String FormatKey(int n) => "key-" + Standard.Convert.FromLong((long)((n * 7919) % 100003), 10u);

Link? PickLink(Link? first, Link? second, int n) => n % 2 == 0 ? first : second;

int Main()
{
    var tree = new Tree();
    for (int i = 0; i < 60000; i++)
        tree.Insert(FormatKey(i));

    int found = 0;
    for (int i = 0; i < 120000; i++)
        if (tree.Contains(FormatKey(i)))
            found++;

    Console.WriteLine("tree: " + Standard.Convert.FromLong((long)found, 10u) + " found, " +
                      Standard.Convert.FromLong(tree.MeasureKeys(), 10u) + " bytes of keys");

    var entries = new List<Entry>();
    for (int i = 0; i < 100000; i++)
    {
        var name = FormatKey(i);
        entries.Add(new Entry(name, i % 3 == 0 ? name : "value", i % 17));
    }

    long weight = 0;
    for (int round = 0; round < 10; round++)
        foreach (var entry in entries)
        {
            var copy = entry;
            weight += (long)copy.Weight + (long)copy.Value.ByteLength();
        }

    Console.WriteLine("entries: " + Standard.Convert.FromLong(weight, 10u));

    Link? chain = null;
    for (int i = 0; i < 200000; i++)
    {
        var made = new Link(i % 5 == 0 ? FormatKey(i) : "link", i % 100 == 0 ? null : chain);
        chain = PickLink(made, chain, i) ?? made;
    }

    long labels = 0;
    var at = chain;
    while (at is Link link)
    {
        labels += (long)link.Label.ByteLength();
        at = link.Next;
    }

    Console.WriteLine("chain: " + Standard.Convert.FromLong(labels, 10u));
    return 0;
}
