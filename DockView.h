#import <AppKit/AppKit.h>

@class DockItem;

@protocol DockViewDelegate
- (void)dockViewDidReceivePaths:(NSArray *)paths;
- (void)dockViewDidActivateItem:(DockItem *)item;
@end

@interface DockView : NSView
{
  NSMutableArray *_items;
  id _delegate;
  NSInteger _highlightIndex;
  NSImage *_gnustepIcon;
  BOOL _horizontal;
}

- (void)setDelegate:(id)delegate;
- (void)setItems:(NSArray *)items;
- (void)setHorizontal:(BOOL)horizontal;
- (BOOL)isHorizontal;
- (NSRect)topTileRect;
- (NSPoint)cellOriginAtIndex:(NSUInteger)index;
- (NSSize)cellSize;

@end
