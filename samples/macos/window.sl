// A window over the generated AppKit bindings: a view defined here that draws
// itself with NSBezierPath, and an application delegate that opens the window.
//
//     stainless build samples/macos/window.sl $(ls -d bindings/macos/*/ | grep -v api/) -o window
//     ./window                          # the window, until it is closed
//     ./window --screenshot shot.png    # the view drawn into a PNG, and no window
module MacWindow;

import Standard.Console;
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.Foundation;
import MacOS.AppKit;

NSRect MakeRect(double x, double y, double width, double height)
{
    NSRect rect;
    rect.origin.x = x;
    rect.origin.y = y;
    rect.size.width = width;
    rect.size.height = height;
    return rect;
}

NSColor MakeColor(double red, double green, double blue) =>
    NSColor.ColorWithSRGBRedGreenBlueAlpha(red, green, blue, 1);

/// Three rings and a frame, drawn whenever AppKit asks.
public objc class Canvas : NSView
{
    public override void DrawRect(NSRect dirtyRect)
    {
        var bounds = Bounds;
        MakeColor(0.97, 0.96, 0.93).SetFill();
        NSBezierPath.FillRect(bounds);

        double size = bounds.size.height * 0.5;
        double y = (bounds.size.height - size) / 2;
        NSColor[] colors = [MakeColor(0.85, 0.25, 0.2), MakeColor(0.2, 0.55, 0.3), MakeColor(0.2, 0.35, 0.8)];
        for (int i = 0; i < 3; i++)
        {
            double x = bounds.size.width * (i + 1) / 4 - size / 2;
            var ring = NSBezierPath.BezierPathWithOvalInRect(MakeRect(x, y, size, size));
            ring.LineWidth = 10;
            colors[i].SetStroke();
            ring.Stroke();
        }

        var frame = NSBezierPath.BezierPathWithRoundedRectXRadiusYRadius(
            MakeRect(8, 8, bounds.size.width - 16, bounds.size.height - 16), 12, 12);
        frame.LineWidth = 2;
        MakeColor(0.3, 0.3, 0.3).SetStroke();
        frame.Stroke();
    }
}

public objc class AppDelegate : NSObject, NSApplicationDelegate
{
    NSWindow? _window;

    public void ApplicationDidFinishLaunching(NSNotification notification)
    {
        var style = NSWindowStyleMask.Titled | NSWindowStyleMask.Closable | NSWindowStyleMask.Resizable;
        var window = NSWindow.Alloc().InitWithContentRectStyleMaskBackingDefer(
            MakeRect(200, 200, 480, 240), style, NSBackingStoreType.Buffered, false);
        window.Title = NSString.StringWithUTF8String("Stainless")!;
        window.ContentView = Canvas.Alloc().InitWithFrame(MakeRect(0, 0, 480, 240));
        window.MakeKeyAndOrderFront(null);
        NSApplication.SharedApplication.ActivateIgnoringOtherApps(true);
        _window = window;
    }

    public bool ApplicationShouldTerminateAfterLastWindowClosed(NSApplication sender) => true;
}

/// The view drawn into a bitmap as AppKit would draw it on screen, and written as a PNG.
int Screenshot(byte* path)
{
    var view = Canvas.Alloc().InitWithFrame(MakeRect(0, 0, 480, 240));
    var bounds = view.Bounds;
    if (view.BitmapImageRepForCachingDisplayInRect(bounds) is not { } bitmap)
    {
        Console.WriteLine("no bitmap to draw into");
        return 1;
    }

    view.CacheDisplayInRectToBitmapImageRep(bounds, bitmap);
    var png = bitmap.RepresentationUsingTypeProperties(NSBitmapImageFileType.PNG, NSDictionary.Dictionary());
    if (png is null || !png.WriteToFileAtomically(NSString.StringWithUTF8String(path)!, true))
    {
        Console.WriteLine("the PNG could not be written");
        return 1;
    }

    Console.WriteLine($"wrote {png.Length} bytes");
    return 0;
}

int Main(String[] args)
{
    var application = NSApplication.SharedApplication;
    application.SetActivationPolicy(NSApplicationActivationPolicy.Regular);

    if (args.Length == 2 && args[0] == "--screenshot")
        return Screenshot(args[1].ToPointer());

    var opener = AppDelegate.Alloc().Init();
    application.Delegate = opener;
    application.Run();
    return 0;
}
