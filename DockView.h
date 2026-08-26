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
}

- (void)setDelegate:(id)delegate;
- (void)setItems:(NSArray *)items;
- (NSRect)topTileRect;
- (NSPoint)cellOriginAtIndex:(NSUInteger)index;
- (NSSize)cellSize;

@end
