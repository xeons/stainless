// SPDX-License-Identifier: 0BSD
//
// A Thread whose last reference goes on that same thread: its closure held
// its owner, and the owner's destructor lets go of the Thread. The join that
// destructor makes would wait on itself for ever, so it detaches instead.
module ThreadsDroppedOnItself;

import Standard.Console;
import Standard.Threading;

public threadsafe class Server
{
    Thread? _thread;
    ManualResetEvent _dropped;
    ManualResetEvent _gone;

    public Server(ManualResetEvent dropped, ManualResetEvent gone)
    {
        _dropped = dropped;
        _gone = gone;
    }

    public void Begin() => _thread = new Thread(() => this.Run());

    void Run()
    {
        _dropped.Wait();
        Console.WriteLine("worker ran");
    }

    ~Server()
    {
        _thread = null;
        Console.WriteLine("thread let go");
        _gone.Set();
    }
}

int Main()
{
    var dropped = new ManualResetEvent(false);
    var gone = new ManualResetEvent(false);

    {
        var server = new Server(dropped, gone);
        server.Begin();
    }

    dropped.Set();
    gone.Wait();
    Console.WriteLine("done");
    return 0;
}
