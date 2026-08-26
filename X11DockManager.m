#import "X11DockManager.h"
#import "DockView.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

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

  _hostWindow = XCreateWindow(display, root, 4, 48, 84, 720, 0,
                             CopyFromParent, InputOutput, CopyFromParent,
                             CWOverrideRedirect | CWBackPixel | CWEventMask,
                             &attrs);
  XMapRaised(display, (Window)_hostWindow);
  XFlush(display);
  _display = display;
  return YES;
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

- (BOOL)windowLooksLikeDockApp:(Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  XWMHints *hints;
  BOOL result = NO;

  if (!XGetWindowAttributes(display, window, &attr) || attr.map_state == IsUnmapped) {
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

  if (window == (Window)_hostWindow) {
    return NO;
  }
  if (!XGetWindowAttributes(display, window, &attr)) {
    return NO;
  }
  if (attr.map_state != IsViewable || attr.override_redirect) {
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
      continue;
    }
    if ([self windowLooksManageable:children[i]]) {
      BOOL dockApp = [self windowLooksLikeDockApp:children[i]];
      [_knownWindows addObject:key];
      if ([_delegate respondsToSelector:@selector(x11DockManagerDidDiscoverWindowWithTitle:window:dockApp:)]) {
        [_delegate x11DockManagerDidDiscoverWindowWithTitle:[self titleForWindow:children[i]]
                                                     window:(unsigned long)children[i]
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
