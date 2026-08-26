#import "AppController.h"
#import "DockItem.h"

static CGFloat DockWindowWidth = 84.0;
static CGFloat DockWindowHeight = 720.0;

@implementation AppController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  _dockOnRight = [[NSUserDefaults standardUserDefaults] boolForKey:@"DockOnRight"];
  frame = [self dockWindowFrameForRightSide:_dockOnRight];

  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setLevel:NSDockWindowLevel];
  [_window setOpaque:NO];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setTitle:@"AppsDockWM"];

  _dockView = [[DockView alloc] initWithFrame:NSMakeRect(0, 0,
                                                         NSWidth(frame),
                                                         NSHeight(frame))];
  [_dockView setDelegate:self];
  [_dockView setMenu:[self dockMenu]];
  [_window setContentView:_dockView];
  [_window makeKeyAndOrderFront:nil];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start]) {
    [_x11 setDockOnRight:_dockOnRight];
    [_window orderFrontRegardless];
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
  [_dockMenu release];
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

- (NSRect)dockWindowFrameForRightSide:(BOOL)rightSide
{
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  CGFloat height = DockWindowHeight;
  CGFloat x;
  CGFloat y;

  if (height > NSHeight(screenFrame)) {
    height = NSHeight(screenFrame);
  }

  x = rightSide ? NSMaxX(screenFrame) - DockWindowWidth : NSMinX(screenFrame);
  y = NSMaxY(screenFrame) - height;

  return NSMakeRect(x, y, DockWindowWidth, height);
}

- (void)updateDockMenu
{
  [_leftMenuItem setState:(_dockOnRight ? NSOffState : NSOnState)];
  [_rightMenuItem setState:(_dockOnRight ? NSOnState : NSOffState)];
}

- (NSMenu *)dockMenu
{
  if (!_dockMenu) {
    _dockMenu = [[NSMenu alloc] initWithTitle:@"Dock"];

    _leftMenuItem = [[NSMenuItem alloc] initWithTitle:@"Left Side"
                                              action:@selector(showDockOnLeft:)
                                       keyEquivalent:@""];
    [_leftMenuItem setTarget:self];
    [_dockMenu addItem:_leftMenuItem];
    [_leftMenuItem release];

    _rightMenuItem = [[NSMenuItem alloc] initWithTitle:@"Right Side"
                                               action:@selector(showDockOnRight:)
                                        keyEquivalent:@""];
    [_rightMenuItem setTarget:self];
    [_dockMenu addItem:_rightMenuItem];
    [_rightMenuItem release];
  }

  [self updateDockMenu];
  return _dockMenu;
}

- (void)setDockOnRight:(BOOL)rightSide
{
  if (_dockOnRight == rightSide && NSEqualRects([_window frame], [self dockWindowFrameForRightSide:rightSide])) {
    [self updateDockMenu];
    return;
  }

  _dockOnRight = rightSide;
  [[NSUserDefaults standardUserDefaults] setBool:_dockOnRight forKey:@"DockOnRight"];
  [_window setFrame:[self dockWindowFrameForRightSide:_dockOnRight] display:YES];
  [_x11 setDockOnRight:_dockOnRight];
  [self updateDockMenu];
}

- (void)showDockOnLeft:(id)sender
{
  [self setDockOnRight:NO];
}

- (void)showDockOnRight:(id)sender
{
  [self setDockOnRight:YES];
}

- (void)refreshDock
{
  [_dockView setItems:_items];
}

- (DockItem *)itemForXWindow:(unsigned long)xWindow
{
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    if ([item xWindow] == xWindow) {
      return item;
    }
  }
  return nil;
}

- (DockItem *)applicationItemMatchingTitle:(NSString *)title
{
  NSString *windowTitle = [title lowercaseString];
  NSUInteger i;

  if (![windowTitle length]) {
    return nil;
  }

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSString *appTitle;

    if ([item kind] != DockItemApplication) {
      continue;
    }

    appTitle = [[item title] lowercaseString];
    if ([appTitle length] &&
        ([windowTitle rangeOfString:appTitle].location != NSNotFound ||
         [appTitle rangeOfString:windowTitle].location != NSNotFound)) {
      return item;
    }
  }

  return nil;
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
    if ([item xWindow] && [item state] != DockItemNotRunning) {
      [_x11 activateWindow:[item xWindow]];
      return;
    }
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
                                          hidden:(BOOL)hidden
                                            icon:(NSImage *)icon
                                         dockApp:(BOOL)dockApp
{
  DockItem *item = dockApp ? nil : [self applicationItemMatchingTitle:title];

  if (item) {
    [item setState:(hidden ? DockItemHidden : DockItemRunning)];
    [item setXWindow:xWindow];
  } else {
    item = [DockItem x11ItemWithTitle:title window:xWindow icon:icon hidden:hidden];
    [_items addObject:item];
  }

  [self refreshDock];
  if (dockApp) {
    [_x11 dockWindow:xWindow atIndex:([_items count] - 1)];
  }
}

- (void)x11DockManagerDidUpdateWindow:(unsigned long)xWindow hidden:(BOOL)hidden
{
  DockItem *item = [self itemForXWindow:xWindow];
  if (item) {
    [item setState:(hidden ? DockItemHidden : DockItemRunning)];
    [self refreshDock];
  }
}

@end
