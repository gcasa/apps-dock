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

#import "AppControllerPrivate.h"

@implementation AppController (Applications)

- (void) loadPersistedApplications
{
  [_applicationStore loadPersistedApplicationsIntoItems:_items];
}

- (void) savePersistedApplications
{
  [_applicationStore savePersistedApplicationsFromItems:_items];
}

- (void) playDockRemovalSoundIfEnabled
{
  if (_playsSoundOnRemove)
    {
      [[NSSound soundNamed:@"Pop"] play];
    }
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

@end
