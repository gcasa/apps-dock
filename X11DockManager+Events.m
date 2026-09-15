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

@implementation X11DockManager (Events)

- (void) processPendingEvents
{
  Display *display = (Display *)_display;
  NSMutableSet *eventWindows = nil;
  NSMutableSet *iconEventWindows = nil;
  BOOL sawRelevantEvent = NO;
  unsigned int processedEvents = 0;
  const unsigned int maxEventsPerTick = 64;
  NSTimeInterval now;

  if (!display)
    {
      return;
    }

  while (processedEvents < maxEventsPerTick && XPending(display) > 0)
    {
      XEvent event;

      XNextEvent(display, &event);
      processedEvents++;
      switch (event.type)
	{
	case CreateNotify:
	  if (event.xcreatewindow.width > 0 &&
	      event.xcreatewindow.height > 0 &&
	      event.xcreatewindow.width <= DockSmallIconWindowMaximumSize &&
	      event.xcreatewindow.height <= DockSmallIconWindowMaximumSize)
	    {
	      if (!iconEventWindows)
		{
		  iconEventWindows = [NSMutableSet set];
		}
	      [iconEventWindows addObject:
				  [NSNumber numberWithUnsignedLong:
					      (unsigned long)event.xcreatewindow.window]];
	    }
	  sawRelevantEvent = YES;
	  break;
	case MapNotify:
	  if (!eventWindows)
	    {
	      eventWindows = [NSMutableSet set];
	    }
	  [eventWindows addObject:
			  [NSNumber numberWithUnsignedLong:
				      (unsigned long)event.xmap.window]];
	  sawRelevantEvent = YES;
	  break;
	case MapRequest:
	  if (!eventWindows)
	    {
	      eventWindows = [NSMutableSet set];
	    }
	  [eventWindows addObject:
			  [NSNumber numberWithUnsignedLong:
				      (unsigned long)event.xmaprequest.window]];
	  sawRelevantEvent = YES;
	  break;
	default:
	  break;
	}
    }

  if (XPending(display) > 0)
    {
      _scanPending = YES;
    }

  if ([eventWindows count] > 0)
    {
      NSArray *windows = [eventWindows allObjects];
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
	{
	  Window window =
	    (Window)[[windows objectAtIndex:i] unsignedLongValue];

	  [self scanClientWindow:window];
	}
    }

  if ([iconEventWindows count] > 0)
    {
      NSArray *windows = [iconEventWindows allObjects];
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
	{
	  Window window =
	    (Window)[[windows objectAtIndex:i] unsignedLongValue];

	  [self handlePossiblyNewWindow:window];
	}
    }

  now = [NSDate timeIntervalSinceReferenceDate];
  if (_scanPending &&
      now - _lastEventScanTime >= X11DockManagerEventScanInterval)
    {
      _scanPending = NO;
      _lastEventScanTime = now;
      [self scanForDockApps];
    }

  if (sawRelevantEvent)
    {
      XFlush(display);
    }
}


- (void) drainTransientIconEvents
{
  Display *display = (Display *)_display;
  unsigned int i;

  if (!display)
    {
      return;
    }

  for (i = 0; i < 12; i++)
    {
      [self processPendingEvents];
      XSync(display, False);
      usleep(1000);
    }
}


- (void) handlePossiblyNewWindow: (Window)window
{
  Display *display = (Display *)_display;
  int processIdentifier;
  NSString *title;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  if ([self windowIsSmallGNUstepIconOrMiniWindow:window])
    {
      processIdentifier = [self processIdentifierForWindow:window];
      title = [self classNameForWindow:window];
      if ([self rememberApplicationIconWindow:window
			    processIdentifier:processIdentifier
					title:title])
	{
	  return;
	}
      [self unmapIconWindow:window];
      return;
    }

  if (([self windowIsSmallRootOverrideRedirectWindow:window] &&
       ![self windowLooksLikeWindowMakerDockApp:window]))
    {
      [self unmapIconWindow:window];
      return;
    }
}


@end
