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
#import <dirent.h>
#import <limits.h>
#import <mntent.h>
#import <paths.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockCompactGap = 1.0;
static CGFloat DockPad = 10.0;
static CGFloat DockCompactPad = 0.0;
static NSString *DockApplicationsDefaultsKey = @"DockApplications";
static NSString *DockOpenAtLoginApplicationsDefaultsKey = @"DockOpenAtLoginApplications";
static NSString *DockBackgroundColorDefaultsKey = @"DockBackgroundColor";
static NSString *DockShowBorderDefaultsKey = @"DockShowBorder";
static NSString *DockCellSizeModeDefaultsKey = @"DockCellSizeMode";
static NSString *DockUseCellTileBackgroundDefaultsKey = @"DockUseCellTileBackground";

enum
{
  DockCellSizeModeCurrent = 0,
  DockCellSizeMode64 = 1
};

static NSColor *
DockCalibratedBackgroundColor (NSColor *color)
{
  NSColor *rgbColor = nil;
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  if (!color)
    {
      return [NSColor blackColor];
    }

  NS_DURING
    rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (!rgbColor)
    {
      rgbColor = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
  if (rgbColor)
    {
      [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
    }
  NS_HANDLER
    rgbColor = nil;
  NS_ENDHANDLER

    if (!rgbColor)
      {
	return [NSColor blackColor];
      }

  return [NSColor colorWithCalibratedRed:red
                                   green:green
                                    blue:blue
                                   alpha:alpha];
}

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
  _applicationIconWindowItems = [NSMutableDictionary new];
  _applicationIconUpdatesByProcessID = [NSMutableDictionary new];
  _dockPlacement = [self savedDockPlacement];
  _dockCellSizeMode = [self savedDockCellSizeMode];
  _backgroundColor = RETAIN([self savedBackgroundColor]);
  _useCellTileBackground = [self savedUseCellTileBackground];
  _showDockBorder = [self savedShowDockBorder];
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
  [self applyDockCellSizeToView];
  [_dockView setBackgroundColor:_backgroundColor];
  [_dockView setShowsBorder:_showDockBorder];
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
  DESTROY(_settingsEmptyRecyclerButton);
  DESTROY(_settingsShowBorderButton);
  DESTROY(_settingsUseCellTileButton);
  DESTROY(_settings64CellSizeButton);
  DESTROY(_settingsCurrentCellSizeButton);
  DESTROY(_settingsBlueSlider);
  DESTROY(_settingsGreenSlider);
  DESTROY(_settingsRedSlider);
  DESTROY(_settingsBackgroundColorWell);
  DESTROY(_settingsPlacementPopup);
  DESTROY(_settingsPanel);
  DESTROY(_dockMenu);
  DESTROY(_x11);
  DESTROY(_dockView);
  DESTROY(_window);
  DESTROY(_applicationIconWindowItems);
  DESTROY(_applicationIconUpdatesByProcessID);
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
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedPlacement = [defaults objectForKey:@"DockPlacement"];

  if (savedPlacement)
    {
      NSInteger placement = [defaults integerForKey:@"DockPlacement"];
      if (placement >= DockPlacementLeftTop && placement <= DockPlacementBottomCenter)
	{
	  return (DockPlacement)placement;
	}
    }

  if ([defaults boolForKey:@"DockOnRight"])
    {
      return [defaults boolForKey:@"DockCentered"] ? DockPlacementRightCenter : DockPlacementRightTop;
    }

  return [defaults boolForKey:@"DockCentered"] ? DockPlacementLeftCenter : DockPlacementLeftTop;
}

- (NSColor *) savedBackgroundColor
{
  id savedColor = [[NSUserDefaults standardUserDefaults]
		    objectForKey:DockBackgroundColorDefaultsKey];
  NSColor *color = nil;

  if ([savedColor isKindOfClass:[NSDictionary class]])
    {
      NSNumber *red = [savedColor objectForKey:@"Red"];
      NSNumber *green = [savedColor objectForKey:@"Green"];
      NSNumber *blue = [savedColor objectForKey:@"Blue"];
      NSNumber *alpha = [savedColor objectForKey:@"Alpha"];

      if (red && green && blue)
        {
          color = [NSColor colorWithCalibratedRed:[red doubleValue]
                                            green:[green doubleValue]
                                             blue:[blue doubleValue]
                                            alpha:alpha ? [alpha doubleValue] : 1.0];
        }
    }
  else if ([savedColor isKindOfClass:[NSData class]])
    {
      NS_DURING
        color = [NSUnarchiver unarchiveObjectWithData:savedColor];
      NS_HANDLER
        color = nil;
      NS_ENDHANDLER
	}

  return DockCalibratedBackgroundColor(color);
}

- (void) saveBackgroundColor
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSColor *color = DockCalibratedBackgroundColor(_backgroundColor);
  NSMutableDictionary *components = [NSMutableDictionary dictionary];
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  [color getRed:&red green:&green blue:&blue alpha:&alpha];
  [components setObject:[NSNumber numberWithDouble:red] forKey:@"Red"];
  [components setObject:[NSNumber numberWithDouble:green] forKey:@"Green"];
  [components setObject:[NSNumber numberWithDouble:blue] forKey:@"Blue"];
  [components setObject:[NSNumber numberWithDouble:alpha] forKey:@"Alpha"];
  [defaults setObject:components forKey:DockBackgroundColorDefaultsKey];
}

- (BOOL) savedShowDockBorder
{
  return [[NSUserDefaults standardUserDefaults]
	   boolForKey:DockShowBorderDefaultsKey];
}

- (void) saveShowDockBorder
{
  [[NSUserDefaults standardUserDefaults] setBool:_showDockBorder
					  forKey:DockShowBorderDefaultsKey];
}

- (NSInteger) savedDockCellSizeMode
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedMode = [defaults objectForKey:DockCellSizeModeDefaultsKey];

  if (savedMode)
    {
      NSInteger mode = [defaults integerForKey:DockCellSizeModeDefaultsKey];
      if (mode == DockCellSizeMode64)
	{
	  return mode;
	}
    }

  return DockCellSizeModeCurrent;
}

- (void) saveDockCellSizeMode
{
  [[NSUserDefaults standardUserDefaults] setInteger:_dockCellSizeMode
					     forKey:DockCellSizeModeDefaultsKey];
}

- (BOOL) savedUseCellTileBackground
{
  return [[NSUserDefaults standardUserDefaults]
	   boolForKey:DockUseCellTileBackgroundDefaultsKey];
}

- (void) saveUseCellTileBackground
{
  [[NSUserDefaults standardUserDefaults] setBool:_useCellTileBackground
					  forKey:DockUseCellTileBackgroundDefaultsKey];
}

- (CGFloat) activeDockPad
{
  return _dockCellSizeMode == DockCellSizeMode64 ? DockCompactPad : DockPad;
}

- (CGFloat) activeDockGap
{
  return _dockCellSizeMode == DockCellSizeMode64 ? DockCompactGap : DockGap;
}

- (CGFloat) activeDockWindowWidth
{
  return DockCell + [self activeDockPad] * 2.0;
}

- (void) applyDockCellSizeToView
{
  if (_dockView)
    {
      [_dockView setIconCellSize:DockCell
			      gap:[self activeDockGap]
			  padding:[self activeDockPad]];
    }
}

- (void) loadPersistedApplications
{
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
		     objectForKey:DockApplicationsDefaultsKey];
  NSUInteger i;

  if (![paths isKindOfClass:[NSArray class]])
    {
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      id path = [paths objectAtIndex:i];
      NSString *bundlePath;
      NSString *applicationPath;
      DockItem *transientItem;
      BOOL isDir = NO;

      if (![path isKindOfClass:[NSString class]])
	{
	  continue;
	}

      bundlePath = [DockItem applicationBundlePathForPath:path];
      applicationPath = [bundlePath length] ? bundlePath : path;

      if ([[NSFileManager defaultManager] fileExistsAtPath:applicationPath
					       isDirectory:&isDir] &&
	  ![self dockHasApplicationPath:applicationPath])
	{
	  transientItem =
	    [self transientApplicationItemMatchingBundlePath:applicationPath];
	  if (transientItem)
	    {
	      [_items removeObject:transientItem];
	    }
	  [_items addObject:[DockItem applicationItemWithPath:applicationPath]];
	}
    }
}

- (void) savePersistedApplications
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSString *path = [item path];

      if ([item kind] == DockItemApplication &&
	  [item isPinned] &&
	  [path length] &&
	  ![paths containsObject:path])
	{
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

  if (![normalizedPath length])
    {
      return NO;
    }

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      if ([item kind] == DockItemApplication &&
	  [item isPinned] &&
	  [[self normalizedPath:[item path]] isEqualToString:normalizedPath])
	{
	  return YES;
	}
    }

  return NO;
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
  if (![path length])
    {
      return nil;
    }

  return [path stringByResolvingSymlinksInPath];
}

- (NSArray *) commandSearchPathComponents
{
  NSString *pathEnvironment = [[[NSProcessInfo processInfo] environment]
				objectForKey:@"PATH"];
  NSMutableArray *components = [NSMutableArray array];

  if ([pathEnvironment length])
    {
      return [pathEnvironment componentsSeparatedByString:@":"];
    }

  {
    size_t length = confstr(_CS_PATH, NULL, 0);

    if (length > 0)
      {
	char *buffer = malloc(length);

	if (buffer)
	  {
	    if (confstr(_CS_PATH, buffer, length) > 0)
	      {
		NSString *fallbackPath =
		  [NSString stringWithUTF8String:buffer];

		if ([fallbackPath length])
		  {
		    [components addObjectsFromArray:
				  [fallbackPath componentsSeparatedByString:@":"]];
		  }
	      }
	    free(buffer);
	  }
      }
  }

  return components;
}

- (NSString *) procFilesystemPath
{
  FILE *mounts;
  struct mntent *entry;
  NSString *path = nil;

  mounts = setmntent(_PATH_MOUNTED, "r");
  if (!mounts)
    {
      return nil;
    }

  while ((entry = getmntent(mounts)) != NULL)
    {
      if (entry->mnt_type && strcmp(entry->mnt_type, "proc") == 0 &&
	  entry->mnt_dir)
	{
	  path = [NSString stringWithUTF8String:entry->mnt_dir];
	  break;
	}
    }

  endmntent(mounts);
  return [path length] ? path : nil;
}

- (NSString *) procPathForProcessIdentifierString: (NSString *)identifier
{
  NSString *procPath = [self procFilesystemPath];

  if (![procPath length] || ![identifier length])
    {
      return nil;
    }

  return [procPath stringByAppendingPathComponent:identifier];
}

- (BOOL) path: (NSString *)path isEqualToOrDescendantOfPath: (NSString *)parentPath
{
  NSArray *pathComponents;
  NSArray *parentComponents;
  NSUInteger i;

  path = [self normalizedPath:path];
  parentPath = [self normalizedPath:parentPath];
  if (![path length] || ![parentPath length])
    {
      return NO;
    }
  if ([path isEqualToString:parentPath])
    {
      return YES;
    }

  pathComponents = [path pathComponents];
  parentComponents = [parentPath pathComponents];
  if ([pathComponents count] <= [parentComponents count])
    {
      return NO;
    }

  for (i = 0; i < [parentComponents count]; i++)
    {
      if (![[pathComponents objectAtIndex:i]
	     isEqualToString:[parentComponents objectAtIndex:i]])
	{
	  return NO;
	}
    }

  return YES;
}

- (NSString *) executablePathForApplicationPath: (NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  if (![path length])
    {
      return nil;
    }

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"app"] && isDir)
    {
      NSBundle *bundle = [NSBundle bundleWithPath:path];
      NSString *executablePath = [bundle executablePath];
      NSString *fallbackPath;

      if ([executablePath length])
	{
	  return [self normalizedPath:executablePath];
	}

      fallbackPath = [path stringByAppendingPathComponent:
			     [[path lastPathComponent] stringByDeletingPathExtension]];
      if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackPath])
	{
	  return [self normalizedPath:fallbackPath];
	}
    }

  if ([extension isEqualToString:@"desktop"])
    {
      NSString *desktopExecutable = [self executablePathForDesktopFile:path];
      if ([desktopExecutable length])
	{
	  return desktopExecutable;
	}
    }

  if (!isDir && [[NSFileManager defaultManager] isExecutableFileAtPath:path])
    {
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

  for (i = 0; i < [string length]; i++)
    {
      unichar ch = [string characterAtIndex:i];

      if (quoted)
	{
	  if (ch == quote)
	    {
	      quoted = NO;
	    }
	  else
	    {
	      [token appendFormat:@"%C", ch];
	    }
	}
      else if (ch == '"' || ch == '\'')
	{
	  quoted = YES;
	  quote = ch;
	}
      else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
		     characterIsMember:ch])
	{
	  if ([token length])
	    {
	      break;
	    }
	}
      else
	{
	  [token appendFormat:@"%C", ch];
	}
    }

  return [token length] ? token : nil;
}

- (NSString *) pathForExecutableCommand: (NSString *)command
{
  NSArray *pathComponents;
  NSUInteger i;

  if (![command length])
    {
      return nil;
    }

  if ([command isAbsolutePath] &&
      [[NSFileManager defaultManager] fileExistsAtPath:command])
    {
      return [self normalizedPath:command];
    }

  pathComponents = [self commandSearchPathComponents];

  for (i = 0; i < [pathComponents count]; i++)
    {
      NSString *candidate = [[pathComponents objectAtIndex:i]
				 stringByAppendingPathComponent:command];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate])
	{
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

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [lines objectAtIndex:i];
      if ([line hasPrefix:@"Exec="])
	{
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

  if (!chars || !chars[0])
    {
      return NO;
    }

  for (i = 0; chars[i]; i++)
    {
      if (!isdigit((unsigned char)chars[i]))
	{
	  return NO;
	}
    }

  return YES;
}

- (NSArray *) runningProcessExecutablePaths
{
  NSString *procPath = [self procFilesystemPath];
  NSArray *entries;
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableSet *seenPaths = [NSMutableSet set];
  NSUInteger i;

  if (![procPath length])
    {
      return paths;
    }
  entries = [[NSFileManager defaultManager] directoryContentsAtPath:procPath];

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *linkPath;
      char target[PATH_MAX];
      ssize_t length;

      if (![self stringIsProcessIdentifier:entry])
	{
	  continue;
	}

      linkPath = [[procPath stringByAppendingPathComponent:entry]
		   stringByAppendingPathComponent:@"exe"];
      length = readlink([linkPath fileSystemRepresentation],
			target,
			sizeof(target) - 1);
      if (length <= 0)
	{
	  continue;
	}

      target[length] = '\0';
      {
	NSString *path = [self normalizedPath:
				 [NSString stringWithUTF8String:target]];
	if ([path length] && ![seenPaths containsObject:path])
	  {
	    [seenPaths addObject:path];
	    [paths addObject:path];
	  }
      }
    }

  return paths;
}

- (NSString *) executablePathForProcessIdentifier: (NSNumber *)processIdentifier
{
  NSString *linkPath;
  char target[PATH_MAX];
  ssize_t length;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return nil;
    }

  linkPath = [[self procPathForProcessIdentifierString:
		      [processIdentifier stringValue]]
	       stringByAppendingPathComponent:@"exe"];
  length = readlink([linkPath fileSystemRepresentation],
		    target,
		    sizeof(target) - 1);
  if (length <= 0)
    {
      return nil;
    }

  target[length] = '\0';
  return [self normalizedPath:[NSString stringWithUTF8String:target]];
}

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  NSString *procPath = [self procFilesystemPath];
  NSArray *entries;
  NSMutableArray *processIds = [NSMutableArray array];
  NSUInteger i;

  if (![procPath length])
    {
      return processIds;
    }
  entries = [[NSFileManager defaultManager] directoryContentsAtPath:procPath];

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *linkPath;
      char target[PATH_MAX];
      ssize_t length;
      NSString *processPath;

      if (![self stringIsProcessIdentifier:entry])
	{
	  continue;
	}

      linkPath = [[procPath stringByAppendingPathComponent:entry]
		   stringByAppendingPathComponent:@"exe"];
      length = readlink([linkPath fileSystemRepresentation],
			target,
			sizeof(target) - 1);
      if (length <= 0)
	{
	  continue;
	}

      target[length] = '\0';
      processPath = [self normalizedPath:[NSString stringWithUTF8String:target]];
      if ([self applicationItem:item matchesRunningProcessPath:processPath])
	{
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

  if (![processPath length])
    {
      return NO;
    }

  if (([itemPath length] && [processPath isEqualToString:itemPath]) ||
      ([executablePath length] && [processPath isEqualToString:executablePath]) ||
      ([processName length] && [processName isEqualToString:itemName]) ||
      ([processName length] && [processName isEqualToString:executableName]) ||
      ([itemPath length] &&
       [[[itemPath pathExtension] lowercaseString] isEqualToString:@"app"] &&
       [self path:processPath isEqualToOrDescendantOfPath:itemPath]))
    {
      return YES;
    }

  return NO;
}

- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
				    paths: (NSArray *)processPaths
{
  NSUInteger i;

  for (i = 0; i < [processPaths count]; i++)
    {
      if ([self applicationItem:item
		matchesRunningProcessPath:[processPaths objectAtIndex:i]])
	{
	  return YES;
	}
    }

  return NO;
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

- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image
{
  return [item icon] == image;
}

- (NSString *) x11IconCacheDirectory
{
  NSArray *libraryPaths =
    NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
					NSUserDomainMask,
					YES);
  NSString *libraryPath = [libraryPaths count] ? [libraryPaths objectAtIndex:0] : nil;
  NSString *cachePath;

  if (![libraryPath length])
    {
      libraryPath = NSHomeDirectory();
    }
  if (![libraryPath length])
    {
      return nil;
    }

  cachePath = [[libraryPath stringByAppendingPathComponent:@"DockWM"]
			   stringByAppendingPathComponent:@"X11Icons"];
  if ([[NSFileManager defaultManager] createDirectoryAtPath:cachePath
				withIntermediateDirectories:YES
						 attributes:nil
						      error:NULL])
    {
      return cachePath;
    }

  return nil;
}

- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier
{
  NSMutableString *name = [NSMutableString string];
  NSUInteger i;

  if (![identifier length])
    {
      identifier = @"x11-window";
    }

  for (i = 0; i < [identifier length] && [name length] < 80; i++)
    {
      unichar c = [identifier characterAtIndex:i];

      if ((c >= 'a' && c <= 'z') ||
	  (c >= 'A' && c <= 'Z') ||
	  (c >= '0' && c <= '9') ||
	  c == '.' || c == '_' || c == '-')
	{
	  [name appendFormat:@"%C", c];
	}
      else
	{
	  [name appendString:@"_"];
	}
    }

  if (![name length])
    {
      [name appendString:@"x11-window"];
    }

  return [NSString stringWithFormat:@"%@-%lx.tiff",
		   name,
		   (unsigned long)[identifier hash]];
}

- (NSString *) storeX11Icon: (NSImage *)icon
		 identifier: (NSString *)identifier
{
  NSString *directory;
  NSString *fileName;
  NSString *path;
  NSData *data;

  if (!icon)
    {
      return nil;
    }

  data = [icon TIFFRepresentation];
  if (![data length])
    {
      return nil;
    }

  directory = [self x11IconCacheDirectory];
  if (![directory length])
    {
      return nil;
    }

  fileName = [self x11IconCacheFileNameForIdentifier:identifier];
  path = [directory stringByAppendingPathComponent:fileName];
  if ([data writeToFile:path atomically:YES])
    {
      return path;
    }

  return nil;
}

- (NSString *) x11IconIdentifierForTitle: (NSString *)title
				    path: (NSString *)path
				  window: (unsigned long)xWindow
{
  if ([path length])
    {
      return path;
    }
  if ([title length])
    {
      return title;
    }
  return [NSString stringWithFormat:@"0x%lx", xWindow];
}

- (void) applyX11Icon: (NSImage *)icon
	       toItem: (DockItem *)item
	   identifier: (NSString *)identifier
{
  NSString *iconPath;
  NSString *bundlePath;

  if (![self shouldApplyX11Icon:icon toItem:item])
    {
      return;
    }

  iconPath = [self storeX11Icon:icon identifier:identifier];
  [item setIcon:icon];
  if ([iconPath length])
    {
      [item setIconPath:iconPath];
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  if ([item kind] == DockItemApplication && ![bundlePath length])
    {
      [item setOriginalIcon:icon];
    }
}

- (void) rememberApplicationIcon: (NSImage *)icon
		       badgeLabel: (NSString *)badgeLabel
	processIdentifier: (NSNumber *)processIdentifier
{
  NSMutableDictionary *update;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return;
    }

  update = [NSMutableDictionary dictionary];
  if (icon)
    {
      NSString *iconPath = [self storeX11Icon:icon
				   identifier:[NSString stringWithFormat:@"pid-%@",
							    processIdentifier]];
      [update setObject:icon forKey:@"icon"];
      if ([iconPath length])
	{
	  [update setObject:iconPath forKey:@"iconPath"];
	}
    }
  [update setObject:([badgeLabel length] ? badgeLabel : (id)[NSNull null])
	     forKey:@"badgeLabel"];
  [_applicationIconUpdatesByProcessID setObject:update
					 forKey:processIdentifier];
}

- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update
			     toItem: (DockItem *)item
{
  id icon = [update objectForKey:@"icon"];
  id iconPath = [update objectForKey:@"iconPath"];
  id badgeObject = [update objectForKey:@"badgeLabel"];
  NSString *badgeLabel = badgeObject == [NSNull null] ? nil : badgeObject;
  BOOL changed = NO;

  if ([icon isKindOfClass:[NSImage class]] &&
      ![self item:item iconMatchesImage:icon])
    {
      [item setIcon:icon];
      changed = YES;
    }
  if ([iconPath isKindOfClass:[NSString class]] && [iconPath length] &&
      !([[item iconPath] isEqualToString:iconPath]))
    {
      [item setIconPath:iconPath];
      changed = YES;
    }

  if (([badgeLabel length] || [[item badgeLabel] length]) &&
      !(([item badgeLabel] == badgeLabel) ||
	([item badgeLabel] && badgeLabel &&
	 [[item badgeLabel] isEqualToString:badgeLabel])))
    {
      [item setBadgeLabel:badgeLabel];
      changed = YES;
    }

  return changed;
}

- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item
{
  NSArray *processIdentifiers = [self runningProcessIdentifiersForApplicationItem:item];
  BOOL changed = NO;
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSDictionary *update = [_applicationIconUpdatesByProcessID
			       objectForKey:[processIdentifiers objectAtIndex:i]];

      if (update)
	{
	  changed = [self applyApplicationIconUpdate:update toItem:item] || changed;
	}
    }

  return changed;
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
  NSString *bundlePath;

  if (!icon || !item)
    {
      return NO;
    }
  if ([item kind] != DockItemApplication)
    {
      return YES;
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  return ![bundlePath length];
}

- (void) pruneApplicationIconUpdatesForExitedProcesses
{
  NSArray *processIdentifiers = [_applicationIconUpdatesByProcessID allKeys];
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSNumber *processIdentifier = [processIdentifiers objectAtIndex:i];
      NSString *processPath = [self procPathForProcessIdentifierString:
				      [processIdentifier stringValue]];

      if (![processPath length] ||
	  ![[NSFileManager defaultManager] fileExistsAtPath:processPath])
	{
	  [_applicationIconUpdatesByProcessID removeObjectForKey:processIdentifier];
	}
    }
}

- (void) x11DockManagerDidUpdateApplicationIcon: (NSImage *)icon
                              processIdentifier: (int)processIdentifier
                                          title: (NSString *)title
{
  DockItem *item = nil;

  if (processIdentifier > 0)
    {
      item = [self applicationItemMatchingProcessIdentifier:
				    [NSNumber numberWithInt:processIdentifier]];
    }
  if (!item && [title length])
    {
      item = [self applicationItemMatchingTitle:title];
    }

  if (item && [self shouldApplyX11Icon:icon toItem:item])
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

  if (processIdentifier > 0)
    {
      processIdentifierNumber = [NSNumber numberWithInt:processIdentifier];
      [self rememberApplicationIcon:icon
			  badgeLabel:badgeLabel
		   processIdentifier:processIdentifierNumber];
      item = [self applicationItemMatchingProcessIdentifier:processIdentifierNumber];
    }

  if (item)
    {
      if ([self applyApplicationIconUpdate:
		  [_applicationIconUpdatesByProcessID
		    objectForKey:processIdentifierNumber]
				       toItem:item])
	{
	  [_dockView setNeedsDisplay:YES];
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
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
		     objectForKey:DockOpenAtLoginApplicationsDefaultsKey];

  return [paths isKindOfClass:[NSArray class]] ? paths : [NSArray array];
}

- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSString *normalizedPath = [self normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length])
    {
      return NO;
    }

  for (i = 0; i < [paths count]; i++)
    {
      if ([normalizedPath isEqualToString:
		     [self normalizedPath:[paths objectAtIndex:i]]])
	{
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

  if (![normalizedPath length])
    {
      return;
    }

  for (i = 0; i < [savedPaths count]; i++)
    {
      NSString *savedPath = [savedPaths objectAtIndex:i];

      if ([[self normalizedPath:savedPath] isEqualToString:normalizedPath])
	{
	  found = YES;
	  if (openAtLogin)
	    {
	      [paths addObject:savedPath];
	    }
	}
      else
	{
	  [paths addObject:savedPath];
	}
    }

  if (openAtLogin && !found)
    {
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
  if ([extension isEqualToString:@"desktop"])
    {
      return [self launchDesktopFile:path];
    }
  else if ([extension isEqualToString:@"app"])
    {
      NSString *executablePath = [self executablePathForApplicationPath:path];

      if ([[NSFileManager defaultManager] isExecutableFileAtPath:executablePath])
	{
	  [NSTask launchedTaskWithLaunchPath:executablePath
				   arguments:[NSArray array]];
	  return YES;
	}
      if ([[NSWorkspace sharedWorkspace] launchApplication:path])
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
      [NSTask launchedTaskWithLaunchPath:path arguments:[NSArray array]];
      return YES;
    }

  return [[NSWorkspace sharedWorkspace] openFile:path];
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

      if (![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
	  continue;
	}

      item = [DockItem applicationItemWithPath:path];
      if ([self applicationItemHasRunningProcess:item paths:processPaths])
	{
	  continue;
	}

      [self rememberLaunchedApplicationPath:path];
      [self launchApplicationAtPath:path];
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
  return NSSearchPathForDirectoriesInDomains(NSTrashDirectory,
					     NSAllDomainsMask,
					     YES);
}

- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path
{
  DIR *directory;
  struct dirent *entry;

  if (![path length])
    {
      return NO;
    }

  directory = opendir([path fileSystemRepresentation]);
  if (!directory)
    {
      return NO;
    }

  while ((entry = readdir(directory)) != NULL)
    {
      if (strcmp(entry->d_name, ".") == 0 ||
	  strcmp(entry->d_name, "..") == 0 ||
	  strcmp(entry->d_name, ".gwdir") == 0)
	{
	  continue;
	}

      closedir(directory);
      return YES;
    }

  closedir(directory);
  return NO;
}

- (BOOL) recyclerHasContents
{
  NSArray *paths = [self recyclerPaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      if ([self directoryHasVisibleContentsAtPath:[paths objectAtIndex:i]])
	{
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

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      BOOL isDir = NO;

      if ([fileManager fileExistsAtPath:path isDirectory:&isDir] && isDir)
	{
	  return path;
	}
    }

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      if ([fileManager createDirectoryAtPath:path
		 withIntermediateDirectories:YES
				  attributes:nil
				       error:NULL])
	{
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

  if (![name length])
    {
      return nil;
    }

  candidate = [recyclerPath stringByAppendingPathComponent:name];
  if (![fileManager fileExistsAtPath:candidate])
    {
      return candidate;
    }

  extension = [name pathExtension];
  base = [extension length] ? [name stringByDeletingPathExtension] : name;

  while (1)
    {
      NSString *numberedName = [NSString stringWithFormat:@"%@ %lu",
					 base, (unsigned long)i];
      if ([extension length])
	{
	  numberedName = [numberedName stringByAppendingPathExtension:extension];
	}

      candidate = [recyclerPath stringByAppendingPathComponent:numberedName];
      if (![fileManager fileExistsAtPath:candidate])
	{
	  return candidate;
	}
      i++;
    }
}

- (BOOL) movePathToRecyclerFallback: (NSString *)path
                       recyclerPath: (NSString *)recyclerPath
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *destination = [self recyclerDestinationPathForPath:path
						  recyclerPath:recyclerPath];

  if (![destination length])
    {
      return NO;
    }

  if ([fileManager movePath:path toPath:destination handler:nil])
    {
      return YES;
    }

  if ([fileManager copyPath:path toPath:destination handler:nil])
    {
      if ([fileManager removeFileAtPath:path handler:nil])
	{
	  return YES;
	}
      [fileManager removeFileAtPath:destination handler:nil];
    }

  return NO;
}

- (void) dockViewDidReceivePathsInRecycler: (NSArray *)paths
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSMutableDictionary *filesBySource = [NSMutableDictionary dictionary];
  NSMutableArray *fallbackPaths = [NSMutableArray array];
  BOOL recycled = NO;
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      NSString *normalizedPath = [self normalizedPath:path];
      NSString *source;
      NSString *filename;
      NSMutableArray *files;

      if (![normalizedPath length] ||
	  ![fileManager fileExistsAtPath:normalizedPath])
	{
	  continue;
	}

      if (![fallbackPaths containsObject:normalizedPath])
	{
	  [fallbackPaths addObject:normalizedPath];
	}

      source = [normalizedPath stringByDeletingLastPathComponent];
      filename = [normalizedPath lastPathComponent];
      if (![source length] || ![filename length])
	{
	  continue;
	}

      files = [filesBySource objectForKey:source];
      if (!files)
	{
	  files = [NSMutableArray array];
	  [filesBySource setObject:files forKey:source];
	}
      if (![files containsObject:filename])
	{
	  [files addObject:filename];
	}
    }

  {
    NSEnumerator *enumerator = [filesBySource keyEnumerator];
    NSString *source;

    while ((source = [enumerator nextObject]))
      {
	NSInteger tag = 0;
	NSArray *files = [filesBySource objectForKey:source];

	if ([[NSWorkspace sharedWorkspace]
	      performFileOperation:NSWorkspaceRecycleOperation
			    source:source
		       destination:@""
			     files:files
			       tag:&tag])
	  {
	    recycled = YES;
	  }
      }
  }

  if ([fallbackPaths count])
    {
      NSString *recyclerPath = [self recyclerPathForDropping];

      if ([recyclerPath length])
	{
	  for (i = 0; i < [fallbackPaths count]; i++)
	    {
	      NSString *path = [fallbackPaths objectAtIndex:i];
	      NSString *normalizedRecyclerPath = [self normalizedPath:recyclerPath];

	      if ([self path:path
		isEqualToOrDescendantOfPath:normalizedRecyclerPath])
		{
		  continue;
		}

	      if ([self movePathToRecyclerFallback:path recyclerPath:recyclerPath])
		{
		  recycled = YES;
		}
	    }
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
  [self updateSettingsPanelControls];
}

- (void) emptyRecyclerPath: (NSString *)path
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSArray *entries = [fileManager directoryContentsAtPath:path];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *entryPath;

      if ([entry isEqualToString:@"."] ||
	  [entry isEqualToString:@".."] ||
	  [entry isEqualToString:@".gwdir"])
	{
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
  CGFloat length = pad * 2.0 + cellCount * DockCell + (cellCount - 1) * gap;
  CGFloat thickness = [self activeDockWindowWidth];
  CGFloat width = DockPlacementIsHorizontal(placement) ? length : thickness;
  CGFloat height = DockPlacementIsHorizontal(placement) ? thickness : length;
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
  [self updateSettingsPanelControls];
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

- (NSTextField *) settingsLabelWithTitle: (NSString *)title
                                   frame: (NSRect)frame
{
  NSTextField *label = AUTORELEASE([[NSTextField alloc] initWithFrame:frame]);

  [label setStringValue:title];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
  return label;
}

- (NSButton *) settingsButtonWithTitle: (NSString *)title
                                 frame: (NSRect)frame
                            buttonType: (NSButtonType)buttonType
                                action: (SEL)action
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];

  [button setTitle:title];
  [button setButtonType:buttonType];
  [button setTarget:self];
  [button setAction:action];
  return button;
}

- (NSSlider *) settingsColorSliderWithFrame: (NSRect)frame
{
  NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];

  [slider setMinValue:0.0];
  [slider setMaxValue:255.0];
  [slider setContinuous:YES];
  [slider setTarget:self];
  [slider setAction:@selector(settingsColorSliderChanged:)];
  return slider;
}

- (void) createSettingsPanel
{
  NSView *contentView;
  NSTextField *label;
  NSButton *closeButton;
  NSArray *placements;
  NSUInteger i;

  if (_settingsPanel)
    {
      return;
    }

  _settingsPanel = [[NSPanel alloc]
		     initWithContentRect:NSMakeRect(0, 0, 320, 386)
			       styleMask:NSTitledWindowMask | NSClosableWindowMask
				 backing:NSBackingStoreBuffered
				   defer:NO];
  [_settingsPanel setTitle:@"Dock Settings"];
  [_settingsPanel setReleasedWhenClosed:NO];
  [_settingsPanel setDelegate:self];

  contentView = [_settingsPanel contentView];

  label = [self settingsLabelWithTitle:@"Placement"
                                 frame:NSMakeRect(18, 342, 110, 20)];
  [contentView addSubview:label];

  _settingsPlacementPopup =
    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(132, 338, 170, 26)
                               pullsDown:NO];
  placements = [NSArray arrayWithObjects:
			  @"Left Top",
			@"Left Center",
			@"Right Top",
			@"Right Center",
			@"Top Center",
			@"Bottom Center",
			nil];
  for (i = 0; i < [placements count]; i++)
    {
      [_settingsPlacementPopup addItemWithTitle:[placements objectAtIndex:i]];
      [[_settingsPlacementPopup itemAtIndex:i] setTag:(NSInteger)i];
    }
  [_settingsPlacementPopup setTarget:self];
  [_settingsPlacementPopup setAction:@selector(settingsPlacementChanged:)];
  [contentView addSubview:_settingsPlacementPopup];

  label = [self settingsLabelWithTitle:@"Color"
                                 frame:NSMakeRect(18, 298, 110, 20)];
  [contentView addSubview:label];

  _settingsBackgroundColorWell =
    [[NSColorWell alloc] initWithFrame:NSMakeRect(132, 292, 58, 32)];
  [_settingsBackgroundColorWell setEnabled:NO];
  [contentView addSubview:_settingsBackgroundColorWell];

  label = [self settingsLabelWithTitle:@"Red"
                                 frame:NSMakeRect(18, 260, 70, 20)];
  [contentView addSubview:label];
  _settingsRedSlider =
    [self settingsColorSliderWithFrame:NSMakeRect(92, 256, 210, 24)];
  [contentView addSubview:_settingsRedSlider];

  label = [self settingsLabelWithTitle:@"Green"
                                 frame:NSMakeRect(18, 230, 70, 20)];
  [contentView addSubview:label];
  _settingsGreenSlider =
    [self settingsColorSliderWithFrame:NSMakeRect(92, 226, 210, 24)];
  [contentView addSubview:_settingsGreenSlider];

  label = [self settingsLabelWithTitle:@"Blue"
                                 frame:NSMakeRect(18, 200, 70, 20)];
  [contentView addSubview:label];
  _settingsBlueSlider =
    [self settingsColorSliderWithFrame:NSMakeRect(92, 196, 210, 24)];
  [contentView addSubview:_settingsBlueSlider];

  label = [self settingsLabelWithTitle:@"Icon Cells"
                                 frame:NSMakeRect(18, 152, 110, 20)];
  [contentView addSubview:label];

  _settingsCurrentCellSizeButton =
    [self settingsButtonWithTitle:@"Current Size"
                            frame:NSMakeRect(132, 150, 160, 24)
                       buttonType:NSRadioButton
                           action:@selector(settingsDockCellSizeChanged:)];
  [_settingsCurrentCellSizeButton setTag:DockCellSizeModeCurrent];
  [contentView addSubview:_settingsCurrentCellSizeButton];

  _settings64CellSizeButton =
    [self settingsButtonWithTitle:@"64 x 64"
                            frame:NSMakeRect(132, 126, 160, 24)
                       buttonType:NSRadioButton
                           action:@selector(settingsDockCellSizeChanged:)];
  [_settings64CellSizeButton setTag:DockCellSizeMode64];
  [contentView addSubview:_settings64CellSizeButton];

  _settingsUseCellTileButton =
    [self settingsButtonWithTitle:@"Use common_Tile"
                            frame:NSMakeRect(18, 88, 170, 24)
                       buttonType:NSSwitchButton
                           action:@selector(settingsUseCellTileChanged:)];
  [contentView addSubview:_settingsUseCellTileButton];

  _settingsShowBorderButton =
    [self settingsButtonWithTitle:@"Show Border"
                            frame:NSMakeRect(18, 62, 140, 24)
                       buttonType:NSSwitchButton
                           action:@selector(settingsShowBorderChanged:)];
  [contentView addSubview:_settingsShowBorderButton];

  _settingsEmptyRecyclerButton =
    [self settingsButtonWithTitle:@"Empty Recycler"
                            frame:NSMakeRect(18, 24, 120, 28)
                       buttonType:NSMomentaryPushInButton
                           action:@selector(emptyRecycler:)];
  [_settingsEmptyRecyclerButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_settingsEmptyRecyclerButton];

  closeButton = [self settingsButtonWithTitle:@"Close"
                                        frame:NSMakeRect(214, 24, 88, 28)
                                   buttonType:NSMomentaryPushInButton
                                       action:@selector(closeSettingsPanel:)];
  [closeButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:closeButton];
  DESTROY(closeButton);

  [self updateSettingsPanelControls];
}

- (void) updateSettingsPanelControls
{
  NSColor *color;
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  if (!_settingsPanel)
    {
      return;
    }

  [_settingsPlacementPopup selectItemWithTag:(NSInteger)_dockPlacement];
  [_settingsCurrentCellSizeButton setState:
      (_dockCellSizeMode == DockCellSizeModeCurrent ? NSOnState : NSOffState)];
  [_settings64CellSizeButton setState:
      (_dockCellSizeMode == DockCellSizeMode64 ? NSOnState : NSOffState)];
  [_settingsUseCellTileButton setState:
      (_useCellTileBackground ? NSOnState : NSOffState)];
  if (![_settingsPanel isVisible])
    {
      color = DockCalibratedBackgroundColor(_backgroundColor);
      [color getRed:&red green:&green blue:&blue alpha:&alpha];
      [_settingsBackgroundColorWell setColor:color];
      [_settingsRedSlider setDoubleValue:red * 255.0];
      [_settingsGreenSlider setDoubleValue:green * 255.0];
      [_settingsBlueSlider setDoubleValue:blue * 255.0];
    }
  [_settingsShowBorderButton setState:(_showDockBorder ? NSOnState : NSOffState)];
  [_settingsEmptyRecyclerButton setEnabled:[self recyclerHasContents]];
}

- (void) showSettingsPanel: (id)sender
{
  [self createSettingsPanel];
  [self updateSettingsPanelControls];
  [_settingsPanel center];
  [_settingsPanel makeKeyAndOrderFront:sender];
}

- (void) closeSettingsPanel: (id)sender
{
  [self settingsColorSliderChanged:sender];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [_settingsPanel orderOut:sender];
}

- (BOOL) windowShouldClose: (id)sender
{
  if (sender == _settingsPanel)
    {
      [self closeSettingsPanel:sender];
      return NO;
    }

  return YES;
}

- (void) windowWillClose: (NSNotification *)notification
{
}

- (void) settingsPlacementChanged: (id)sender
{
  _dockPlacement = (DockPlacement)[sender selectedTag];
  [self applyDockPlacement];
}

- (void) settingsColorSliderChanged: (id)sender
{
  if (!_settingsRedSlider || !_settingsGreenSlider || !_settingsBlueSlider)
    {
      return;
    }

  ASSIGN(_backgroundColor,
         [NSColor colorWithCalibratedRed:[_settingsRedSlider doubleValue] / 255.0
                                   green:[_settingsGreenSlider doubleValue] / 255.0
                                    blue:[_settingsBlueSlider doubleValue] / 255.0
                                   alpha:1.0]);
  [_dockView setBackgroundColor:_backgroundColor];
  [_settingsBackgroundColorWell setColor:_backgroundColor];
  [self saveBackgroundColor];
}

- (void) settingsShowBorderChanged: (id)sender
{
  NSButton *button = (NSButton *)sender;

  _showDockBorder = [button state] == NSOnState;
  [_dockView setShowsBorder:_showDockBorder];
  [self saveShowDockBorder];
}

- (void) settingsUseCellTileChanged: (id)sender
{
  NSButton *button = (NSButton *)sender;

  _useCellTileBackground = [button state] == NSOnState;
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [self saveUseCellTileBackground];
}

- (void) settingsDockCellSizeChanged: (id)sender
{
  NSInteger mode = [sender tag];

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

  [self updateSettingsPanelControls];
}

- (void) applyDockPlacement
{
  [[NSUserDefaults standardUserDefaults] setInteger:_dockPlacement forKey:@"DockPlacement"];
  [self applyDockCellSizeToView];
  [_dockView setHorizontal:DockPlacementIsHorizontal(_dockPlacement)];
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
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [_dockView setShowsBorder:_showDockBorder];
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
  return [_applicationIconWindowItems objectForKey:
				       [NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item
{
  if (!item || !xWindow)
    {
      return;
    }

  [_applicationIconWindowItems setObject:item
				  forKey:[NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) removeApplicationIconWindowsForItem: (DockItem *)item
{
  NSArray *keys = [_applicationIconWindowItems allKeysForObject:item];
  NSUInteger i;

  for (i = 0; i < [keys count]; i++)
    {
      [_applicationIconWindowItems removeObjectForKey:[keys objectAtIndex:i]];
    }
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
  if (index >= [_items count])
    {
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
	      [self refreshDock];
	      return;
	    }

	  [_x11 drainTransientIconEvents];
	  if ([_x11 activateApplicationWithProcessIdentifiers:processIds])
	    {
	      [_x11 drainTransientIconEvents];
	      [item setState:DockItemRunning];
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
	  return;
	}

      [self rememberLaunchedApplicationPath:path];
      launched = [self launchApplicationAtPath:path];
      [_x11 drainTransientIconEvents];

      if (launched)
	{
	  [item setState:DockItemRunning];
	  [_dockView startWiggleForItem:item];
	  [self refreshDock];
	}
    }
  else
    {
      [_x11 drainTransientIconEvents];
      [_x11 activateWindow:[item xWindow]];
      [_x11 drainTransientIconEvents];
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

- (BOOL) launchDesktopFile: (NSString *)path
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

	      if ([shellPath length])
		{
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
  DockItem *item = [self applicationItemMatchingExecutablePath:path];
  BOOL matchedApplication;
  NSString *iconIdentifier = [self x11IconIdentifierForTitle:title
							path:path
						      window:xWindow];

  if (!item)
    {
      item = [self applicationItemMatchingTitle:title];
    }
  matchedApplication = item && [item kind] == DockItemApplication;

  if (dockApp &&
      ([self applicationBundlePathIsDockWM:path] ||
       [self windowPathMatchesLaunchedApplication:path]))
    {
      if (item)
	{
	  [self setApplicationIconWindow:xWindow forItem:item];
	  [item setState:DockItemRunning];
	  if ([self shouldApplyX11Icon:icon toItem:item])
	    {
	      [self applyX11Icon:icon toItem:item identifier:iconIdentifier];
	    }
	  [self applyStoredApplicationIconUpdateForItem:item];
	  [self refreshDock];
	}
      return;
    }

  if (item)
    {
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
      if ([path length] && ![self applicationBundlePathIsDockWM:path])
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
