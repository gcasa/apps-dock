#import "AppController.h"
#import "DockItem.h"

static CGFloat DockWindowWidth = 84.0;
static CGFloat DockWindowHeight = 720.0;

static BOOL DockPlacementIsHorizontal(DockPlacement placement)
{
  return placement == DockPlacementTopCenter || placement == DockPlacementBottomCenter;
}

@implementation AppController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  _dockPlacement = [self savedDockPlacement];
  frame = [self dockWindowFrameForPlacement:_dockPlacement];

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
  [_dockView setHorizontal:DockPlacementIsHorizontal(_dockPlacement)];
  [_dockView setMenu:[self dockMenu]];
  [_window setContentView:_dockView];
  [_window makeKeyAndOrderFront:nil];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start]) {
    [_x11 setDockPlacement:_dockPlacement];
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
  [_placementMenuItems release];
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

- (DockPlacement)savedDockPlacement
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedPlacement = [defaults objectForKey:@"DockPlacement"];

  if (savedPlacement) {
    NSInteger placement = [defaults integerForKey:@"DockPlacement"];
    if (placement >= DockPlacementLeftTop && placement <= DockPlacementBottomCenter) {
      return (DockPlacement)placement;
    }
  }

  if ([defaults boolForKey:@"DockOnRight"]) {
    return [defaults boolForKey:@"DockCentered"] ? DockPlacementRightCenter : DockPlacementRightTop;
  }

  return [defaults boolForKey:@"DockCentered"] ? DockPlacementLeftCenter : DockPlacementLeftTop;
}

- (NSRect)dockWindowFrameForPlacement:(DockPlacement)placement
{
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  CGFloat width = DockPlacementIsHorizontal(placement) ? DockWindowHeight : DockWindowWidth;
  CGFloat height = DockPlacementIsHorizontal(placement) ? DockWindowWidth : DockWindowHeight;
  CGFloat x;
  CGFloat y;

  if (height > NSHeight(screenFrame)) {
    height = NSHeight(screenFrame);
  }
  if (width > NSWidth(screenFrame)) {
    width = NSWidth(screenFrame);
  }

  switch (placement) {
    case DockPlacementRightTop:
    case DockPlacementRightCenter:
      x = NSMaxX(screenFrame) - width;
      break;
    case DockPlacementTopCenter:
    case DockPlacementBottomCenter:
      x = NSMinX(screenFrame) + (NSWidth(screenFrame) - width) / 2.0;
      break;
    case DockPlacementLeftTop:
    case DockPlacementLeftCenter:
    default:
      x = NSMinX(screenFrame);
      break;
  }

  switch (placement) {
    case DockPlacementLeftCenter:
    case DockPlacementRightCenter:
      y = NSMinY(screenFrame) + (NSHeight(screenFrame) - height) / 2.0;
      break;
    case DockPlacementBottomCenter:
      y = NSMinY(screenFrame);
      break;
    case DockPlacementLeftTop:
    case DockPlacementRightTop:
    case DockPlacementTopCenter:
    default:
      y = NSMaxY(screenFrame) - height;
      break;
  }

  return NSMakeRect(x, y, width, height);
}

- (void)updateDockMenu
{
  NSUInteger i;

  for (i = 0; i < [_placementMenuItems count]; i++) {
    NSMenuItem *item = [_placementMenuItems objectAtIndex:i];
    [item setState:([item tag] == _dockPlacement ? NSOnState : NSOffState)];
  }
}

- (NSMenu *)dockMenu
{
  if (!_dockMenu) {
    NSArray *titles = [NSArray arrayWithObjects:
      @"Left Top",
      @"Left Center",
      @"Right Top",
      @"Right Center",
      @"Top Center",
      @"Bottom Center",
      nil];
    NSUInteger i;

    _dockMenu = [[NSMenu alloc] initWithTitle:@"Dock"];
    _placementMenuItems = [NSMutableArray new];

    for (i = 0; i < [titles count]; i++) {
      NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:i]
                                                    action:@selector(selectDockPlacement:)
                                             keyEquivalent:@""];
      [item setTarget:self];
      [item setTag:(NSInteger)i];
      [_dockMenu addItem:item];
      [_placementMenuItems addObject:item];
      [item release];
    }
  }

  [self updateDockMenu];
  return _dockMenu;
}

- (void)applyDockPlacement
{
  [[NSUserDefaults standardUserDefaults] setInteger:_dockPlacement forKey:@"DockPlacement"];
  [_dockView setHorizontal:DockPlacementIsHorizontal(_dockPlacement)];
  [_window setFrame:[self dockWindowFrameForPlacement:_dockPlacement]
            display:YES];
  [_dockView setFrame:NSMakeRect(0, 0,
                                 NSWidth([_window frame]),
                                 NSHeight([_window frame]))];
  [_x11 setDockPlacement:_dockPlacement];
  [self updateDockMenu];
}

- (void)selectDockPlacement:(id)sender
{
  _dockPlacement = (DockPlacement)[sender tag];
  [self applyDockPlacement];
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
