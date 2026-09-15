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

@implementation AppController (Icons)

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

@end
