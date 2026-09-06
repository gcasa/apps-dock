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
static const NSTimeInterval X11DockManagerEventScanInterval = 1.0;
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

- (NSRect) x11FrameForDockPlacement: (DockPlacement)placement
{
  Display *display = (Display *)_display;
  int screen;
  int screenWidth;
  int screenHeight;
  unsigned int width = (unsigned int)NSWidth([_dockView bounds]);
  unsigned int height = (unsigned int)NSHeight([_dockView bounds]);
  int x;
  int y;

  if (!display)
    {
      return NSZeroRect;
    }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  if (width > (unsigned int)screenWidth)
    {
      width = (unsigned int)screenWidth;
    }
  if (height > (unsigned int)screenHeight)
    {
      height = (unsigned int)screenHeight;
    }

  switch (placement)
    {
    case DockPlacementRightTop:
    case DockPlacementRightCenter:
      x = screenWidth - (int)width;
      break;
    case DockPlacementTopCenter:
    case DockPlacementBottomCenter:
      x = (screenWidth - (int)width) / 2;
      break;
    case DockPlacementLeftTop:
    case DockPlacementLeftCenter:
    default:
      x = 0;
      break;
    }

  switch (placement)
    {
    case DockPlacementLeftCenter:
    case DockPlacementRightCenter:
      y = (screenHeight - (int)height) / 2;
      break;
    case DockPlacementBottomCenter:
      y = screenHeight - (int)height;
      break;
    case DockPlacementLeftTop:
    case DockPlacementRightTop:
    case DockPlacementTopCenter:
    default:
      y = 0;
      break;
    }

  return NSMakeRect(x, y, width, height);
}

- (unsigned char) componentFromPixel: (unsigned long)pixel mask: (unsigned long)mask
{
  unsigned long value;
  unsigned int shift = 0;
  unsigned int bits = 0;

  if (!mask)
    {
      return 0;
    }

  while (((mask >> shift) & 1UL) == 0)
    {
      shift++;
    }

  value = (pixel & mask) >> shift;
  while (((mask >> (shift + bits)) & 1UL) != 0)
    {
      bits++;
    }

  if (bits >= 8)
    {
      return (unsigned char)(value >> (bits - 8));
    }

  return (unsigned char)((value * 255UL) / ((1UL << bits) - 1UL));
}

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

- (NSData *) imageDataFromDrawable: (Drawable)drawable
                              mask: (Pixmap)mask
                             width: (unsigned int)width
                            height: (unsigned int)height
{
  Display *display = (Display *)_display;
  XImage *ximage;
  XImage *maskImage = NULL;
  NSMutableData *imageData;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;
  NSInteger x;
  NSInteger y;
  BOOL sawVisiblePixel = NO;

  if (!display || !drawable || width == 0 || height == 0 ||
      width > 128 || height > 128)
    {
      return nil;
    }

  XSync(display, False);
  [self clearX11Error];
  ximage = XGetImage(display, drawable, 0, 0, width, height,
                     AllPlanes, ZPixmap);
  if (!ximage || [self x11ErrorOccurred])
    {
      if (ximage)
	{
	  XDestroyImage(ximage);
	}
      return nil;
    }

  if (mask)
    {
      [self clearX11Error];
      maskImage = XGetImage(display, mask, 0, 0, width, height,
			    AllPlanes, ZPixmap);
      if ([self x11ErrorOccurred])
	{
	  if (maskImage)
	    {
	      XDestroyImage(maskImage);
	    }
	  maskImage = NULL;
	}
    }

  bytesPerRow = (NSInteger)width * 4;
  imageData = [NSMutableData dataWithLength:bytesPerRow * (NSInteger)height];
  if (!imageData)
    {
      XDestroyImage(ximage);
      if (maskImage)
	{
	  XDestroyImage(maskImage);
	}
      return nil;
    }

  bitmapData = [imageData mutableBytes];
  for (y = 0; y < (NSInteger)height; y++)
    {
      for (x = 0; x < (NSInteger)width; x++)
	{
	  unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
	  unsigned char alpha = 255;
	  unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

	  if (maskImage && XGetPixel(maskImage, (int)x, (int)y) == 0)
	    {
	      alpha = 0;
	    }

	  dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
	  dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
	  dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
	  dst[3] = alpha;
	  if (alpha && (dst[0] || dst[1] || dst[2]))
	    {
	      sawVisiblePixel = YES;
	    }
	}
    }

  XDestroyImage(ximage);
  if (maskImage)
    {
      XDestroyImage(maskImage);
    }

  if (!sawVisiblePixel)
    {
      return nil;
    }

  return imageData;
}

- (NSImage *) imageFromData: (NSData *)imageData
                      width: (unsigned int)width
                     height: (unsigned int)height
{
  NSBitmapImageRep *rep;
  NSImage *image;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;

  if (![imageData length] || width == 0 || height == 0)
    {
      return nil;
    }

  bytesPerRow = (NSInteger)width * 4;
  if ([imageData length] < bytesPerRow * (NSInteger)height)
    {
      return nil;
    }

  rep = [[NSBitmapImageRep alloc]
	  initWithBitmapDataPlanes:NULL
			pixelsWide: (NSInteger)width
			pixelsHigh: (NSInteger)height
		     bitsPerSample:8
		   samplesPerPixel:4
			  hasAlpha:YES
			  isPlanar:NO
		    colorSpaceName:NSDeviceRGBColorSpace
		       bytesPerRow:bytesPerRow
		      bitsPerPixel:32];
  rep = AUTORELEASE(rep);
  if (!rep)
    {
      return nil;
    }

  bitmapData = [rep bitmapData];
  memcpy(bitmapData, [imageData bytes], bytesPerRow * (NSInteger)height);

  image = AUTORELEASE([[NSImage alloc]
			initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
}

- (NSImage *) imageFromDrawable: (Drawable)drawable
                           mask: (Pixmap)mask
                          width: (unsigned int)width
                         height: (unsigned int)height
{
  NSData *imageData = [self imageDataFromDrawable:drawable
					     mask:mask
					    width:width
					   height:height];

  return [self imageFromData:imageData width:width height:height];
}

- (NSImage *) imageFromPixmap: (Pixmap)pixmap mask: (Pixmap)mask
{
  Display *display = (Display *)_display;
  Window root;
  int x;
  int y;
  unsigned int width;
  unsigned int height;
  unsigned int borderWidth;
  unsigned int depth;

  if (!display || !pixmap)
    {
      return nil;
    }

  [self clearX11Error];
  if (!XGetGeometry(display, pixmap, &root, &x, &y,
                    &width, &height, &borderWidth, &depth) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }

  return [self imageFromDrawable:pixmap mask:mask width:width height:height];
}

- (NSImage *) imageFromWindowContents: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }
  if (attr.width <= 0 || attr.height <= 0 ||
      attr.width > 128 || attr.height > 128)
    {
      return nil;
    }

  return [self imageFromDrawable:window
                            mask:None
                           width:(unsigned int)attr.width
                          height:(unsigned int)attr.height];
}

- (NSImage *) iconForWindow: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_ICON", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  NSImage *netWmIcon = nil;
  NSImage *hintIcon = nil;
  NSImage *icon = nil;
  XWMHints *hints;
  NSImage *managedIcon;
  int pid;
  NSString *className;

  pid = [self processIdentifierForWindow:window];
  className = [self classNameForWindow:window];
  managedIcon = [self iconForIdentifier:
			[self iconIdentifierForProcessIdentifier:pid title:className]];
  if (managedIcon)
    {
      return managedIcon;
    }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints)
    {
      if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	{
	  hintIcon = [self imageFromWindowContents:hints->icon_window];
	}

      if (!hintIcon &&
	  (hints->flags & IconPixmapHint) &&
	  hints->icon_pixmap != None)
	{
	  Pixmap mask = None;

	  if ((hints->flags & IconMaskHint) && hints->icon_mask != None)
	    {
	      mask = hints->icon_mask;
	    }
	  hintIcon = [self imageFromPixmap:hints->icon_pixmap mask:mask];
	}

      XFree(hints);
    }
  else if (hints)
    {
      XFree(hints);
    }

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 65536, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if ([self x11ErrorOccurred])
	{
	  if (data) XFree(data);
	  return icon;
	}
      if (actualFormat == 32 && itemCount >= 3)
	{
	  unsigned long *values = (unsigned long *)data;
	  unsigned long offset = 0;
	  unsigned long bestOffset = 0;
	  unsigned long bestWidth = 0;
	  unsigned long bestHeight = 0;
	  unsigned long bestScore = ~0UL;

	  while (offset + 2 < itemCount)
	    {
	      unsigned long width = values[offset];
	      unsigned long height = values[offset + 1];
	      unsigned long pixelCount = width * height;
	      unsigned long score;

	      if (!width || !height || pixelCount > itemCount - offset - 2)
		{
		  break;
		}

	      score = labs((long)width - 48) + labs((long)height - 48);
	      if (score < bestScore)
		{
		  bestScore = score;
		  bestOffset = offset + 2;
		  bestWidth = width;
		  bestHeight = height;
		}

	      offset += 2 + pixelCount;
	    }

	  if (bestWidth && bestHeight)
	    {
	      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
					       initWithBitmapDataPlanes:NULL
							     pixelsWide: (NSInteger)bestWidth
							     pixelsHigh: (NSInteger)bestHeight
							  bitsPerSample:8
							samplesPerPixel:4
							       hasAlpha:YES
							       isPlanar:NO
							 colorSpaceName:NSCalibratedRGBColorSpace
							    bytesPerRow: (NSInteger)bestWidth * 4
							   bitsPerPixel:32];
	      rep = AUTORELEASE(rep);
	      unsigned char *bitmap = [rep bitmapData];
	      unsigned long i;

	      for (i = 0; i < bestWidth * bestHeight; i++)
		{
		  unsigned long argb = values[bestOffset + i];
		  bitmap[i * 4 + 0] = (argb >> 16) & 0xff;
		  bitmap[i * 4 + 1] = (argb >> 8) & 0xff;
		  bitmap[i * 4 + 2] = argb & 0xff;
		  bitmap[i * 4 + 3] = (argb >> 24) & 0xff;
		}

	      netWmIcon = AUTORELEASE([[NSImage alloc]
					initWithSize:NSMakeSize(bestWidth, bestHeight)]);
	      [netWmIcon addRepresentation:rep];
	    }
	}
      XFree(data);
    }

  if (netWmIcon)
    {
      return netWmIcon;
    }
  if (hintIcon)
    {
      return hintIcon;
    }
  return icon;
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

- (BOOL) windowIsRegisteredIconWindow: (Window)window
{
  return [[_iconWindowsByProcessID allValues]
	   containsObject:[NSNumber numberWithUnsignedLong:(unsigned long)window]];
}

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

- (NSImage *) iconForIdentifier: (id)identifier
{
  if (!identifier)
    {
      return nil;
    }

  return nil;
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

- (BOOL) windowHasGNUstepWindowAttributes: (Window)window
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

	  result = (attrs[0] & DockGSWindowStyleAttr) ? YES : NO;
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

- (BOOL) windowIsSmallGNUstepIconOrMiniWindow: (Window)window
{
  long state = NormalState;

  if (![self windowIsSmallIconSized:window])
    {
      return NO;
    }

  if ([self windowHasGNUstepIconStyle:window] ||
      [self windowHasGNUstepMiniWindowStyle:window])
    {
      return YES;
    }

  return [self windowIsSmallIconSized:window] &&
    ![self wmStateForWindow:window state:&state] &&
    [self windowHasGNUstepWindowAttributes:window];
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

- (BOOL) windowLooksLikeDockApp: (Window)window
{
  return [self windowIsRegisteredIconWindow:window] ||
    [self windowIsKnownDockAppWindow:window] ||
    [self windowLooksLikeWindowMakerDockApp:window];
}

- (BOOL) windowIsKnownDockAppWindow: (Window)window
{
  return [_dockAppWindows containsObject:
			    [NSNumber numberWithUnsignedLong:(unsigned long)window]];
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

- (NSRect) setWindow: (unsigned int)aWindowNumber
        appProcessId: (int)aProcessId
{
  if (aWindowNumber == 0 || aProcessId <= 0)
    {
      return NSZeroRect;
    }
  if (![self windowHasGNUstepIconStyle:(Window)aWindowNumber] ||
      ![self windowIsIconSized:(Window)aWindowNumber])
    {
      return NSZeroRect;
    }

  if ([self rememberApplicationIconWindow:(Window)aWindowNumber
                        processIdentifier:aProcessId
                                    title:nil])
    {
      return [self hiddenIconWindowFrame];
    }

  return NSZeroRect;
}

- (void) setApplicationIconData: (NSData *)data
                      badgeText: (NSString *)badgeText
                   appProcessId: (int)aProcessId
{
  NSImage *icon = nil;

  if (aProcessId <= 0)
    {
      return;
    }

  if ([data length])
    {
      icon = AUTORELEASE([[NSImage alloc] initWithData:data]);
    }

  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidUpdateApplicationIcon:badgeLabel:processIdentifier:)])
    {
      [_delegate x11DockManagerDidUpdateApplicationIcon:icon
					     badgeLabel:badgeText
				      processIdentifier:aProcessId];
    }
}

- (void) requestUserAttention: (NSInteger)requestType
		 appProcessId: (int)aProcessId
{
  if (aProcessId <= 0)
    {
      return;
    }

  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidRequestUserAttentionForProcessIdentifier:requestType:)])
    {
      [_delegate x11DockManagerDidRequestUserAttentionForProcessIdentifier:aProcessId
							 requestType:requestType];
    }
}

- (void) removeWindow: (unsigned int)aWindowNumber
{
  NSArray *processKeys = [_iconWindowsByProcessID allKeys];
  NSNumber *windowKey =
    [NSNumber numberWithUnsignedLong:(unsigned long)aWindowNumber];
  NSUInteger i;

  for (i = 0; i < [processKeys count]; i++)
    {
      NSNumber *processKey = [processKeys objectAtIndex:i];

      if ([[_iconWindowsByProcessID objectForKey:processKey]
	    isEqual:windowKey])
	{
	  [_iconWindowsByProcessID removeObjectForKey:processKey];
	  [_iconImageDataByProcessID removeObjectForKey:processKey];
	  break;
	}
    }
}

- (NSSize) getSizeWindow
{
  return NSMakeSize(64, 64);
}

- (NSRect) hiddenIconWindowFrame
{
  Display *display = (Display *)_display;
  int screen;

  if (!display)
    {
      return NSMakeRect(0, 0, 64, 64);
    }

  screen = DefaultScreen(display);
  return NSMakeRect(DisplayWidth(display, screen) + DockHiddenIconWindowOffset,
		    DisplayHeight(display, screen) + DockHiddenIconWindowOffset,
		    64, 64);
}

- (void) updateHostWindowShape
{
  Display *display = (Display *)_display;
  NSArray *frames;
  XRectangle *rectangles = NULL;
  int eventBase;
  int errorBase;
  NSUInteger count;
  NSUInteger i;

  if (!display || !_hostWindow ||
      !XShapeQueryExtension(display, &eventBase, &errorBase))
    {
      return;
    }

  frames = [_dockedWindowFrames allValues];
  count = [frames count];
  if (count > 0)
    {
      rectangles = malloc(sizeof(XRectangle) * count);
      if (!rectangles)
	{
	  return;
	}
      for (i = 0; i < count; i++)
	{
	  NSRect rect = [[frames objectAtIndex:i] rectValue];

	  rectangles[i].x = (short)NSMinX(rect);
	  rectangles[i].y = (short)NSMinY(rect);
	  rectangles[i].width = (unsigned short)NSWidth(rect);
	  rectangles[i].height = (unsigned short)NSHeight(rect);
	}
    }

  XShapeCombineRectangles(display, (Window)_hostWindow, ShapeBounding,
			  0, 0, rectangles, (int)count, ShapeSet, YXBanded);
  XShapeCombineRectangles(display, (Window)_hostWindow, ShapeInput,
			  0, 0, rectangles, (int)count, ShapeSet, YXBanded);
  if (rectangles)
    {
      free(rectangles);
    }
  XFlush(display);
}

- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;
  int x;
  int y;

  if (!display || !_hostWindow) return;
  if (![self windowIsRegisteredIconWindow:(Window)xWindow] &&
      ![self windowIsKnownDockAppWindow:(Window)xWindow] &&
      ![self windowLooksLikeWindowMakerDockApp:(Window)xWindow])
    {
      return;
    }
  origin = [_dockView cellOriginAtIndex:index];
  x = (int)origin.x;
  y = (int)(NSHeight([_dockView bounds]) - origin.y - 64.0);
  [_dockedWindowFrames setObject:[NSValue valueWithRect:NSMakeRect(x, y, 64, 64)]
			   forKey:[NSNumber numberWithUnsignedLong:xWindow]];
  [self updateHostWindowShape];
  XRaiseWindow(display, (Window)_hostWindow);
  XReparentWindow(display, (Window)xWindow, (Window)_hostWindow, x, y);
  XResizeWindow(display, (Window)xWindow, 64, 64);
  XMapRaised(display, (Window)xWindow);
  XFlush(display);
}

- (void) moveDockedWindow: (unsigned long)xWindow toIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;
  int x;
  int y;

  if (!display || !_hostWindow) return;
  origin = [_dockView cellOriginAtIndex:index];
  x = (int)origin.x;
  y = (int)(NSHeight([_dockView bounds]) - origin.y - 64.0);
  [_dockedWindowFrames setObject:[NSValue valueWithRect:NSMakeRect(x, y, 64, 64)]
			   forKey:[NSNumber numberWithUnsignedLong:xWindow]];
  [self updateHostWindowShape];
  XRaiseWindow(display, (Window)_hostWindow);
  XMoveWindow(display, (Window)xWindow, x, y);
  XFlush(display);
}

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
      return activated;
    }

  [self activateWindow:(unsigned long)window];
  return YES;
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
