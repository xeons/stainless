// SPDX-License-Identifier: 0BSD
module IoTest;

import Standard.Collections;
import Standard.IO;
import Standard.File;
import Standard.Directory;
import Standard.Path;
import Standard.Console;

extern "C" int printf(byte* format, ...);
extern "C" byte* getenv(byte* name);

// Somewhere writable that is not the source tree. The test cleans up after
// itself, but it should not be leaving anything behind here either way.
String Scratch() {
    var windows = getenv("TEMP".ToPointer());
    if (windows != null) { return Path.Join(Text.FromNullTerminated(windows), "stainless-io"); }

    var unix = getenv("TMPDIR".ToPointer());
    if (unix != null) { return Path.Join(Text.FromNullTerminated(unix), "stainless-io"); }

    return "stainless-io";
}

// Removes the tree from a previous run, so the test starts from nothing.
void Wipe(String root) {
    if (!Directory.Exists(root)) { return; }

    var files = Directory.AllFiles(root);
    if (files.Ok) {
        for (nuint i = 0; i < files.Value.Count(); i = i + 1) { File.Delete(files.Value.At(i)); }
    }

    var nested = Directory.Directories(root);
    if (nested.Ok) {
        for (nuint i = 0; i < nested.Value.Count(); i = i + 1) { Directory.Delete(nested.Value.At(i)); }
    }

    Directory.Delete(root);
}

int Main() {
    // -------------------------------------------------------------- paths
    // Purely textual: nothing below touches a disk.
    printf("join=%s %s %s\n",
        Path.Join("a", "b").ToPointer(),
        Path.Join("a/", "b").ToPointer(),
        Path.Join("a/", "/b").ToPointer());

    printf("name=%s dir=%s\n",
        Path.FileName("x/y/notes.txt").ToPointer(),
        Path.DirectoryName("x/y/notes.txt").ToPointer());

    printf("ext=%s stem=%s with=%s\n",
        Path.Extension("x/y/notes.txt").ToPointer(),
        Path.WithoutExtension("x/y/notes.txt").ToPointer(),
        Path.WithExtension("x/notes.txt", "md").ToPointer());

    printf("noext=%s dotfile=%s\n",
        Path.Extension("README").ToPointer(),
        Path.Extension(".gitignore").ToPointer());

    printf("rooted=%d %d %d parts=%llu\n",
        Path.IsRooted("/x") ? 1 : 0, Path.IsRooted("C:/x") ? 1 : 0,
        Path.IsRooted("x") ? 1 : 0, Path.Split("a/b/c").Count());

    // ------------------------------------------------------- memory stream
    var buffer = new MemoryStream();
    buffer.WriteText("hello ");
    buffer.WriteText("world");
    printf("memory=%s length=%lld position=%lld\n",
        buffer.ToText().ToPointer(), buffer.Length(), buffer.Position());

    buffer.Seek(0, SeekOrigin.Start);
    var five = new byte[5];
    printf("memory-read=%llu bytes=%s at=%lld\n",
        buffer.Read(five, 0, (nuint)5), Text.FromBytes(&five[0], (nuint)5).ToPointer(),
        buffer.Position());

    printf("memory-can=%d%d%d seek-past=%d\n",
        buffer.CanRead() ? 1 : 0, buffer.CanWrite() ? 1 : 0, buffer.CanSeek() ? 1 : 0,
        buffer.Seek(9999, SeekOrigin.Start) ? 1 : 0);

    // ------------------------------------------------------------- files
    var root = Scratch();
    Wipe(root);

    printf("create=%d exists=%d\n",
        (int)Directory.CreateAll(Path.Join(root, "nested")),
        Directory.Exists(root) ? 1 : 0);

    var notes = Path.Join(root, "notes.txt");
    printf("write=%d is-file=%d size=%lld\n",
        (int)File.WriteAllText(notes, "line one\nline two\n"),
        File.Exists(notes) ? 1 : 0, File.Size(notes));

    var text = File.ReadAllText(notes);
    printf("read=%d bytes=%llu\n", text.Ok ? 1 : 0, text.Ok ? text.Value.ByteLength() : 0);

    var lines = File.ReadAllLines(notes);
    if (lines.Ok) {
        printf("lines=%llu first=%s last=%s\n",
            lines.Value.Count(), lines.Value.At(0).ToPointer(),
            lines.Value.At(lines.Value.Count() - 1).ToPointer());
    }

    File.AppendText(notes, "line three\n");
    var appended = File.ReadAllLines(notes);
    if (appended.Ok) { printf("appended=%llu\n", appended.Value.Count()); }

    var raw = File.ReadAllBytes(notes);
    printf("bytes=%d %llu\n", raw.Ok ? 1 : 0, raw.Ok ? raw.Value.Length : 0);

    // A missing file is an ordinary outcome and says why. Its Error is readable
    // only because the check proved there is one.
    var missing = File.ReadAllText(Path.Join(root, "nope.txt"));
    if (!missing.Ok) {
        printf("missing=0 reason=%s\n", IO.Describe(missing.Error).ToPointer());
    }

    // There is no failed value to read by mistake; a caller that wants to carry
    // on supplies its own.
    printf("missing-value=%llu\n", missing.ValueOr("").ByteLength());

    // --------------------------------------------------------- file stream
    var stream = File.OpenRead(notes);
    var head = new byte[4];
    nuint got = stream.Read(head, 0, (nuint)4);
    printf("stream=%d read=%llu head=%s position=%lld\n",
        stream.IsOpen() ? 1 : 0, got,
        Text.FromBytes(&head[0], got).ToPointer(), stream.Position());

    printf("can=%d%d%d length=%lld\n",
        stream.CanRead() ? 1 : 0, stream.CanWrite() ? 1 : 0, stream.CanSeek() ? 1 : 0,
        stream.Length());

    stream.Seek(0, SeekOrigin.Start);
    var whole = IO.ReadTextToEnd(stream);
    stream.Close();
    printf("whole=%d bytes=%llu after-close=%llu\n",
        whole.Ok ? 1 : 0, whole.Ok ? whole.Value.ByteLength() : 0,
        stream.Read(head, 0, (nuint)4));
    printf("closed-error=%s\n", IO.Describe(stream.Error()).ToPointer());

    // Opening something that is not there fails without a null to unwrap.
    var absent = File.OpenRead(Path.Join(root, "nope.txt"));
    printf("absent-open=%d reason=%s\n",
        absent.IsOpen() ? 1 : 0, IO.Describe(absent.Error()).ToPointer());

    // Writing through a stream, then reading it back.
    var written = File.Create(Path.Join(root, "stream.txt"));
    written.WriteText("via a stream");
    written.Close();
    var back = File.ReadAllText(Path.Join(root, "stream.txt"));
    if (back.Ok) { printf("round-trip=%s\n", back.Value.ToPointer()); }

    // --------------------------------------------------------- directories
    File.WriteAllText(Path.Join(root, "nested", "deep.txt"), "deep");
    var lineList = new List<String>();
    lineList.Add("alpha");
    lineList.Add("beta");
    File.WriteAllLines(Path.Join(root, "list.txt"), lineList);

    var entries = Directory.Entries(root);
    var files = Directory.Files(root);
    var dirs = Directory.Directories(root);
    var everything = Directory.AllFiles(root);
    if (entries.Ok && files.Ok && dirs.Ok && everything.Ok) {
        printf("entries=%llu files=%llu dirs=%llu all-files=%llu\n",
            entries.Value.Count(), files.Value.Count(),
            dirs.Value.Count(), everything.Value.Count());
    }

    var listed = File.ReadAllLines(Path.Join(root, "list.txt"));
    if (listed.Ok) {
        printf("written-lines=%llu %s\n",
            listed.Value.Count(), listed.Value.At(1).ToPointer());
    }

    var nowhere = Directory.Entries(Path.Join(root, "no-such"));
    if (!nowhere.Ok) {
        printf("no-dir=0 reason=%s\n", IO.Describe(nowhere.Error).ToPointer());
    }

    // Copy and rename.
    File.Copy(notes, Path.Join(root, "copy.txt"));
    printf("copied=%lld renamed=%d\n",
        File.Size(Path.Join(root, "copy.txt")),
        (int)File.Rename(Path.Join(root, "copy.txt"), Path.Join(root, "moved.txt")));
    printf("moved=%d original-gone=%d\n",
        File.Exists(Path.Join(root, "moved.txt")) ? 1 : 0,
        File.Exists(Path.Join(root, "copy.txt")) ? 1 : 0);

    // ------------------------------------------------------------- cleanup
    Wipe(root);
    printf("cleaned=%d\n", Directory.Exists(root) ? 1 : 0);

    printf("done\n");
    return 0;
}
