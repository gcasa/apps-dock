#import <AppKit/AppKit.h>

@class DockView;
@class DockItem;

@protocol X11DockManagerDelegate
- (void)x11DockManagerDidDiscoverWindowWithTitle:(NSString *)title
                                          window:(unsigned long)xWindow
                                         hidden:(BOOL)hidden
                                           icon:(NSImage *)icon
                                        dockApp:(BOOL)dockApp;
- (void)x11DockManagerDidUpdateWindow:(unsigned long)xWindow hidden:(BOOL)hidden;
@end

@interface X11DockManager : NSObject
{
  id _delegate;
  DockView *_dockView;
  void *_display;
  unsigned long _hostWindow;
  NSMutableSet *_knownWindows;
}

- (id)initWithDockView:(DockView *)view;
- (void)setDelegate:(id)delegate;
- (BOOL)start;
- (void)setDockOnRight:(BOOL)rightSide centered:(BOOL)centered;
- (void)scanForDockApps;
- (void)dockWindow:(unsigned long)xWindow atIndex:(NSUInteger)index;
- (void)activateWindow:(unsigned long)xWindow;

@end
