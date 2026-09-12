#import <Cocoa/Cocoa.h>
__attribute__((constructor)) static void startCapture(void) {
 if (![NSProcessInfo.processInfo.processName isEqualToString:@"tempo-time-live"]) return;
 NSString *trigger=NSProcessInfo.processInfo.environment[@"TEMPO_CAPTURE_REQUEST"];
 if (!trigger) return;
 dispatch_async(dispatch_get_main_queue(), ^{
  [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
   NSString *path=[NSString stringWithContentsOfFile:trigger encoding:NSUTF8StringEncoding error:nil];
   NSWindow *window=NSApp.mainWindow ?: NSApp.windows.firstObject;
   NSView *view=window.contentView.superview;
   if (!path || !view) return;
   [[NSFileManager defaultManager] removeItemAtPath:trigger error:nil];
   NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
   [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
   NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
   [png writeToFile:path atomically:YES];
   NSLog(@"Captured %ld x %ld",(long)rep.pixelsWide,(long)rep.pixelsHigh);
  }];
 });
}
