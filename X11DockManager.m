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
#import <GNUstepBase/GNUstep.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#import <limits.h>
#import <string.h>
#import <unistd.h>

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
  if (self) {
    _dockView = view;
    _knownWindows = [NSMutableSet new];
  }
  return self;
}

- (void) dealloc
{
  if (_display && _hostWindow) {
    XDestroyWindow((Display *)_display, (Window)_hostWindow);
  }
  if (_display) {
    XCloseDisplay((Display *)_display);
  }
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
  if (!display) {
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
  return YES;
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

  if (!display || !_hostWindow) {
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

  if (!display) {
    return NSZeroRect;
  }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  if (width > (unsigned int)screenWidth) {
    width = (unsigned int)screenWidth;
  }
  if (height > (unsigned int)screenHeight) {
    height = (unsigned int)screenHeight;
  }

  switch (placement) {
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

  switch (placement) {
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

  if (!mask) {
    return 0;
  }

  while (((mask >> shift) & 1UL) == 0) {
    shift++;
  }

  value = (pixel & mask) >> shift;
  while (((mask >> (shift + bits)) & 1UL) != 0) {
    bits++;
  }

  if (bits >= 8) {
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

  if (!display) {
    return NSZeroRect;
  }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  x = (int)floor(NSMinX(dockFrame));
  width = (int)ceil(NSWidth(dockFrame));
  height = (int)ceil(NSHeight(dockFrame));
  y = screenHeight - (int)ceil(NSMaxY(dockFrame));

  if (x < 0) {
    width += x;
    x = 0;
  }
  if (y < 0) {
    height += y;
    y = 0;
  }
  if (x + width > screenWidth) {
    width = screenWidth - x;
  }
  if (y + height > screenHeight) {
    height = screenHeight - y;
  }
  if (width < 0) {
    width = 0;
  }
  if (height < 0) {
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

  if (!display) {
    return nil;
  }

  frame = [self x11FrameForAppKitFrame:dockFrame];
  width = (NSInteger)NSWidth(frame);
  height = (NSInteger)NSHeight(frame);
  if (width <= 0 || height <= 0) {
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
  if (!ximage) {
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
  if (!rep) {
    XDestroyImage(ximage);
    return nil;
  }

  bitmapData = [rep bitmapData];
  bytesPerRow = [rep bytesPerRow];
  for (y = 0; y < height; y++) {
    for (x = 0; x < width; x++) {
      unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
      unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

      dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
      dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
      dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
      dst[3] = 255;
      if (dst[0] || dst[1] || dst[2]) {
        sawNonBlackPixel = YES;
      }
    }
  }

  XDestroyImage(ximage);

  if (!sawNonBlackPixel) {
    return nil;
  }

  image = AUTORELEASE([[NSImage alloc] initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
}

- (NSString *) titleForWindow: (Window)window
{
  Display *display = (Display *)_display;
  char *name = NULL;
  NSString *title = nil;

  [self clearX11Error];
  if (XFetchName(display, window, &name) && name) {
    if ([self x11ErrorOccurred]) {
      if (name) XFree(name);
      return nil;
    }
    title = [NSString stringWithUTF8String:name];
    XFree(name);
  }

  if (![title length]) {
    XClassHint hint;
    [self clearX11Error];
    if (XGetClassHint(display, window, &hint)) {
      if ([self x11ErrorOccurred]) {
        return nil;
      }
      if (hint.res_class) {
        title = [NSString stringWithUTF8String:hint.res_class];
      } else if (hint.res_name) {
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
                         &data) == Success && data) {
    if ([self x11ErrorOccurred]) {
      if (data) XFree(data);
      return NO;
    }
    if (actualFormat == 32 && itemCount >= 1) {
      *state = ((long *)data)[0];
      found = YES;
    }
    XFree(data);
  }

  return found;
}

- (BOOL) windowIsHidden: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if ([self wmStateForWindow:window state:&state] && state == IconicState) {
    return YES;
  }
  [self clearX11Error];
  if (XGetWindowAttributes(display, window, &attr) && attr.map_state != IsViewable) {
    if ([self x11ErrorOccurred]) {
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
      width > 128 || height > 128) {
    return nil;
  }

  XSync(display, False);
  [self clearX11Error];
  ximage = XGetImage(display, drawable, 0, 0, width, height,
                     AllPlanes, ZPixmap);
  if (!ximage || [self x11ErrorOccurred]) {
    if (ximage) {
      XDestroyImage(ximage);
    }
    return nil;
  }

  if (mask) {
    [self clearX11Error];
    maskImage = XGetImage(display, mask, 0, 0, width, height,
                          AllPlanes, ZPixmap);
    if ([self x11ErrorOccurred]) {
      if (maskImage) {
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
  if (!rep) {
    XDestroyImage(ximage);
    if (maskImage) {
      XDestroyImage(maskImage);
    }
    return nil;
  }

  bitmapData = [rep bitmapData];
  bytesPerRow = [rep bytesPerRow];
  for (y = 0; y < (NSInteger)height; y++) {
    for (x = 0; x < (NSInteger)width; x++) {
      unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
      unsigned char alpha = 255;
      unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

      if (maskImage && XGetPixel(maskImage, (int)x, (int)y) == 0) {
        alpha = 0;
      }

      dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
      dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
      dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
      dst[3] = alpha;
      if (alpha && (dst[0] || dst[1] || dst[2])) {
        sawVisiblePixel = YES;
      }
    }
  }

  XDestroyImage(ximage);
  if (maskImage) {
    XDestroyImage(maskImage);
  }

  if (!sawVisiblePixel) {
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

  if (!display || !pixmap) {
    return nil;
  }

  [self clearX11Error];
  if (!XGetGeometry(display, pixmap, &root, &x, &y,
                    &width, &height, &borderWidth, &depth) ||
      [self x11ErrorOccurred]) {
    return nil;
  }

  return [self imageFromDrawable:pixmap mask:mask width:width height:height];
}

- (NSImage *) imageFromWindowContents: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr)) {
    return nil;
  }
  if ([self x11ErrorOccurred]) {
    return nil;
  }
  if (attr.width <= 0 || attr.height <= 0 ||
      attr.width > 128 || attr.height > 128) {
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
  NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];
  XWMHints *hints;

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints) {
    NSImage *hintIcon = nil;

    if ((hints->flags & IconWindowHint) && hints->icon_window != None) {
      hintIcon = [self imageFromWindowContents:hints->icon_window];
    }

    if (!hintIcon &&
        (hints->flags & IconPixmapHint) &&
        hints->icon_pixmap != None) {
      Pixmap mask = None;

      if ((hints->flags & IconMaskHint) && hints->icon_mask != None) {
        mask = hints->icon_mask;
      }
      hintIcon = [self imageFromPixmap:hints->icon_pixmap mask:mask];
    }

    XFree(hints);
    if (hintIcon) {
      return hintIcon;
    }
  } else if (hints) {
    XFree(hints);
  }

  if ([self windowLooksLikeDockApp:window]) {
    NSImage *windowImage = [self imageFromWindowContents:window];
    if (windowImage) {
      return windowImage;
    }
  }

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 65536, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data) {
    if ([self x11ErrorOccurred]) {
      if (data) XFree(data);
      return icon ? icon : [NSImage imageNamed:@"NSApplicationIcon"];
    }
    if (actualFormat == 32 && itemCount >= 3) {
      unsigned long *values = (unsigned long *)data;
      unsigned long offset = 0;
      unsigned long bestOffset = 0;
      unsigned long bestWidth = 0;
      unsigned long bestHeight = 0;
      unsigned long bestScore = ~0UL;

      while (offset + 2 < itemCount) {
        unsigned long width = values[offset];
        unsigned long height = values[offset + 1];
        unsigned long pixelCount = width * height;
        unsigned long score;

        if (!width || !height || pixelCount > itemCount - offset - 2) {
          break;
        }

        score = labs((long)width - 48) + labs((long)height - 48);
        if (score < bestScore) {
          bestScore = score;
          bestOffset = offset + 2;
          bestWidth = width;
          bestHeight = height;
        }

        offset += 2 + pixelCount;
      }

      if (bestWidth && bestHeight) {
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

        for (i = 0; i < bestWidth * bestHeight; i++) {
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

  if (netWmIcon) {
    return netWmIcon;
  }
  if (!icon) {
    icon = [NSImage imageNamed:@"NSApplicationIcon"];
  }
  return icon;
}

- (NSString *) executablePathForWindow: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_PID", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  NSString *path = nil;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 1, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data) {
    if (![self x11ErrorOccurred] && actualFormat == 32 && itemCount >= 1) {
      unsigned long pid = ((unsigned long *)data)[0];
      char procPath[64];
      char target[PATH_MAX];
      ssize_t length;

      snprintf(procPath, sizeof(procPath), "/proc/%lu/exe", pid);
      length = readlink(procPath, target, sizeof(target) - 1);
      if (length > 0) {
        target[length] = '\0';
        path = [NSString stringWithUTF8String:target];
      }
    }
    XFree(data);
  }

  return [path length] ? path : nil;
}

- (BOOL) windowLooksLikeDockApp: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  XWMHints *hints;
  BOOL result = NO;

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr)) {
    return NO;
  }
  if ([self x11ErrorOccurred]) {
    return NO;
  }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if ([self x11ErrorOccurred]) {
    return NO;
  }
  if (hints) {
    if ((hints->flags & IconWindowHint) && hints->icon_window != None) {
      result = YES;
    }
    XFree(hints);
  }

  if (!result && attr.width <= 96 && attr.height <= 96) {
    result = YES;
  }

  return result;
}

- (BOOL) windowLooksManageable: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if (window == (Window)_hostWindow) {
    return NO;
  }
  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr)) {
    return NO;
  }
  if ([self x11ErrorOccurred]) {
    return NO;
  }
  if (attr.override_redirect) {
    return NO;
  }
  if (attr.map_state != IsViewable &&
      (![self wmStateForWindow:window state:&state] || state != IconicState)) {
    return NO;
  }
  return YES;
}

- (BOOL) knownWindowStillExists: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  if (window == (Window)_hostWindow) {
    return NO;
  }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr)) {
    return NO;
  }
  if ([self x11ErrorOccurred]) {
    return NO;
  }
  if (attr.override_redirect) {
    return NO;
  }

  return YES;
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
      [lowerPath rangeOfString:@"/dockwm.app/"].location != NSNotFound) {
    return YES;
  }

  if ([lowerTitle rangeOfString:@"drag"].location != NSNotFound &&
      [lowerName isEqualToString:@"gworkspace"]) {
    return YES;
  }

  return NO;
}

- (void) scanKnownWindows
{
  NSArray *windows = [_knownWindows allObjects];
  NSUInteger i;

  for (i = 0; i < [windows count]; i++) {
    NSNumber *key = [windows objectAtIndex:i];
    Window window = (Window)[key unsignedLongValue];

    if (![self knownWindowStillExists:window]) {
      [_knownWindows removeObject:key];
      continue;
    }

    if ([_delegate respondsToSelector:
          @selector(x11DockManagerDidUpdateWindow:hidden:icon:)]) {
      [_delegate x11DockManagerDidUpdateWindow: (unsigned long)window
                                        hidden:[self windowIsHidden:window]
                                          icon:[self iconForWindow:window]];
    }
  }
}

- (void) scanForDockApps
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;

  if (!display) return;
  [self scanKnownWindows];

  root = RootWindow(display, DefaultScreen(display));
  if (!XQueryTree(display, root, &root, &parent, &children, &count)) {
    return;
  }

  for (i = 0; i < count; i++) {
    NSNumber *key = [NSNumber numberWithUnsignedLong: (unsigned long)children[i]];
    if ([_knownWindows containsObject:key]) {
      continue;
    }
    if ([self windowLooksManageable:children[i]]) {
      BOOL dockApp = [self windowLooksLikeDockApp:children[i]];
      BOOL hidden = [self windowIsHidden:children[i]];
      NSString *title = [self titleForWindow:children[i]];
      NSString *path = [self executablePathForWindow:children[i]];

      if ([self windowShouldBeIgnoredWithTitle:title path:path]) {
        if (dockApp) {
          NSString *lowerPath = [path lowercaseString];
          NSString *lowerName = [[path lastPathComponent] lowercaseString];
          NSString *lowerTitle = [title lowercaseString];

          if (([lowerPath length] &&
               ([lowerPath rangeOfString:@"/dockwm.app/"].location != NSNotFound ||
                [lowerPath rangeOfString:@"/gworkspace.app/"].location != NSNotFound)) ||
              [lowerName isEqualToString:@"dockwm"] ||
              [lowerName isEqualToString:@"gworkspace"] ||
              [lowerTitle isEqualToString:@"dockwm"] ||
              [lowerTitle isEqualToString:@"gworkspace"]) {
            XMoveWindow(display, children[i], -10000, -10000);
            XMapWindow(display, children[i]);
            XFlush(display);
          }

          [_knownWindows addObject:key];
          if ([_delegate respondsToSelector:
                @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)]) {
            [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
                                                         window: (unsigned long)children[i]
                                                         hidden:YES
                                                           icon:[self iconForWindow:children[i]]
                                                           path:path
                                                        dockApp:dockApp];
          }
        }
        continue;
      }

      [_knownWindows addObject:key];
      if ([_delegate respondsToSelector:@selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)]) {
        [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
                                                     window: (unsigned long)children[i]
                                                     hidden:hidden
                                                       icon:[self iconForWindow:children[i]]
                                                       path:path
                                                    dockApp:dockApp];
      }
    }
  }

  if (children) XFree(children);
}

- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;

  if (!display || !_hostWindow) return;
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

- (void) hideWindow: (unsigned long)xWindow
{
  Display *display = (Display *)_display;

  if (!display) return;
  XUnmapWindow(display, (Window)xWindow);
  XFlush(display);
}

- (void) suppressWindow: (unsigned long)xWindow
{
  Display *display = (Display *)_display;

  if (!display) return;
  XMoveWindow(display, (Window)xWindow, -1000, -1000);
  XMapWindow(display, (Window)xWindow);
  XFlush(display);
}

- (void) suppressWindow: (unsigned long)xWindow atIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;

  if (!display || !_hostWindow) {
    [self suppressWindow:xWindow];
    return;
  }

  origin = [_dockView cellOriginAtIndex:index];
  XReparentWindow(display, (Window)xWindow, (Window)_hostWindow,
                  (int)origin.x,
                  (int)(NSHeight([_dockView bounds]) - origin.y - 64.0));
  XResizeWindow(display, (Window)xWindow, 64, 64);
  XMapWindow(display, (Window)xWindow);
  XLowerWindow(display, (Window)_hostWindow);
  XFlush(display);
}

- (void) activateWindow: (unsigned long)xWindow
{
  Display *display = (Display *)_display;
  if (!display) return;
  XMapRaised(display, (Window)xWindow);
  XSetInputFocus(display, (Window)xWindow, RevertToParent, CurrentTime);
  XFlush(display);
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

  wmProtocols = XInternAtom(display, "WM_PROTOCOLS", False);
  wmDeleteWindow = XInternAtom(display, "WM_DELETE_WINDOW", False);

  if (XGetWindowProperty(display, (Window)xWindow, wmProtocols,
                         0, 32, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount,
                         &bytesAfter, &data) == Success && data) {
    unsigned long i;
    Atom *protocols = (Atom *)data;

    if (actualFormat == 32) {
      for (i = 0; i < itemCount; i++) {
        if (protocols[i] == wmDeleteWindow) {
          supportsDelete = YES;
          break;
        }
      }
    }
    XFree(data);
  }

  if (supportsDelete) {
    XEvent event;

    memset(&event, 0, sizeof(event));
    event.xclient.type = ClientMessage;
    event.xclient.window = (Window)xWindow;
    event.xclient.message_type = wmProtocols;
    event.xclient.format = 32;
    event.xclient.data.l[0] = wmDeleteWindow;
    event.xclient.data.l[1] = CurrentTime;
    XSendEvent(display, (Window)xWindow, False, NoEventMask, &event);
  } else {
    XKillClient(display, (Window)xWindow);
  }

  XFlush(display);
}

@end
