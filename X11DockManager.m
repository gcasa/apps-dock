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

#import "X11DockManager.h"
#import "DockView.h"
#import <Foundation/NSConnection.h>
#import <GNUstepBase/GNUstep.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#import <X11/extensions/shape.h>
#import <limits.h>
#import <mntent.h>
#import <paths.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#define DockGSWindowStyleAttr (1UL << 0)
#define DockNSIconWindowMask 64UL
#define DockNSMiniWindowMask 128UL
#define DockSmallIconWindowMaximumSize 70
#define DockHiddenIconWindowOffset 256

static int X11DockManagerLastErrorCode = 0;
static int X11DockManagerHandleError(Display *display, XErrorEvent *event)
{
  X11DockManagerLastErrorCode = event->error_code;
  return 0;
}

@interface X11DockManager (Private)
- (void) registerIconManager;
- (NSRect) x11FrameForDockPlacement: (DockPlacement)placement;
- (NSString *) classNameForWindow: (Window)window;
- (Window) dockAppIconWindowForWindow: (Window)window;
- (BOOL) windowHasDockAppClass: (Window)window;
- (BOOL) windowIsDockAppIconChild: (Window)window;
- (id) iconIdentifierForProcessIdentifier: (int)processIdentifier
                                    title: (NSString *)title;
- (BOOL) rememberApplicationIconWindow: (Window)window
                     processIdentifier: (int)processIdentifier
                                 title: (NSString *)title;
- (void) hideApplicationIconWindow: (Window)window;
- (BOOL) windowLooksLikeWindowMakerDockApp: (Window)window;
- (BOOL) windowIsKnownDockAppWindow: (Window)window;
- (void) updateHostWindowShape;
- (NSRect) hiddenIconWindowFrame;
- (void) handlePossiblyNewWindow: (Window)window;
- (void) scanClientWindow: (Window)window;
- (void) deiconifyWindow: (Window)window;
- (NSUInteger) activateIconicWindowsForProcessIdentifiers: (NSArray *)processIdentifiers
					      underWindow: (Window)parentWindow;
@end

@implementation X11DockManager

- (id) initWithDockView: (DockView *)view
{
  self = [super init];
  if (self)
    {
      _dockView = view;
      _knownWindows = [NSMutableSet new];
      _iconWindowsByProcessID = [NSMutableDictionary new];
      _iconImageDataByProcessID = [NSMutableDictionary new];
      _dockedWindowFrames = [NSMutableDictionary new];
      _dockAppWindows = [NSMutableSet new];
    }
  return self;
}

- (void) dealloc
{
  if (_iconConnection)
    {
      [_iconConnection invalidate];
    }
  if (_display && _hostWindow)
    {
      XDestroyWindow((Display *)_display, (Window)_hostWindow);
    }
  if (_display)
    {
      XCloseDisplay((Display *)_display);
    }
  DESTROY(_iconWindowsByProcessID);
  DESTROY(_iconImageDataByProcessID);
  DESTROY(_dockedWindowFrames);
  DESTROY(_dockAppWindows);
  DESTROY(_iconConnection);
  DESTROY(_knownWindows);
  DEALLOC;
}

- (void) setDelegate: (id)delegate
{
  _delegate = delegate;
}

- (BOOL) start
{
  Display *display = XOpenDisplay(NULL);
  if (!display)
    {
      NSLog(@"Unable to open X display; X11 docking is disabled.");
      return NO;
    }

  int screen = DefaultScreen(display);
  Window root = RootWindow(display, screen);
  XSetWindowAttributes attrs;
  attrs.override_redirect = True;
  attrs.background_pixel = BlackPixel(display, screen);
  attrs.event_mask = SubstructureNotifyMask | ExposureMask;

  _hostWindow = XCreateWindow(display, root, 0, 0,
			      (unsigned int)NSWidth([_dockView bounds]),
			      (unsigned int)NSHeight([_dockView bounds]), 0,
			      CopyFromParent, InputOutput, CopyFromParent,
			      CWOverrideRedirect | CWBackPixel | CWEventMask,
			      &attrs);
  XStoreName(display, (Window)_hostWindow, "DockWM X11 Dock Host");
  XMapWindow(display, (Window)_hostWindow);
  XFlush(display);
  _display = display;
  XSetErrorHandler(X11DockManagerHandleError);
  XSelectInput(display, root, SubstructureNotifyMask | PropertyChangeMask);
  [self updateHostWindowShape];
  [self registerIconManager];
  return YES;
}

- (void) registerIconManager
{
  _iconConnection = [NSConnection new];
  [_iconConnection setRootObject:self];
  if (![_iconConnection registerName:@"GSIconManager"])
    {
      NSLog(@"Unable to register GSIconManager; GNUstep app icon windows will not be handed to DockWM.");
      DESTROY(_iconConnection);
    }
}

- (BOOL) x11ErrorOccurred
{
  Display *display = (Display *)_display;
  XSync(display, False);
  return X11DockManagerLastErrorCode != 0;
}

- (void) clearX11Error
{
  X11DockManagerLastErrorCode = 0;
}

- (void) makeWindowSticky: (unsigned long)xWindow
{
  Display *display = (Display *)_display;
  Atom desktopProperty;
  unsigned long allDesktops = 0xFFFFFFFFUL;

  if (!display || !xWindow)
    {
      return;
    }

  desktopProperty = XInternAtom(display, "_NET_WM_DESKTOP", False);
  [self clearX11Error];
  XChangeProperty(display, (Window)xWindow, desktopProperty, XA_CARDINAL, 32,
		  PropModeReplace, (unsigned char *)&allDesktops, 1);
  XFlush(display);
  if ([self x11ErrorOccurred])
    {
      NSLog(@"Unable to mark DockWM window %lu as sticky.", xWindow);
    }
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

- (void) setDockPlacement: (DockPlacement)placement
{
  Display *display = (Display *)_display;
  NSRect frame;

  if (!display || !_hostWindow)
    {
      return;
    }

  frame = [self x11FrameForDockPlacement:placement];
  XMoveResizeWindow(display,
                    (Window)_hostWindow,
                    (int)NSMinX(frame),
                    (int)NSMinY(frame),
                    (unsigned int)NSWidth(frame),
                    (unsigned int)NSHeight(frame));
  XLowerWindow(display, (Window)_hostWindow);
  XFlush(display);
}



































































@end
