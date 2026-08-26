#import <AppKit/AppKit.h>
#import "AppController.h"

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSApplication *app = [NSApplication sharedApplication];
  AppController *delegate = [AppController new];

  [app setDelegate:delegate];
  [app run];

  [delegate release];
  [pool release];
  return 0;
}
