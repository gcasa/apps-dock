/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "AppController.h"
#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>
#import <ctype.h>
#import <limits.h>
#import <signal.h>
#import <unistd.h>

static CGFloat DockWindowWidth = 84.0;
static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;
static NSString *DockApplicationsDefaultsKey = @"DockApplications";
static NSString *DockOpenAtLoginApplicationsDefaultsKey = @"DockOpenAtLoginApplications";
static NSString *DockBackgroundModeDefaultsKey = @"DockBackgroundMode";

static BOOL DockPlacementIsHorizontal(DockPlacement placement)
{
  return placement == DockPlacementTopCenter || placement == DockPlacementBottomCenter;
}

@implementation AppController

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  _launchedApplicationPaths = [NSMutableSet new];
  _suppressedWindowItems = [NSMutableDictionary new];
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
  [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
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
  _backgroundRefreshTimer =
    [NSTimer scheduledTimerWithTimeInterval:0.25
                                     target:self
                                   selector:@selector(refreshDockBackground:)
                                   userInfo:nil
                                    repeats:YES];
  [self scanRunningApplications];
  [self launchOpenAtLoginApplications];
}

- (void) dealloc
{
  [_scanTimer invalidate];
  [_processScanTimer invalidate];
  [_backgroundRefreshTimer invalidate];
  DESTROY(_transparentBackgroundMenuItem);
  DESTROY(_blackBackgroundMenuItem);
  DESTROY(_emptyRecyclerMenuItem);
  DESTROY(_dockMenu);
  DESTROY(_placementMenuItems);
  DESTROY(_x11);
  DESTROY(_dockView);
  DESTROY(_window);
  DESTROY(_suppressedWindowItems);
  DESTROY(_launchedApplicationPaths);
  DESTROY(_items);
  DEALLOC;
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)sender
{
  return YES;
}

- (void) applicationWillTerminate: (NSNotification *)notification
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (DockPlacement) savedDockPlacement
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

- (DockBackgroundMode) savedBackgroundMode
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

- (void) loadPersistedApplications
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

- (void) savePersistedApplications
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSString *path = [item path];

    if ([item kind] == DockItemApplication &&
        [item isPinned] &&
        [path length] &&
        ![paths containsObject:path]) {
      [paths addObject:path];
    }
  }

  [defaults setObject:paths forKey:DockApplicationsDefaultsKey];
  [defaults synchronize];
}

- (BOOL) dockHasApplicationPath: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length]) {
    return NO;
  }

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    if ([item kind] == DockItemApplication &&
        [item isPinned] &&
        [[self normalizedPath:[item path]] isEqualToString:normalizedPath]) {
      return YES;
    }
  }

  return NO;
}

- (NSUInteger) pinnedApplicationCount
{
  NSUInteger count = 0;
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];

    if ([item isPinned]) {
      count++;
    }
  }

  return count;
}

- (NSString *) normalizedPath: (NSString *)path
{
  if (![path length]) {
    return nil;
  }

  return [path stringByResolvingSymlinksInPath];
}

- (NSString *) executablePathForApplicationPath: (NSString *)path
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

- (NSString *) firstCommandTokenFromString: (NSString *)string
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

- (NSString *) pathForExecutableCommand: (NSString *)command
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

- (NSString *) executablePathForDesktopFile: (NSString *)path
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

- (BOOL) stringIsProcessIdentifier: (NSString *)string
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

- (NSArray *) runningProcessExecutablePaths
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

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  NSArray *entries = [[NSFileManager defaultManager]
    directoryContentsAtPath:@"/proc"];
  NSMutableArray *processIds = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++) {
    NSString *entry = [entries objectAtIndex:i];
    NSString *linkPath;
    char target[PATH_MAX];
    ssize_t length;
    NSString *processPath;

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
    processPath = [self normalizedPath:[NSString stringWithUTF8String:target]];
    if ([self applicationItem:item matchesRunningProcessPath:processPath]) {
      [processIds addObject:[NSNumber numberWithInt:[entry intValue]]];
    }
  }

  return processIds;
}

- (BOOL) applicationItem: (DockItem *)item matchesRunningProcessPath: (NSString *)processPath
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

- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
                                   paths: (NSArray *)processPaths
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

- (DockItem *) transientApplicationItemMatchingBundlePath: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length]) {
    return nil;
  }

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSString *itemBundlePath;

    if ([item kind] == DockItemApplication &&
        ![item isPinned] &&
        [[self normalizedPath:[item path]] isEqualToString:normalizedPath]) {
      return item;
    }

    itemBundlePath = [DockItem applicationBundlePathForPath:[item path]];
    if ([item kind] == DockItemApplication &&
        ![item isPinned] &&
        [itemBundlePath length] &&
        [[self normalizedPath:itemBundlePath] isEqualToString:normalizedPath]) {
      return item;
    }
  }

  return nil;
}

- (BOOL) applicationBundlePathIsDockWM: (NSString *)path
{
  NSString *candidateBundlePath = [DockItem applicationBundlePathForPath:path];
  NSString *bundlePath = [self normalizedPath:
    [candidateBundlePath length] ? candidateBundlePath : path];
  NSString *mainBundlePath = [self normalizedPath:[[NSBundle mainBundle] bundlePath]];
  NSString *bundleName = [[bundlePath lastPathComponent] lowercaseString];

  if (![bundlePath length]) {
    return NO;
  }

  if ([mainBundlePath length] && [bundlePath isEqualToString:mainBundlePath]) {
    return YES;
  }

  return [bundleName isEqualToString:@"dockwm.app"];
}

- (void) rememberLaunchedApplicationPath: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSString *executablePath = [self executablePathForApplicationPath:path];

  if ([normalizedPath length]) {
    [_launchedApplicationPaths addObject:normalizedPath];
  }
  if ([executablePath length]) {
    [_launchedApplicationPaths addObject:executablePath];
  }
}

- (BOOL) windowPathMatchesLaunchedApplication: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
  NSString *normalizedBundlePath = [self normalizedPath:bundlePath];

  if ([normalizedPath length] &&
      [_launchedApplicationPaths containsObject:normalizedPath]) {
    return YES;
  }

  if ([normalizedBundlePath length] &&
      [_launchedApplicationPaths containsObject:normalizedBundlePath]) {
    return YES;
  }

  return NO;
}

- (NSArray *) openAtLoginApplicationPaths
{
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
    objectForKey:DockOpenAtLoginApplicationsDefaultsKey];

  return [paths isKindOfClass:[NSArray class]] ? paths : [NSArray array];
}

- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length]) {
    return NO;
  }

  for (i = 0; i < [paths count]; i++) {
    if ([normalizedPath isEqualToString:
          [self normalizedPath:[paths objectAtIndex:i]]]) {
      return YES;
    }
  }

  return NO;
}

- (void) setApplicationPath: (NSString *)path openAtLogin: (BOOL)openAtLogin
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray *savedPaths = [self openAtLoginApplicationPaths];
  NSMutableArray *paths = [NSMutableArray array];
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;
  BOOL found = NO;

  if (![normalizedPath length]) {
    return;
  }

  for (i = 0; i < [savedPaths count]; i++) {
    NSString *savedPath = [savedPaths objectAtIndex:i];

    if ([[self normalizedPath:savedPath] isEqualToString:normalizedPath]) {
      found = YES;
      if (openAtLogin) {
        [paths addObject:savedPath];
      }
    } else {
      [paths addObject:savedPath];
    }
  }

  if (openAtLogin && !found) {
    [paths addObject:path];
  }

  [defaults setObject:paths forKey:DockOpenAtLoginApplicationsDefaultsKey];
  [defaults synchronize];
}

- (BOOL) launchApplicationAtPath: (NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"desktop"]) {
    return [self launchDesktopFile:path];
  } else if ([extension isEqualToString:@"app"]) {
    if ([[NSWorkspace sharedWorkspace] launchApplication:path]) {
      return YES;
    }
    return [[NSWorkspace sharedWorkspace] openFile:path];
  } else if (isDir) {
    return [[NSWorkspace sharedWorkspace] openFile:path];
  } else if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    [NSTask launchedTaskWithLaunchPath:path arguments:[NSArray array]];
    return YES;
  }

  return [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void) terminateApplicationItemProcesses: (DockItem *)item
{
  NSArray *processIds = [self runningProcessIdentifiersForApplicationItem:item];
  NSUInteger i;

  for (i = 0; i < [processIds count]; i++) {
    int processId = [[processIds objectAtIndex:i] intValue];

    if (processId > 0 && processId != getpid()) {
      kill((pid_t)processId, SIGTERM);
    }
  }
}

- (void) launchOpenAtLoginApplications
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSArray *processPaths = [self runningProcessExecutablePaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    DockItem *item;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      continue;
    }

    item = [DockItem applicationItemWithPath:path];
    if ([self applicationItemHasRunningProcess:item paths:processPaths]) {
      continue;
    }

    if ([self launchApplicationAtPath:path]) {
      [self rememberLaunchedApplicationPath:path];
    }
  }
}

- (void) scanRunningApplications
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

  for (i = 0; i < [processPaths count]; i++) {
    NSString *processPath = [processPaths objectAtIndex:i];
    NSString *bundlePath = [DockItem applicationBundlePathForPath:processPath];
    DockItem *item;

    if (![bundlePath length] ||
        [self applicationBundlePathIsDockWM:bundlePath] ||
        [self dockHasApplicationPath:bundlePath] ||
        [self transientApplicationItemMatchingBundlePath:bundlePath]) {
      continue;
    }

    item = [DockItem applicationItemWithPath:bundlePath];
    [item setPinned:NO];
    [item setState:DockItemRunning];
    [_items addObject:item];
    changed = YES;
  }

  for (i = [_items count]; i > 0; i--) {
    DockItem *item = [_items objectAtIndex:i - 1];

    if ([item kind] == DockItemApplication &&
        ![item isPinned] &&
        ![self applicationItemHasRunningProcess:item paths:processPaths]) {
      [_items removeObjectAtIndex:i - 1];
      changed = YES;
    }
  }

  if (changed) {
    [self refreshDock];
  }

  [self updateRecyclerState];
}

- (NSArray *) recyclerPaths
{
  NSString *home = NSHomeDirectory();
  return [NSArray arrayWithObjects:
    [home stringByAppendingPathComponent:@".Trash"],
    [home stringByAppendingPathComponent:@".local/share/Trash/files"],
    [home stringByAppendingPathComponent:@"GNUstep/Library/Recycler"],
    nil];
}

- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path
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

- (BOOL) recyclerHasContents
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

- (NSString *) recyclerPathForDropping
{
  NSArray *paths = [self recyclerPaths];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    BOOL isDir = NO;

    if ([fileManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
      return path;
    }
  }

  if ([paths count]) {
    NSString *path = [paths objectAtIndex:0];
    if ([fileManager createDirectoryAtPath:path attributes:nil]) {
      return path;
    }
  }

  return nil;
}

- (NSString *) recyclerDestinationPathForPath: (NSString *)path
                               recyclerPath: (NSString *)recyclerPath
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *name = [path lastPathComponent];
  NSString *base;
  NSString *extension;
  NSString *candidate;
  NSUInteger i = 2;

  if (![name length]) {
    return nil;
  }

  candidate = [recyclerPath stringByAppendingPathComponent:name];
  if (![fileManager fileExistsAtPath:candidate]) {
    return candidate;
  }

  extension = [name pathExtension];
  base = [extension length] ? [name stringByDeletingPathExtension] : name;

  while (1) {
    NSString *numberedName = [NSString stringWithFormat:@"%@ %lu",
      base, (unsigned long)i];
    if ([extension length]) {
      numberedName = [numberedName stringByAppendingPathExtension:extension];
    }

    candidate = [recyclerPath stringByAppendingPathComponent:numberedName];
    if (![fileManager fileExistsAtPath:candidate]) {
      return candidate;
    }
    i++;
  }
}

- (void) dockViewDidReceivePathsInRecycler: (NSArray *)paths
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *recyclerPath = [self recyclerPathForDropping];
  NSString *normalizedRecyclerPath = [self normalizedPath:recyclerPath];
  BOOL moved = NO;
  NSUInteger i;

  if (![recyclerPath length]) {
    NSBeep();
    return;
  }

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    NSString *normalizedPath = [self normalizedPath:path];
    NSString *destination;

    if (![normalizedPath length] ||
        [normalizedPath isEqualToString:normalizedRecyclerPath] ||
        [normalizedPath hasPrefix:
          [normalizedRecyclerPath stringByAppendingString:@"/"]] ||
        ![fileManager fileExistsAtPath:path]) {
      continue;
    }

    destination = [self recyclerDestinationPathForPath:path
                                         recyclerPath:recyclerPath];
    if ([destination length] &&
        [fileManager movePath:path toPath:destination handler:nil]) {
      moved = YES;
    }
  }

  if (moved) {
    [self updateRecyclerState];
    [self refreshDock];
    [[NSSound soundNamed:@"Pop"] play];
  } else {
    NSBeep();
  }
}

- (void) updateRecyclerState
{
  [_dockView setRecyclerHasContents:[self recyclerHasContents]];
  [_emptyRecyclerMenuItem setEnabled:[self recyclerHasContents]];
}

- (void) emptyRecyclerPath: (NSString *)path
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSArray *entries = [fileManager directoryContentsAtPath:path];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++) {
    NSString *entry = [entries objectAtIndex:i];
    NSString *entryPath;

    if ([entry isEqualToString:@"."] ||
        [entry isEqualToString:@".."] ||
        [entry isEqualToString:@".gwdir"]) {
      continue;
    }

    entryPath = [path stringByAppendingPathComponent:entry];
    [fileManager removeFileAtPath:entryPath handler:nil];
  }
}

- (void) emptyRecycler: (id)sender
{
  NSArray *paths = [self recyclerPaths];
  NSUInteger i;
  int result;

  result = NSRunAlertPanel(@"Empty Recycler",
                           @"Are you sure you want to permanently remove the items in the Recycler?",
                           @"Empty Recycler",
                           @"Cancel",
                           nil);
  if (result != NSAlertDefaultReturn) {
    return;
  }

  for (i = 0; i < [paths count]; i++) {
    [self emptyRecyclerPath:[paths objectAtIndex:i]];
  }

  [self updateRecyclerState];
  [self refreshDock];
  [[NSSound soundNamed:@"Glass"] play];
}

- (NSRect) dockWindowFrameForPlacement: (DockPlacement)placement
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

- (void) updateDockMenu
{
  NSUInteger i;

  for (i = 0; i < [_placementMenuItems count]; i++) {
    NSMenuItem *item = [_placementMenuItems objectAtIndex:i];
    [item setState: ([item tag] == _dockPlacement ? NSOnState : NSOffState)];
  }

  [_blackBackgroundMenuItem setState:
    (_backgroundMode == DockBackgroundBlack ? NSOnState : NSOffState)];
  [_transparentBackgroundMenuItem setState:
    (_backgroundMode == DockBackgroundSimulatedTransparency ? NSOnState : NSOffState)];
  [_emptyRecyclerMenuItem setEnabled:[self recyclerHasContents]];
}

- (NSMenu *) dockMenu
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
      [item setTag: (NSInteger)i];
      [_dockMenu addItem:item];
      [_placementMenuItems addObject:item];
      DESTROY(item);
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

    _emptyRecyclerMenuItem =
      [[NSMenuItem alloc] initWithTitle:@"Empty Recycler"
                                 action:@selector(emptyRecycler:)
                          keyEquivalent:@""];
    [_emptyRecyclerMenuItem setTarget:self];
    [_dockMenu addItem:_emptyRecyclerMenuItem];

    [_dockMenu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                      action:@selector(quitDock:)
                               keyEquivalent:@"q"];
    [item setTarget:self];
    [_dockMenu addItem:item];
    DESTROY(item);
  }

  [self updateDockMenu];
  return _dockMenu;
}

- (void) applyDockPlacement
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

- (void) refreshDockBackground: (NSTimer *)timer
{
  if (_backgroundMode == DockBackgroundSimulatedTransparency) {
    [self updateDockBackgroundHidingWindow:NO];
  }
}

- (void) updateDockBackgroundHidingWindow: (BOOL)hideWindow
{
  NSImage *image;
  BOOL wasVisible;

  if (_updatingDockBackground) {
    return;
  }

  [_dockView setBackgroundMode:_backgroundMode];

  if (_backgroundMode == DockBackgroundBlack) {
    [_dockView setBackgroundImage:nil];
    return;
  }

  if (!_x11) {
    return;
  }

  _updatingDockBackground = YES;
  wasVisible = [_window isVisible];
  if (hideWindow && wasVisible) {
    [_window orderOut:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow:0.02]];
  }

  image = [_x11 backgroundImageForDockFrame:[_window frame]];
  if (image) {
    [_dockView setBackgroundImage:image];
  } else if (!wasVisible) {
    [_dockView setBackgroundImage:nil];
  }

  if (hideWindow && wasVisible) {
    [_window orderFrontRegardless];
  }
  _updatingDockBackground = NO;
}

- (void) selectBackgroundMode: (id)sender
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  _backgroundMode = (DockBackgroundMode)[sender tag];
  [defaults setInteger:_backgroundMode forKey:DockBackgroundModeDefaultsKey];
  [defaults synchronize];
  [self updateDockBackgroundHidingWindow:YES];
  [self updateDockMenu];
}

- (void) selectDockPlacement: (id)sender
{
  _dockPlacement = (DockPlacement)[sender tag];
  [self applyDockPlacement];
}

- (void) quitDock: (id)sender
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [NSApp terminate:sender];
}

- (void) refreshDock
{
  [_dockView setItems:_items];
  [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
  [self applyDockPlacement];
}

- (DockItem *) itemForXWindow: (unsigned long)xWindow
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

- (DockItem *) itemForSuppressedXWindow: (unsigned long)xWindow
{
  return [_suppressedWindowItems objectForKey:
    [NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) setSuppressedXWindow: (unsigned long)xWindow forItem: (DockItem *)item
{
  if (!item || !xWindow) {
    return;
  }

  [_suppressedWindowItems setObject:item
                             forKey:[NSNumber numberWithUnsignedLong:xWindow]];
}

- (NSUInteger) indexForItem: (DockItem *)targetItem
{
  NSUInteger i;

  for (i = 0; i < [_items count]; i++) {
    if ([_items objectAtIndex:i] == targetItem) {
      return i;
    }
  }

  return NSNotFound;
}

- (DockItem *) applicationItemMatchingTitle: (NSString *)title
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

- (DockItem *) applicationItemMatchingExecutablePath: (NSString *)path
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

- (void) dockViewDidReceivePaths: (NSArray *)paths
{
  [self dockViewDidReceivePaths:paths atIndex:[_items count]];
}

- (void) dockViewDidReceivePaths: (NSArray *)paths
                        atIndex: (NSUInteger)index
{
  NSUInteger i;
  BOOL added = NO;
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  NSUInteger insertionIndex = MIN(index, pinnedCount);

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex:i];
    NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
    NSString *applicationPath = [bundlePath length] ? bundlePath : path;
    DockItem *transientItem;
    NSUInteger transientIndex;
    BOOL isDir = NO;

    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] &&
        ![self dockHasApplicationPath:applicationPath]) {
      DockItem *item = [DockItem applicationItemWithPath:applicationPath];

      transientItem = [self transientApplicationItemMatchingBundlePath:applicationPath];
      transientIndex = transientItem ? [self indexForItem:transientItem] : NSNotFound;
      if (transientIndex != NSNotFound) {
        [_items removeObjectAtIndex:transientIndex];
        if (transientIndex < insertionIndex && insertionIndex > 0) {
          insertionIndex--;
        }
      }

      [item setPinned:YES];
      [_items insertObject:item atIndex:insertionIndex];
      insertionIndex++;
      added = YES;
    }
  }

  if (added) {
    [self savePersistedApplications];
    [self refreshDock];
  }
}

- (void) dockViewDidMoveItemFromIndex: (NSUInteger)fromIndex
                              toIndex: (NSUInteger)toIndex
{
  DockItem *item;
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  BOOL promoteItem = NO;

  if (fromIndex >= [_items count] || toIndex > [_items count]) {
    return;
  }

  if (fromIndex < pinnedCount && toIndex > pinnedCount) {
    toIndex = pinnedCount;
  } else if (fromIndex >= pinnedCount && toIndex <= pinnedCount) {
    promoteItem = YES;
  }

  if (toIndex > fromIndex) {
    toIndex--;
  }

  if (fromIndex == toIndex && !promoteItem) {
    return;
  }

  item = RETAIN([_items objectAtIndex:fromIndex]);
  [_items removeObjectAtIndex:fromIndex];
  if (promoteItem) {
    [item setPinned:YES];
  }
  [_items insertObject:item atIndex:toIndex];
  DESTROY(item);

  [self savePersistedApplications];
  [self refreshDock];
}

- (void) dockViewDidRemoveItemAtIndex: (NSUInteger)index
{
  if (index >= [_items count]) {
    return;
  }

  [_items removeObjectAtIndex:index];
  [self savePersistedApplications];
  [self refreshDock];
}

- (BOOL) dockView: (id)dockView itemIsOpenAtLogin: (DockItem *)item
{
  return [self applicationPathIsOpenAtLogin:[item path]];
}

- (void) dockView: (id)dockView didToggleOpenAtLoginForItem: (DockItem *)item
{
  BOOL openAtLogin;

  if (![[item path] length]) {
    return;
  }

  openAtLogin = ![self applicationPathIsOpenAtLogin:[item path]];
  [self setApplicationPath:[item path] openAtLogin:openAtLogin];
}

- (void) dockView: (id)dockView didShowItemInFileViewer: (DockItem *)item
{
  NSString *path = [item path];
  NSString *directory;

  if (![path length]) {
    return;
  }

  directory = [path stringByDeletingLastPathComponent];
  [[NSWorkspace sharedWorkspace] selectFile:path
                   inFileViewerRootedAtPath:directory];
}

- (void) dockView: (id)dockView didQuitItem: (DockItem *)item
{
  NSUInteger index;

  if ([item xWindow]) {
    [_x11 closeWindow:[item xWindow]];
  }

  if ([item kind] == DockItemApplication) {
    [self terminateApplicationItemProcesses:item];
  }

  [item setState:DockItemNotRunning];
  if (![item isPinned]) {
    index = [self indexForItem:item];
    if (index != NSNotFound) {
      [_items removeObjectAtIndex:index];
    }
  }

  [self refreshDock];
}

- (void) dockViewDidEmptyRecycler: (id)dockView
{
  [self emptyRecycler:dockView];
}

- (void) dockViewDidActivateItem: (DockItem *)item
{
  if ([item kind] == DockItemApplication) {
    NSString *path = [item path];
    BOOL launched = NO;

    if ([item xWindow] && [item state] != DockItemNotRunning) {
      [_x11 activateWindow:[item xWindow]];
      return;
    }

    launched = [self launchApplicationAtPath:path];

    if (launched) {
      [self rememberLaunchedApplicationPath:path];
      [item setState:DockItemRunning];
      [_dockView startWiggleForItem:item];
      [self refreshDock];
    }
  } else {
    [_x11 activateWindow:[item xWindow]];
  }
}

- (void) dockViewDidActivateTopIcon
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
      [self rememberLaunchedApplicationPath:path];
      return;
    }
  }
}

- (BOOL) launchDesktopFile: (NSString *)path
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

- (void) x11DockManagerDidDiscoverWindowWithTitle: (NSString *)title
                                          window: (unsigned long)xWindow
                                          hidden: (BOOL)hidden
                                            icon: (NSImage *)icon
                                            path: (NSString *)path
                                         dockApp: (BOOL)dockApp
{
  DockItem *item = [self applicationItemMatchingExecutablePath:path];
  NSUInteger itemIndex;
  BOOL matchedPinnedApplication;

  if (!item) {
    item = [self applicationItemMatchingTitle:title];
  }
  matchedPinnedApplication = item && [item kind] == DockItemApplication && [item isPinned];

  if (dockApp &&
      ([self applicationBundlePathIsDockWM:path] ||
       [self windowPathMatchesLaunchedApplication:path])) {
    if (item) {
      itemIndex = [self indexForItem:item];
      [self setSuppressedXWindow:xWindow forItem:item];
      if (itemIndex != NSNotFound) {
        [_x11 suppressWindow:xWindow atIndex:itemIndex];
      } else {
        [_x11 suppressWindow:xWindow];
      }
      [item setState:DockItemRunning];
      if (icon) {
        [item setIcon:icon];
      }
      [self refreshDock];
    }
    return;
  }

  if (item) {
    [item setState: (hidden ? DockItemHidden : DockItemRunning)];
    if (!(dockApp && matchedPinnedApplication)) {
      [item setXWindow:xWindow];
    }
    if (icon) {
      [item setIcon:icon];
    }
  } else {
    if ([path length] && ![self applicationBundlePathIsDockWM:path]) {
      NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
      NSString *applicationPath = [bundlePath length] ? bundlePath : path;

      item = [DockItem applicationItemWithPath:applicationPath];
      [item setPinned:NO];
      [item setState: (hidden ? DockItemHidden : DockItemRunning)];
      [item setXWindow:xWindow];
      if (icon) {
        [item setIcon:icon];
      }
    } else {
      item = [DockItem x11ItemWithTitle:title window:xWindow icon:icon hidden:hidden];
    }
    [_items addObject:item];
  }

  [self refreshDock];
  if (dockApp) {
    if (matchedPinnedApplication) {
      itemIndex = [self indexForItem:item];
      [self setSuppressedXWindow:xWindow forItem:item];
      if (itemIndex != NSNotFound) {
        [_x11 suppressWindow:xWindow atIndex:itemIndex];
      } else {
        [_x11 suppressWindow:xWindow];
      }
    } else {
      itemIndex = [self indexForItem:item];
      if (itemIndex != NSNotFound) {
        [_x11 dockWindow:xWindow atIndex:itemIndex];
      }
    }
  }
}

- (void) x11DockManagerDidUpdateWindow: (unsigned long)xWindow
                                hidden: (BOOL)hidden
                                  icon: (NSImage *)icon
{
  DockItem *item = [self itemForXWindow:xWindow];
  BOOL suppressedWindow = NO;

  if (!item) {
    item = [self itemForSuppressedXWindow:xWindow];
    suppressedWindow = item != nil;
  }
  if (item) {
    NSUInteger itemIndex = [self indexForItem:item];

    [item setState: (hidden ? DockItemHidden : DockItemRunning)];
    if (icon) {
      [item setIcon:icon];
    }
    if (itemIndex != NSNotFound) {
      if (suppressedWindow) {
        [_x11 suppressWindow:xWindow atIndex:itemIndex];
      } else {
        [_x11 moveDockedWindow:xWindow toIndex:itemIndex];
      }
    }
    [self refreshDock];
  }
}

@end
