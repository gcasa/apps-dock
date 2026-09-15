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

#import "DockViewPrivate.h"

@implementation DockView

- (id) initWithFrame: (NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self)
    {
      _items = [NSMutableArray new];
      _draggingPaths = NO;
      _performedDragOperation = NO;
      _lastMouseDownIndex = NSNotFound;
      _lastMouseDownTime = 0.0;
      _hoveredItemIndex = DockHoverNone;
      _tooltipItemIndex = DockHoverNone;
      _trackingRectTag = 0;
      _mouseDownItemIndex = NSNotFound;
      _draggedItemIndex = NSNotFound;
      _dropIndex = NSNotFound;
      _pinnedItemCount = 0;
      _backgroundColor = RETAIN([NSColor blackColor]);
      _backgroundAlpha = 1.0;
      _cellSize = DockCell;
      _dockGap = DockGap;
      _dockPad = DockPad;
      _hoverIconScale = 1.2;
      _runningIndicatorMode = DockRunningIndicatorModeRunningDot;
      _gnustepIcon = RETAIN([self loadGNUstepIcon]);
      _recyclerIcon = RETAIN([self loadRecyclerIcon]);
      _cellBackgroundImage = RETAIN([self loadCellBackgroundImage]);
      [self registerForDraggedTypes:
	      [NSArray arrayWithObjects:NSFilenamesPboardType,
		       NSURLPboardType,
		       NSStringPboardType,
		       @"text/uri-list",
		       @"text/plain",
		       DockReorderPboardType,
		       GWRemoteFilenamesPboardType,
		       GWLSFolderPboardType,
		       GWDockIconPboardType,
		       nil]];
    }
  return self;
}

- (void) dealloc
{
  [_tooltipTimer invalidate];
  DESTROY(_tooltipTimer);
  [_wiggleTimer invalidate];
  DESTROY(_wiggleTimer);
  [_recyclerWiggleTimer invalidate];
  DESTROY(_recyclerWiggleTimer);
  DESTROY(_wiggleItem);
  if (_trackingRectTag)
    {
      [self removeTrackingRect:_trackingRectTag];
    }
  DESTROY(_backgroundColor);
  DESTROY(_cellBackgroundImage);
  DESTROY(_gnustepIcon);
  DESTROY(_recyclerIcon);
  DESTROY(_items);
  DEALLOC;
}

- (NSImage *) loadGNUstepIcon
{
  NSString *path = [[NSBundle mainBundle] pathForResource:@"GNUstep_circle"
                                                   ofType:@"png"];
  NSImage *image;

  image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile:path]);
  return image;
}

- (NSImage *) loadRecyclerIcon
{
  NSString *path = [[NSBundle mainBundle] pathForResource:@"Recycler.GNUstep"
                                                   ofType:@"xpm"];
  NSImage *image;

  image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile:path]);
  if (image)
    {
      return image;
    }

  return nil;
}

- (NSImage *) loadCellBackgroundImage
{
  return [NSImage imageNamed:@"common_Tile"];
}

- (void) updateTrackingRect
{
  if (_trackingRectTag)
    {
      [self removeTrackingRect:_trackingRectTag];
      _trackingRectTag = 0;
    }

  _trackingRectTag = [self addTrackingRect:[self bounds]
                                     owner:self
                                  userData:NULL
                              assumeInside:NO];
}

- (void) viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self updateTrackingRect];
}

- (void) setFrame: (NSRect)frame
{
  [super setFrame:frame];
  [self updateTrackingRect];
}

- (void) setDelegate: (id)delegate
{
  _delegate = delegate;
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (BOOL) isOpaque
{
  return NO;
}

- (void) setItems: (NSArray *)items
{
  [_items setArray:items];
  if (_pinnedItemCount > [_items count])
    {
      _pinnedItemCount = [_items count];
    }
  [self hideTooltip];
  [self setNeedsDisplay:YES];
}

- (void) setPinnedItemCount: (NSUInteger)count
{
  if (count > [_items count])
    {
      count = [_items count];
    }

  if (_pinnedItemCount != count)
    {
      _pinnedItemCount = count;
      [self setNeedsDisplay:YES];
    }
}









- (void) setBackgroundColor: (NSColor *)color
{
  color = DockViewCalibratedBackgroundColor(color);

  if (_backgroundColor != color)
    {
      ASSIGN(_backgroundColor, color);
      [self setNeedsDisplay:YES];
    }
}

- (void) setBackgroundAlpha: (CGFloat)alpha
{
  if (alpha < 0.0)
    {
      alpha = 0.0;
    }
  else if (alpha > 1.0)
    {
      alpha = 1.0;
    }

  if (_backgroundAlpha != alpha)
    {
      _backgroundAlpha = alpha;
      [self setNeedsDisplay:YES];
    }
}

- (void) setShowsBorder: (BOOL)showsBorder
{
  if (_showsBorder != showsBorder)
    {
      _showsBorder = showsBorder;
      [self setNeedsDisplay:YES];
    }
}

- (BOOL) showsBorder
{
  return _showsBorder;
}

- (void) setRunningIndicatorMode: (DockRunningIndicatorMode)mode
{
  if (mode != DockRunningIndicatorModeNotRunningDots)
    {
      mode = DockRunningIndicatorModeRunningDot;
    }

  if (_runningIndicatorMode != mode)
    {
      _runningIndicatorMode = mode;
      [self setNeedsDisplay:YES];
    }
}

- (DockRunningIndicatorMode) runningIndicatorMode
{
  return _runningIndicatorMode;
}

- (void) setRecyclerHasContents: (BOOL)hasContents
{
  if (_recyclerHasContents != hasContents)
    {
      _recyclerHasContents = hasContents;
      [self setNeedsDisplay:YES];
    }
}

- (void) setIconCellSize: (CGFloat)cellSize
		     gap: (CGFloat)gap
		 padding: (CGFloat)padding
{
  if (cellSize <= 0.0)
    {
      cellSize = DockCell;
    }
  if (gap < 0.0)
    {
      gap = 0.0;
    }
  if (padding < 0.0)
    {
      padding = 0.0;
    }

  if (_cellSize != cellSize || _dockGap != gap || _dockPad != padding)
    {
      _cellSize = cellSize;
      _dockGap = gap;
      _dockPad = padding;
      [self setNeedsDisplay:YES];
    }
}

- (void) setMagnifiesHoveredIcons: (BOOL)magnifies
{
  if (_magnifiesHoveredIcons != magnifies)
    {
      _magnifiesHoveredIcons = magnifies;
      [self setNeedsDisplay:YES];
    }
}

- (BOOL) magnifiesHoveredIcons
{
  return _magnifiesHoveredIcons;
}

- (void) setHoverIconScale: (CGFloat)scale
{
  if (scale < 1.0)
    {
      scale = 1.0;
    }
  else if (scale > 1.5)
    {
      scale = 1.5;
    }

  if (_hoverIconScale != scale)
    {
      _hoverIconScale = scale;
      [self setNeedsDisplay:YES];
    }
}

- (CGFloat) hoverIconScale
{
  return _hoverIconScale;
}

- (void) setSingleClickLaunchesApplications: (BOOL)singleClickLaunches
{
  _singleClickLaunchesApplications = singleClickLaunches;
  _lastMouseDownIndex = NSNotFound;
  _lastMouseDownTime = 0.0;
}

- (BOOL) singleClickLaunchesApplications
{
  return _singleClickLaunchesApplications;
}

- (void) setUsesCellBackgroundTile: (BOOL)usesTile
{
  if (_usesCellBackgroundTile != usesTile)
    {
      _usesCellBackgroundTile = usesTile;
      [self setNeedsDisplay:YES];
    }
}

- (BOOL) usesCellBackgroundTile
{
  return _usesCellBackgroundTile;
}

- (void) setHorizontal: (BOOL)horizontal
{
  if (_horizontal != horizontal)
    {
      _horizontal = horizontal;
      [self setNeedsDisplay:YES];
    }
}

- (BOOL) isHorizontal
{
  return _horizontal;
}



































































@end
