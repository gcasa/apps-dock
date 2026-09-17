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

@implementation X11DockManager (WindowFiltering)

- (BOOL) windowIsRegisteredIconWindow: (Window)window
{
  return [[_iconWindowsByProcessID allValues]
	   containsObject:[NSNumber numberWithUnsignedLong:(unsigned long)window]];
}


- (BOOL) windowHasGNUstepStyleMask: (unsigned long)styleMask
                             window: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_GNUSTEP_WM_ATTR", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL result = NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0,
                         2,
                         False, property, &actualType, &actualFormat,
                         &itemCount, &bytesAfter, &data) == Success && data)
    {
      if (![self x11ErrorOccurred] &&
	  actualFormat == 32 &&
	  itemCount >= 2)
	{
	  unsigned long *attrs = (unsigned long *)data;

	  if ((attrs[0] & DockGSWindowStyleAttr) &&
	      (attrs[1] & styleMask))
	    {
	      result = YES;
	    }
	}
      XFree(data);
    }

  return result;
}


- (BOOL) windowHasGNUstepIconStyle: (Window)window
{
  return [self windowHasGNUstepStyleMask:DockNSIconWindowMask
                                  window:window];
}


- (BOOL) windowIsIconSized: (Window)window
{
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  return attr.width > 0 && attr.height > 0 &&
    attr.width <= 128 && attr.height <= 128;
}


- (BOOL) windowIsSmallIconSized: (Window)window
{
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  return attr.width > 0 && attr.height > 0 &&
    attr.width <= DockSmallIconWindowMaximumSize &&
    attr.height <= DockSmallIconWindowMaximumSize;
}


- (BOOL) windowHasGNUstepMiniWindowStyle: (Window)window
{
  return [self windowHasGNUstepStyleMask:DockNSMiniWindowMask
                                  window:window];
}


- (BOOL) windowIsGNUstepMainMenu: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_GNUSTEP_WM_ATTR", False);
  Atom dockType = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  Atom windowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL isMenu = NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 2, False, property,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32 && itemCount >= 2)
        {
          unsigned long *attrs = (unsigned long *)data;
          isMenu = (attrs[0] & DockGSWindowStyleAttr) && attrs[1] == 0;
        }
      XFree(data);
    }
  if (!isMenu)
    {
      return NO;
    }

  data = NULL;
  [self clearX11Error];
  if (XGetWindowProperty(display, window, windowType, 0, 8, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      unsigned long i;
      isMenu = NO;
      if (![self x11ErrorOccurred] && actualFormat == 32)
        {
          Atom *types = (Atom *)data;
          for (i = 0; i < itemCount; i++)
            {
              if (types[i] == dockType)
                {
                  isMenu = YES;
                  break;
                }
            }
        }
      XFree(data);
    }
  else
    {
      isMenu = NO;
    }

  return isMenu;
}


- (BOOL) windowIsSmallGNUstepIconOrMiniWindow: (Window)window
{
  if (![self windowIsSmallIconSized:window])
    {
      return NO;
    }

  return [self windowHasGNUstepIconStyle:window] ||
    [self windowHasGNUstepMiniWindowStyle:window];
}


- (BOOL) windowIsSmallRootOverrideRedirectWindow: (Window)window
{
  Display *display = (Display *)_display;
  int screen;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  XWindowAttributes attr;
  BOOL result = NO;

  if (!display || window == (Window)_hostWindow ||
      ![self windowIsSmallIconSized:window])
    {
      return NO;
    }

  screen = DefaultScreen(display);
  root = RootWindow(display, screen);

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  [self clearX11Error];
  if (XQueryTree(display, window, &root, &parent, &children, &childCount) &&
      ![self x11ErrorOccurred])
    {
      result = attr.override_redirect && parent == RootWindow(display, screen);
    }
  if (children)
    {
      XFree(children);
    }

  return result;
}


- (BOOL) windowIsSmallDockedOverrideRedirectWindow: (Window)window
{
  Display *display = (Display *)_display;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  XWindowAttributes attr;
  BOOL result = NO;

  if (!display || !_hostWindow || window == (Window)_hostWindow ||
      ![self windowIsSmallIconSized:window])
    {
      return NO;
    }

  root = RootWindow(display, DefaultScreen(display));

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  [self clearX11Error];
  if (XQueryTree(display, window, &root, &parent, &children, &childCount) &&
      ![self x11ErrorOccurred])
    {
      result = attr.override_redirect && parent == (Window)_hostWindow;
    }
  if (children)
    {
      XFree(children);
    }

  return result;
}


- (BOOL) windowHasTransientForHint: (Window)window
{
  Display *display = (Display *)_display;
  Window transientFor = None;

  if (!display)
    {
      return NO;
    }

  [self clearX11Error];
  if (XGetTransientForHint(display, window, &transientFor) &&
      ![self x11ErrorOccurred] &&
      transientFor != None)
    {
      return YES;
    }

  return NO;
}


- (BOOL) windowLooksLikeDockApp: (Window)window
{
  return [self windowIsRegisteredIconWindow:window] ||
    [self windowIsKnownDockAppWindow:window] ||
    [self windowLooksLikeWindowMakerDockApp:window];
}


- (BOOL) windowLooksManageable: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;
  BOOL dockApp;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  if ([self windowIsRegisteredIconWindow:window])
    {
      return NO;
    }
  if ([self windowIsSmallGNUstepIconOrMiniWindow:window])
    {
      if (![self rememberApplicationIconWindow:window
			    processIdentifier:[self processIdentifierForWindow:window]
					title:[self classNameForWindow:window]])
	{
	  [self unmapIconWindow:window];
	}
      return NO;
    }
  if (([self windowIsSmallRootOverrideRedirectWindow:window] &&
       ![self windowLooksLikeWindowMakerDockApp:window]))
    {
      [self unmapIconWindow:window];
      return NO;
    }
  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr))
    {
      return NO;
    }
  if ([self x11ErrorOccurred])
    {
      return NO;
    }
  dockApp = [self windowLooksLikeDockApp:window];
  if ([self wmStateForWindow:window state:&state] && state == WithdrawnState)
    {
      return dockApp;
    }
  if (attr.override_redirect && !dockApp)
    {
      return NO;
    }
  if (attr.map_state != IsViewable &&
      (![self wmStateForWindow:window state:&state] || state != IconicState))
    {
      return NO;
    }
  return YES;
}


- (BOOL) windowHasIgnoredWindowType: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom ignoredTypes[8];
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL ignored = NO;
  unsigned long i;
  unsigned int j;

  ignoredTypes[0] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
  ignoredTypes[1] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  ignoredTypes[2] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLBAR", False);
  ignoredTypes[3] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_MENU", False);
  ignoredTypes[4] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", False);
  ignoredTypes[5] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_SPLASH", False);
  ignoredTypes[6] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", False);
  ignoredTypes[7] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLTIP", False);

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 16, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32)
	{
	  unsigned long *types = (unsigned long *)data;

	  for (i = 0; i < itemCount && !ignored; i++)
	    {
	      for (j = 0; j < 8; j++)
		{
		  if (types[i] == ignoredTypes[j])
		    {
		      ignored = YES;
		      break;
		    }
		}
	    }
	}
      XFree(data);
    }

  return ignored;
}


- (NSArray *) clientListWindows
{
  Display *display = (Display *)_display;
  Window root;
  Atom property;
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  NSMutableArray *windows = [NSMutableArray array];
  unsigned long i;

  if (!display)
    {
      return windows;
    }

  root = RootWindow(display, DefaultScreen(display));
  property = XInternAtom(display, "_NET_CLIENT_LIST", False);

  [self clearX11Error];
  if (XGetWindowProperty(display, root, property, 0, 4096, False, XA_WINDOW,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32)
	{
	  unsigned long *clientWindows = (unsigned long *)data;

	  for (i = 0; i < itemCount; i++)
	    {
	      [windows addObject:[NSNumber numberWithUnsignedLong:clientWindows[i]]];
	    }
	}
      XFree(data);
    }

  return windows;
}


- (BOOL) knownWindowStillExists: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  if ([self windowIsRegisteredIconWindow:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr))
    {
      return NO;
    }
  if ([self x11ErrorOccurred])
    {
      return NO;
    }
  if ([self wmStateForWindow:window state:&state] && state == WithdrawnState)
    {
      return NO;
    }
  if (attr.override_redirect && ![self windowLooksLikeDockApp:window])
    {
      return NO;
    }
  if (attr.map_state != IsViewable &&
      (![self wmStateForWindow:window state:&state] || state != IconicState))
    {
      return NO;
    }

  return YES;
}


- (BOOL) windowExists: (unsigned long)xWindow
{
  BOOL exists = [self knownWindowStillExists:(Window)xWindow];

  if (!exists &&
      [_dockedWindowFrames objectForKey:
			     [NSNumber numberWithUnsignedLong:xWindow]])
    {
      [_dockedWindowFrames removeObjectForKey:
			     [NSNumber numberWithUnsignedLong:xWindow]];
      [_dockAppWindows removeObject:
			 [NSNumber numberWithUnsignedLong:xWindow]];
      [self updateHostWindowShape];
    }

  return exists;
}


- (BOOL) windowShouldBeIgnoredWithTitle: (NSString *)title path: (NSString *)path
{
  NSString *lowerTitle = [title lowercaseString];
  NSString *lowerName = [[path lastPathComponent] lowercaseString];
  NSArray *pathComponents = [[path lowercaseString] pathComponents];

  if ([lowerTitle isEqualToString:@"gworkspace"] ||
      [lowerTitle isEqualToString:@"dockwm"] ||
      [lowerName isEqualToString:@"gworkspace"] ||
      [lowerName isEqualToString:@"dockwm"] ||
      [pathComponents containsObject:@"gworkspace.app"] ||
      [pathComponents containsObject:@"dockwm.app"])
    {
      return YES;
    }

  if ([lowerTitle rangeOfString:@"drag"].location != NSNotFound &&
      [lowerName isEqualToString:@"gworkspace"])
    {
      return YES;
    }

  return NO;
}


- (void) scanKnownWindows
{
  NSArray *windows = [_knownWindows allObjects];
  NSUInteger i;

  for (i = 0; i < [windows count]; i++)
    {
      NSNumber *key = [windows objectAtIndex:i];
      Window window = (Window)[key unsignedLongValue];

      if (![self knownWindowStillExists:window])
	{
	  [_knownWindows removeObject:key];
	  continue;
	}

      if ([_delegate respondsToSelector:
		       @selector(x11DockManagerDidUpdateWindow:hidden:icon:)])
	{
	  [_delegate x11DockManagerDidUpdateWindow: (unsigned long)window
					    hidden:[self windowIsHidden:window]
					      icon:nil];
	}
    }
}


@end
