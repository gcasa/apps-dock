#import "X11DockManager.h"
#import "DockView.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

static unsigned int X11DockWidth = 84;

@implementation X11DockManager

- (id)initWithDockView:(DockView *)view
{
  self = [super init];
  if (self) {
    _dockView = view;
    _knownWindows = [NSMutableSet new];
  }
  return self;
}

- (void)dealloc
{
  if (_display && _hostWindow) {
    XDestroyWindow((Display *)_display, (Window)_hostWindow);
  }
  if (_display) {
    XCloseDisplay((Display *)_display);
  }
  [_knownWindows release];
  [super dealloc];
}

- (void)setDelegate:(id)delegate
{
  _delegate = delegate;
}

- (BOOL)start
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

  _hostWindow = XCreateWindow(display, root, 0, 0, X11DockWidth,
                             (unsigned int)NSHeight([_dockView bounds]), 0,
                             CopyFromParent, InputOutput, CopyFromParent,
                             CWOverrideRedirect | CWBackPixel | CWEventMask,
                             &attrs);
  XMapWindow(display, (Window)_hostWindow);
  XFlush(display);
  _display = display;
  return YES;
}

- (void)setDockOnRight:(BOOL)rightSide centered:(BOOL)centered
{
  Display *display = (Display *)_display;
  int screen;
  int screenWidth;
  int screenHeight;
  unsigned int height = (unsigned int)NSHeight([_dockView bounds]);
  int x;
  int y;

  if (!display || !_hostWindow) {
    return;
  }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  if (height > (unsigned int)screenHeight) {
    height = (unsigned int)screenHeight;
  }

  x = rightSide ? screenWidth - (int)X11DockWidth : 0;
  y = centered ? (screenHeight - (int)height) / 2 : 0;
  XMoveResizeWindow(display, (Window)_hostWindow, x, y, X11DockWidth, height);
  XLowerWindow(display, (Window)_hostWindow);
  XFlush(display);
}

- (NSString *)titleForWindow:(Window)window
{
  Display *display = (Display *)_display;
  char *name = NULL;
  NSString *title = nil;

  if (XFetchName(display, window, &name) && name) {
    title = [NSString stringWithUTF8String:name];
    XFree(name);
  }

  if (![title length]) {
    XClassHint hint;
    if (XGetClassHint(display, window, &hint)) {
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

- (BOOL)wmStateForWindow:(Window)window state:(long *)state
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "WM_STATE", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  BOOL found = NO;

  if (XGetWindowProperty(display, window, property, 0, 2, False, property,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data) {
    if (actualFormat == 32 && itemCount >= 1) {
      *state = ((long *)data)[0];
      found = YES;
    }
    XFree(data);
  }

  return found;
}

- (BOOL)windowIsHidden:(Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if ([self wmStateForWindow:window state:&state] && state == IconicState) {
    return YES;
  }
  if (XGetWindowAttributes(display, window, &attr) && attr.map_state != IsViewable) {
    return YES;
  }
  return NO;
}

- (NSImage *)iconForWindow:(Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_ICON", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  NSImage *netWmIcon = nil;
  NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];

  if (XGetWindowProperty(display, window, property, 0, 65536, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data) {
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
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
          initWithBitmapDataPlanes:NULL
                        pixelsWide:(NSInteger)bestWidth
                        pixelsHigh:(NSInteger)bestHeight
                     bitsPerSample:8
                   samplesPerPixel:4
                          hasAlpha:YES
                          isPlanar:NO
                    colorSpaceName:NSCalibratedRGBColorSpace
                       bytesPerRow:(NSInteger)bestWidth * 4
                      bitsPerPixel:32] autorelease];
        unsigned char *bitmap = [rep bitmapData];
        unsigned long i;

        for (i = 0; i < bestWidth * bestHeight; i++) {
          unsigned long argb = values[bestOffset + i];
          bitmap[i * 4 + 0] = (argb >> 16) & 0xff;
          bitmap[i * 4 + 1] = (argb >> 8) & 0xff;
          bitmap[i * 4 + 2] = argb & 0xff;
          bitmap[i * 4 + 3] = (argb >> 24) & 0xff;
        }

        netWmIcon = [[[NSImage alloc] initWithSize:NSMakeSize(bestWidth, bestHeight)] autorelease];
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

- (BOOL)windowLooksLikeDockApp:(Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  XWMHints *hints;
  BOOL result = NO;

  if (!XGetWindowAttributes(display, window, &attr)) {
    return NO;
  }

  hints = XGetWMHints(display, window);
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

- (BOOL)windowLooksManageable:(Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if (window == (Window)_hostWindow) {
    return NO;
  }
  if (!XGetWindowAttributes(display, window, &attr)) {
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

- (void)scanForDockApps
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;

  if (!display) return;
  root = RootWindow(display, DefaultScreen(display));
  if (!XQueryTree(display, root, &root, &parent, &children, &count)) {
    return;
  }

  for (i = 0; i < count; i++) {
    NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)children[i]];
    if ([_knownWindows containsObject:key]) {
      if ([_delegate respondsToSelector:@selector(x11DockManagerDidUpdateWindow:hidden:)]) {
        [_delegate x11DockManagerDidUpdateWindow:(unsigned long)children[i]
                                          hidden:[self windowIsHidden:children[i]]];
      }
      continue;
    }
    if ([self windowLooksManageable:children[i]]) {
      BOOL dockApp = [self windowLooksLikeDockApp:children[i]];
      BOOL hidden = [self windowIsHidden:children[i]];
      [_knownWindows addObject:key];
      if ([_delegate respondsToSelector:@selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:dockApp:)]) {
        [_delegate x11DockManagerDidDiscoverWindowWithTitle:[self titleForWindow:children[i]]
                                                     window:(unsigned long)children[i]
                                                     hidden:hidden
                                                       icon:[self iconForWindow:children[i]]
                                                    dockApp:dockApp];
      }
    }
  }

  if (children) XFree(children);
}

- (void)dockWindow:(unsigned long)xWindow atIndex:(NSUInteger)index
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

- (void)activateWindow:(unsigned long)xWindow
{
  Display *display = (Display *)_display;
  if (!display) return;
  XMapRaised(display, (Window)xWindow);
  XSetInputFocus(display, (Window)xWindow, RevertToParent, CurrentTime);
  XFlush(display);
}

@end
