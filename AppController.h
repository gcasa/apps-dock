#import <AppKit/AppKit.h>
#import "DockView.h"
#import "X11DockManager.h"

@interface AppController : NSObject <DockViewDelegate, X11DockManagerDelegate>
{
  NSWindow *_window;
  DockView *_dockView;
  NSMutableArray *_items;
  X11DockManager *_x11;
  NSTimer *_scanTimer;
  NSMenu *_dockMenu;
  NSMenuItem *_leftMenuItem;
  NSMenuItem *_rightMenuItem;
  NSMenuItem *_topMenuItem;
  NSMenuItem *_centerMenuItem;
  BOOL _dockOnRight;
  BOOL _dockCentered;
}

@end
