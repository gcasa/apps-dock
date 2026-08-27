#import "AppController.h"
#import "DockItem.h"
#import <ctype.h>
#import <limits.h>
#import <unistd.h>

static CGFloat DockWindowWidth = 84.0;
static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;
static NSString *DockApplicationsDefaultsKey = @"DockApplications";
static NSString *DockBackgroundModeDefaultsKey = @"DockBackgroundMode";

static BOOL DockPlacementIsHorizontal(DockPlacement placement)
{
  return placement == DockPlacementTopCenter || placement == DockPlacementBottomCenter;
}

@implementation AppController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  [self loadPersistedApplications];
  _dockPlacement = [self savedDockPlacement];
  _backgroundMode = [self savedBackgroundMode];
  frame = [self dockWindowFrameForPlacement:_dockPlacement];

  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setLevel:NSDockWindowLevel];
  [_window setOpaque:NO];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setTitle:@"AppsDockWM"];
  [_window setAcceptsMouseMovedEvents:YES];

  _dockView = [[DockView alloc] initWithFrame:NSMakeRect(0, 0,
                                                         NSWidth(frame),
                                                         NSHeight(frame))];
  [_dockView setDelegate:self];
  [_dockView setHorizontal:DockPlacementIsHorizontal(_dockPlacement)];
  [_dockView setBackgroundMode:_backgroundMode];
  [_dockView setItems:_items];
  [_dockView setMenu:[self dockMenu]];
  [_window setContentView:_dockView];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start]) {
    [_x11 setDockPlacement:_dockPlacement];
    [self updateDockBackgroundHidingWindow:NO];
    [_window makeKeyAndOrderFront:nil];
    [_window orderFrontRegardless];
    _scanTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:_x11
                                                selector:@selector(scanForDockApps)
                                                userInfo:nil
                                                 repeats:YES];
    [_x11 scanForDockApps];
  } else {
    [_window makeKeyAndOrderFront:nil];
  }

  _processScanTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(scanRunningApplications)
                                                     userInfo:nil
                                                      repeats:YES];
  [self scanRunningApplications];
}

- (void)dealloc
{
  [_scanTimer invalidate];
  [_processScanTimer invalidate];
  [_transparentBackgroundMenuItem release];
  [_blackBackgroundMenuItem release];
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

- (void)applicationWillTerminate:(NSNotification *)notification
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
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

- (DockBackgroundMode)savedBackgroundMode
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedMode = [defaults objectForKey:DockBackgroundModeDefaultsKey];

  if (savedMode) {
    NSInteger mode = [defaults integerForKey:DockBackgroundModeDefaultsKey];
    if (mode >= DockBackgroundBlack &&
        mode <= DockBackgroundSimulatedTransparency) {
      return (DockBackgroundMode)mode;
    }
  }

  return DockBackgroundBlack;
}

- (void)loadPersistedApplications
{
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
    objectForKey:DockApplicationsDefaultsKey];
  NSUInteger i;

  if (![paths isKindOfClass:[NSArray class]]) {
    return;
  }

  for (i = 0; i < [paths count]; i++) {
    id path = [paths objectAtIndex:i];
    BOOL isDir = NO;

    if (![path isKindOfClass:[NSString class]]) {
      continue;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:path
                                             isDirectory:&isDir] &&
        ![self dockHasApplicationPath:path]) {
      [_items addObject:[DockItem applicationItemWithPath:path]];
    }
  }
}

- (void)savePersistedApplications
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSString *path = [item path];

    if ([item kind] == DockItemApplication &&
        [path length] &&
        ![paths containsObject:path]) {
      [paths addObject:path];
    }
  }

  [defaults setObject:paths forKey:DockApplicationsDefaultsKey];
  [defaults synchronize];
}

- (BOOL)dockHasApplicationPath:(NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length]) {
    return NO;
  }

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    if ([item kind] == DockItemApplication &&
        [[self normalizedPath:[item path]] isEqualToString:normalizedPath]) {
      return YES;
    }
  }

  return NO;
}

- (NSString *)normalizedPath:(NSString *)path
{
  if (![path length]) {
    return nil;
  }

  return [path stringByResolvingSymlinksInPath];
}

- (NSString *)executablePathForApplicationPath:(NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  if (![path length]) {
    return nil;
  }

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"app"] && isDir) {
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSString *executablePath = [bundle executablePath];
    NSString *fallbackPath;

    if ([executablePath length]) {
      return [self normalizedPath:executablePath];
    }

    fallbackPath = [path stringByAppendingPathComponent:
      [[path lastPathComponent] stringByDeletingPathExtension]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackPath]) {
      return [self normalizedPath:fallbackPath];
    }
  }

  if ([extension isEqualToString:@"desktop"]) {
    NSString *desktopExecutable = [self executablePathForDesktopFile:path];
    if ([desktopExecutable length]) {
      return desktopExecutable;
    }
  }

  if (!isDir && [[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return [self normalizedPath:path];
  }

  return [self normalizedPath:path];
}

- (NSString *)firstCommandTokenFromString:(NSString *)string
{
  NSMutableString *token = [NSMutableString string];
  NSUInteger i;
  BOOL quoted = NO;
  unichar quote = 0;

  for (i = 0; i < [string length]; i++) {
    unichar ch = [string characterAtIndex:i];

    if (quoted) {
      if (ch == quote) {
        quoted = NO;
      } else {
        [token appendFormat:@"%C", ch];
      }
    } else if (ch == '"' || ch == '\'') {
      quoted = YES;
      quote = ch;
    } else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
                  characterIsMember:ch]) {
      if ([token length]) {
        break;
      }
    } else {
      [token appendFormat:@"%C", ch];
    }
  }

  return [token length] ? token : nil;
}

- (NSString *)pathForExecutableCommand:(NSString *)command
{
  NSArray *pathComponents;
  NSUInteger i;

  if (![command length]) {
    return nil;
  }

  if ([command isAbsolutePath] &&
      [[NSFileManager defaultManager] fileExistsAtPath:command]) {
    return [self normalizedPath:command];
  }

  pathComponents = [[[NSProcessInfo processInfo] environment]
    objectForKey:@"PATH"] ?
    [[[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"]
      componentsSeparatedByString:@":"] :
    [NSArray arrayWithObjects:@"/usr/local/bin", @"/usr/bin", @"/bin", nil];

  for (i = 0; i < [pathComponents count]; i++) {
    NSString *candidate = [[pathComponents objectAtIndex:i]
      stringByAppendingPathComponent:command];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return [self normalizedPath:candidate];
    }
  }

  return command;
}

- (NSString *)executablePathForDesktopFile:(NSString *)path
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
      return [self pathForExecutableCommand:
        [self firstCommandTokenFromString:command]];
    }
  }

  return nil;
}

- (BOOL)stringIsProcessIdentifier:(NSString *)string
{
  const char *chars = [string UTF8String];
  NSUInteger i;

  if (!chars || !chars[0]) {
    return NO;
  }

  for (i = 0; chars[i]; i++) {
    if (!isdigit((unsigned char)chars[i])) {
      return NO;
    }
  }

  return YES;
}

- (NSArray *)runningProcessExecutablePaths
{
  NSArray *entries = [[NSFileManager defaultManager]
    directoryContentsAtPath:@"/proc"];
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++) {
    NSString *entry = [entries objectAtIndex:i];
    NSString *linkPath;
    char target[PATH_MAX];
    ssize_t length;

    if (![self stringIsProcessIdentifier:entry]) {
      continue;
    }

    linkPath = [[@"/proc" stringByAppendingPathComponent:entry]
      stringByAppendingPathComponent:@"exe"];
    length = readlink([linkPath fileSystemRepresentation],
                      target,
                      sizeof(target) - 1);
    if (length <= 0) {
      continue;
    }

    target[length] = '\0';
    {
      NSString *path = [self normalizedPath:
        [NSString stringWithUTF8String:target]];
      if ([path length] && ![paths containsObject:path]) {
        [paths addObject:path];
      }
    }
  }

  return paths;
}

- (BOOL)applicationItem:(DockItem *)item matchesRunningProcessPath:(NSString *)processPath
{
  NSString *itemPath = [self normalizedPath:[item path]];
  NSString *executablePath = [self executablePathForApplicationPath:[item path]];
  NSString *processName = [[processPath lastPathComponent] lowercaseString];
  NSString *itemName = [[[[item path] lastPathComponent]
    stringByDeletingPathExtension] lowercaseString];
  NSString *executableName = [[executablePath lastPathComponent] lowercaseString];

  if (![processPath length]) {
    return NO;
  }

  if (([itemPath length] && [processPath isEqualToString:itemPath]) ||
      ([executablePath length] && [processPath isEqualToString:executablePath]) ||
      ([processName length] && [processName isEqualToString:itemName]) ||
      ([processName length] && [processName isEqualToString:executableName]) ||
      ([itemPath length] &&
       [[[itemPath pathExtension] lowercaseString] isEqualToString:@"app"] &&
       [processPath hasPrefix:[itemPath stringByAppendingString:@"/"]])) {
    return YES;
  }

  return NO;
}

- (BOOL)applicationItemHasRunningProcess:(DockItem *)item
                                   paths:(NSArray *)processPaths
{
  NSUInteger i;

  for (i = 0; i < [processPaths count]; i++) {
    if ([self applicationItem:item
      matchesRunningProcessPath:[processPaths objectAtIndex:i]]) {
      return YES;
    }
  }

  return NO;
}

- (void)scanRunningApplications
{
  NSArray *processPaths = [self runningProcessExecutablePaths];
  BOOL changed = NO;
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    BOOL running;
    DockItemState newState;

    if ([item kind] != DockItemApplication) {
      continue;
    }

    running = [self applicationItemHasRunningProcess:item paths:processPaths];
    if (!running && [item xWindow]) {
      continue;
    }

    newState = running ? DockItemRunning : DockItemNotRunning;
    if ([item state] != newState) {
      [item setState:newState];
      changed = YES;
    }
  }

  if (changed) {
    [self refreshDock];
  }

  [self updateRecyclerState];
}

- (NSArray *)recyclerPaths
{
  NSString *home = NSHomeDirectory();
  return [NSArray arrayWithObjects:
    [home stringByAppendingPathComponent:@".Trash"],
    [home stringByAppendingPathComponent:@".local/share/Trash/files"],
    [home stringByAppendingPathComponent:@"GNUstep/Library/Recycler"],
    nil];
}

- (BOOL)directoryHasVisibleContentsAtPath:(NSString *)path
{
  NSArray *entries = [[NSFileManager defaultManager] directoryContentsAtPath:path];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++) {
    NSString *entry = [entries objectAtIndex:i];

    if ([entry isEqualToString:@"."] ||
        [entry isEqualToString:@".."] ||
        [entry isEqualToString:@".gwdir"]) {
      continue;
    }

    return YES;
  }

  return NO;
}

- (BOOL)recyclerHasContents
{
  NSArray *paths = [self recyclerPaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    if ([self directoryHasVisibleContentsAtPath:[paths objectAtIndex:i]]) {
      return YES;
    }
  }

  return NO;
}

- (void)updateRecyclerState
{
  [_dockView setRecyclerHasContents:[self recyclerHasContents]];
}

- (NSRect)dockWindowFrameForPlacement:(DockPlacement)placement
{
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  NSUInteger cellCount = [_items count] + 2;
  CGFloat length = DockPad * 2.0 + cellCount * DockCell + (cellCount - 1) * DockGap;
  CGFloat width = DockPlacementIsHorizontal(placement) ? length : DockWindowWidth;
  CGFloat height = DockPlacementIsHorizontal(placement) ? DockWindowWidth : length;
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

  [_blackBackgroundMenuItem setState:
    (_backgroundMode == DockBackgroundBlack ? NSOnState : NSOffState)];
  [_transparentBackgroundMenuItem setState:
    (_backgroundMode == DockBackgroundSimulatedTransparency ? NSOnState : NSOffState)];
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
    NSMenuItem *item;

    _dockMenu = [[NSMenu alloc] initWithTitle:@"Dock"];
    _placementMenuItems = [NSMutableArray new];

    for (i = 0; i < [titles count]; i++) {
      item = [[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:i]
                                        action:@selector(selectDockPlacement:)
                                 keyEquivalent:@""];
      [item setTarget:self];
      [item setTag:(NSInteger)i];
      [_dockMenu addItem:item];
      [_placementMenuItems addObject:item];
      [item release];
    }

    [_dockMenu addItem:[NSMenuItem separatorItem]];

    _blackBackgroundMenuItem =
      [[NSMenuItem alloc] initWithTitle:@"Black Background"
                                 action:@selector(selectBackgroundMode:)
                          keyEquivalent:@""];
    [_blackBackgroundMenuItem setTarget:self];
    [_blackBackgroundMenuItem setTag:DockBackgroundBlack];
    [_dockMenu addItem:_blackBackgroundMenuItem];

    _transparentBackgroundMenuItem =
      [[NSMenuItem alloc] initWithTitle:@"Simulated Transparency"
                                 action:@selector(selectBackgroundMode:)
                          keyEquivalent:@""];
    [_transparentBackgroundMenuItem setTarget:self];
    [_transparentBackgroundMenuItem setTag:DockBackgroundSimulatedTransparency];
    [_dockMenu addItem:_transparentBackgroundMenuItem];

    [_dockMenu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                      action:@selector(quitDock:)
                               keyEquivalent:@""];
    [item setTarget:self];
    [_dockMenu addItem:item];
    [item release];
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
  [self updateDockBackgroundHidingWindow:YES];
  [self updateDockMenu];
}

- (void)updateDockBackgroundHidingWindow:(BOOL)hideWindow
{
  NSImage *image;
  BOOL wasVisible;

  [_dockView setBackgroundMode:_backgroundMode];

  if (_backgroundMode == DockBackgroundBlack) {
    [_dockView setBackgroundImage:nil];
    return;
  }

  if (!_x11) {
    return;
  }

  wasVisible = [_window isVisible];
  if (hideWindow && wasVisible) {
    [_window orderOut:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow:0.02]];
  }

  image = [_x11 backgroundImageForDockPlacement:_dockPlacement];
  if (image) {
    [_dockView setBackgroundImage:image];
  } else if (!wasVisible) {
    [_dockView setBackgroundImage:nil];
  }

  if (hideWindow && wasVisible) {
    [_window orderFrontRegardless];
  }
}

- (void)selectBackgroundMode:(id)sender
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  _backgroundMode = (DockBackgroundMode)[sender tag];
  [defaults setInteger:_backgroundMode forKey:DockBackgroundModeDefaultsKey];
  [defaults synchronize];
  [self updateDockBackgroundHidingWindow:YES];
  [self updateDockMenu];
}

- (void)selectDockPlacement:(id)sender
{
  _dockPlacement = (DockPlacement)[sender tag];
  [self applyDockPlacement];
}

- (void)quitDock:(id)sender
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [NSApp terminate:sender];
}

- (void)refreshDock
{
  [_dockView setItems:_items];
  [self applyDockPlacement];
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

- (NSUInteger)indexForItem:(DockItem *)targetItem
{
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    if ([_items objectAtIndex:i] == targetItem) {
      return i;
    }
  }

  return NSNotFound;
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

- (DockItem *)applicationItemMatchingExecutablePath:(NSString *)path
{
  NSString *windowPath = [self normalizedPath:path];
  NSString *windowName = [[windowPath lastPathComponent] lowercaseString];
  NSUInteger i;

  if (![windowPath length]) {
    return nil;
  }

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSString *itemPath;
    NSString *executablePath;
    NSString *itemName;
    NSString *executableName;

    if ([item kind] != DockItemApplication) {
      continue;
    }

    itemPath = [self normalizedPath:[item path]];
    executablePath = [self executablePathForApplicationPath:[item path]];
    itemName = [[[[item path] lastPathComponent]
      stringByDeletingPathExtension] lowercaseString];
    executableName = [[executablePath lastPathComponent] lowercaseString];

    if (([itemPath length] && [windowPath isEqualToString:itemPath]) ||
        ([executablePath length] && [windowPath isEqualToString:executablePath]) ||
        ([windowName length] && [windowName isEqualToString:itemName]) ||
        ([windowName length] && [windowName isEqualToString:executableName]) ||
        ([itemPath length] &&
         [[[itemPath pathExtension] lowercaseString] isEqualToString:@"app"] &&
         [windowPath hasPrefix:
           [itemPath stringByAppendingString:@"/"]])) {
      return item;
    }
  }

  return nil;
}

- (void)dockViewDidReceivePaths:(NSArray *)paths
{
  NSUInteger i;
  BOOL added = NO;

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    BOOL isDir = NO;

    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] &&
        ![self dockHasApplicationPath:path]) {
      [_items addObject:[DockItem applicationItemWithPath:path]];
      added = YES;
    }
  }

  if (added) {
    [self savePersistedApplications];
    [self refreshDock];
  }
}

- (void)dockViewDidActivateItem:(DockItem *)item
{
  if ([item kind] == DockItemApplication) {
    NSString *path = [item path];
    NSString *extension = [[path pathExtension] lowercaseString];
    BOOL isDir = NO;
    BOOL launched = NO;

    if ([item xWindow] && [item state] != DockItemNotRunning) {
      [_x11 activateWindow:[item xWindow]];
      return;
    }

    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if ([extension isEqualToString:@"desktop"]) {
      launched = [self launchDesktopFile:path];
    } else if ([extension isEqualToString:@"app"]) {
      launched = [[NSWorkspace sharedWorkspace] launchApplication:path];
      if (!launched) {
        launched = [[NSWorkspace sharedWorkspace] openFile:path];
      }
    } else if (isDir) {
      launched = [[NSWorkspace sharedWorkspace] openFile:path];
    } else if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
      [NSTask launchedTaskWithLaunchPath:path arguments:[NSArray array]];
      launched = YES;
    } else {
      launched = [[NSWorkspace sharedWorkspace] openFile:path];
    }

    if (launched) {
      [item setState:DockItemRunning];
      [self refreshDock];
    }
  } else {
    [_x11 activateWindow:[item xWindow]];
  }
}

- (void)dockViewDidActivateTopIcon
{
  NSArray *paths = [NSArray arrayWithObjects:
    @"/usr/GNUstep/System/Applications/GWorkspace.app",
    @"/usr/GNUstep/Local/Applications/GWorkspace.app",
    nil];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      if (![[NSWorkspace sharedWorkspace] launchApplication:path]) {
        [[NSWorkspace sharedWorkspace] openFile:path];
      }
      return;
    }
  }
}

- (BOOL)launchDesktopFile:(NSString *)path
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];
  NSUInteger i;

  if (![contents length]) {
    return NO;
  }

  for (i = 0; i < [lines count]; i++) {
    NSString *line = [lines objectAtIndex:i];
    if ([line hasPrefix:@"Exec="]) {
      NSString *command = [line substringFromIndex:5];
      command = [[command componentsSeparatedByString:@"%"] objectAtIndex:0];
      if ([command length]) {
        [NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-lc", command, nil]];
        return YES;
      }
      return NO;
    }
  }

  return NO;
}

- (void)x11DockManagerDidDiscoverWindowWithTitle:(NSString *)title
                                          window:(unsigned long)xWindow
                                          hidden:(BOOL)hidden
                                            icon:(NSImage *)icon
                                            path:(NSString *)path
                                         dockApp:(BOOL)dockApp
{
  DockItem *item = [self applicationItemMatchingExecutablePath:path];
  NSUInteger itemIndex;

  if (!item) {
    item = [self applicationItemMatchingTitle:title];
  }

  if (item) {
    [item setState:(hidden ? DockItemHidden : DockItemRunning)];
    [item setXWindow:xWindow];
    if (![item icon] && icon) {
      [item setIcon:icon];
    }
  } else {
    item = [DockItem x11ItemWithTitle:title window:xWindow icon:icon hidden:hidden];
    [_items addObject:item];
  }

  [self refreshDock];
  if (dockApp) {
    itemIndex = [self indexForItem:item];
    if (itemIndex != NSNotFound) {
      [_x11 dockWindow:xWindow atIndex:itemIndex];
    }
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
