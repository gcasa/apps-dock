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
#import "ApplicationIconManager.h"
#import "DockApplicationStore.h"
#import "DockItem.h"
#import "DockPreferences.h"
#import "RecyclerController.h"
#import "RunningApplicationScanner.h"
#import <GNUstepBase/GNUstep.h>
#import <signal.h>
#import <unistd.h>

@implementation AppController

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  _recyclerController = [RecyclerController new];
  _preferences = [DockPreferences new];
  _applicationScanner = [RunningApplicationScanner new];
  _applicationStore = [[DockApplicationStore alloc]
			initWithScanner:_applicationScanner];
  _applicationIconManager = [[ApplicationIconManager alloc]
			      initWithScanner:_applicationScanner];
  _launchedApplicationPaths = [NSMutableSet new];
  _dockPlacement = [self savedDockPlacement];
  _dockCellSizeMode = [self savedDockCellSizeMode];
  _runningIndicatorMode = [self savedRunningIndicatorMode];
  _backgroundColor = RETAIN([self savedBackgroundColor]);
  _windowAlpha = [self savedWindowAlpha];
  _useCellTileBackground = [self savedUseCellTileBackground];
  _showDockBorder = [self savedShowDockBorder];
  _magnifiesHoveredIcons = [_preferences savedMagnifiesHoveredIcons];
  _hoverIconScale = [_preferences savedHoverIconScale];
  _wigglesOnLaunch = [_preferences savedWigglesOnLaunch];
  _wigglesOnActivation = [_preferences savedWigglesOnActivation];
  frame = [self dockWindowFrameForPlacement:_dockPlacement];

  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setLevel:NSDockWindowLevel];
  [_window setOpaque:NO];
  [_window setAlphaValue:_windowAlpha];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setTitle:@"AppsDockWM"];
  [_window setAcceptsMouseMovedEvents:YES];

  _dockView = [[DockView alloc] initWithFrame:NSMakeRect(0, 0,
                                                         NSWidth(frame),
                                                         NSHeight(frame))];
  [_dockView setDelegate:self];
  [_dockView setHorizontal:[DockPreferences placementIsHorizontal:_dockPlacement]];
  [self applyDockCellSizeToView];
  [_dockView setBackgroundColor:_backgroundColor];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [_dockView setShowsBorder:_showDockBorder];
  [_dockView setRunningIndicatorMode:_runningIndicatorMode];
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_dockView setHoverIconScale:_hoverIconScale];
  [_dockView setItems:_items];
  [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
  [_dockView setMenu:[self dockMenu]];
  [_window setContentView:_dockView];

  [self updateDockBackground];
  [_window makeKeyAndOrderFront:nil];
  [_window orderFrontRegardless];
  [_window display];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start])
    {
      [_x11 setDockPlacement:_dockPlacement];
    }

  [self performSelector:@selector(performInitialApplicationScans)
	     withObject:nil
	     afterDelay:0.5];
}

- (void) dealloc
{
  [_x11EventTimer invalidate];
  [_scanTimer invalidate];
  [_processScanTimer invalidate];
  DESTROY(_settingsController);
  DESTROY(_recyclerController);
  DESTROY(_preferences);
  DESTROY(_dockMenu);
  DESTROY(_x11);
  DESTROY(_dockView);
  DESTROY(_window);
  DESTROY(_applicationStore);
  DESTROY(_applicationIconManager);
  DESTROY(_applicationScanner);
  DESTROY(_launchedApplicationPaths);
  DESTROY(_backgroundColor);
  DESTROY(_items);
  DEALLOC;
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)sender
{
  return NO;
}

- (void) applicationWillTerminate: (NSNotification *)notification
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (DockPlacement) savedDockPlacement
{
  return [_preferences savedDockPlacement];
}

- (NSColor *) savedBackgroundColor
{
  return [_preferences savedBackgroundColor];
}

- (void) saveBackgroundColor
{
  [_preferences saveBackgroundColor:_backgroundColor];
}

- (CGFloat) savedWindowAlpha
{
  return [_preferences savedWindowAlpha];
}

- (void) saveWindowAlpha
{
  [_preferences saveWindowAlpha:_windowAlpha];
}

- (BOOL) savedShowDockBorder
{
  return [_preferences savedShowDockBorder];
}

- (void) saveShowDockBorder
{
  [_preferences saveShowDockBorder:_showDockBorder];
}

- (NSInteger) savedDockCellSizeMode
{
  return [_preferences savedDockCellSizeMode];
}

- (void) saveDockCellSizeMode
{
  [_preferences saveDockCellSizeMode:_dockCellSizeMode];
}

- (DockRunningIndicatorMode) savedRunningIndicatorMode
{
  return [_preferences savedRunningIndicatorMode];
}

- (void) saveRunningIndicatorMode
{
  [_preferences saveRunningIndicatorMode:_runningIndicatorMode];
}

- (BOOL) savedUseCellTileBackground
{
  return [_preferences savedUseCellTileBackground];
}

- (void) saveUseCellTileBackground
{
  [_preferences saveUseCellTileBackground:_useCellTileBackground];
}

- (CGFloat) activeDockPad
{
  return [DockPreferences padForCellSizeMode:_dockCellSizeMode];
}

- (CGFloat) activeDockGap
{
  return [DockPreferences gapForCellSizeMode:_dockCellSizeMode];
}

- (CGFloat) activeDockWindowWidth
{
  return [DockPreferences windowWidthForCellSizeMode:_dockCellSizeMode];
}

- (void) applyDockCellSizeToView
{
  if (_dockView)
    {
      [_dockView setIconCellSize:[DockPreferences dockCellSize]
			      gap:[self activeDockGap]
			  padding:[self activeDockPad]];
    }
}

- (void) loadPersistedApplications
{
  [_applicationStore loadPersistedApplicationsIntoItems:_items];
}

- (void) savePersistedApplications
{
  [_applicationStore savePersistedApplicationsFromItems:_items];
}

- (id) persistedApplicationRecordForItem: (DockItem *)item
{
  return [_applicationStore persistedApplicationRecordForItem:item];
}

- (NSString *) persistedApplicationPathFromRecord: (id)record
{
  return [_applicationStore persistedApplicationPathFromRecord:record];
}

- (NSString *) persistedApplicationArgumentsFromRecord: (id)record
{
  return [_applicationStore persistedApplicationArgumentsFromRecord:record];
}

- (BOOL) dockHasApplicationPath: (NSString *)path
{
  return [_applicationStore items:_items haveApplicationPath:path];
}

- (NSUInteger) pinnedApplicationCount
{
  NSUInteger count = 0;
  NSUInteger i;

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];

      if ([item isPinned])
	{
	  count++;
	}
    }

  return count;
}

- (NSString *) normalizedPath: (NSString *)path
{
  return [_applicationScanner normalizedPath:path];
}

- (NSArray *) commandSearchPathComponents
{
  return [_applicationScanner commandSearchPathComponents];
}

- (NSString *) procFilesystemPath
{
  return [_applicationScanner procFilesystemPath];
}

- (NSString *) procPathForProcessIdentifierString: (NSString *)identifier
{
  return [_applicationScanner procPathForProcessIdentifierString:identifier];
}

- (BOOL) path: (NSString *)path isEqualToOrDescendantOfPath: (NSString *)parentPath
{
  return [_applicationScanner path:path isEqualToOrDescendantOfPath:parentPath];
}

- (NSString *) executablePathForApplicationPath: (NSString *)path
{
  return [_applicationScanner executablePathForApplicationPath:path];
}

- (NSString *) firstCommandTokenFromString: (NSString *)string
{
  return [_applicationScanner firstCommandTokenFromString:string];
}

- (NSString *) pathForExecutableCommand: (NSString *)command
{
  return [_applicationScanner pathForExecutableCommand:command];
}

- (NSString *) executablePathForDesktopFile: (NSString *)path
{
  return [_applicationScanner executablePathForDesktopFile:path];
}

- (BOOL) stringIsProcessIdentifier: (NSString *)string
{
  return [_applicationScanner stringIsProcessIdentifier:string];
}

- (NSArray *) runningProcessExecutablePaths
{
  return [_applicationScanner runningProcessExecutablePaths];
}

- (NSString *) executablePathForProcessIdentifier: (NSNumber *)processIdentifier
{
  return [_applicationScanner executablePathForProcessIdentifier:processIdentifier];
}

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  return [_applicationScanner runningProcessIdentifiersForApplicationItem:item];
}

- (BOOL) applicationItem: (DockItem *)item matchesRunningProcessPath: (NSString *)processPath
{
  return [_applicationScanner applicationItem:item
		   matchesRunningProcessPath:processPath];
}

- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
				    paths: (NSArray *)processPaths
{
  return [_applicationScanner applicationItemHasRunningProcess:item
							paths:processPaths];
}

- (DockItem *) transientApplicationItemMatchingBundlePath: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length])
    {
      return nil;
    }

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSString *itemBundlePath;

      if ([item kind] == DockItemApplication &&
	  ![item isPinned] &&
	  [[self normalizedPath:[item path]] isEqualToString:normalizedPath])
	{
	  return item;
	}

      itemBundlePath = [DockItem applicationBundlePathForPath:[item path]];
      if ([item kind] == DockItemApplication &&
	  ![item isPinned] &&
	  [itemBundlePath length] &&
	  [[self normalizedPath:itemBundlePath] isEqualToString:normalizedPath])
	{
	  return item;
	}
    }

  return nil;
}

- (DockItem *) applicationItemMatchingProcessIdentifier: (NSNumber *)processIdentifier
{
  NSString *processPath;
  NSUInteger i;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return nil;
    }

  processPath = [self executablePathForProcessIdentifier:processIdentifier];
  if (![processPath length])
    {
      return nil;
    }

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];

      if ([item kind] == DockItemApplication &&
	  [self applicationItem:item matchesRunningProcessPath:processPath])
	{
	  return item;
	}
    }

  return nil;
}

- (DockItem *) transientApplicationItemForProcessIdentifier: (NSNumber *)processIdentifier
{
  NSString *processPath;
  NSString *bundlePath;
  DockItem *item;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return nil;
    }

  processPath = [self executablePathForProcessIdentifier:processIdentifier];
  bundlePath = [DockItem applicationBundlePathForPath:processPath];
  if (![bundlePath length] ||
      [self applicationBundlePathIsDockWM:bundlePath] ||
      [self dockHasApplicationPath:bundlePath])
    {
      return nil;
    }

  item = [self transientApplicationItemMatchingBundlePath:bundlePath];
  if (item)
    {
      return item;
    }

  item = [DockItem applicationItemWithPath:bundlePath];
  [item setPinned:NO];
  [item setState:DockItemRunning];
  [_items addObject:item];
  return item;
}

- (NSString *) executablePathForX11WindowTitle: (NSString *)title
{
  NSString *lowerTitle = [title lowercaseString];
  NSArray *processPaths;
  NSUInteger i;

  if (![lowerTitle length])
    {
      return nil;
    }

  processPaths = [self runningProcessExecutablePaths];
  for (i = 0; i < [processPaths count]; i++)
    {
      NSString *path = [processPaths objectAtIndex:i];
      NSString *name = [[path lastPathComponent] lowercaseString];
      NSString *nameWithoutExtension =
	[[[path lastPathComponent] stringByDeletingPathExtension] lowercaseString];

      if (([name length] && [name isEqualToString:lowerTitle]) ||
	  ([nameWithoutExtension length] &&
	   [nameWithoutExtension isEqualToString:lowerTitle]))
	{
	  return path;
	}
    }

  return nil;
}

- (void) resolvePathForX11WindowItem: (DockItem *)item
{
  NSString *path;

  if ([item kind] != DockItemX11Window || [[item path] length])
    {
      return;
    }

  path = [self executablePathForX11WindowTitle:[item title]];
  if ([path length])
    {
      [item setPath:path];
    }
}

- (void) resolvePathsForX11WindowItems
{
  NSUInteger i;

  for (i = 0; i < [_items count]; i++)
    {
      [self resolvePathForX11WindowItem:[_items objectAtIndex:i]];
    }
}

- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image
{
  return [_applicationIconManager item:item iconMatchesImage:image];
}

- (NSString *) x11IconCacheDirectory
{
  return [_applicationIconManager x11IconCacheDirectory];
}

- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier
{
  return [_applicationIconManager x11IconCacheFileNameForIdentifier:identifier];
}

- (NSString *) storeX11Icon: (NSImage *)icon
		 identifier: (NSString *)identifier
{
  return [_applicationIconManager storeX11Icon:icon identifier:identifier];
}

- (NSString *) x11IconIdentifierForTitle: (NSString *)title
				    path: (NSString *)path
				  window: (unsigned long)xWindow
{
  return [_applicationIconManager x11IconIdentifierForTitle:title
						       path:path
						     window:xWindow];
}

- (void) applyX11Icon: (NSImage *)icon
	       toItem: (DockItem *)item
	   identifier: (NSString *)identifier
{
  [_applicationIconManager applyX11Icon:icon toItem:item identifier:identifier];
}

- (void) rememberApplicationIcon: (NSImage *)icon
		       badgeLabel: (NSString *)badgeLabel
	processIdentifier: (NSNumber *)processIdentifier
{
  [_applicationIconManager rememberApplicationIcon:icon
				       badgeLabel:badgeLabel
				processIdentifier:processIdentifier];
}

- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update
			     toItem: (DockItem *)item
{
  return [_applicationIconManager applyApplicationIconUpdate:update toItem:item];
}

- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item
{
  return [_applicationIconManager applyStoredApplicationIconUpdateForItem:item];
}

- (BOOL) activateRunningApplicationWithProcessIdentifiers: (NSArray *)processIdentifiers
{
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSNumber *processIdentifier = [processIdentifiers objectAtIndex:i];
      NSRunningApplication *application;

      if (![processIdentifier isKindOfClass:[NSNumber class]])
	{
	  continue;
	}

      application = [NSRunningApplication
		      runningApplicationWithProcessIdentifier:
			(pid_t)[processIdentifier intValue]];
      if (application &&
	  [application activateWithOptions:
			 NSApplicationActivateAllWindows |
			 NSApplicationActivateIgnoringOtherApps])
	{
	  return YES;
	}
    }

  return NO;
}

- (BOOL) shouldApplyX11Icon: (NSImage *)icon toItem: (DockItem *)item
{
  return [_applicationIconManager shouldApplyX11Icon:icon toItem:item];
}

- (void) pruneApplicationIconUpdatesForExitedProcesses
{
  [_applicationIconManager pruneApplicationIconUpdatesForExitedProcesses];
}

- (void) x11DockManagerDidUpdateApplicationIcon: (NSImage *)icon
                              processIdentifier: (int)processIdentifier
                                          title: (NSString *)title
{
  DockItem *item = nil;
  NSNumber *processIdentifierNumber = nil;
  NSUInteger originalItemCount = [_items count];

  if (processIdentifier > 0)
    {
      processIdentifierNumber = [NSNumber numberWithInt:processIdentifier];
      [self rememberApplicationIcon:icon
			  badgeLabel:nil
		   processIdentifier:processIdentifierNumber];

      item = [self applicationItemMatchingProcessIdentifier:processIdentifierNumber];
      if (!item)
	{
	  item = [self transientApplicationItemForProcessIdentifier:
				processIdentifierNumber];
	}
    }
  if (!item && [title length])
    {
      item = [self applicationItemMatchingTitle:title];
    }

  if (item && processIdentifierNumber)
    {
      if ([self applyApplicationIconUpdate:
		  [_applicationIconManager
		    applicationIconUpdateForProcessIdentifier:processIdentifierNumber]
				       toItem:item])
	{
	  [_dockView setNeedsDisplay:YES];
	}
      if ([_items count] != originalItemCount)
	{
	  [self refreshDock];
	}
    }
  else if (item && [self shouldApplyX11Icon:icon toItem:item])
    {
      NSString *identifier = nil;

      if (processIdentifier > 0)
	{
	  identifier = [NSString stringWithFormat:@"pid-%d", processIdentifier];
	}
      else
	{
	  identifier = title;
	}
      [self applyX11Icon:icon toItem:item identifier:identifier];
      [_dockView setNeedsDisplay:YES];
    }
}

- (void) x11DockManagerDidUpdateApplicationIcon: (NSImage *)icon
                                     badgeLabel: (NSString *)badgeLabel
                              processIdentifier: (int)processIdentifier
{
  DockItem *item = nil;
  NSNumber *processIdentifierNumber = nil;
  NSUInteger originalItemCount = [_items count];

  if (processIdentifier > 0)
    {
      processIdentifierNumber = [NSNumber numberWithInt:processIdentifier];
      [self rememberApplicationIcon:icon
			  badgeLabel:badgeLabel
		   processIdentifier:processIdentifierNumber];
      item = [self applicationItemMatchingProcessIdentifier:processIdentifierNumber];
      if (!item)
	{
	  item = [self transientApplicationItemForProcessIdentifier:
				processIdentifierNumber];
	}
    }

  if (item)
    {
      if ([self applyApplicationIconUpdate:
		  [_applicationIconManager
		    applicationIconUpdateForProcessIdentifier:processIdentifierNumber]
				       toItem:item])
	{
	  [_dockView setNeedsDisplay:YES];
	}
      if ([_items count] != originalItemCount)
	{
	  [self refreshDock];
	}
    }
}

- (BOOL) applicationBundlePathIsDockWM: (NSString *)path
{
  NSString *candidateBundlePath = [DockItem applicationBundlePathForPath:path];
  NSString *bundlePath = [self normalizedPath:
				 [candidateBundlePath length] ? candidateBundlePath : path];
  NSString *mainBundlePath = [self normalizedPath:[[NSBundle mainBundle] bundlePath]];
  NSString *bundleName = [[bundlePath lastPathComponent] lowercaseString];

  if (![bundlePath length])
    {
      return NO;
    }

  if ([mainBundlePath length] && [bundlePath isEqualToString:mainBundlePath])
    {
      return YES;
    }

  return [bundleName isEqualToString:@"dockwm.app"];
}

- (void) rememberLaunchedApplicationPath: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSString *executablePath = [self executablePathForApplicationPath:path];

  if ([normalizedPath length])
    {
      [_launchedApplicationPaths addObject:normalizedPath];
    }
  if ([executablePath length])
    {
      [_launchedApplicationPaths addObject:executablePath];
    }
}

- (BOOL) windowPathMatchesLaunchedApplication: (NSString *)path
{
  NSString *normalizedPath = [self normalizedPath:path];
  NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
  NSString *normalizedBundlePath = [self normalizedPath:bundlePath];

  if ([normalizedPath length] &&
      [_launchedApplicationPaths containsObject:normalizedPath])
    {
      return YES;
    }

  if ([normalizedBundlePath length] &&
      [_launchedApplicationPaths containsObject:normalizedBundlePath])
    {
      return YES;
    }

  return NO;
}

- (NSArray *) openAtLoginApplicationPaths
{
  return [_applicationStore openAtLoginApplicationPaths];
}

- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path
{
  return [_applicationStore applicationPathIsOpenAtLogin:path];
}

- (void) setApplicationPath: (NSString *)path openAtLogin: (BOOL)openAtLogin
{
  [_applicationStore setApplicationPath:path openAtLogin:openAtLogin];
}

- (BOOL) launchApplicationAtPath: (NSString *)path
{
  DockItem *item = [DockItem applicationItemWithPath:path];
  return [self launchApplicationItem:item];
}

- (BOOL) launchApplicationItem: (DockItem *)item
{
  NSString *path = [item path];
  NSArray *arguments = [self launchArgumentsFromString:[item launchArguments]];
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"desktop"])
    {
      return [self launchDesktopFile:path arguments:arguments];
    }
  else if ([extension isEqualToString:@"app"])
    {
      NSString *executablePath = [self executablePathForApplicationPath:path];

      if ([[NSFileManager defaultManager] isExecutableFileAtPath:executablePath])
	{
	  [NSTask launchedTaskWithLaunchPath:executablePath
				   arguments:arguments];
	  return YES;
	}
      if (![arguments count] &&
	  [[NSWorkspace sharedWorkspace] launchApplication:path])
	{
	  return YES;
	}
      return [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else if (isDir)
    {
      return [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else if ([[NSFileManager defaultManager] isExecutableFileAtPath:path])
    {
      [NSTask launchedTaskWithLaunchPath:path arguments:arguments];
      return YES;
    }

  return [[NSWorkspace sharedWorkspace] openFile:path];
}

- (NSArray *) launchArgumentsFromString: (NSString *)arguments
{
  NSMutableArray *tokens = [NSMutableArray array];
  NSMutableString *token = [NSMutableString string];
  NSUInteger i;
  BOOL inSingleQuote = NO;
  BOOL inDoubleQuote = NO;
  BOOL escaping = NO;

  for (i = 0; i < [arguments length]; i++)
    {
      unichar character = [arguments characterAtIndex:i];

      if (escaping)
	{
	  [token appendFormat:@"%C", character];
	  escaping = NO;
	  continue;
	}
      if (character == '\\' && !inSingleQuote)
	{
	  escaping = YES;
	  continue;
	}
      if (character == '\'' && !inDoubleQuote)
	{
	  inSingleQuote = !inSingleQuote;
	  continue;
	}
      if (character == '"' && !inSingleQuote)
	{
	  inDoubleQuote = !inDoubleQuote;
	  continue;
	}
      if (!inSingleQuote && !inDoubleQuote &&
	  [[NSCharacterSet whitespaceAndNewlineCharacterSet]
	    characterIsMember:character])
	{
	  if ([token length])
	    {
	      [tokens addObject:[[token copy] autorelease]];
	      [token setString:@""];
	    }
	  continue;
	}

      [token appendFormat:@"%C", character];
    }

  if (escaping)
    {
      [token appendString:@"\\"];
    }
  if ([token length])
    {
      [tokens addObject:[[token copy] autorelease]];
    }

  return tokens;
}

- (NSString *) shellQuotedArgument: (NSString *)argument
{
  return [NSString stringWithFormat:@"'%@'",
		   [argument stringByReplacingOccurrencesOfString:@"'"
						       withString:@"'\\''"]];
}

- (void) terminateApplicationItemProcesses: (DockItem *)item
{
  NSArray *processIds = [self runningProcessIdentifiersForApplicationItem:item];
  NSUInteger i;

  for (i = 0; i < [processIds count]; i++)
    {
      int processId = [[processIds objectAtIndex:i] intValue];

      if (processId > 0 && processId != getpid())
	{
	  kill((pid_t)processId, SIGTERM);
	}
    }
}

- (void) launchOpenAtLoginApplications
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSArray *processPaths = [self runningProcessExecutablePaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      DockItem *item;
      NSUInteger itemIndex;

      if (![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
	  continue;
	}

      item = [DockItem applicationItemWithPath:path];
      for (itemIndex = 0; itemIndex < [_items count]; itemIndex++)
	{
	  DockItem *candidate = [_items objectAtIndex:itemIndex];

	  if ([candidate kind] == DockItemApplication &&
	      [[self normalizedPath:[candidate path]]
		isEqualToString:[self normalizedPath:path]])
	    {
	      item = candidate;
	      break;
	    }
	}
      if ([self applicationItemHasRunningProcess:item paths:processPaths])
	{
	  continue;
	}

      [self rememberLaunchedApplicationPath:path];
      [self launchApplicationItem:item];
      [_x11 drainTransientIconEvents];
    }
}

- (void) performInitialApplicationScans
{
  [self loadPersistedApplications];
  [self refreshDock];
  [self scanRunningApplications];
  if (_x11)
    {
      [_x11 scanForDockApps];
      if (!_x11EventTimer)
	{
	  _x11EventTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
							    target:_x11
							  selector:@selector(processPendingEvents)
							  userInfo:nil
							   repeats:YES];
	}
      if (!_scanTimer)
	{
	  _scanTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
							target:_x11
						      selector:@selector(scanForDockApps)
						      userInfo:nil
						       repeats:YES];
	}
    }
  if (!_processScanTimer)
    {
      _processScanTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
							   target:self
							 selector:@selector(scanRunningApplications)
							 userInfo:nil
							  repeats:YES];
    }
  [self launchOpenAtLoginApplications];
}

- (void) scanRunningApplications
{
  NSArray *processPaths = [self runningProcessExecutablePaths];
  BOOL changed = NO;
  NSUInteger i;

  [self pruneApplicationIconUpdatesForExitedProcesses];

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      BOOL running;
      DockItemState newState;

      if ([item kind] != DockItemApplication)
	{
	  continue;
	}

      running = [self applicationItemHasRunningProcess:item paths:processPaths];
      if (!running && [item xWindow])
	{
	  if ([_x11 windowExists:[item xWindow]])
	    {
	      continue;
	    }
	}

      newState = running ? DockItemRunning : DockItemNotRunning;
      if (!running)
	{
	  if ([item state] != DockItemNotRunning ||
	      [item xWindow] ||
	      [[item badgeLabel] length])
	    {
	      [self restoreApplicationItemAfterExit:item];
	      changed = YES;
	    }
	}
      else if ([item state] != newState)
	{
	  [item setState:newState];
	  changed = YES;
	}
    }

  for (i = 0; i < [processPaths count]; i++)
    {
      NSString *processPath = [processPaths objectAtIndex:i];
      NSString *bundlePath = [DockItem applicationBundlePathForPath:processPath];
      DockItem *item;

      if (![bundlePath length] ||
	  [self applicationBundlePathIsDockWM:bundlePath] ||
	  [self dockHasApplicationPath:bundlePath] ||
	  [self transientApplicationItemMatchingBundlePath:bundlePath])
	{
	  continue;
	}

      item = [DockItem applicationItemWithPath:bundlePath];
      [item setPinned:NO];
      [item setState:DockItemRunning];
      [self applyStoredApplicationIconUpdateForItem:item];
      [_items addObject:item];
      changed = YES;
    }

  for (i = [_items count]; i > 0; i--)
    {
      DockItem *item = [_items objectAtIndex:i - 1];

      if ([item kind] == DockItemApplication &&
	  ![item isPinned] &&
	  ![self applicationItemHasRunningProcess:item paths:processPaths])
	{
	  [_items removeObjectAtIndex:i - 1];
	  changed = YES;
	}
      else if ([item kind] == DockItemX11Window &&
	       ![item isPinned] &&
	       [item xWindow] &&
	       ![_x11 windowExists:[item xWindow]])
	{
	  [_items removeObjectAtIndex:i - 1];
	  changed = YES;
	}
    }

  if (changed)
    {
      [self refreshDock];
    }

  [self updateRecyclerState];
}

- (NSArray *) recyclerPaths
{
  return [_recyclerController recyclerPaths];
}

- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path
{
  return [_recyclerController directoryHasVisibleContentsAtPath:path];
}

- (BOOL) recyclerHasContents
{
  return [_recyclerController recyclerHasContents];
}

- (NSString *) recyclerPathForDropping
{
  return [_recyclerController recyclerPathForDropping];
}

- (NSString *) recyclerDestinationPathForPath: (NSString *)path
				 recyclerPath: (NSString *)recyclerPath
{
  return [_recyclerController recyclerDestinationPathForPath:path
						recyclerPath:recyclerPath];
}

- (BOOL) movePathToRecyclerFallback: (NSString *)path
                       recyclerPath: (NSString *)recyclerPath
{
  return [_recyclerController movePathToRecyclerFallback:path
					    recyclerPath:recyclerPath];
}

- (void) dockViewDidReceivePathsInRecycler: (NSArray *)paths
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *recyclerPath = [self recyclerPathForDropping];
  NSString *normalizedRecyclerPath = [self normalizedPath:recyclerPath];
  BOOL recycled = NO;
  NSUInteger i;

  if (![recyclerPath length])
    {
      NSBeep();
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      NSString *normalizedPath = [self normalizedPath:path];

      if (![normalizedPath length] ||
	  ![fileManager fileExistsAtPath:normalizedPath])
	{
	  continue;
	}

      if ([self path:normalizedPath
	isEqualToOrDescendantOfPath:normalizedRecyclerPath])
	{
	  continue;
	}

      if ([self movePathToRecyclerFallback:normalizedPath recyclerPath:recyclerPath])
	{
	  recycled = YES;
	}
    }

  if (recycled)
    {
      [self updateRecyclerState];
      [_dockView startRecyclerWiggle];
      [self refreshDock];
      [[NSSound soundNamed:@"Pop"] play];
    }
  else
    {
      NSBeep();
    }
}

- (void) updateRecyclerState
{
  [_dockView setRecyclerHasContents:[self recyclerHasContents]];
  [_settingsController updateControls];
}

- (void) emptyRecyclerPath: (NSString *)path
{
  [_recyclerController emptyRecyclerPath:path];
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
  if (result != NSAlertDefaultReturn)
    {
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      [self emptyRecyclerPath:[paths objectAtIndex:i]];
    }

  [self updateRecyclerState];
  [_dockView startRecyclerWiggle];
  [self refreshDock];
  [[NSSound soundNamed:@"Glass"] play];
}

- (NSRect) dockWindowFrameForPlacement: (DockPlacement)placement
{
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  NSUInteger cellCount = [_items count] + 2;
  CGFloat pad = [self activeDockPad];
  CGFloat gap = [self activeDockGap];
  CGFloat length = pad * 2.0 + cellCount * [DockPreferences dockCellSize] + (cellCount - 1) * gap;
  CGFloat thickness = [self activeDockWindowWidth];
  CGFloat width = [DockPreferences placementIsHorizontal:placement] ? length : thickness;
  CGFloat height = [DockPreferences placementIsHorizontal:placement] ? thickness : length;
  CGFloat x;
  CGFloat y;

  if (height > NSHeight(screenFrame))
    {
      height = NSHeight(screenFrame);
    }
  if (width > NSWidth(screenFrame))
    {
      width = NSWidth(screenFrame);
    }

  switch (placement)
    {
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

  switch (placement)
    {
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
  [_settingsController updateControls];
}

- (NSMenu *) dockMenu
{
  if (!_dockMenu)
    {
      NSMenuItem *item;

      _dockMenu = [[NSMenu alloc] initWithTitle:@"Dock"];

      item = [[NSMenuItem alloc] initWithTitle:@"Settings..."
					action:@selector(showSettingsPanel:)
				 keyEquivalent:@","];
      [item setTarget:self];
      [_dockMenu addItem:item];
      DESTROY(item);

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

- (SettingsController *) settingsController
{
  if (!_settingsController)
    {
      _settingsController = [[SettingsController alloc] initWithDelegate:self];
    }

  return _settingsController;
}

- (void) showSettingsPanel: (id)sender
{
  [[self settingsController] showWindow:sender];
}

- (void) showSettingsForDockItem: (DockItem *)item
{
  [[self settingsController] showWindowForItem:item];
}

- (DockPlacement) settingsControllerDockPlacement: (SettingsController *)controller
{
  return _dockPlacement;
}

- (NSString *) settingsControllerCurrentDockCellSizeTitle: (SettingsController *)controller
{
  return [DockPreferences largerCellSizeTitle];
}

- (NSInteger) settingsControllerDockCellSizeMode: (SettingsController *)controller
{
  return _dockCellSizeMode;
}

- (DockRunningIndicatorMode) settingsControllerRunningIndicatorMode: (SettingsController *)controller
{
  return _runningIndicatorMode;
}

- (NSColor *) settingsControllerBackgroundColor: (SettingsController *)controller
{
  return [DockPreferences calibratedBackgroundColor:_backgroundColor];
}

- (CGFloat) settingsControllerWindowAlpha: (SettingsController *)controller
{
  return _windowAlpha;
}

- (BOOL) settingsControllerUsesCellTileBackground: (SettingsController *)controller
{
  return _useCellTileBackground;
}

- (BOOL) settingsControllerShowsDockBorder: (SettingsController *)controller
{
  return _showDockBorder;
}

- (BOOL) settingsControllerMagnifiesHoveredIcons: (SettingsController *)controller
{
  return _magnifiesHoveredIcons;
}

- (CGFloat) settingsControllerHoverIconScale: (SettingsController *)controller
{
  return _hoverIconScale;
}

- (BOOL) settingsControllerWigglesOnLaunch: (SettingsController *)controller
{
  return _wigglesOnLaunch;
}

- (BOOL) settingsControllerWigglesOnActivation: (SettingsController *)controller
{
  return _wigglesOnActivation;
}

- (BOOL) settingsControllerRecyclerHasContents: (SettingsController *)controller
{
  return [self recyclerHasContents];
}

- (NSArray *) settingsControllerDockItems: (SettingsController *)controller
{
  [self resolvePathsForX11WindowItems];
  return _items;
}

- (NSUInteger) settingsControllerPinnedItemCount: (SettingsController *)controller
{
  return [self pinnedApplicationCount];
}

- (BOOL) settingsController: (SettingsController *)controller
	       itemIsDockWM: (DockItem *)item
{
  return [self applicationBundlePathIsDockWM:[item path]];
}

- (BOOL) settingsController: (SettingsController *)controller
	 itemIsOpenAtLogin: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return NO;
    }

  return [self applicationPathIsOpenAtLogin:[item path]];
}

- (void) settingsController: (SettingsController *)controller
     didChangeDockPlacement: (DockPlacement)placement
{
  _dockPlacement = placement;
  [self applyDockPlacement];
}

- (void) settingsController: (SettingsController *)controller
   didChangeBackgroundColor: (NSColor *)color
{
  ASSIGN(_backgroundColor, [DockPreferences calibratedBackgroundColor:color]);
  [_dockView setBackgroundColor:_backgroundColor];
  [self saveBackgroundColor];
}

- (void) settingsController: (SettingsController *)controller
       didChangeWindowAlpha: (CGFloat)alpha
{
  _windowAlpha = alpha;
  [_window setAlphaValue:_windowAlpha];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [self saveWindowAlpha];
}

- (void) settingsController: (SettingsController *)controller
    didChangeShowDockBorder: (BOOL)showBorder
{
  _showDockBorder = showBorder;
  [_dockView setShowsBorder:_showDockBorder];
  [self saveShowDockBorder];
}

- (void) settingsController: (SettingsController *)controller
didChangeUseCellTileBackground: (BOOL)useCellTileBackground
{
  _useCellTileBackground = useCellTileBackground;
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [self saveUseCellTileBackground];
}

- (void) settingsController: (SettingsController *)controller
didChangeMagnifiesHoveredIcons: (BOOL)magnifiesHoveredIcons
{
  _magnifiesHoveredIcons = magnifiesHoveredIcons;
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_preferences saveMagnifiesHoveredIcons:_magnifiesHoveredIcons];
}

- (void) settingsController: (SettingsController *)controller
didChangeHoverIconScale: (CGFloat)scale
{
  if (scale < 1.0)
    {
      scale = 1.0;
    }
  else if (scale > 1.5)
    {
      scale = 1.5;
    }

  _hoverIconScale = scale;
  [_dockView setHoverIconScale:_hoverIconScale];
  [_preferences saveHoverIconScale:_hoverIconScale];
}

- (void) settingsController: (SettingsController *)controller
  didChangeWigglesOnLaunch: (BOOL)wiggles
{
  _wigglesOnLaunch = wiggles;
  [_preferences saveWigglesOnLaunch:_wigglesOnLaunch];
}

- (void) settingsController: (SettingsController *)controller
didChangeWigglesOnActivation: (BOOL)wiggles
{
  _wigglesOnActivation = wiggles;
  [_preferences saveWigglesOnActivation:_wigglesOnActivation];
}

- (void) settingsController: (SettingsController *)controller
  didChangeDockCellSizeMode: (NSInteger)mode
{
  if (mode != DockCellSizeMode64)
    {
      mode = DockCellSizeModeCurrent;
    }

  if (_dockCellSizeMode != mode)
    {
      _dockCellSizeMode = mode;
      [self saveDockCellSizeMode];
      [self applyDockPlacement];
    }
}

- (void) settingsController: (SettingsController *)controller
didChangeRunningIndicatorMode: (DockRunningIndicatorMode)mode
{
  if (mode != DockRunningIndicatorModeNotRunningDots)
    {
      mode = DockRunningIndicatorModeRunningDot;
    }

  if (_runningIndicatorMode != mode)
    {
      _runningIndicatorMode = mode;
      [_dockView setRunningIndicatorMode:_runningIndicatorMode];
      [self saveRunningIndicatorMode];
    }
}

- (void) settingsController: (SettingsController *)controller
   didChangeLaunchArguments: (NSString *)arguments
		    forItem: (DockItem *)item
{
  if ([item kind] != DockItemApplication || ![[item path] length])
    {
      return;
    }

  [item setLaunchArguments:arguments];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
       didChangeOpenAtLogin: (BOOL)openAtLogin
		    forItem: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (!([item kind] == DockItemApplication ||
	[item kind] == DockItemX11Window) ||
      ![[item path] length])
    {
      return;
    }

  [self setApplicationPath:[item path] openAtLogin:openAtLogin];
}

- (void) settingsController: (SettingsController *)controller
       didMoveItemFromIndex: (NSUInteger)fromIndex
		    toIndex: (NSUInteger)toIndex
{
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  DockItem *item;

  if (fromIndex >= [_items count] || toIndex >= [_items count])
    {
      return;
    }

  item = RETAIN([_items objectAtIndex:fromIndex]);
  if ([item isPinned] && toIndex >= pinnedCount)
    {
      DESTROY(item);
      return;
    }

  [_items removeObjectAtIndex:fromIndex];
  if (![item isPinned] && toIndex < pinnedCount)
    {
      [item setPinned:YES];
    }
  [_items insertObject:item atIndex:toIndex];
  [self savePersistedApplications];
  [self refreshDock];
  DESTROY(item);
}

- (void) settingsController: (SettingsController *)controller
       didDeleteItemAtIndex: (NSUInteger)index
{
  DockItem *item;

  if (index >= [_items count])
    {
      return;
    }

  item = [_items objectAtIndex:index];
  if (([item kind] == DockItemApplication ||
       [item kind] == DockItemX11Window) &&
      [[item path] length])
    {
      [self setApplicationPath:[item path] openAtLogin:NO];
    }
  [_items removeObjectAtIndex:index];
  [self savePersistedApplications];
  [self refreshDock];
}

- (void) settingsControllerDidEmptyRecycler: (SettingsController *)controller
{
  [self emptyRecycler:self];
}

- (void) applyDockPlacement
{
  [[NSUserDefaults standardUserDefaults] setInteger:_dockPlacement forKey:@"DockPlacement"];
  [self applyDockCellSizeToView];
  [_dockView setHorizontal:[DockPreferences placementIsHorizontal:_dockPlacement]];
  [_window setFrame:[self dockWindowFrameForPlacement:_dockPlacement]
            display:YES];
  [_dockView setFrame:NSMakeRect(0, 0,
                                 NSWidth([_window frame]),
                                 NSHeight([_window frame]))];
  [_x11 setDockPlacement:_dockPlacement];
  [self updateDockBackground];
  [self updateDockMenu];
}

- (void) updateDockBackground
{
  [_dockView setBackgroundColor:_backgroundColor];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [_dockView setShowsBorder:_showDockBorder];
  [_dockView setRunningIndicatorMode:_runningIndicatorMode];
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_dockView setHoverIconScale:_hoverIconScale];
}

- (void) startLaunchWiggleForItem: (DockItem *)item
{
  if (_wigglesOnLaunch)
    {
      [_dockView startWiggleForItem:item];
    }
}

- (void) startActivationWiggleForItem: (DockItem *)item
{
  if (_wigglesOnActivation)
    {
      [_dockView startWiggleForItem:item];
    }
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

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      if ([item xWindow] == xWindow)
	{
	  return item;
	}
    }
  return nil;
}

- (DockItem *) itemForApplicationIconWindow: (unsigned long)xWindow
{
  return [_applicationIconManager itemForApplicationIconWindow:xWindow];
}

- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item
{
  [_applicationIconManager setApplicationIconWindow:xWindow forItem:item];
}

- (void) removeApplicationIconWindowsForItem: (DockItem *)item
{
  [_applicationIconManager removeApplicationIconWindowsForItem:item];
}

- (void) restoreApplicationItemAfterExit: (DockItem *)item
{
  [item setState:DockItemNotRunning];
  [item setXWindow:0];
  [item restoreOriginalIcon];
  [item setBadgeLabel:nil];
  [self removeApplicationIconWindowsForItem:item];
}

- (NSUInteger) indexForItem: (DockItem *)targetItem
{
  NSUInteger i;

  for (i = 0; i < [_items count]; i++)
    {
      if ([_items objectAtIndex:i] == targetItem)
	{
	  return i;
	}
    }

  return NSNotFound;
}

- (DockItem *) applicationItemMatchingTitle: (NSString *)title
{
  NSString *windowTitle = [title lowercaseString];
  NSUInteger i;

  if (![windowTitle length])
    {
      return nil;
    }

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSString *appTitle;

      if ([item kind] != DockItemApplication)
	{
	  continue;
	}

      appTitle = [[item title] lowercaseString];
      if ([appTitle length] &&
	  ([windowTitle rangeOfString:appTitle].location != NSNotFound ||
	   [appTitle rangeOfString:windowTitle].location != NSNotFound))
	{
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

  if (![windowPath length])
    {
      return nil;
    }

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSString *itemPath;
      NSString *executablePath;
      NSString *itemName;
      NSString *executableName;

      if ([item kind] != DockItemApplication)
	{
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
	   [self path:windowPath isEqualToOrDescendantOfPath:itemPath]))
	{
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

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
      NSString *applicationPath = [bundlePath length] ? bundlePath : path;
      DockItem *transientItem;
      NSUInteger transientIndex;
      BOOL isDir = NO;

      if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] &&
	  ![self dockHasApplicationPath:applicationPath])
	{
	  DockItem *item = [DockItem applicationItemWithPath:applicationPath];

	  transientItem = [self transientApplicationItemMatchingBundlePath:applicationPath];
	  transientIndex = transientItem ? [self indexForItem:transientItem] : NSNotFound;
	  if (transientIndex != NSNotFound)
	    {
	      [_items removeObjectAtIndex:transientIndex];
	      if (transientIndex < insertionIndex && insertionIndex > 0)
		{
		  insertionIndex--;
		}
	    }

	  [item setPinned:YES];
	  [_items insertObject:item atIndex:insertionIndex];
	  insertionIndex++;
	  added = YES;
	}
    }

  if (added)
    {
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

  if (fromIndex >= [_items count] || toIndex > [_items count])
    {
      return;
    }

  if (fromIndex < pinnedCount && toIndex > pinnedCount)
    {
      toIndex = pinnedCount;
    }
  else if (fromIndex >= pinnedCount && toIndex <= pinnedCount)
    {
      promoteItem = YES;
    }

  if (toIndex > fromIndex)
    {
      toIndex--;
    }

  if (fromIndex == toIndex && !promoteItem)
    {
      return;
    }

  item = RETAIN([_items objectAtIndex:fromIndex]);
  [_items removeObjectAtIndex:fromIndex];
  if (promoteItem)
    {
      [item setPinned:YES];
    }
  [_items insertObject:item atIndex:toIndex];
  DESTROY(item);

  [self savePersistedApplications];
  [self refreshDock];
}

- (void) dockViewDidRemoveItemAtIndex: (NSUInteger)index
{
  DockItem *item;

  if (index >= [_items count])
    {
      return;
    }

  item = [_items objectAtIndex:index];
  if (([item kind] == DockItemApplication ||
       [item kind] == DockItemX11Window) &&
      [[item path] length])
    {
      [self setApplicationPath:[item path] openAtLogin:NO];
    }

  [_items removeObjectAtIndex:index];
  [self savePersistedApplications];
  [self refreshDock];
}

- (BOOL) dockView: (id)dockView itemIsOpenAtLogin: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return NO;
    }

  return [self applicationPathIsOpenAtLogin:[item path]];
}

- (void) dockView: (id)dockView didToggleOpenAtLoginForItem: (DockItem *)item
{
  BOOL openAtLogin;

  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return;
    }

  openAtLogin = ![self applicationPathIsOpenAtLogin:[item path]];
  [self setApplicationPath:[item path] openAtLogin:openAtLogin];
}

- (void) dockView: (id)dockView didShowItemInFileViewer: (DockItem *)item
{
  NSString *path = [item path];
  NSString *directory;

  if (![path length])
    {
      return;
    }

  directory = [path stringByDeletingLastPathComponent];
  [[NSWorkspace sharedWorkspace] selectFile:path
                   inFileViewerRootedAtPath:directory];
}

- (void) dockView: (id)dockView didQuitItem: (DockItem *)item
{
  NSUInteger index;

  if ([item kind] == DockItemApplication)
    {
      [self terminateApplicationItemProcesses:item];
      [self restoreApplicationItemAfterExit:item];
    }
  else if ([item xWindow])
    {
      [_x11 closeWindow:[item xWindow]];
      [item setState:DockItemNotRunning];
    }
  if (![item isPinned])
    {
      index = [self indexForItem:item];
      if (index != NSNotFound)
	{
	  [_items removeObjectAtIndex:index];
	}
    }

  [self refreshDock];
}

- (void) dockViewDidEmptyRecycler: (id)dockView
{
  [self emptyRecycler:dockView];
}

- (void) dockViewDidActivateRecycler
{
  NSString *path = [self recyclerPathForDropping];

  if ([path length])
    {
      [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else
    {
      NSBeep();
    }
}

- (BOOL) dockView: (id)dockView canShowSettingsForItem: (DockItem *)item
{
  return ([item kind] == DockItemApplication ||
	  [item kind] == DockItemX11Window) &&
    ![self applicationBundlePathIsDockWM:[item path]];
}

- (void) dockView: (id)dockView didShowSettingsForItem: (DockItem *)item
{
  if ([self dockView:dockView canShowSettingsForItem:item])
    {
      [self showSettingsForDockItem:item];
    }
}

- (void) dockViewDidActivateItem: (DockItem *)item
{
  if ([item kind] == DockItemApplication)
    {
      NSString *path = [item path];
      NSArray *processIds;
      BOOL launched = NO;

      processIds = [self runningProcessIdentifiersForApplicationItem:item];
      if ([processIds count])
	{
	  if ([self activateRunningApplicationWithProcessIdentifiers:processIds])
	    {
	      [item setState:DockItemRunning];
	      [self startActivationWiggleForItem:item];
	      [self refreshDock];
	      return;
	    }

	  [_x11 drainTransientIconEvents];
	  if ([_x11 activateApplicationWithProcessIdentifiers:processIds])
	    {
	      [_x11 drainTransientIconEvents];
	      [item setState:DockItemRunning];
	      [self startActivationWiggleForItem:item];
	      [self refreshDock];
	      return;
	    }
	  [_x11 drainTransientIconEvents];
	}

      if ([item xWindow] && [item state] != DockItemNotRunning)
	{
	  [_x11 drainTransientIconEvents];
	  [_x11 activateWindow:[item xWindow]];
	  [_x11 drainTransientIconEvents];
	  [self startActivationWiggleForItem:item];
	  return;
	}

      [self rememberLaunchedApplicationPath:path];
      launched = [self launchApplicationItem:item];
      [_x11 drainTransientIconEvents];

      if (launched)
	{
	  [item setState:DockItemRunning];
	  [self startLaunchWiggleForItem:item];
	  [self refreshDock];
	}
    }
  else
    {
      [_x11 drainTransientIconEvents];
      [_x11 activateWindow:[item xWindow]];
      [_x11 drainTransientIconEvents];
      [self startActivationWiggleForItem:item];
    }
}

- (void) dockViewDidActivateTopIcon
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
						       NSAllDomainsMask,
						       YES);
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [[paths objectAtIndex:i]
			 stringByAppendingPathComponent:@"GWorkspace.app"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:path])
	{
	  [self rememberLaunchedApplicationPath:path];
	  if (![[NSWorkspace sharedWorkspace] launchApplication:path])
	    {
	      [[NSWorkspace sharedWorkspace] openFile:path];
	    }
	  [_x11 drainTransientIconEvents];
	  return;
	}
    }
}

- (BOOL) launchDesktopFile: (NSString *)path arguments: (NSArray *)arguments
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
			       [NSCharacterSet newlineCharacterSet]];
  NSUInteger i;

  if (![contents length])
    {
      return NO;
    }

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [lines objectAtIndex:i];
      if ([line hasPrefix:@"Exec="])
	{
	  NSString *command = [line substringFromIndex:5];
	  command = [[command componentsSeparatedByString:@"%"] objectAtIndex:0];
	  if ([command length])
	    {
	      NSString *shellPath = [self pathForExecutableCommand:@"sh"];
	      NSUInteger j;

	      if ([shellPath length])
		{
		  for (j = 0; j < [arguments count]; j++)
		    {
		      command = [command stringByAppendingFormat:@" %@",
				 [self shellQuotedArgument:
					 [arguments objectAtIndex:j]]];
		    }
		  [NSTask launchedTaskWithLaunchPath:shellPath
					   arguments:[NSArray arrayWithObjects:@"-lc", command, nil]];
		  return YES;
		}
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
  DockItem *item = [self itemForXWindow:xWindow];
  BOOL matchedApplication;
  NSString *iconIdentifier;

  if (dockApp && ![path length])
    {
      path = [self executablePathForX11WindowTitle:title];
    }
  iconIdentifier = [self x11IconIdentifierForTitle:title
					      path:path
					    window:xWindow];

  if (!item)
    {
      item = [self itemForApplicationIconWindow:xWindow];
    }
  if (!item && !dockApp)
    {
      item = [self applicationItemMatchingExecutablePath:path];
    }
  if (!item && !dockApp)
    {
      item = [self applicationItemMatchingTitle:title];
    }
  matchedApplication = item && [item kind] == DockItemApplication;

  if (dockApp && [self applicationBundlePathIsDockWM:path])
    {
      return;
    }

  if (dockApp && item &&
      [self windowPathMatchesLaunchedApplication:path])
    {
      [self setApplicationIconWindow:xWindow forItem:item];
      [item setState:DockItemRunning];
      if ([item kind] == DockItemX11Window && [path length])
	{
	  [item setPath:path];
	}
      if ([self shouldApplyX11Icon:icon toItem:item])
	{
	  [self applyX11Icon:icon toItem:item identifier:iconIdentifier];
	}
      [self applyStoredApplicationIconUpdateForItem:item];
      [self refreshDock];
      return;
    }

  if (item)
    {
      if ([item kind] == DockItemX11Window && [path length])
	{
	  [item setPath:path];
	}
      [item setState: (hidden ? DockItemHidden : DockItemRunning)];
      if (!(dockApp && matchedApplication))
	{
	  [item setXWindow:xWindow];
	}
      if ([self shouldApplyX11Icon:icon toItem:item])
	{
	  [self applyX11Icon:icon toItem:item identifier:iconIdentifier];
	}
      if ([item kind] == DockItemApplication)
	{
	  [self applyStoredApplicationIconUpdateForItem:item];
	}
    }
  else
    {
      if (!dockApp && [path length] && ![self applicationBundlePathIsDockWM:path])
	{
	  NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
	  NSString *applicationPath = [bundlePath length] ? bundlePath : path;

	  item = [DockItem applicationItemWithPath:applicationPath];
	  [item setPinned:NO];
	  [item setState: (hidden ? DockItemHidden : DockItemRunning)];
	  [item setXWindow:xWindow];
	  if ([self shouldApplyX11Icon:icon toItem:item])
	    {
	      [self applyX11Icon:icon toItem:item identifier:iconIdentifier];
	    }
	  [self applyStoredApplicationIconUpdateForItem:item];
	}
      else
	{
	  item = [DockItem x11ItemWithTitle:title window:xWindow icon:icon hidden:hidden];
	  if ([path length])
	    {
	      [item setPath:path];
	    }
	  [self applyX11Icon:icon toItem:item identifier:iconIdentifier];
	}
      [_items addObject:item];
    }

  [self refreshDock];
  if (dockApp)
    {
      if ([item kind] == DockItemApplication)
	{
	  [self setApplicationIconWindow:xWindow forItem:item];
	}
      else
	{
	  NSUInteger itemIndex = [self indexForItem:item];
	  if (itemIndex != NSNotFound)
	    {
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

  if (!item)
    {
      item = [self itemForApplicationIconWindow:xWindow];
    }
  if (item)
    {
      [item setState: (hidden ? DockItemHidden : DockItemRunning)];
      if ([self shouldApplyX11Icon:icon toItem:item])
	{
	  [self applyX11Icon:icon
		      toItem:item
		  identifier:[NSString stringWithFormat:@"0x%lx", xWindow]];
	}
      [_dockView setNeedsDisplay:YES];
    }
}

@end
