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
}

@end
