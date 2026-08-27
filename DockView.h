#import <AppKit/AppKit.h>

@class DockItem;

typedef enum {
  DockBackgroundBlack = 0,
  DockBackgroundSimulatedTransparency
} DockBackgroundMode;

@protocol DockViewDelegate
- (void)dockViewDidReceivePaths:(NSArray *)paths;
- (void)dockViewDidActivateItem:(DockItem *)item;
- (void)dockViewDidActivateTopIcon;
@end

@interface DockView : NSView
{
  NSMutableArray *_items;
  id _delegate;
  BOOL _draggingPaths;
  BOOL _performedDragOperation;
  NSImage *_gnustepIcon;
  NSImage *_recyclerIcon;
  NSImage *_backgroundImage;
  DockBackgroundMode _backgroundMode;
  BOOL _recyclerHasContents;
  BOOL _horizontal;
  NSUInteger _lastMouseDownIndex;
  NSTimeInterval _lastMouseDownTime;
}

- (void)setDelegate:(id)delegate;
- (void)setItems:(NSArray *)items;
- (void)setBackgroundImage:(NSImage *)image;
- (void)setBackgroundMode:(DockBackgroundMode)mode;
- (void)setRecyclerHasContents:(BOOL)hasContents;
- (void)setHorizontal:(BOOL)horizontal;
- (BOOL)isHorizontal;
- (NSRect)topTileRect;
- (NSRect)recyclerTileRect;
- (NSPoint)cellOriginAtIndex:(NSUInteger)index;
- (NSSize)cellSize;

@end
