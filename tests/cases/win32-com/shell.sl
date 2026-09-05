// The Windows COM bindings: known folders, shell items, and the file dialog.
//
// tests/cases/com checks that the language's COM is self-consistent, with
// Stainless on both sides of every vtable. This checks it against Microsoft's:
// the objects here were built by the shell, the vtables are theirs, and the
// slot numbers in Win32.ShellCom have to agree with ShObjIdl.h exactly or the
// calls land on the wrong methods.
//
// The dialog is created and driven and never shown, because a test cannot
// answer one. Everything short of Show is here, and Show is one slot.
module Win32Com;

import Standard.Console;
import Standard.Text;
import Standard.Com;

import Win32.Com;
import Win32.Ole32;
import Win32.Shell;
import Win32.ShellCom;
import Win32.Dialogs;

void Say(String label, bool value) {
    Console.WriteLine(label + " " + Text.FromBool(value));
}

/// A known folder path is checked for shape rather than for content: what it
/// is depends on the machine, and that it is rooted and non-empty does not.
void Folder(String label, Result<String, ComError> found) {
    if (!found.Ok) { Console.WriteLine(label + " <failed>"); return; }

    String path = found.Value;
    bool rooted = path.ByteLength() > 3u && path.Substring(1u, 2u) == ":\\";
    Console.WriteLine(label + " " + Text.FromBool(rooted));
}

/// Everything that needs an apartment, in a scope that ends before the
/// apartment does -- see Win32.Com.Uninitialize for why that matters.
void Run() {
    // --- known folders ------------------------------------------------
    //
    // Downloads and SavedGames are the point: neither has an
    // SHGetFolderPathW number, and neither ever will.
    Folder("downloads ", Shell.Downloads());
    Folder("documents ", Shell.Documents());
    Folder("appdata   ", Shell.AppData());
    Folder("windows   ", Shell.WindowsFolder());
    Folder("savedgames", Shell.SavedGames());

    // A GUID survives being written out and read back.
    Say("guid round trip",
        Com.Format(Shell.DownloadsId()) ==
        Com.Format(Com.Parse(Com.Format(Shell.DownloadsId()))));

    // --- shell items --------------------------------------------------
    var windows = Shell.KnownFolder(Shell.WindowsId());
    if (!windows.Ok) { Console.WriteLine("no windows folder"); return; }

    var item = Shell.ItemFromPath(windows.Value);
    if (!item.Ok) { Console.WriteLine("no item"); return; }

    Say("path matches   ", Shell.PathOf(item.Value) == windows.Value);
    Say("is a folder    ", Shell.IsFolder(item.Value));
    Say("has a name     ", !Shell.NameOf(item.Value).IsEmpty());

    var parent = Shell.ParentOf(item.Value);
    Say("has a parent   ", parent.Ok);

    // An item for a path that is not there is a failure rather than a crash.
    Say("missing fails  ", !Shell.ItemFromPath("Z:\\no\\such\\place").Ok);

    // --- the file dialog ----------------------------------------------
    //
    // Created through CoCreateInstance and driven through a vtable the shell
    // built, which is what makes the slot numbers real rather than internally
    // consistent.
    var made = Com.Create(Dialogs.FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!made.Ok) { Console.WriteLine("no dialog"); return; }

    IFileOpenDialog dialog = (IFileOpenDialog)made.Value;

    // Slots 9 and 10. A round trip proves both are where ShObjIdl.h puts them:
    // a wrong number here would write into some other method's argument.
    uint before = 0u;
    dialog.GetOptions(&before);
    dialog.SetOptions(before | OptionForceShowHidden | OptionDontAddToRecent);

    uint after = 0u;
    dialog.GetOptions(&after);
    Say("options set    ", (after & OptionForceShowHidden) != 0u);
    Say("options kept   ", (after & OptionDontAddToRecent) != 0u);

    // Slots 16 and 17: what goes in comes back out.
    dialog.SetFileName("suggested.txt".ToUtf16().ToPointer());
    char16* name = null;
    if (Com.Succeeded(dialog.GetFileName(&name))) {
        Say("filename kept  ", Com.TakeString(name) == "suggested.txt");
    }

    // Slot 18, which returns nothing to check but would fault on a bad slot.
    Say("title accepted ",
        Com.Succeeded(dialog.SetTitle("A title".ToUtf16().ToPointer())));

    // Slots 13 and 14. Setting a folder takes an IShellItem rather than a
    // path, which is the whole reason this dialog replaced the old one.
    Say("folder set     ",
        Com.Succeeded(dialog.SetFolder((byte*)item.Value)));

    byte* back = null;
    if (Com.Succeeded(dialog.GetFolder(&back))) {
        IShellItem got = (IShellItem)back;
        Say("folder kept    ", Shell.PathOf(got) == windows.Value);
    }

    // Slots 4, 5 and 6: a type list, built from label and pattern pairs.
    //
    // Not with PickFolders set, which is why the options above use two flags
    // that do not conflict: the shell refuses a type list on a folder picker,
    // and it is right to.
    var held = new Utf16String[4];
    var specs = Dialogs.BuildSpecs(["Text", "*.txt", "All", "*.*"], held);
    Say("filters set    ",
        Com.Succeeded(dialog.SetFileTypes((uint)specs.Length, &specs[0])));

    dialog.SetFileTypeIndex(2u);
    uint index = 0u;
    dialog.GetFileTypeIndex(&index);
    Say("filter index   ", index == 2u);

    // The object is every interface its own extends, and reaching them costs
    // nothing: a COM vtable begins with its base's slots.
    IFileDialog asDialog = dialog;
    IModalWindow asModal = dialog;
    Say("is IFileDialog ", asDialog is IFileDialog);
    Say("is IModalWindow", asModal is IModalWindow);

    // And is not what it is not. This one is a real QueryInterface, and the
    // shell's own answer: an open dialog is not a save dialog.
    Say("not a save one ", !(asDialog is IFileSaveDialog));

    // A folder picker is the same dialog with one option, which is what
    // replaced SHBrowseForFolder.
    var picker = Com.Create(Dialogs.FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!picker.Ok) { return; }

    IFileOpenDialog folders = (IFileOpenDialog)picker.Value;
    uint mode = 0u;
    folders.GetOptions(&mode);
    folders.SetOptions(mode | OptionPickFolders);

    uint asked = 0u;
    folders.GetOptions(&asked);
    Say("picks folders  ", (asked & OptionPickFolders) != 0u);
}

public void Main() {
    if (!Com.Initialize()) { Console.WriteLine("COM would not start"); return; }

    Run();

    // Every reference Run made is gone, because Run's scope ended.
    Com.Uninitialize();
    Console.WriteLine("done");
}
