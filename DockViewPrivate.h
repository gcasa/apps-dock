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

#import "DockView.h"
#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>
#import <math.h>

#define DockCell 64.0
#define DockGap 2.0
#define DockPad 10.0
#define DockSeparatorInset 12.0
#define DockWiggleDuration 0.8
#define DockAttentionWiggleInterval 2.0
#define GWRemoteFilenamesPboardType @"GWRemoteFilenamesPboardType"
#define GWLSFolderPboardType @"GWLSFolderPboardType"
#define GWDockIconPboardType @"DockIconPboardType"
#define DockReorderPboardType @"DockWMReorderPboardType"
#define DockTopIconClickIndex (NSUIntegerMax - 1)
#define DockRecyclerClickIndex (NSUIntegerMax - 2)
#define DockHoverNone -1
#define DockHoverTopIcon -2
#define DockHoverRecycler -3

static inline NSColor *
DockViewCalibratedBackgroundColor(NSColor *color)
{
  NSColor *rgbColor = nil;
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  if (!color)
    {
      return [NSColor blackColor];
    }

  NS_DURING
    rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (!rgbColor)
    {
      rgbColor = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
  if (rgbColor)
    {
      [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
    }
  NS_HANDLER
    rgbColor = nil;
  NS_ENDHANDLER

    if (!rgbColor)
      {
	return [NSColor blackColor];
      }

  return [NSColor colorWithCalibratedRed:red
                                   green:green
                                    blue:blue
                                   alpha:alpha];
}

@interface DockView (Private)
- (id) initWithFrame: (NSRect)frame;
- (void) dealloc;
- (NSImage *) loadGNUstepIcon;
- (NSImage *) loadRecyclerIcon;
- (NSImage *) standardRecyclerIcon;
- (NSImage *) loadCellBackgroundImage;
- (void) updateTrackingRect;
- (void) viewDidMoveToWindow;
- (void) setFrame: (NSRect)frame;
- (void) setDelegate: (id)delegate;
- (BOOL) acceptsFirstMouse: (NSEvent *)event;
- (BOOL) isOpaque;
- (void) setItems: (NSArray *)items;
- (void) setPinnedItemCount: (NSUInteger)count;
- (void) stopWiggle;
- (void) stepWiggle: (NSTimer *)timer;
- (void) startWiggleForItem: (DockItem *)item;
- (void) startAttentionWiggleForItem: (DockItem *)item;
- (void) acknowledgeWiggleForItem: (DockItem *)item;
- (void) stopRecyclerWiggle;
- (void) stepRecyclerWiggle: (NSTimer *)timer;
- (void) startRecyclerWiggle;
- (void) setBackgroundColor: (NSColor *)color;
- (void) setBackgroundAlpha: (CGFloat)alpha;
- (void) setShowsBorder: (BOOL)showsBorder;
- (BOOL) showsBorder;
- (void) setRunningIndicatorMode: (DockRunningIndicatorMode)mode;
- (DockRunningIndicatorMode) runningIndicatorMode;
- (void) setRecyclerHasContents: (BOOL)hasContents;
- (void) setIconCellSize: (CGFloat)cellSize
		     gap: (CGFloat)gap
		 padding: (CGFloat)padding;
- (void) setMagnifiesHoveredIcons: (BOOL)magnifies;
- (BOOL) magnifiesHoveredIcons;
- (void) setHoverIconScale: (CGFloat)scale;
- (CGFloat) hoverIconScale;
- (void) setSingleClickLaunchesApplications: (BOOL)singleClickLaunches;
- (BOOL) singleClickLaunchesApplications;
- (void) setUsesCellBackgroundTile: (BOOL)usesTile;
- (BOOL) usesCellBackgroundTile;
- (void) setHorizontal: (BOOL)horizontal;
- (BOOL) isHorizontal;
- (NSSize) cellSize;
- (NSRect) topTileRect;
- (NSPoint) cellOriginAtIndex: (NSUInteger)index;
- (NSRect) recyclerTileRect;
- (NSUInteger) indexAtPoint: (NSPoint)p;
- (BOOL) recyclerContainsPoint: (NSPoint)p;
- (NSUInteger) insertionIndexAtPoint: (NSPoint)p;
- (NSUInteger) pinnedInsertionIndexAtPoint: (NSPoint)p;
- (NSUInteger) reorderInsertionIndexAtPoint: (NSPoint)p
                                  fromIndex: (NSUInteger)fromIndex;
- (BOOL) topIconContainsPoint: (NSPoint)p;
- (NSInteger) hoverIndexAtPoint: (NSPoint)p;
- (NSRect) cellRectForHoverIndex: (NSInteger)index;
- (NSString *) tooltipTitleForHoverIndex: (NSInteger)index;
- (void) hideTooltip;
- (NSMenuItem *) menuItemWithTitle: (NSString *)title
                            action: (SEL)action
                              item: (DockItem *)item;
- (NSMenu *) menuForDockItem: (DockItem *)item;
- (NSMenu *) menuForRecycler;
- (void) toggleOpenAtLogin: (id)sender;
- (void) showItemInFileViewer: (id)sender;
- (void) showItemSettings: (id)sender;
- (void) quitItem: (id)sender;
- (void) emptyRecycler: (id)sender;
- (void) scheduleTooltipForHoverIndex: (NSInteger)index;
- (void) drawTooltip;
- (void) showTooltip: (NSTimer *)timer;
- (NSArray *) pathsFromPasteboard: (NSPasteboard *)pb;
- (BOOL) pasteboardHasSupportedType: (NSPasteboard *)pb;
- (void) addPathsFromPasteboardObject: (id)object toArray: (NSMutableArray *)paths;
- (void) addPathsFromPasteboardString: (NSString *)string toArray: (NSMutableArray *)paths;
- (NSDragOperation) dragOperationForSender: (id <NSDraggingInfo>)sender;
- (BOOL) pasteboardHasReorderType: (NSPasteboard *)pb;
- (BOOL) drawImage: (NSImage *)image
	    inCell: (NSRect)cell
	      size: (CGFloat)size
	     angle: (CGFloat)angle;
- (NSRect) iconRectInCell: (NSRect)cell size: (CGFloat)size;
- (CGFloat) iconSizeForItemAtIndex: (NSUInteger)index;
- (void) drawCellBackgroundInCell: (NSRect)cell;
- (BOOL) drawImage: (NSImage *)image inCell: (NSRect)cell size: (CGFloat)size;
- (void) drawFallbackIconForItem: (DockItem *)item inCell: (NSRect)cell;
- (void) drawBadgeForItem: (DockItem *)item inCell: (NSRect)cell iconSize: (CGFloat)size;
- (void) drawDockTileForItem: (DockItem *)item inCell: (NSRect)cell size: (CGFloat)size;
- (void) drawStateForItem: (DockItem *)item inCell: (NSRect)cell;
- (void) drawTopTile;
- (void) drawRecyclerFallbackInCell: (NSRect)cell;
- (void) drawRecyclerContentsIndicatorInCell: (NSRect)cell;
- (void) drawRecyclerTile;
- (void) drawDropIndicator;
- (void) drawSeparatorBeforeIndex: (NSUInteger)index;
- (void) drawDockSeparators;
- (void) drawDockBorder;
- (void) drawRect: (NSRect)dirtyRect;
- (void) mouseMoved: (NSEvent *)event;
- (void) mouseExited: (NSEvent *)event;
- (void) rightMouseDown: (NSEvent *)event;
- (NSImage *) dragImageForItemAtIndex: (NSUInteger)index;
- (void) mouseDragged: (NSEvent *)event;
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL)isLocal;
- (BOOL) screenPointIsInsideDock: (NSPoint)screenPoint;
- (void) finishDraggingItemWithRemove: (BOOL)remove;
- (void) draggedImage: (NSImage *)image
	      endedAt: (NSPoint)screenPoint
	    operation: (NSDragOperation)operation;
- (void) draggedImage: (NSImage *)image
	      endedAt: (NSPoint)screenPoint
	    deposited: (BOOL)flag;
- (NSDragOperation) draggingEntered: (id <NSDraggingInfo>)sender;
- (NSDragOperation) draggingUpdated: (id <NSDraggingInfo>)sender;
- (void) draggingExited: (id <NSDraggingInfo>)sender;
- (BOOL) prepareForDragOperation: (id <NSDraggingInfo>)sender;
- (BOOL) performDragOperation: (id <NSDraggingInfo>)sender;
- (void) concludeDragOperation: (id <NSDraggingInfo>)sender;
- (void) mouseDown: (NSEvent *)event;
@end
