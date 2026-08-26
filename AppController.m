#import "AppController.h"
#import "DockItem.h"

@implementation AppController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect frame = NSMakeRect(60, 140, 84, 720);
  _items = [NSMutableArray new];

  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setLevel:NSDockWindowLevel];
  [_window setOpaque:NO];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setTitle:@"AppsDockWM"];

  _dockView = [[DockView alloc] initWithFrame:NSMakeRect(0, 0, 84, 720)];
  [_dockView setDelegate:self];
  [_window setContentView:_dockView];
  [_window makeKeyAndOrderFront:nil];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start]) {
    _scanTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:_x11
                                                selector:@selector(scanForDockApps)
                                                userInfo:nil
                                                 repeats:YES];
    [_x11 scanForDockApps];
  }
}

- (void)dealloc
{
  [_scanTimer invalidate];
  [_x11 release];
  [_dockView release];
  [_window release];
  [_items release];
  [super dealloc];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  return YES;
}

- (void)refreshDock
{
  [_dockView setItems:_items];
}

- (void)dockViewDidReceivePaths:(NSArray *)paths
{
  NSUInteger i;
  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
      [_items addObject:[DockItem applicationItemWithPath:path]];
    }
  }
  [self refreshDock];
}

- (void)dockViewDidActivateItem:(DockItem *)item
{
  if ([item kind] == DockItemApplication) {
    NSString *path = [item path];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if ([[path pathExtension] isEqualToString:@"desktop"]) {
      [self launchDesktopFile:path];
    } else if (isDir || [[path pathExtension] isEqualToString:@"app"]) {
      [[NSWorkspace sharedWorkspace] openFile:path];
    } else if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
      [NSTask launchedTaskWithLaunchPath:path arguments:[NSArray array]];
    } else {
      [[NSWorkspace sharedWorkspace] openFile:path];
    }
  } else {
    [_x11 activateWindow:[item xWindow]];
  }
}

- (void)launchDesktopFile:(NSString *)path
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];
  NSUInteger i;

  for (i = 0; i < [lines count]; i++) {
    NSString *line = [lines objectAtIndex:i];
    if ([line hasPrefix:@"Exec="]) {
      NSString *command = [line substringFromIndex:5];
      command = [[command componentsSeparatedByString:@"%"] objectAtIndex:0];
      if ([command length]) {
        [NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-lc", command, nil]];
      }
      return;
    }
  }
}

- (void)x11DockManagerDidDiscoverWindowWithTitle:(NSString *)title
                                          window:(unsigned long)xWindow
                                         dockApp:(BOOL)dockApp
{
  DockItem *item = [DockItem x11ItemWithTitle:title window:xWindow];
  [_items addObject:item];
  [self refreshDock];
  if (dockApp) {
    [_x11 dockWindow:xWindow atIndex:([_items count] - 1)];
  }
}

@end
