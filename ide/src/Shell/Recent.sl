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

// The files and projects opened lately, newest first, kept in `recent.json`
// beside the layout. Read the same forgiving way the layout is: a file that
// cannot be read is an empty list, never a reason not to start.
module Ide.Shell;

import Standard.Collections;
import Standard.Directory;
import Standard.File;
import Standard.IO;
import Standard.Json;

/// How many of each are kept, as Visual Studio keeps.
public const nuint RecentLimit = 10u;

public class RecentItems
{
    public List<String> Files;
    public List<String> Projects;

    public RecentItems()
    {
        Files = new List<String>();
        Projects = new List<String>();
    }

    public void RememberFile(String path) => RememberIn(Files, path);
    public void RememberProject(String path) => RememberIn(Projects, path);

    /// Moves `path` to the front of `list`, or puts it there, and drops what
    /// falls off the end. One file named two ways is one entry.
    static void RememberIn(List<String> list, String path)
    {
        for (nuint i = 0u; i < list.Count; i++)
        {
            if (Standard.Path.IsSamePath(list[i], path))
            {
                list.RemoveAt(i);
                break;
            }
        }
        list.Insert(0u, path);
        while (list.Count > RecentLimit)
            list.RemoveAt(list.Count - 1u);
    }
}

public String GetRecentPath() => Standard.Path.Join(GetSettingsDirectory(), "recent.json");

public RecentItems ReadRecent(String path)
{
    var recent = new RecentItems();
    if (!File.Exists(path))
        return recent;
    var text = File.ReadAllText(path);
    if (!text.Ok)
        return recent;
    var parsed = Json.Parse(text.Value);
    if (!parsed.Ok)
        return recent;
    var document = parsed.Value;
    if (!document.Object)
        return recent;

    var members = document.Members;
    ReadRecentList(members, "files", recent.Files);
    ReadRecentList(members, "projects", recent.Projects);
    return recent;
}

void ReadRecentList(JsonObject members, String name, List<String> into)
{
    if (members.IndexOf(name) is not Some at)
        return;
    var value = members.GetValueAt(at.Value);
    if (!value.Array)
        return;
    foreach (var item in value.Items)
    {
        String path = Json.GetTextOrDefault(item, "");
        if (path != "" && into.Count < RecentLimit)
            into.Add(path);
    }
}

/// Saves the lists, making the directory if it is not there. Answers whether
/// they landed; nothing depends on it.
public bool SaveRecent(RecentItems recent, String path)
{
    String folder = Standard.Path.GetDirectoryName(path);
    if (folder != "" && !Directory.Exists(folder))
    {
        if (Directory.CreateDirectoryTree(folder) != IOError.None)
            return false;
    }

    var members = new JsonObject();
    members.Add("files", JsonValue.Array(WriteRecentList(recent.Files)));
    members.Add("projects", JsonValue.Array(WriteRecentList(recent.Projects)));
    return File.WriteAllText(path, Json.ToJsonTextIndented(JsonValue.Object(members))) == IOError.None;
}

List<JsonValue> WriteRecentList(List<String> paths)
{
    var values = new List<JsonValue>();
    foreach (var path in paths)
        values.Add(JsonValue.Text(path));
    return values;
}
