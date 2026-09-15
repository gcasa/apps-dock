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

@implementation X11DockManager (WindowMetadata)

- (NSString *) titleForWindow: (Window)window
{
  Display *display = (Display *)_display;
  char *name = NULL;
  NSString *title = nil;

  [self clearX11Error];
  if (XFetchName(display, window, &name) && name)
    {
      if ([self x11ErrorOccurred])
	{
	  if (name) XFree(name);
	  return nil;
	}
      title = [NSString stringWithUTF8String:name];
      XFree(name);
    }

  if (![title length])
    {
      XClassHint hint;
      [self clearX11Error];
      if (XGetClassHint(display, window, &hint))
	{
	  if ([self x11ErrorOccurred])
	    {
	      return nil;
	    }
	  if (hint.res_class)
	    {
	      title = [NSString stringWithUTF8String:hint.res_class];
	    }
	  else if (hint.res_name)
	    {
	      title = [NSString stringWithUTF8String:hint.res_name];
	    }
	  if (hint.res_name) XFree(hint.res_name);
	  if (hint.res_class) XFree(hint.res_class);
	}
    }

  return [title length] ? title : nil;
}


- (BOOL) wmStateForWindow: (Window)window state: (long *)state
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "WM_STATE", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  BOOL found = NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 2, False, property,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if ([self x11ErrorOccurred])
	{
	  if (data) XFree(data);
	  return NO;
	}
      if (actualFormat == 32 && itemCount >= 1)
	{
	  *state = ((long *)data)[0];
	  found = YES;
	}
      XFree(data);
    }

  return found;
}


- (int) processIdentifierForWindow: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_PID", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  int pid = 0;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 1, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32 && itemCount >= 1)
	{
	  pid = (int)((unsigned long *)data)[0];
	}
      XFree(data);
    }

  return pid;
}


- (BOOL) windowIsHidden: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if ([self wmStateForWindow:window state:&state] && state == IconicState)
    {
      return YES;
    }
  [self clearX11Error];
  if (XGetWindowAttributes(display, window, &attr) && attr.map_state != IsViewable)
    {
      if ([self x11ErrorOccurred])
	{
	  return NO;
	}
      return YES;
    }
  return NO;
}


- (NSString *) executablePathForWindow: (Window)window
{
  int pid = [self processIdentifierForWindow:window];
  NSString *path = nil;

  if (pid > 0)
    {
      NSString *procPath = [self procFilesystemPath];
      NSString *linkPath;
      char target[PATH_MAX];
      ssize_t length;

      if (![procPath length])
	{
	  return nil;
	}

      linkPath = [[procPath stringByAppendingPathComponent:
			      [NSString stringWithFormat:@"%d", pid]]
		   stringByAppendingPathComponent:@"exe"];
      length = readlink([linkPath fileSystemRepresentation],
			target,
			sizeof(target) - 1);
      if (length > 0)
	{
	  target[length] = '\0';
	  path = [NSString stringWithUTF8String:target];
	}
    }

  return [path length] ? path : nil;
}


- (NSString *) classNameForWindow: (Window)window
{
  Display *display = (Display *)_display;
  XClassHint hint;
  NSString *name = nil;

  [self clearX11Error];
  if (XGetClassHint(display, window, &hint) && ![self x11ErrorOccurred])
    {
      if (hint.res_class && strlen(hint.res_class) > 0)
	{
	  name = [NSString stringWithUTF8String:hint.res_class];
	}
      else if (hint.res_name && strlen(hint.res_name) > 0)
	{
	  name = [NSString stringWithUTF8String:hint.res_name];
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

  return [name length] ? name : nil;
}


@end
