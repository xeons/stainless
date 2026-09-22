// SPDX-License-Identifier: 0BSD
//
// Slow work off the UI thread, and the answer back onto it.
//
//   stainless run samples/forms/background.sl forms/src bindings/win32/api \
//       bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
//
// Click Fetch and the window stays alive while the work runs -- drag it, resize
// it, click Count. Neither is possible if the work is done on the UI thread,
// which is what the Block button demonstrates by doing exactly that.
//
// `--selftest` proves the part a screenshot cannot: that the continuation runs,
// that it runs on the UI thread, and that it carries the value the work
// returned.
module BackgroundSample;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.Threading;
import Forms;
import Forms.Drawing;
import Forms.Platform;

/// Stands in for a slow call -- a socket read, a big file, a query. It sleeps,
/// which is exactly what makes it the wrong thing to put on the worker pool:
/// a pool thread parked in a syscall is a pool thread doing nothing.
String Fetch(String city)
{
    Sleep(1200u);
    return city + ": 14 degrees and raining";
}

public class BackgroundForm : Form
{
    Label _explain;
    TextBox _city;
    Button _fetch;
    Button _block;
    Button _count;
    Label _forecast;
    Label _clicks;

    int _clicked;

    /// What the last continuation saw, for the self test: the value it was
    /// handed, and whether it was on the right thread when it got it.
    public String Delivered;
    public bool DeliveredOnUiThread;

    public BackgroundForm()
    {
        base(WindowBorder.Sizable);
        Text = "Work on another thread";
        SetBounds(0, 0, 520, 230);

        _clicked = 0;
        Delivered = "";
        DeliveredOnUiThread = false;

        _explain = new Label(this);
        _explain.SetBounds(12, 12, 490, 34);
        _explain.Text = "Fetch runs on a thread of its own and posts its answer back. "
                      + "Block does the same work on this thread, so the window freezes.";

        _city = new TextBox(this);
        _city.SetBounds(12, 56, 180, 26);
        _city.Text = "Edinburgh";

        _fetch = new Button(this);
        _fetch.SetBounds(202, 56, 90, 26);
        _fetch.Text = "Fetch";
        _fetch.Click += this.OnFetch;

        _block = new Button(this);
        _block.SetBounds(300, 56, 90, 26);
        _block.Text = "Block";
        _block.Click += this.OnBlock;

        _count = new Button(this);
        _count.SetBounds(398, 56, 90, 26);
        _count.Text = "Count";
        _count.Click += this.OnCount;

        _forecast = new Label(this);
        _forecast.SetBounds(12, 100, 490, 22);
        _forecast.Text = "";

        _clicks = new Label(this);
        _clicks.SetBounds(12, 130, 490, 22);
        _clicks.Text = "Count: 0 -- click it while a fetch is running";
    }

    /// The whole pattern, and the reason this sample exists.
    ///
    /// `_city.Text` is read here, on the UI thread, and the copy is what the
    /// work closure carries. Reading it inside the work would be the bug the
    /// arrangement exists to avoid.
    /// Starts a fetch without a click, so that a screenshot can be taken of the
    /// state after one -- which is the only thing that shows the continuation
    /// reached the screen rather than merely running.
    public void StartFetch() => OnFetch(this);

    void OnFetch(Control sender)
    {
        var city = _city.Text;

        _fetch.Enabled = false;
        _forecast.Text = "fetching...";

        Background.Run(
            () => Fetch(city),
            weather =>
            {
                _forecast.Text = weather;
                _fetch.Enabled = true;

                // `this.` is not decoration. A bare member write inside a
                // lambda assigns to the captured *copy* -- §2.15 of the spec --
                // so without it these two record nothing and the check below
                // fails for a reason that has nothing to do with threads.
                this.Delivered = weather;
                this.DeliveredOnUiThread = Application.OnUiThread;
            });
    }

    /// The same work, on the wrong thread, so there is something to compare
    /// against. The window stops answering for as long as this runs.
    void OnBlock(Control sender)
    {
        _forecast.Text = Fetch(_city.Text) + "  (and the window was frozen)";
    }

    void OnCount(Control sender)
    {
        _clicked++;
        _clicks.Text = "Count: " + FromInteger(_clicked)
                     + " -- click it while a fetch is running";
    }

    public int Clicked => _clicked;

    /// What can be checked with nobody in front of it, and it is the part that
    /// matters: a self test that only read back what it set would pass whether
    /// or not a single byte ever crossed a thread.
    public bool SelfTest()
    {
        bool ok = true;

        // Nothing has been fetched, so nothing has been delivered.
        if (Delivered != "")
        {
            Console.WriteLine("FAIL: something was delivered before any fetch");
            ok = false;
        }

        OnFetch(this);

        // The UI thread stays responsive while the work runs, which is the
        // whole claim. Pumping is what a person dragging the window would do.
        for (int i = 0; i < 40 && Delivered == ""; i++)
        {
            OnCount(this);
            Application.DoEvents();
            Sleep(50u);
        }

        if (Delivered == "")
        {
            Console.WriteLine("FAIL: the continuation never ran");
            return false;
        }

        Console.WriteLine("  ok   the continuation ran");

        if (!DeliveredOnUiThread)
        {
            Console.WriteLine("FAIL: the continuation ran off the UI thread");
            ok = false;
        }
        else
        {
            Console.WriteLine("  ok   it ran on the UI thread");
        }

        if (Delivered != "Edinburgh: 14 degrees and raining")
        {
            Console.WriteLine("FAIL: it carried '" + Delivered + "'");
            ok = false;
        }
        else
        {
            Console.WriteLine("  ok   it carried what the work returned");
        }

        // The clicks happened while the fetch was in flight, which is the
        // difference between this and doing the work here.
        if (Clicked < 2)
        {
            Console.WriteLine("FAIL: the UI was not answering during the fetch");
            ok = false;
        }
        else
        {
            Console.WriteLine("  ok   the UI answered " + FromInteger(Clicked)
                            + " times while the work ran");
        }

        // Post from this thread too: it is the UI thread, so the work is queued
        // rather than run, and one pump is enough to see it.
        // An `AtomicBool` rather than a `bool`, and not because of threads:
        // capture is by value, so a lambda assigning to a captured local writes
        // its own copy and this would read false however well Post worked. A
        // class reference is copied too, and a copy of a reference still names
        // the one object.
        var posted = new AtomicBool(false);
        Application.Post(() => posted.Store(true));
        if (posted.Load())
        {
            Console.WriteLine("FAIL: Post ran its work before the loop turned");
            ok = false;
        }

        Application.DoEvents();
        if (!posted.Load())
        {
            Console.WriteLine("FAIL: Post never ran its work");
            ok = false;
        }
        else
        {
            Console.WriteLine("  ok   Post queued rather than ran, and the loop ran it");
        }

        // Send from the UI thread runs inline rather than deadlocking against
        // a loop it is itself blocking.
        var sent = new AtomicBool(false);
        Application.Send(() => sent.Store(true));
        if (!sent.Load())
        {
            Console.WriteLine("FAIL: Send from the UI thread did not run inline");
            ok = false;
        }
        else
        {
            Console.WriteLine("  ok   Send ran inline on the UI thread");
        }

        return ok;
    }
}

int Main()
{
    Application.Initialize();
    var form = new BackgroundForm();

    bool testing = false;
    bool fetching = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
        if (arguments[i] == "--fetch")
            fetching = true;
    }

    if (testing)
    {
        Console.WriteLine("Forms for Stainless -- work on another thread");
        form.Show();
        for (int i = 0; i < 20; i++)
            Application.DoEvents();
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    if (fetching)
        form.StartFetch();
    Application.Run();
    return 0;
}
