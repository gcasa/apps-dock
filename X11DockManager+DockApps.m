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

#import "X11DockManagerPrivate.h"

@implementation X11DockManager (DockApps)

- (id) iconIdentifierForProcessIdentifier: (int)processIdentifier
                                    title: (NSString *)title
{
  if (processIdentifier > 0)
    {
      return [NSNumber numberWithInt:processIdentifier];
    }
  if ([title length])
    {
      return [title lowercaseString];
    }
  return nil;
}


- (BOOL) windowIsDockAppIconChild: (Window)window
{
  Display *display = (Display *)_display;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  BOOL result = NO;

  if (!display || window == (Window)_hostWindow ||
      ![self windowIsSmallIconSized:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (XQueryTree(display, window, &root, &parent, &children, &childCount) &&
      ![self x11ErrorOccurred])
    {
      result = parent != None && parent != root &&
	[self windowHasDockAppClass:parent];
    }
  if (children)
    {
      XFree(children);
    }

  return result;
}


- (BOOL) windowLooksLikeWindowMakerDockApp: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  Window dockWindow;
  NSString *title;

  dockWindow = [self dockAppIconWindowForWindow:window];
  if (dockWindow == None)
    {
      return NO;
    }
  if (![self windowHasDockAppClass:window] &&
      ![self windowIsDockAppIconChild:window] &&
      ![self windowIsSmallRootOverrideRedirectWindow:window] &&
      ![self windowIsSmallDockedOverrideRedirectWindow:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, dockWindow, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  if (attr.map_state != IsViewable &&
      ![self windowHasDockAppClass:window] &&
      ![self windowIsDockAppIconChild:window])
    {
      return NO;
    }
  if ([self windowHasTransientForHint:window])
    {
      return NO;
    }
  if ([self windowHasIgnoredWindowType:window])
    {
      return NO;
    }

  title = [self titleForWindow:window];
  if ([title length] || [self processIdentifierForWindow:window] > 0)
    {
      return YES;
    }

  return NO;
}


- (void) unmapIconWindow: (Window)window
{
  Display *display = (Display *)_display;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  Window moveWindow;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  root = RootWindow(display, DefaultScreen(display));
  moveWindow = window;

  [self clearX11Error];
  if (XQueryTree(display, window, &root, &parent, &children, &childCount) &&
      ![self x11ErrorOccurred])
    {
      while (parent != None &&
	     parent != root &&
	     parent != (Window)_hostWindow)
	{
	  Window grandparent;
	  Window *siblings = NULL;
	  unsigned int siblingCount = 0;

	  moveWindow = parent;
	  if (!XQueryTree(display, moveWindow, &root, &grandparent,
			  &siblings, &siblingCount) ||
	      [self x11ErrorOccurred])
	    {
	      if (siblings)
		{
		  XFree(siblings);
		}
	      break;
	    }
	  if (siblings)
	    {
	      XFree(siblings);
	    }
	  parent = grandparent;
	}
    }
  if (children)
    {
      XFree(children);
    }

  if (moveWindow == (Window)_hostWindow)
    {
      return;
    }

  XUnmapWindow(display, moveWindow);
  XFlush(display);
}


- (void) hideApplicationIconWindow: (Window)window
{
  Display *display = (Display *)_display;
  NSRect frame;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  frame = [self hiddenIconWindowFrame];
  XMoveResizeWindow(display,
		    window,
		    (int)NSMinX(frame),
		    (int)NSMinY(frame),
		    (unsigned int)NSWidth(frame),
		    (unsigned int)NSHeight(frame));
  XMapWindow(display, window);
  XFlush(display);
}


- (BOOL) windowIsKnownDockAppWindow: (Window)window
{
  return [_dockAppWindows containsObject:
			    [NSNumber numberWithUnsignedLong:(unsigned long)window]];
}


- (BOOL) windowHasDockAppClass: (Window)window
{
  Display *display = (Display *)_display;
  XClassHint hint;
  BOOL dockApp = NO;

  [self clearX11Error];
  if (XGetClassHint(display, window, &hint) && ![self x11ErrorOccurred])
    {
      if ((hint.res_class && strcasecmp(hint.res_class, "DockApp") == 0) ||
	  (hint.res_name && strcasecmp(hint.res_name, "DockApp") == 0))
	{
	  dockApp = YES;
	}
      if (hint.res_name)
	{
	  XFree(hint.res_name);
	}
      if (hint.res_class)
	{
	  XFree(hint.res_class);
	}
    }

  return dockApp;
}


- (Window) dockAppIconWindowForWindow: (Window)window
{
  Display *display = (Display *)_display;
  XWMHints *hints;
  Window iconWindow = None;

  if (!display || window == (Window)_hostWindow)
    {
      return None;
    }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints)
    {
      if ((hints->flags & IconWindowHint) && hints->icon_window != None &&
	  [self windowIsSmallIconSized:hints->icon_window])
	{
	  iconWindow = hints->icon_window;
	}
      XFree(hints);
    }
  else if (hints)
    {
      XFree(hints);
    }

  if (iconWindow != None)
    {
      return iconWindow;
    }

  if ([self windowIsSmallIconSized:window])
    {
      return window;
    }

  return None;
}


- (BOOL) rememberApplicationIconWindow: (Window)window
                     processIdentifier: (int)processIdentifier
                                 title: (NSString *)title
{
  id identifier;
  NSNumber *windowKey;
  XWindowAttributes attr;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  identifier = [self iconIdentifierForProcessIdentifier:processIdentifier
                                                  title:title];
  if (!identifier)
    {
      return NO;
    }
  if (![self windowHasGNUstepIconStyle:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  windowKey = [NSNumber numberWithUnsignedLong:(unsigned long)window];
  if (!attr.override_redirect &&
      [[self clientListWindows] containsObject:windowKey])
    {
      return NO;
    }

  if (attr.width <= 0 || attr.height <= 0 ||
      attr.width > 128 || attr.height > 128)
    {
      return NO;
    }

  if ([_iconWindowsByProcessID objectForKey:identifier] &&
      ![[_iconWindowsByProcessID objectForKey:identifier] isEqual:windowKey])
    {
      return NO;
    }
  [_iconWindowsByProcessID setObject:windowKey forKey:identifier];
  [_knownWindows removeObject:windowKey];

  [self hideApplicationIconWindow:window];

  return YES;
}


- (void) discoverApplicationIconWindows: (Window *)children
                                  count: (unsigned int)count
{
  unsigned int i;

  for (i = 0; i < count; i++)
    {
      int pid;
      NSString *title;

      if ([self windowIsRegisteredIconWindow:children[i]])
	{
	  continue;
	}
      if (![self windowIsSmallIconSized:children[i]])
	{
	  continue;
	}
      if (![self windowHasGNUstepIconStyle:children[i]])
	{
	  continue;
	}

      pid = [self processIdentifierForWindow:children[i]];
      title = [self classNameForWindow:children[i]];

      [self rememberApplicationIconWindow:children[i]
			processIdentifier:pid
				    title:title];
    }

  for (i = 0; i < count; i++)
    {
      XWMHints *hints;

      [self clearX11Error];
      hints = XGetWMHints((Display *)_display, children[i]);
      if ([self x11ErrorOccurred])
	{
	  if (hints)
	    {
	      XFree(hints);
	    }
	  continue;
	}
      if (hints)
	{
	  if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	    {
	      int pid = [self processIdentifierForWindow:children[i]];
	      NSString *title = [self classNameForWindow:children[i]];

	      [self rememberApplicationIconWindow:hints->icon_window
				processIdentifier:pid
					    title:title];
	    }
	  XFree(hints);
	}
    }
}


- (void) scanApplicationIconWindows
{
  NSArray *iconKeys = [_iconWindowsByProcessID allKeys];
  NSUInteger i;

  for (i = 0; i < [iconKeys count]; i++)
    {
      id iconKey = [iconKeys objectAtIndex:i];
      NSNumber *windowKey = [_iconWindowsByProcessID objectForKey:iconKey];
      Window window = (Window)[windowKey unsignedLongValue];
      XWindowAttributes attr;
      [self clearX11Error];
      if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
	  [self x11ErrorOccurred])
	{
	  [_iconWindowsByProcessID removeObjectForKey:iconKey];
	  [_iconImageDataByProcessID removeObjectForKey:iconKey];
	  continue;
	}
    }
}


- (void) scanClientWindow: (Window)window
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)window];
  Window reportedWindow = window;
  BOOL dockApp;
  BOOL hidden;
  NSString *title;
  NSString *path;

  if ([_knownWindows containsObject:key])
    {
      return;
    }
  if (![self windowLooksManageable:window])
    {
      return;
    }
  if ([self windowHasIgnoredWindowType:window])
    {
      return;
    }

  dockApp = [self windowLooksLikeDockApp:window];
  if (dockApp)
    {
      Window iconWindow = [self dockAppIconWindowForWindow:window];

      if (iconWindow != None)
	{
	  reportedWindow = iconWindow;
	  [_dockAppWindows addObject:
			     [NSNumber numberWithUnsignedLong:
					       (unsigned long)reportedWindow]];
	}
  }
  hidden = [self windowIsHidden:window];
  title = [self titleForWindow:window];
  path = [self executablePathForWindow:window];

  if (!dockApp && ![title length] && ![path length])
    {
      return;
    }

  if ([self windowShouldBeIgnoredWithTitle:title path:path])
    {
      if (dockApp)
	{
	  [_knownWindows addObject:key];
	  if ([_delegate respondsToSelector:
			   @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)])
	    {
	      [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
							   window:(unsigned long)reportedWindow
							   hidden:YES
							     icon:[self iconForWindow:reportedWindow]
							     path:path
							  dockApp:dockApp];
	    }
	}
      return;
    }

  [_knownWindows addObject:key];
  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)])
    {
      [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
						   window:(unsigned long)reportedWindow
						   hidden:hidden
						     icon:[self iconForWindow:reportedWindow]
						     path:path
						  dockApp:dockApp];
    }
}


- (void) scanForDockApps
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  NSArray *clientWindows;

  if (!display) return;
  _scanPending = NO;
  _lastEventScanTime = [NSDate timeIntervalSinceReferenceDate];
  [self scanApplicationIconWindows];
  [self scanKnownWindows];

  clientWindows = [self clientListWindows];
  for (i = 0; i < [clientWindows count]; i++)
    {
      [self scanClientWindow:
	      (Window)[[clientWindows objectAtIndex:i] unsignedLongValue]];
    }

  root = RootWindow(display, DefaultScreen(display));
  if (!XQueryTree(display, root, &root, &parent, &children, &count))
    {
      return;
    }

  [self discoverApplicationIconWindows:children count:count];
  [self scanApplicationIconWindows];

  for (i = 0; i < count; i++)
    {
      [self scanClientWindow:children[i]];
    }

  if (children) XFree(children);
}


@end
