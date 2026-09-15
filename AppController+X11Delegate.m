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

@implementation AppController (X11Delegate)

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

- (void) x11DockManagerDidRequestUserAttentionForProcessIdentifier: (int)processIdentifier
						       requestType: (NSInteger)requestType
{
  DockItem *item = nil;
  NSNumber *processIdentifierNumber = nil;

  if (processIdentifier <= 0)
    {
      return;
    }

  processIdentifierNumber = [NSNumber numberWithInt:processIdentifier];
  item = [self applicationItemMatchingProcessIdentifier:processIdentifierNumber];
  if (!item)
    {
      item = [self transientApplicationItemForProcessIdentifier:
			processIdentifierNumber];
    }

  if (item)
    {
      [self startAttentionWiggleForItem:item];
    }
}

- (void) x11DockManagerDidCancelUserAttentionRequest: (NSInteger)request
				forProcessIdentifier: (int)processIdentifier
{
  DockItem *item = nil;
  NSNumber *processIdentifierNumber = nil;

  if (processIdentifier <= 0)
    {
      return;
    }

  processIdentifierNumber = [NSNumber numberWithInt:processIdentifier];
  item = [self applicationItemMatchingProcessIdentifier:processIdentifierNumber];
  if (item)
    {
      [self cancelAttentionWiggleForItem:item];
    }
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
      DockItemState newState = hidden ? DockItemHidden : DockItemRunning;
      BOOL changed = NO;

      if ([item state] != newState)
	{
	  [item setState:newState];
	  changed = YES;
	}
      if ([self shouldApplyX11Icon:icon toItem:item])
	{
	  [self applyX11Icon:icon
		      toItem:item
		  identifier:[NSString stringWithFormat:@"0x%lx", xWindow]];
	  changed = YES;
	}
      if (changed)
	{
	  [_dockView setNeedsDisplay:YES];
	}
    }
}

@end
