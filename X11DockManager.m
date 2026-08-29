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
#import <limits.h>
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
  DESTROY(_iconImageDataByProcessID);
  DESTROY(_iconWindowsByProcessID);
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
  XMapWindow(display, (Window)_hostWindow);
  XFlush(display);
  _display = display;
  XSetErrorHandler(X11DockManagerHandleError);
  XSelectInput(display, root, SubstructureNotifyMask | PropertyChangeMask);
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

- (NSRect) x11FrameForAppKitFrame: (NSRect)dockFrame
{
  Display *display = (Display *)_display;
  int screen;
  int screenWidth;
  int screenHeight;
  int x;
  int y;
  int width;
  int height;

  if (!display)
    {
      return NSZeroRect;
    }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  x = (int)floor(NSMinX(dockFrame));
  width = (int)ceil(NSWidth(dockFrame));
  height = (int)ceil(NSHeight(dockFrame));
  y = screenHeight - (int)ceil(NSMaxY(dockFrame));

  if (x < 0)
    {
      width += x;
      x = 0;
    }
  if (y < 0)
    {
      height += y;
      y = 0;
    }
  if (x + width > screenWidth)
    {
      width = screenWidth - x;
    }
  if (y + height > screenHeight)
    {
      height = screenHeight - y;
    }
  if (width < 0)
    {
      width = 0;
    }
  if (height < 0)
    {
      height = 0;
    }

  return NSMakeRect(x, y, width, height);
}

- (NSImage *) backgroundImageForDockFrame: (NSRect)dockFrame
{
  Display *display = (Display *)_display;
  int screen;
  Window root;
  NSRect frame;
  XImage *ximage;
  NSBitmapImageRep *rep;
  NSImage *image;
  NSInteger width;
  NSInteger height;
  NSInteger x;
  NSInteger y;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;
  BOOL sawNonBlackPixel = NO;

  if (!display)
    {
      return nil;
    }

  frame = [self x11FrameForAppKitFrame:dockFrame];
  width = (NSInteger)NSWidth(frame);
  height = (NSInteger)NSHeight(frame);
  if (width <= 0 || height <= 0)
    {
      return nil;
    }

  screen = DefaultScreen(display);
  root = RootWindow(display, screen);
  XSync(display, False);
  ximage = XGetImage(display, root,
                     (int)NSMinX(frame),
                     (int)NSMinY(frame),
                     (unsigned int)width,
                     (unsigned int)height,
                     AllPlanes,
                     ZPixmap);
  if (!ximage)
    {
      return nil;
    }

  rep = [[NSBitmapImageRep alloc]
	  initWithBitmapDataPlanes:NULL
			pixelsWide:width
			pixelsHigh:height
		     bitsPerSample:8
		   samplesPerPixel:4
			  hasAlpha:YES
			  isPlanar:NO
		    colorSpaceName:NSDeviceRGBColorSpace
		       bytesPerRow:0
		      bitsPerPixel:32];
  rep = AUTORELEASE(rep);
  if (!rep)
    {
      XDestroyImage(ximage);
      return nil;
    }

  bitmapData = [rep bitmapData];
  bytesPerRow = [rep bytesPerRow];
  for (y = 0; y < height; y++)
    {
      for (x = 0; x < width; x++)
	{
	  unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
	  unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

	  dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
	  dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
	  dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
	  dst[3] = 255;
	  if (dst[0] || dst[1] || dst[2])
	    {
	      sawNonBlackPixel = YES;
	    }
	}
    }

  XDestroyImage(ximage);

  if (!sawNonBlackPixel)
    {
      return nil;
    }

  image = AUTORELEASE([[NSImage alloc] initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
}

- (void) processPendingEvents
{
  Display *display = (Display *)_display;
  BOOL sawRelevantEvent = NO;

  if (!display)
    {
      return;
    }

  while (XPending(display) > 0)
    {
      XEvent event;
      Window window = None;

      XNextEvent(display, &event);
      switch (event.type)
	{
	case CreateNotify:
	  window = event.xcreatewindow.window;
	  break;
	case MapNotify:
	  window = event.xmap.window;
	  break;
	case MapRequest:
	  window = event.xmaprequest.window;
	  break;
	case PropertyNotify:
	  window = event.xproperty.window;
	  break;
	default:
	  break;
	}

      if (window != None)
	{
	  [self handlePossiblyNewWindow:window];
	  sawRelevantEvent = YES;
	}
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

  return [title length] ? title : [NSString stringWithFormat:@"0x%lx", (unsigned long)window];
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

- (NSImage *) imageFromDrawable: (Drawable)drawable
                           mask: (Pixmap)mask
                          width: (unsigned int)width
                         height: (unsigned int)height
{
  Display *display = (Display *)_display;
  XImage *ximage;
  XImage *maskImage = NULL;
  NSBitmapImageRep *rep;
  NSImage *image;
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

  rep = [[NSBitmapImageRep alloc]
	  initWithBitmapDataPlanes:NULL
			pixelsWide: (NSInteger)width
			pixelsHigh: (NSInteger)height
		     bitsPerSample:8
		   samplesPerPixel:4
			  hasAlpha:YES
			  isPlanar:NO
		    colorSpaceName:NSDeviceRGBColorSpace
		       bytesPerRow:0
		      bitsPerPixel:32];
  rep = AUTORELEASE(rep);
  if (!rep)
    {
      XDestroyImage(ximage);
      if (maskImage)
	{
	  XDestroyImage(maskImage);
	}
      return nil;
    }

  bitmapData = [rep bitmapData];
  bytesPerRow = [rep bytesPerRow];
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

  image = AUTORELEASE([[NSImage alloc]
			initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
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
  if (!XGetWindowAttributes(display, window, &attr))
    {
      return nil;
    }
  if ([self x11ErrorOccurred])
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
                           width: (unsigned int)attr.width
                          height: (unsigned int)attr.height];
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
      char procPath[64];
      char target[PATH_MAX];
      ssize_t length;

      snprintf(procPath, sizeof(procPath), "/proc/%d/exe", pid);
      length = readlink(procPath, target, sizeof(target) - 1);
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

- (void) moveIconWindowOffscreen: (Window)window
{
  Display *display = (Display *)_display;
  int screen;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  Window moveWindow;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  screen = DefaultScreen(display);
  root = RootWindow(display, screen);
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

  XMoveWindow(display, moveWindow,
	      DisplayWidth(display, screen) + DockHiddenIconWindowOffset,
	      DisplayHeight(display, screen) + DockHiddenIconWindowOffset);
  XFlush(display);
}

- (void) handlePossiblyNewWindow: (Window)window
{
  Display *display = (Display *)_display;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  if ([self windowIsSmallGNUstepIconOrMiniWindow:window] ||
      [self windowIsSmallRootOverrideRedirectWindow:window])
    {
      [self moveIconWindowOffscreen:window];
      return;
    }

  if ([self windowIsRegisteredIconWindow:window] ||
      [self rememberApplicationIconWindow:window
                        processIdentifier:[self processIdentifierForWindow:window]
                                    title:[self classNameForWindow:window]])
    {
      return;
    }
}

- (BOOL) windowLooksLikeDockApp: (Window)window
{
  return [self windowIsRegisteredIconWindow:window];
}

- (BOOL) windowLooksManageable: (Window)window
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
  if ([self windowIsSmallGNUstepIconOrMiniWindow:window] ||
      [self windowIsSmallRootOverrideRedirectWindow:window])
    {
      [self moveIconWindowOffscreen:window];
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
  if (attr.override_redirect)
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
  if (attr.override_redirect)
    {
      return NO;
    }

  return YES;
}

- (BOOL) windowExists: (unsigned long)xWindow
{
  return [self knownWindowStillExists:(Window)xWindow];
}

- (BOOL) windowShouldBeIgnoredWithTitle: (NSString *)title path: (NSString *)path
{
  NSString *lowerTitle = [title lowercaseString];
  NSString *lowerPath = [path lowercaseString];
  NSString *lowerName = [[path lastPathComponent] lowercaseString];

  if ([lowerTitle isEqualToString:@"gworkspace"] ||
      [lowerTitle isEqualToString:@"dockwm"] ||
      [lowerName isEqualToString:@"gworkspace"] ||
      [lowerName isEqualToString:@"dockwm"] ||
      [lowerPath rangeOfString:@"/gworkspace.app/"].location != NSNotFound ||
      [lowerPath rangeOfString:@"/dockwm.app/"].location != NSNotFound)
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
					      icon:[self iconForWindow:window]];
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
  NSNumber *windowKey;

  if (!identifier)
    {
      return nil;
    }

  windowKey = [_iconWindowsByProcessID objectForKey:identifier];
  if (!windowKey)
    {
      return nil;
    }

  return [self imageFromWindowContents:(Window)[windowKey unsignedLongValue]];
}

- (BOOL) rememberApplicationIconWindow: (Window)window
                     processIdentifier: (int)processIdentifier
                                 title: (NSString *)title
{
  id identifier;
  NSNumber *windowKey;
  XWindowAttributes attr;
  NSImage *icon;

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

  icon = [self imageFromWindowContents:window];
  [self moveIconWindowOffscreen:window];

  if (processIdentifier == getpid())
    {
      XFlush((Display *)_display);
      return YES;
    }

  if (icon && [_delegate respondsToSelector:
			   @selector(x11DockManagerDidUpdateApplicationIcon:processIdentifier:title:)])
    {
      [_delegate x11DockManagerDidUpdateApplicationIcon:icon
				      processIdentifier:processIdentifier
						  title:title];
    }

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
      NSImage *icon;
      NSData *iconData;
      int processIdentifier = 0;
      NSString *title = nil;

      [self clearX11Error];
      if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
	  [self x11ErrorOccurred])
	{
	  [_iconWindowsByProcessID removeObjectForKey:iconKey];
	  [_iconImageDataByProcessID removeObjectForKey:iconKey];
	  continue;
	}

      icon = [self imageFromWindowContents:window];
      iconData = [icon TIFFRepresentation];
      if (!icon || !iconData)
	{
	  continue;
	}

      if (![iconData isEqual:[_iconImageDataByProcessID objectForKey:iconKey]])
	{
	  [_iconImageDataByProcessID setObject:iconData forKey:iconKey];
	  if ([iconKey isKindOfClass:[NSNumber class]])
	    {
	      processIdentifier = [iconKey intValue];
	    }
	  else if ([iconKey isKindOfClass:[NSString class]])
	    {
	      title = iconKey;
	    }
	  if ([_delegate respondsToSelector:
			   @selector(x11DockManagerDidUpdateApplicationIcon:processIdentifier:title:)])
	    {
	      [_delegate x11DockManagerDidUpdateApplicationIcon:icon
					      processIdentifier:processIdentifier
							  title:title];
	    }
	}
    }
}

- (void) scanClientWindow: (Window)window
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)window];
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
  hidden = [self windowIsHidden:window];
  title = [self titleForWindow:window];
  path = [self executablePathForWindow:window];

  if ([self windowShouldBeIgnoredWithTitle:title path:path])
    {
      if (dockApp)
	{
	  [_knownWindows addObject:key];
	  if ([_delegate respondsToSelector:
			   @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)])
	    {
	      [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
							   window:(unsigned long)window
							   hidden:YES
							     icon:[self iconForWindow:window]
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
						   window:(unsigned long)window
						   hidden:hidden
						     icon:[self iconForWindow:window]
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

#if 0
  NSNumber *processKey;
  NSNumber *windowKey;
  NSImage *icon;

  processKey = [NSNumber numberWithInt:aProcessId];
  windowKey = [NSNumber numberWithUnsignedLong:(unsigned long)aWindowNumber];
  if ([_iconWindowsByProcessID objectForKey:processKey] &&
      ![[_iconWindowsByProcessID objectForKey:processKey] isEqual:windowKey])
    {
      return NSMakeRect(0, 0, 64, 64);
    }

  [_iconWindowsByProcessID setObject:windowKey forKey:processKey];
  [_knownWindows removeObject:windowKey];

  icon = [self imageFromWindowContents:(Window)aWindowNumber];
  if (icon && [_delegate respondsToSelector:
			   @selector(x11DockManagerDidUpdateApplicationIcon:processIdentifier:title:)])
    {
      [_delegate x11DockManagerDidUpdateApplicationIcon:icon
				      processIdentifier:aProcessId
						  title:nil];
    }

  return NSMakeRect(0, 0, 64, 64);
#endif
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

- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;

  if (!display || !_hostWindow) return;
  if (![self windowIsRegisteredIconWindow:(Window)xWindow])
    {
      return;
    }
  origin = [_dockView cellOriginAtIndex:index];
  XReparentWindow(display, (Window)xWindow, (Window)_hostWindow,
                  (int)origin.x,
                  (int)(NSHeight([_dockView bounds]) - origin.y - 64.0));
  XResizeWindow(display, (Window)xWindow, 64, 64);
  XMapRaised(display, (Window)xWindow);
  XFlush(display);
}

- (void) moveDockedWindow: (unsigned long)xWindow toIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;

  if (!display || !_hostWindow) return;
  origin = [_dockView cellOriginAtIndex:index];
  XMoveWindow(display, (Window)xWindow,
              (int)origin.x,
              (int)(NSHeight([_dockView bounds]) - origin.y - 64.0));
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

  if (!display || ![processIdentifiers count])
    {
      return NO;
    }

  root = RootWindow(display, DefaultScreen(display));
  window = [self activatableWindowForProcessIdentifiers:processIdentifiers
                                            underWindow:root];
  if (window == None)
    {
      return NO;
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
