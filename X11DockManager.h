#import <AppKit/AppKit.h>

@class DockView;
@class DockItem;

typedef enum {
  DockPlacementLeftTop = 0,
  DockPlacementLeftCenter,
  DockPlacementRightTop,
  DockPlacementRightCenter,
  DockPlacementTopCenter,
  DockPlacementBottomCenter
} DockPlacement;

@protocol X11DockManagerDelegate
- (void)x11DockManagerDidDiscoverWindowWithTitle:(NSString *)title
                                          window:(unsigned long)xWindow
                                         hidden:(BOOL)hidden
                                           icon:(NSImage *)icon
                                           path:(NSString *)path
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
- (void)setDockPlacement:(DockPlacement)placement;
- (NSImage *)backgroundImageForDockPlacement:(DockPlacement)placement;
- (void)scanForDockApps;
- (void)dockWindow:(unsigned long)xWindow atIndex:(NSUInteger)index;
- (void)activateWindow:(unsigned long)xWindow;

@end
