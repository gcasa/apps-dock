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

#import <AppKit/AppKit.h>

@class DockItem;

typedef enum
  {
    DockBackgroundBlack = 0,
    DockBackgroundSimulatedTransparency
  } DockBackgroundMode;

@protocol DockViewDelegate
- (void) dockViewDidReceivePaths: (NSArray *)paths;
- (void) dockViewDidReceivePaths: (NSArray *)paths
			 atIndex: (NSUInteger)index;
- (void) dockViewDidReceivePathsInRecycler: (NSArray *)paths;
- (void) dockViewDidActivateItem: (DockItem *)item;
- (void) dockViewDidActivateTopIcon;
- (void) dockViewDidMoveItemFromIndex: (NSUInteger)fromIndex
                              toIndex: (NSUInteger)toIndex;
- (void) dockViewDidRemoveItemAtIndex: (NSUInteger)index;
- (BOOL) dockView: (id)dockView itemIsOpenAtLogin: (DockItem *)item;
- (void) dockView: (id)dockView didToggleOpenAtLoginForItem: (DockItem *)item;
- (void) dockView: (id)dockView didShowItemInFileViewer: (DockItem *)item;
- (void) dockView: (id)dockView didQuitItem: (DockItem *)item;
- (void) dockViewDidEmptyRecycler: (id)dockView;
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
  NSColor *_backgroundColor;
  DockBackgroundMode _backgroundMode;
  BOOL _recyclerHasContents;
  BOOL _horizontal;
  NSTimer *_tooltipTimer;
  NSTimer *_wiggleTimer;
  NSTimer *_recyclerWiggleTimer;
  DockItem *_wiggleItem;
  NSTimeInterval _wiggleStartTime;
  NSTimeInterval _recyclerWiggleStartTime;
  NSInteger _hoveredItemIndex;
  NSInteger _tooltipItemIndex;
  NSTrackingRectTag _trackingRectTag;
  NSPoint _mouseDownPoint;
  NSUInteger _mouseDownItemIndex;
  NSUInteger _draggedItemIndex;
  NSUInteger _dropIndex;
  NSUInteger _pinnedItemCount;
  NSUInteger _lastMouseDownIndex;
  NSTimeInterval _lastMouseDownTime;
}

- (void) setDelegate: (id)delegate;
- (void) setItems: (NSArray *)items;
- (void) setPinnedItemCount: (NSUInteger)count;
- (void) setBackgroundImage: (NSImage *)image;
- (void) setBackgroundColor: (NSColor *)color;
- (void) setBackgroundMode: (DockBackgroundMode)mode;
- (void) setRecyclerHasContents: (BOOL)hasContents;
- (void) startWiggleForItem: (DockItem *)item;
- (void) startRecyclerWiggle;
- (void) setHorizontal: (BOOL)horizontal;
- (BOOL) isHorizontal;
- (NSRect) topTileRect;
- (NSRect) recyclerTileRect;
- (NSPoint) cellOriginAtIndex: (NSUInteger)index;
- (NSSize) cellSize;

@end
