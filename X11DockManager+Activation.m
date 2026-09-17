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

@implementation X11DockManager (Activation)

- (void) activateWindow: (unsigned long)xWindow
{
  Display *display = (Display *)_display;
  Window root;
  Atom activeWindow;
  XEvent event;

  if (!display) return;
  if ([self windowIsRegisteredIconWindow:(Window)xWindow])
    {
      return;
    }
  if ([self windowHasGNUstepMiniWindowStyle:(Window)xWindow])
    {
      return;
    }

  [self deiconifyWindow:(Window)xWindow];

  root = RootWindow(display, DefaultScreen(display));
  activeWindow = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
  memset(&event, 0, sizeof(event));
  event.xclient.type = ClientMessage;
  event.xclient.window = (Window)xWindow;
  event.xclient.message_type = activeWindow;
  event.xclient.format = 32;
  event.xclient.data.l[0] = 2;
  event.xclient.data.l[1] = CurrentTime;
  XSendEvent(display, root, False,
             SubstructureRedirectMask | SubstructureNotifyMask, &event);

  XMapRaised(display, (Window)xWindow);
  XSetInputFocus(display, (Window)xWindow, RevertToParent, CurrentTime);
  XFlush(display);
}


- (void) deiconifyWindow: (Window)window
{
  Display *display = (Display *)_display;
  Window root;
  Atom changeState;
  XEvent event;
  long state = NormalState;

  if (!display)
    {
      return;
    }

  if (![self wmStateForWindow:window state:&state] || state != IconicState)
    {
      return;
    }

  root = RootWindow(display, DefaultScreen(display));
  changeState = XInternAtom(display, "WM_CHANGE_STATE", False);
  memset(&event, 0, sizeof(event));
  event.xclient.type = ClientMessage;
  event.xclient.display = display;
  event.xclient.window = window;
  event.xclient.message_type = changeState;
  event.xclient.format = 32;
  event.xclient.data.l[0] = NormalState;
  XSendEvent(display, root, False,
	     SubstructureRedirectMask | SubstructureNotifyMask, &event);

  XMapRaised(display, window);
}


- (NSUInteger) activateIconicWindowsForProcessIdentifiers: (NSArray *)processIdentifiers
					      underWindow: (Window)parentWindow
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  NSUInteger activated = 0;

  if (!display)
    {
      return 0;
    }

  if (!XQueryTree(display, parentWindow, &root, &parent, &children, &count))
    {
      return 0;
    }

  for (i = count; i > 0; i--)
    {
      Window window = children[i - 1];
      XWindowAttributes attr;
      long state = NormalState;
      BOOL hasState;
      int processIdentifier;

      if ([self windowIsRegisteredIconWindow:window])
	{
	  continue;
	}
      if ([self windowHasGNUstepMiniWindowStyle:window])
	{
	  continue;
	}

      [self clearX11Error];
      if (!XGetWindowAttributes(display, window, &attr) ||
	  [self x11ErrorOccurred])
	{
	  continue;
	}

      if (attr.override_redirect && attr.width <= 96 && attr.height <= 96)
	{
	  continue;
	}

      hasState = [self wmStateForWindow:window state:&state];
      processIdentifier = [self processIdentifierForWindow:window];
      if (hasState && state == IconicState &&
	  processIdentifier > 0 &&
	  [processIdentifiers containsObject:
		     [NSNumber numberWithInt:processIdentifier]])
	{
	  [self activateWindow:(unsigned long)window];
	  activated++;
	}

      activated += [self activateIconicWindowsForProcessIdentifiers:processIdentifiers
							underWindow:window];
    }

  if (children)
    {
      XFree(children);
    }

  return activated;
}


- (Window) activatableWindowForProcessIdentifiers: (NSArray *)processIdentifiers
                                      underWindow: (Window)parentWindow
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  Window match = None;

  if (!display)
    {
      return None;
    }

  if (!XQueryTree(display, parentWindow, &root, &parent, &children, &count))
    {
      return None;
    }

  for (i = count; i > 0; i--)
    {
      Window window = children[i - 1];
      XWindowAttributes attr;
      long state = NormalState;
      BOOL hasState;
      int processIdentifier;

      if ([self windowIsRegisteredIconWindow:window])
	{
	  continue;
	}
      if ([self windowHasGNUstepMiniWindowStyle:window])
	{
	  continue;
	}

      [self clearX11Error];
      if (!XGetWindowAttributes(display, window, &attr) ||
	  [self x11ErrorOccurred])
	{
	  continue;
	}

      if (attr.override_redirect && attr.width <= 96 && attr.height <= 96)
	{
	  continue;
	}

      hasState = [self wmStateForWindow:window state:&state];
      if ((hasState && state == WithdrawnState &&
	   attr.map_state != IsViewable) ||
	  (attr.map_state != IsViewable &&
	   (!hasState || state != IconicState)))
	{
	  continue;
	}

      processIdentifier = [self processIdentifierForWindow:window];
      if (processIdentifier > 0 &&
	  [processIdentifiers containsObject:
		     [NSNumber numberWithInt:processIdentifier]])
	{
	  match = window;
	  break;
	}

      match = [self activatableWindowForProcessIdentifiers:processIdentifiers
					       underWindow:window];
      if (match != None)
	{
	  break;
	}
    }

  if (children)
    {
      XFree(children);
    }
  return match;
}


- (BOOL) activateApplicationWithProcessIdentifiers: (NSArray *)processIdentifiers
{
  Display *display = (Display *)_display;
  Window root;
  Window window;
  BOOL activated = NO;

  if (!display || ![processIdentifiers count])
    {
      return NO;
    }

  root = RootWindow(display, DefaultScreen(display));
  if ([self activateIconicWindowsForProcessIdentifiers:processIdentifiers
					   underWindow:root] > 0)
    {
      activated = YES;
    }

  window = [self activatableWindowForProcessIdentifiers:processIdentifiers
                                            underWindow:root];
  if (window == None)
    {
      window = [self mainMenuWindowForProcessIdentifiers:processIdentifiers
                                            underWindow:root];
      if (window == None)
        {
          return activated;
        }
    }

  [self activateWindow:(unsigned long)window];
  return YES;
}


- (Window) mainMenuWindowForProcessIdentifiers: (NSArray *)processIdentifiers
                                  underWindow: (Window)parentWindow
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  Window match = None;

  [self clearX11Error];
  if (!XQueryTree(display, parentWindow, &root, &parent, &children, &count) ||
      [self x11ErrorOccurred])
    {
      if (children) XFree(children);
      return None;
    }

  for (i = count; i > 0 && match == None; i--)
    {
      Window child = children[i - 1];
      int pid = [self processIdentifierForWindow:child];

      if (pid > 0 &&
          [processIdentifiers containsObject:[NSNumber numberWithInt:pid]] &&
          [self windowIsGNUstepMainMenu:child])
        {
          match = child;
        }
      else
        {
          match = [self mainMenuWindowForProcessIdentifiers:processIdentifiers
                                               underWindow:child];
        }
    }
  if (children) XFree(children);
  return match;
}


- (void) closeWindow: (unsigned long)xWindow
{
  Display *display = (Display *)_display;
  Atom wmProtocols;
  Atom wmDeleteWindow;
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL supportsDelete = NO;

  if (!display) return;
  if ([self windowIsRegisteredIconWindow:(Window)xWindow])
    {
      return;
    }
  if ([self windowHasGNUstepMiniWindowStyle:(Window)xWindow])
    {
      return;
    }

  wmProtocols = XInternAtom(display, "WM_PROTOCOLS", False);
  wmDeleteWindow = XInternAtom(display, "WM_DELETE_WINDOW", False);

  if (XGetWindowProperty(display, (Window)xWindow, wmProtocols,
                         0, 32, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount,
                         &bytesAfter, &data) == Success && data)
    {
      unsigned long i;
      Atom *protocols = (Atom *)data;

      if (actualFormat == 32)
	{
	  for (i = 0; i < itemCount; i++)
	    {
	      if (protocols[i] == wmDeleteWindow)
		{
		  supportsDelete = YES;
		  break;
		}
	    }
	}
      XFree(data);
    }

  if (supportsDelete)
    {
      XEvent event;

      memset(&event, 0, sizeof(event));
      event.xclient.type = ClientMessage;
      event.xclient.window = (Window)xWindow;
      event.xclient.message_type = wmProtocols;
      event.xclient.format = 32;
      event.xclient.data.l[0] = wmDeleteWindow;
      event.xclient.data.l[1] = CurrentTime;
      XSendEvent(display, (Window)xWindow, False, NoEventMask, &event);
    }
  else
    {
      XKillClient(display, (Window)xWindow);
    }

  XFlush(display);
}


@end
