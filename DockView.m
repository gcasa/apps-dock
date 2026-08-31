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

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;
static CGFloat DockSeparatorInset = 12.0;
static NSTimeInterval DockWiggleDuration = 0.8;

static NSString *GWRemoteFilenamesPboardType = @"GWRemoteFilenamesPboardType";
static NSString *GWLSFolderPboardType = @"GWLSFolderPboardType";
static NSString *GWDockIconPboardType = @"DockIconPboardType";
static NSString *DockReorderPboardType = @"DockWMReorderPboardType";
static NSUInteger DockTopIconClickIndex = NSUIntegerMax - 1;
static NSUInteger DockRecyclerClickIndex = NSUIntegerMax - 2;
static NSInteger DockHoverNone = -1;
static NSInteger DockHoverTopIcon = -2;
static NSInteger DockHoverRecycler = -3;

static NSColor *
DockViewCalibratedBackgroundColor (NSColor *color)
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
      _cellSize = DockCell;
      _dockGap = DockGap;
      _dockPad = DockPad;
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

- (void) stopWiggle
{
  [_wiggleTimer invalidate];
  DESTROY(_wiggleTimer);
  DESTROY(_wiggleItem);
  _wiggleStartTime = 0.0;
  [self setNeedsDisplay:YES];
}

- (void) stepWiggle: (NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if (!_wiggleItem || now - _wiggleStartTime >= DockWiggleDuration)
    {
      [self stopWiggle];
      return;
    }

  [self setNeedsDisplay:YES];
}

- (void) startWiggleForItem: (DockItem *)item
{
  if (!item)
    {
      return;
    }

  [_wiggleTimer invalidate];
  DESTROY(_wiggleTimer);
  ASSIGN(_wiggleItem, item);
  _wiggleStartTime = [NSDate timeIntervalSinceReferenceDate];
  _wiggleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(stepWiggle:)
                                                userInfo:nil
						 repeats:YES];
  _wiggleTimer = RETAIN(_wiggleTimer);
  [self setNeedsDisplay:YES];
}

- (void) stopRecyclerWiggle
{
  [_recyclerWiggleTimer invalidate];
  DESTROY(_recyclerWiggleTimer);
  _recyclerWiggleStartTime = 0.0;
  [self setNeedsDisplay:YES];
}

- (void) stepRecyclerWiggle: (NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if (!_recyclerWiggleStartTime ||
      now - _recyclerWiggleStartTime >= DockWiggleDuration)
    {
      [self stopRecyclerWiggle];
      return;
    }

  [self setNeedsDisplay:YES];
}

- (void) startRecyclerWiggle
{
  [_recyclerWiggleTimer invalidate];
  DESTROY(_recyclerWiggleTimer);
  _recyclerWiggleStartTime = [NSDate timeIntervalSinceReferenceDate];
  _recyclerWiggleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                          target:self
                                                        selector:@selector(stepRecyclerWiggle:)
                                                        userInfo:nil
                                                         repeats:YES];
  _recyclerWiggleTimer = RETAIN(_recyclerWiggleTimer);
  [self setNeedsDisplay:YES];
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

- (NSSize) cellSize
{
  return NSMakeSize(_cellSize, _cellSize);
}

- (NSRect) topTileRect
{
  NSRect bounds = [self bounds];
  if (_horizontal)
    {
      return NSMakeRect(_dockPad,
			_dockPad,
			_cellSize,
			_cellSize);
    }
  else
    {
      return NSMakeRect(_dockPad,
			NSMaxY(bounds) - _dockPad - _cellSize,
			_cellSize,
			_cellSize);
    }
}

- (NSPoint) cellOriginAtIndex: (NSUInteger)index
{
  NSRect topTile = [self topTileRect];
  if (_horizontal)
    {
      return NSMakePoint(NSMaxX(topTile) + _dockGap + index * (_cellSize + _dockGap),
			 NSMinY(topTile));
    }
  else
    {
      return NSMakePoint(_dockPad,
			 NSMinY(topTile) - _dockGap - _cellSize
			 - index * (_cellSize + _dockGap));
    }
}

- (NSRect) recyclerTileRect
{
  NSPoint origin = [self cellOriginAtIndex:[_items count]];
  return NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);
}

- (NSUInteger) indexAtPoint: (NSPoint)p
{
  NSUInteger i;
  for (i = 0; i < [_items count]; i++)
    {
      NSRect r = NSMakeRect([self cellOriginAtIndex:i].x,
			    [self cellOriginAtIndex:i].y,
			    _cellSize, _cellSize);
      if (NSPointInRect(p, r))
	{
	  return i;
	}
    }
  return NSNotFound;
}

- (BOOL) recyclerContainsPoint: (NSPoint)p
{
  return NSPointInRect(p, [self recyclerTileRect]);
}

- (NSUInteger) insertionIndexAtPoint: (NSPoint)p
{
  NSUInteger i;

  if (![_items count])
    {
      return 0;
    }

  for (i = 0; i < [_items count]; i++)
    {
      NSPoint origin = [self cellOriginAtIndex:i];
      NSRect cell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);

      if (_horizontal)
	{
	  if (p.x < NSMidX(cell))
	    {
	      return i;
	    }
	}
      else
	{
	  if (p.y > NSMidY(cell))
	    {
	      return i;
	    }
	}
    }

  return [_items count];
}

- (NSUInteger) pinnedInsertionIndexAtPoint: (NSPoint)p
{
  NSUInteger index = [self insertionIndexAtPoint:p];

  return MIN(index, _pinnedItemCount);
}

- (NSUInteger) reorderInsertionIndexAtPoint: (NSPoint)p
                                  fromIndex: (NSUInteger)fromIndex
{
  NSUInteger index = [self insertionIndexAtPoint:p];

  if (fromIndex < _pinnedItemCount)
    {
      return MIN(index, _pinnedItemCount);
    }

  return index;
}

- (BOOL) topIconContainsPoint: (NSPoint)p
{
  return NSPointInRect(p, [self topTileRect]);
}

- (NSInteger) hoverIndexAtPoint: (NSPoint)p
{
  NSUInteger index;

  if ([self topIconContainsPoint:p])
    {
      return DockHoverTopIcon;
    }

  if ([self recyclerContainsPoint:p])
    {
      return DockHoverRecycler;
    }

  index = [self indexAtPoint:p];
  return index == NSNotFound ? DockHoverNone : (NSInteger)index;
}

- (NSRect) cellRectForHoverIndex: (NSInteger)index
{
  if (index == DockHoverTopIcon)
    {
      return [self topTileRect];
    }

  if (index == DockHoverRecycler)
    {
      return [self recyclerTileRect];
    }

  if (index >= 0 && index < (NSInteger)[_items count])
    {
      NSPoint origin = [self cellOriginAtIndex: (NSUInteger)index];
      return NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);
    }

  return NSZeroRect;
}

- (NSString *) tooltipTitleForHoverIndex: (NSInteger)index
{
  if (index == DockHoverTopIcon)
    {
      return @"DockWM";
    }

  if (index == DockHoverRecycler)
    {
      return @"Recycler";
    }

  if (index >= 0 && index < (NSInteger)[_items count])
    {
      DockItem *item = [_items objectAtIndex: (NSUInteger)index];
      return [[item title] length] ? [item title] : [[item path] lastPathComponent];
    }

  return nil;
}

- (void) hideTooltip
{
  [_tooltipTimer invalidate];
  DESTROY(_tooltipTimer);
  if (_tooltipItemIndex != DockHoverNone)
    {
      _tooltipItemIndex = DockHoverNone;
      [self setNeedsDisplay:YES];
    }
}

- (NSMenuItem *) menuItemWithTitle: (NSString *)title
                            action: (SEL)action
                              item: (DockItem *)item
{
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:title
						    action:action
					     keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menuItem setRepresentedObject:item];
  return menuItem;
}

- (NSMenu *) menuForDockItem: (DockItem *)item
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Application"]);
  NSMenuItem *menuItem;
  BOOL hasPath = [[item path] length] > 0;
  BOOL openAtLogin = NO;

  if ([_delegate respondsToSelector:
		 @selector(dockView:itemIsOpenAtLogin:)])
    {
      openAtLogin = [_delegate dockView:self itemIsOpenAtLogin:item];
    }

  menuItem = [self menuItemWithTitle:@"Open At Login"
                              action:@selector(toggleOpenAtLogin:)
                                item:item];
  [menuItem setState: (openAtLogin ? NSOnState : NSOffState)];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Show In File Viewer"
                              action:@selector(showItemInFileViewer:)
                                item:item];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Quit"
                              action:@selector(quitItem:)
                                item:item];
  [menu addItem:menuItem];

  return menu;
}

- (NSMenu *) menuForRecycler
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Recycler"]);
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:@"Empty Recycler"
                                                    action:@selector(emptyRecycler:)
                                             keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menu addItem:menuItem];
  return menu;
}

- (void) toggleOpenAtLogin: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didToggleOpenAtLoginForItem:)])
    {
      [_delegate dockView:self didToggleOpenAtLoginForItem:item];
    }
}

- (void) showItemInFileViewer: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didShowItemInFileViewer:)])
    {
      [_delegate dockView:self didShowItemInFileViewer:item];
    }
}

- (void) quitItem: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:@selector(dockView:didQuitItem:)])
    {
      [_delegate dockView:self didQuitItem:item];
    }
}

- (void) emptyRecycler: (id)sender
{
  if ([_delegate respondsToSelector:@selector(dockViewDidEmptyRecycler:)])
    {
      [_delegate dockViewDidEmptyRecycler:self];
    }
}

- (void) scheduleTooltipForHoverIndex: (NSInteger)index
{
  [_tooltipTimer invalidate];
  DESTROY(_tooltipTimer);
  _tooltipItemIndex = DockHoverNone;

  if (index == DockHoverNone)
    {
      [self setNeedsDisplay:YES];
      return;
    }

  _tooltipTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                   target:self
                                                 selector:@selector(showTooltip:)
                                                 userInfo:nil
						  repeats:NO];
  _tooltipTimer = RETAIN(_tooltipTimer);
  [self setNeedsDisplay:YES];
}

- (void) drawTooltip
{
  NSString *title = [self tooltipTitleForHoverIndex:_tooltipItemIndex];
  NSRect cell;
  NSDictionary *attrs;
  NSSize textSize;
  CGFloat padX = 7.0;
  CGFloat padY = 4.0;
  NSRect tooltipRect;
  NSPoint textPoint;
  NSRect bounds = [self bounds];

  if (![title length])
    {
      return;
    }

  cell = [self cellRectForHoverIndex:_tooltipItemIndex];
  if (NSIsEmptyRect(cell))
    {
      return;
    }

  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
			    [NSFont systemFontOfSize:11.0], NSFontAttributeName,
			[NSColor whiteColor], NSForegroundColorAttributeName,
			nil];
  textSize = [title sizeWithAttributes:attrs];

  tooltipRect = NSMakeRect(0.0, 0.0,
                           textSize.width + padX * 2.0,
                           textSize.height + padY * 2.0);
  if (_horizontal)
    {
      tooltipRect.origin.x = NSMidX(cell) - NSWidth(tooltipRect) / 2.0;
      tooltipRect.origin.y = NSMaxY(cell) - NSHeight(tooltipRect) - 2.0;
    }
  else
    {
      tooltipRect.origin.x = NSMaxX(cell) - NSWidth(tooltipRect) - 2.0;
      tooltipRect.origin.y = NSMidY(cell) - NSHeight(tooltipRect) / 2.0;
    }

  if (NSMinX(tooltipRect) < NSMinX(bounds) + 2.0)
    {
      tooltipRect.origin.x = NSMinX(bounds) + 2.0;
    }
  if (NSMaxX(tooltipRect) > NSMaxX(bounds) - 2.0)
    {
      tooltipRect.origin.x = NSMaxX(bounds) - NSWidth(tooltipRect) - 2.0;
    }
  if (NSMinY(tooltipRect) < NSMinY(bounds) + 2.0)
    {
      tooltipRect.origin.y = NSMinY(bounds) + 2.0;
    }
  if (NSMaxY(tooltipRect) > NSMaxY(bounds) - 2.0)
    {
      tooltipRect.origin.y = NSMaxY(bounds) - NSHeight(tooltipRect) - 2.0;
    }

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.82] set];
  [[NSBezierPath bezierPathWithRoundedRect:tooltipRect
                                   xRadius:4.0
                                   yRadius:4.0] fill];

  textPoint = NSMakePoint(NSMinX(tooltipRect) + padX,
                          NSMinY(tooltipRect) + padY);
  [title drawAtPoint:textPoint withAttributes:attrs];
}

- (void) showTooltip: (NSTimer *)timer
{
  DESTROY(_tooltipTimer);

  if (_hoveredItemIndex != DockHoverNone)
    {
      _tooltipItemIndex = _hoveredItemIndex;
      [self setNeedsDisplay:YES];
    }
}

- (NSArray *) pathsFromPasteboard: (NSPasteboard *)pb
{
  NSArray *types = [pb types];
  NSArray *paths;
  NSMutableArray *collectedPaths = [NSMutableArray array];
  NSString *string;
  NSURL *url;
  NSUInteger i;

  if ([types containsObject:NSFilenamesPboardType])
    {
      paths = [pb propertyListForType:NSFilenamesPboardType];
      if ([paths count])
	{
	  return paths;
	}
    }

  if ([types containsObject:NSURLPboardType])
    {
      url = [NSURL URLFromPasteboard:pb];
      if ([url isFileURL] && [[url path] length])
	{
	  return [NSArray arrayWithObject:[url path]];
	}
    }

  if ([types containsObject:GWRemoteFilenamesPboardType])
    {
      NSData *data = [pb dataForType:GWRemoteFilenamesPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
				     toArray:collectedPaths];
	}
    }

  if ([types containsObject:GWLSFolderPboardType])
    {
      NSData *data = [pb dataForType:GWLSFolderPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
				     toArray:collectedPaths];
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"path"]
				     toArray:collectedPaths];
	}
    }

  if ([types containsObject:GWDockIconPboardType])
    {
      NSData *data = [pb dataForType:GWDockIconPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"path"]
				     toArray:collectedPaths];
	}
    }

  for (i = 0; i < [types count]; i++)
    {
      NSString *type = [types objectAtIndex:i];
      id plist = [pb propertyListForType:type];

      [self addPathsFromPasteboardObject:plist toArray:collectedPaths];

      string = [pb stringForType:type];
      if ([string length])
	{
	  [self addPathsFromPasteboardString:string toArray:collectedPaths];
	}
    }

  if ([collectedPaths count])
    {
      return collectedPaths;
    }

  return nil;
}

- (BOOL) pasteboardHasSupportedType: (NSPasteboard *)pb
{
  NSArray *supportedTypes = [NSArray arrayWithObjects:NSFilenamesPboardType,
				     NSURLPboardType,
				     NSStringPboardType,
				     @"text/uri-list",
				     @"text/plain",
				     GWRemoteFilenamesPboardType,
				     GWLSFolderPboardType,
				     GWDockIconPboardType,
				     nil];
  return [pb availableTypeFromArray:supportedTypes] != nil;
}

- (void) addPathsFromPasteboardObject: (id)object toArray: (NSMutableArray *)paths
{
  if ([object isKindOfClass:[NSString class]])
    {
      [self addPathsFromPasteboardString:object toArray:paths];
    }
  else if ([object isKindOfClass:[NSArray class]])
    {
      NSUInteger i;
      for (i = 0; i < [object count]; i++)
	{
	  [self addPathsFromPasteboardObject:[object objectAtIndex:i] toArray:paths];
	}
    }
  else if ([object isKindOfClass:[NSDictionary class]])
    {
      NSEnumerator *enumerator = [object objectEnumerator];
      id value;

      while ((value = [enumerator nextObject]))
	{
	  [self addPathsFromPasteboardObject:value toArray:paths];
	}
    }
}

- (void) addPathsFromPasteboardString: (NSString *)string toArray: (NSMutableArray *)paths
{
  NSArray *lines;
  NSUInteger i;

  if (![string length])
    {
      return;
    }

  lines = [string componentsSeparatedByCharactersInSet:
		    [NSCharacterSet newlineCharacterSet]];

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [[lines objectAtIndex:i]
			    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSString *path = nil;

      if (![line length] || [line hasPrefix:@"#"])
	{
	  continue;
	}

      if ([line hasPrefix:@"\""] && [line hasSuffix:@"\""] && [line length] > 1)
	{
	  line = [line substringWithRange:NSMakeRange(1, [line length] - 2)];
	}

      if ([line hasPrefix:@"file:"])
	{
	  NSURL *fileURL = [NSURL URLWithString:line];
	  if ([fileURL isFileURL])
	    {
	      path = [fileURL path];
	    }
	}
      else if ([line isAbsolutePath])
	{
	  path = line;
	}

      if ([path length] && ![paths containsObject:path])
	{
	  [paths addObject:path];
	}
    }
}

- (NSDragOperation) dragOperationForSender: (id <NSDraggingInfo>)sender
{
  return NSDragOperationEvery;
}

- (BOOL) pasteboardHasReorderType: (NSPasteboard *)pb
{
  return [[pb types] containsObject:DockReorderPboardType];
}

- (BOOL) drawImage: (NSImage *)image
	    inCell: (NSRect)cell
	      size: (CGFloat)size
	     angle: (CGFloat)angle
{
  NSSize imageSize;
  NSRect sourceRect;
  NSRect destRect;

  if (!image || (![[image representations] count] && ![image isValid]))
    {
      return NO;
    }

  imageSize = [image size];
  if (imageSize.width <= 0.0 || imageSize.height <= 0.0)
    {
      NSImageRep *rep = [[image representations] count]
	? [[image representations] objectAtIndex:0] : nil;
      if (rep)
	{
	  imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
	  [image setSize:imageSize];
	}
    }

  if (imageSize.width <= 0.0 || imageSize.height <= 0.0)
    {
      return NO;
    }

  sourceRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);
  destRect = NSMakeRect(NSMidX(cell) - size / 2.0,
                        NSMidY(cell) - size / 2.0,
                        size,
                        size);

  if (angle != 0.0)
    {
      NSAffineTransform *transform = [NSAffineTransform transform];

      [NSGraphicsContext saveGraphicsState];
      [transform translateXBy:NSMidX(destRect) yBy:NSMidY(destRect)];
      [transform rotateByDegrees:angle];
      [transform translateXBy:-NSMidX(destRect) yBy:-NSMidY(destRect)];
      [transform concat];
    }

  [image drawInRect:destRect
           fromRect:sourceRect
          operation:NSCompositeSourceOver
           fraction:1.0];
  if (angle != 0.0)
    {
      [NSGraphicsContext restoreGraphicsState];
    }
  return YES;
}

- (void) drawCellBackgroundInCell: (NSRect)cell
{
  NSSize imageSize;
  NSRect sourceRect;

  if (!_usesCellBackgroundTile || !_cellBackgroundImage)
    {
      return;
    }

  imageSize = [_cellBackgroundImage size];
  if (imageSize.width <= 0.0 || imageSize.height <= 0.0)
    {
      NSImageRep *rep = [[_cellBackgroundImage representations] count]
	? [[_cellBackgroundImage representations] objectAtIndex:0] : nil;
      if (!rep)
	{
	  return;
	}
      imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
      [_cellBackgroundImage setSize:imageSize];
    }

  sourceRect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);
  [_cellBackgroundImage drawInRect:cell
			  fromRect:sourceRect
			 operation:NSCompositeSourceOver
			  fraction:1.0];
}

- (BOOL) drawImage: (NSImage *)image inCell: (NSRect)cell size: (CGFloat)size
{
  return [self drawImage:image inCell:cell size:size angle:0.0];
}

- (void) drawFallbackIconForItem: (DockItem *)item inCell: (NSRect)cell
{
  NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
				      [NSFont boldSystemFontOfSize:18], NSFontAttributeName,
				 [NSColor colorWithCalibratedWhite:0.95 alpha:1.0], NSForegroundColorAttributeName,
				      nil];
  NSString *title = [[item title] length] ? [item title] : @"?";
  NSString *label = [[title substringToIndex:MIN((NSUInteger)2, [title length])] uppercaseString];
  NSSize size = [label sizeWithAttributes:attrs];

  [label drawAtPoint:NSMakePoint(NSMidX(cell) - size.width / 2.0,
                                 NSMidY(cell) - size.height / 2.0)
      withAttributes:attrs];
}

- (void) drawBadgeForItem: (DockItem *)item inCell: (NSRect)cell iconSize: (CGFloat)size
{
  NSString *badgeLabel = [item badgeLabel];
  NSString *displayString = badgeLabel;
  NSDictionary *attrs;
  NSSize textSize;
  NSSize badgeSize;
  NSRect iconRect;
  NSRect badgeRect;
  CGFloat pad;
  CGFloat minSide;

  if (![badgeLabel length])
    {
      return;
    }

  if ([displayString length] > 5)
    {
      displayString = [NSString stringWithFormat:@"%@...%@",
				[displayString substringToIndex:2],
				[displayString substringFromIndex:
						[displayString length] - 2]];
    }

  pad = MAX(4.0, size / 10.0);
  minSide = MAX(14.0, size / 3.2);
  iconRect = NSMakeRect(NSMidX(cell) - size / 2.0,
                        NSMidY(cell) - size / 2.0,
                        size,
                        size);

  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSFont boldSystemFontOfSize:MAX(9.0, size / 5.0)],
			NSFontAttributeName,
			[NSColor whiteColor],
			NSForegroundColorAttributeName,
			nil];
  textSize = [displayString sizeWithAttributes:attrs];
  badgeSize = NSMakeSize(MAX(minSide, textSize.width + pad),
			 MAX(minSide, textSize.height + pad / 2.0));
  badgeRect = NSMakeRect(NSMaxX(iconRect) - badgeSize.width,
			 NSMaxY(iconRect) - badgeSize.height,
			 badgeSize.width,
			 badgeSize.height);

  [[NSColor colorWithCalibratedRed:0.82 green:0.05 blue:0.09 alpha:1.0] set];
  [[NSBezierPath bezierPathWithOvalInRect:badgeRect] fill];
  [displayString drawAtPoint:
		   NSMakePoint(NSMidX(badgeRect) - textSize.width / 2.0,
			       NSMidY(badgeRect) - textSize.height / 2.0)
		     withAttributes:attrs];
}

- (void) drawDockTileForItem: (DockItem *)item inCell: (NSRect)cell size: (CGFloat)size
{
  NSImage *icon = [item icon];
  CGFloat angle = 0.0;

  if (item == _wiggleItem)
    {
      NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _wiggleStartTime;
      CGFloat progress = (CGFloat)(elapsed / DockWiggleDuration);
      CGFloat decay = MAX(0.0, 1.0 - progress);

      angle = sin(progress * 8.0 * M_PI) * 8.0 * decay;
    }

  if (![self drawImage:icon inCell:cell size:size angle:angle])
    {
      [self drawFallbackIconForItem:item inCell:cell];
    }
  [self drawBadgeForItem:item inCell:cell iconSize:size];
}

- (void) drawStateForItem: (DockItem *)item inCell: (NSRect)cell
{
  CGFloat dotSize = 5.0;
  CGFloat x;
  CGFloat y = NSMinY(cell) + 2.0;

  if ([item kind] != DockItemApplication)
    {
      return;
    }

  if (_runningIndicatorMode == DockRunningIndicatorModeNotRunningDots)
    {
      NSUInteger i;
      CGFloat iconSize = 46.0;
      NSRect iconRect = NSMakeRect(NSMidX(cell) - iconSize / 2.0,
				   NSMidY(cell) - iconSize / 2.0,
				   iconSize,
				   iconSize);
      CGFloat spacing = dotSize + 3.0;
      CGFloat startX;

      if ([item state] != DockItemNotRunning)
	{
	  return;
	}

      startX = NSMinX(iconRect) + 2.0;
      y = NSMinY(iconRect) - 7.0;

      for (i = 0; i < 3; i++)
	{
	  x = startX + spacing * (CGFloat)i;

	  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.65] set];
	  [[NSBezierPath bezierPathWithOvalInRect:
			   NSMakeRect(x - 1.0, y - 1.0,
				      dotSize + 2.0, dotSize + 2.0)] fill];

	  [[NSColor colorWithCalibratedWhite:0.92 alpha:0.95] set];
	  [[NSBezierPath bezierPathWithOvalInRect:
			   NSMakeRect(x, y, dotSize, dotSize)] fill];
	}
      return;
    }

  if ([item state] == DockItemNotRunning)
    {
      return;
    }

  x = NSMidX(cell) - dotSize / 2.0;

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.65] set];
  [[NSBezierPath bezierPathWithOvalInRect:
		   NSMakeRect(x - 1.0, y - 1.0, dotSize + 2.0, dotSize + 2.0)] fill];

  [[NSColor colorWithCalibratedWhite:0.92 alpha:0.95] set];
  [[NSBezierPath bezierPathWithOvalInRect:
		   NSMakeRect(x, y, dotSize, dotSize)] fill];
}

- (void) drawTopTile
{
  NSRect cell = [self topTileRect];

  [self drawCellBackgroundInCell:cell];
  [self drawImage:_gnustepIcon inCell:cell size:50.0];
}

- (void) drawRecyclerFallbackInCell: (NSRect)cell
{
  NSPoint center = NSMakePoint(NSMidX(cell), NSMidY(cell));
  CGFloat radius = 18.0;
  NSUInteger i;

  [[NSColor colorWithCalibratedWhite:0.88 alpha:0.95] set];

  for (i = 0; i < 3; i++)
    {
      CGFloat angle = (CGFloat)i * 120.0;
      CGFloat start = angle + 18.0;
      CGFloat end = angle + 92.0;
      CGFloat arrowAngle = end * M_PI / 180.0;
      NSBezierPath *arc = [NSBezierPath bezierPath];
      NSPoint arrowPoint = NSMakePoint(center.x + cos(arrowAngle) * radius,
				       center.y + sin(arrowAngle) * radius);
      NSBezierPath *head = [NSBezierPath bezierPath];

      [arc appendBezierPathWithArcWithCenter:center
				      radius:radius
				  startAngle:start
				    endAngle:end];
      [arc setLineWidth:3.0];
      [arc stroke];

      [head moveToPoint:arrowPoint];
      [head relativeLineToPoint:NSMakePoint(-8.0 * sin(arrowAngle) -
					    4.0 * cos(arrowAngle),
					    8.0 * cos(arrowAngle) -
					    4.0 * sin(arrowAngle))];
      [head relativeLineToPoint:NSMakePoint(8.0 * cos(arrowAngle),
					    8.0 * sin(arrowAngle))];
      [head closePath];
      [head fill];
    }
}

- (void) drawRecyclerContentsIndicatorInCell: (NSRect)cell
{
  CGFloat dotSize = 8.0;
  CGFloat x = NSMidX(cell) - dotSize / 2.0;
  CGFloat y = NSMidY(cell) - dotSize / 2.0;

  if (!_recyclerHasContents)
    {
      return;
    }

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.70] set];
  [[NSBezierPath bezierPathWithOvalInRect:
		   NSMakeRect(x - 1.0, y - 1.0, dotSize + 2.0, dotSize + 2.0)] fill];

  [[NSColor colorWithCalibratedRed:0.10
                             green:0.80
                              blue:0.35
                             alpha:0.96] set];
  [[NSBezierPath bezierPathWithOvalInRect:
		   NSMakeRect(x, y, dotSize, dotSize)] fill];
}

- (void) drawRecyclerTile
{
  NSRect cell = [self recyclerTileRect];
  CGFloat angle = 0.0;

  [self drawCellBackgroundInCell:cell];

  if (_recyclerWiggleStartTime)
    {
      NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] -
	_recyclerWiggleStartTime;
      CGFloat progress = (CGFloat)(elapsed / DockWiggleDuration);
      CGFloat decay = MAX(0.0, 1.0 - progress);

      angle = sin(progress * 8.0 * M_PI) * 8.0 * decay;
    }

  if (![self drawImage:_recyclerIcon inCell:cell size:46.0 angle:angle])
    {
      if (angle != 0.0)
	{
	  NSAffineTransform *transform = [NSAffineTransform transform];

	  [NSGraphicsContext saveGraphicsState];
	  [transform translateXBy:NSMidX(cell) yBy:NSMidY(cell)];
	  [transform rotateByDegrees:angle];
	  [transform translateXBy:-NSMidX(cell) yBy:-NSMidY(cell)];
	  [transform concat];
	  [self drawRecyclerFallbackInCell:cell];
	  [NSGraphicsContext restoreGraphicsState];
	}
      else
	{
	  [self drawRecyclerFallbackInCell:cell];
	}
    }
  [self drawRecyclerContentsIndicatorInCell:cell];
}

- (void) drawDropIndicator
{
  NSRect cell;
  CGFloat thickness = 3.0;

  if ((!_draggingPaths && _draggedItemIndex == NSNotFound) ||
      _dropIndex == NSNotFound ||
      _dropIndex > [_items count])
    {
      return;
    }

  if (_dropIndex < [_items count])
    {
      NSPoint origin = [self cellOriginAtIndex:_dropIndex];
      cell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);
    }
  else
    {
      cell = [self recyclerTileRect];
    }

  [[NSColor colorWithCalibratedWhite:0.95 alpha:0.95] set];
  if (_horizontal)
    {
      NSRectFill(NSMakeRect(NSMinX(cell) - _dockGap / 2.0 - thickness / 2.0,
			    NSMinY(cell) + 8.0,
			    thickness,
			    NSHeight(cell) - 16.0));
    }
  else
    {
      NSRectFill(NSMakeRect(NSMinX(cell) + 8.0,
			    NSMaxY(cell) + _dockGap / 2.0 - thickness / 2.0,
			    NSWidth(cell) - 16.0,
			    thickness));
    }
}

- (void) drawSeparatorBeforeIndex: (NSUInteger)index
{
  NSPoint origin;
  NSRect previousCell;
  NSRect nextCell;
  CGFloat x;
  CGFloat y;
  NSBezierPath *path;

  if (index > [_items count])
    {
      return;
    }

  if (index > 0)
    {
      origin = [self cellOriginAtIndex:index - 1];
      previousCell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);
    }
  else
    {
      previousCell = [self topTileRect];
    }

  if (index < [_items count])
    {
      origin = [self cellOriginAtIndex:index];
      nextCell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);
    }
  else
    {
      nextCell = [self recyclerTileRect];
    }

  path = [NSBezierPath bezierPath];
  [path setLineWidth:1.0];
  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.55] set];

  if (_horizontal)
    {
      x = floor((NSMaxX(previousCell) + NSMinX(nextCell)) / 2.0) + 0.5;
      [path moveToPoint:NSMakePoint(x, NSMinY(nextCell) + DockSeparatorInset)];
      [path lineToPoint:NSMakePoint(x, NSMaxY(nextCell) - DockSeparatorInset)];
    }
  else
    {
      y = floor((NSMinY(previousCell) + NSMaxY(nextCell)) / 2.0) + 0.5;
      [path moveToPoint:NSMakePoint(NSMinX(nextCell) + DockSeparatorInset, y)];
      [path lineToPoint:NSMakePoint(NSMaxX(nextCell) - DockSeparatorInset, y)];
    }

  [path stroke];
}

- (void) drawDockSeparators
{
  if (_pinnedItemCount >= [_items count])
    {
      return;
    }

  [self drawSeparatorBeforeIndex:_pinnedItemCount];
  [self drawSeparatorBeforeIndex:[_items count]];
}

- (void) drawDockBorder
{
  NSRect bounds;
  NSBezierPath *path;

  if (!_showsBorder)
    {
      return;
    }

  bounds = NSInsetRect([self bounds], 0.5, 0.5);
  path = [NSBezierPath bezierPathWithRect:bounds];
  [path setLineWidth:1.0];
  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.60] set];
  [path stroke];
}

- (void) drawRect: (NSRect)dirtyRect
{
  NSUInteger i;

  [_backgroundColor set];
  NSRectFill([self bounds]);

  [self drawTopTile];
  [self drawDockSeparators];

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSPoint origin = [self cellOriginAtIndex:i];
      NSRect cell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);

      [self drawCellBackgroundInCell:cell];
      [self drawDockTileForItem:item inCell:cell size:46.0];
      [self drawStateForItem:item inCell:cell];
    }

  [self drawDropIndicator];
  [self drawRecyclerTile];
  [self drawTooltip];
  [self drawDockBorder];
}

- (void) mouseMoved: (NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger hoverIndex = [self hoverIndexAtPoint:location];

  if (hoverIndex != _hoveredItemIndex)
    {
      _hoveredItemIndex = hoverIndex;
      [self scheduleTooltipForHoverIndex:hoverIndex];
    }
}

- (void) mouseExited: (NSEvent *)event
{
  _hoveredItemIndex = DockHoverNone;
  [self hideTooltip];
}

- (void) rightMouseDown: (NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSUInteger index = [self indexAtPoint:location];
  NSMenu *contextMenu = nil;

  [self hideTooltip];

  if ([self topIconContainsPoint:location])
    {
      contextMenu = [self menu];
    }
  else if ([self recyclerContainsPoint:location])
    {
      contextMenu = [self menuForRecycler];
    }
  else if (index != NSNotFound && index < [_items count])
    {
      contextMenu = [self menuForDockItem:[_items objectAtIndex:index]];
    }

  if (contextMenu)
    {
      [NSMenu popUpContextMenu:contextMenu withEvent:event forView:self];
    }
}

- (NSImage *) dragImageForItemAtIndex: (NSUInteger)index
{
  NSImage *image = AUTORELEASE([[NSImage alloc]
				 initWithSize:NSMakeSize(_cellSize, _cellSize)]);
  NSRect cell = NSMakeRect(0.0, 0.0, _cellSize, _cellSize);

  if (index >= [_items count])
    {
      return nil;
    }

  [image lockFocus];
  [self drawCellBackgroundInCell:cell];
  [self drawDockTileForItem:[_items objectAtIndex:index] inCell:cell size:46.0];
  [self drawStateForItem:[_items objectAtIndex:index] inCell:cell];
  [image unlockFocus];
  return image;
}

- (void) mouseDragged: (NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  CGFloat dx = location.x - _mouseDownPoint.x;
  CGFloat dy = location.y - _mouseDownPoint.y;

  if (_mouseDownItemIndex == NSNotFound ||
      _mouseDownItemIndex >= [_items count] ||
      (dx * dx + dy * dy) < 16.0)
    {
      return;
    }

  _draggedItemIndex = _mouseDownItemIndex;
  _dropIndex = _mouseDownItemIndex;
  [self hideTooltip];

  {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    NSImage *dragImage = [self dragImageForItemAtIndex:_mouseDownItemIndex];
    NSPoint dragPoint = NSMakePoint(location.x - _cellSize / 2.0,
                                    location.y - _cellSize / 2.0);

    [pasteboard declareTypes:[NSArray arrayWithObject:DockReorderPboardType]
                       owner:nil];
    [pasteboard setString:[NSString stringWithFormat:@"%lu",
				    (unsigned long)_mouseDownItemIndex]
                  forType:DockReorderPboardType];
    [self dragImage:dragImage
                 at:dragPoint
             offset:NSZeroSize
              event:event
         pasteboard:pasteboard
             source:self
          slideBack:YES];
  }
}

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL)isLocal
{
  return NSDragOperationMove | NSDragOperationDelete;
}

- (BOOL) screenPointIsInsideDock: (NSPoint)screenPoint
{
  NSPoint windowPoint;
  NSPoint viewPoint;

  if (![self window])
    {
      return NO;
    }

  windowPoint = [[self window] convertScreenToBase:screenPoint];
  viewPoint = [self convertPoint:windowPoint fromView:nil];
  return NSPointInRect(viewPoint, [self bounds]);
}

- (void) finishDraggingItemWithRemove: (BOOL)remove
{
  NSUInteger draggedIndex = _draggedItemIndex;

  if (remove &&
      draggedIndex != NSNotFound &&
      draggedIndex < [_items count] &&
      [_delegate respondsToSelector:
		   @selector(dockViewDidRemoveItemAtIndex:)])
    {
      [_delegate dockViewDidRemoveItemAtIndex:draggedIndex];
    }

  _mouseDownItemIndex = NSNotFound;
  _draggedItemIndex = NSNotFound;
  _dropIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (void) draggedImage: (NSImage *)image
	      endedAt: (NSPoint)screenPoint
	    operation: (NSDragOperation)operation
{
  [self finishDraggingItemWithRemove:
	  ![self screenPointIsInsideDock:screenPoint]];
}

- (void) draggedImage: (NSImage *)image
	      endedAt: (NSPoint)screenPoint
	    deposited: (BOOL)flag
{
  [self finishDraggingItemWithRemove:
	  ![self screenPointIsInsideDock:screenPoint]];
}

- (NSDragOperation) draggingEntered: (id <NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
  NSPasteboard *pasteboard = [sender draggingPasteboard];

  [self hideTooltip];

  if ([self pasteboardHasReorderType:pasteboard])
    {
      if ([self recyclerContainsPoint:location])
	{
	  _dropIndex = NSNotFound;
	  [self setNeedsDisplay:YES];
	  return NSDragOperationDelete;
	}
      _dropIndex = [self reorderInsertionIndexAtPoint:location
					    fromIndex:_draggedItemIndex];
      [self setNeedsDisplay:YES];
      return NSDragOperationMove;
    }

  if ([self pasteboardHasSupportedType:pasteboard])
    {
      _draggingPaths = YES;
      _dropIndex = [self recyclerContainsPoint:location]
	? NSNotFound : [self pinnedInsertionIndexAtPoint:location];
      [self setNeedsDisplay:YES];
      return [self dragOperationForSender:sender];
    }
  return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated: (id <NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];

  if ([self pasteboardHasReorderType:[sender draggingPasteboard]])
    {
      if ([self recyclerContainsPoint:location])
	{
	  _dropIndex = NSNotFound;
	  [self setNeedsDisplay:YES];
	  return NSDragOperationDelete;
	}
      _dropIndex = [self reorderInsertionIndexAtPoint:location
					    fromIndex:_draggedItemIndex];
      [self setNeedsDisplay:YES];
      return NSDragOperationMove;
    }

  if ([self pasteboardHasSupportedType:[sender draggingPasteboard]])
    {
      if ([self recyclerContainsPoint:location])
	{
	  _dropIndex = NSNotFound;
	  [self setNeedsDisplay:YES];
	  return [self dragOperationForSender:sender];
	}
      _dropIndex = [self pinnedInsertionIndexAtPoint:location];
      [self setNeedsDisplay:YES];
      return [self dragOperationForSender:sender];
    }

  return [self draggingEntered:sender];
}

- (void) draggingExited: (id <NSDraggingInfo>)sender
{
  _draggingPaths = NO;
  _performedDragOperation = NO;
  _dropIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (BOOL) prepareForDragOperation: (id <NSDraggingInfo>)sender
{
  if ([self pasteboardHasReorderType:[sender draggingPasteboard]])
    {
      return YES;
    }

  return [self pasteboardHasSupportedType:[sender draggingPasteboard]];
}

- (BOOL) performDragOperation: (id <NSDraggingInfo>)sender
{
  NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
  NSPasteboard *pasteboard = [sender draggingPasteboard];
  _draggingPaths = NO;
  [self setNeedsDisplay:YES];

  if ([self pasteboardHasReorderType:pasteboard])
    {
      NSString *indexString = [pasteboard stringForType:DockReorderPboardType];
      NSUInteger fromIndex = (NSUInteger)[indexString integerValue];

      if ([self recyclerContainsPoint:location])
	{
	  _dropIndex = NSNotFound;
	  _draggedItemIndex = NSNotFound;
	  _performedDragOperation = YES;
	  if (fromIndex < [_items count] &&
	      [_delegate respondsToSelector:
			   @selector(dockViewDidRemoveItemAtIndex:)])
	    {
	      [_delegate dockViewDidRemoveItemAtIndex:fromIndex];
	      return YES;
	    }
	  return NO;
	}

      {
	NSUInteger toIndex = [self reorderInsertionIndexAtPoint:location
						      fromIndex:fromIndex];

	_dropIndex = NSNotFound;
	_draggedItemIndex = NSNotFound;
	_performedDragOperation = YES;
	if (fromIndex < [_items count] &&
	    toIndex <= [_items count] &&
	    [_delegate respondsToSelector:
			 @selector(dockViewDidMoveItemFromIndex:toIndex:)])
	  {
	    [_delegate dockViewDidMoveItemFromIndex:fromIndex toIndex:toIndex];
	    return YES;
	  }
      }
      return NO;
    }

  if ([self recyclerContainsPoint:location])
    {
      if ([paths count] &&
	  [_delegate respondsToSelector:
		       @selector(dockViewDidReceivePathsInRecycler:)])
	{
	  [_delegate dockViewDidReceivePathsInRecycler:paths];
	  _performedDragOperation = YES;
	  _dropIndex = NSNotFound;
	  return YES;
	}
      return NO;
    }

  if ([paths count] && [_delegate respondsToSelector:@selector(dockViewDidReceivePaths:)])
    {
      NSUInteger toIndex = [self pinnedInsertionIndexAtPoint:location];

      if ([_delegate respondsToSelector:
		       @selector(dockViewDidReceivePaths:atIndex:)])
	{
	  [_delegate dockViewDidReceivePaths:paths atIndex:toIndex];
	}
      else
	{
	  [_delegate dockViewDidReceivePaths:paths];
	}
      _performedDragOperation = YES;
      _dropIndex = NSNotFound;
      return YES;
    }
  return NO;
}

- (void) concludeDragOperation: (id <NSDraggingInfo>)sender
{
  if (!_performedDragOperation)
    {
      NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
      NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
      if (![self pasteboardHasReorderType:[sender draggingPasteboard]] &&
	  [paths count])
	{
	  NSUInteger toIndex = [self pinnedInsertionIndexAtPoint:location];

	  if ([self recyclerContainsPoint:location] &&
	      [_delegate respondsToSelector:
			   @selector(dockViewDidReceivePathsInRecycler:)])
	    {
	      [_delegate dockViewDidReceivePathsInRecycler:paths];
	    }
	  else if (![self recyclerContainsPoint:location] &&
		   [_delegate respondsToSelector:
				@selector(dockViewDidReceivePaths:atIndex:)])
	    {
	      [_delegate dockViewDidReceivePaths:paths atIndex:toIndex];
	    }
	  else if (![self recyclerContainsPoint:location] &&
		   [_delegate respondsToSelector:
				@selector(dockViewDidReceivePaths:)])
	    {
	      [_delegate dockViewDidReceivePaths:paths];
	    }
	}
    }

  _draggingPaths = NO;
  _performedDragOperation = NO;
  _dropIndex = NSNotFound;
  _draggedItemIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (void) mouseDown: (NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSUInteger index = [self indexAtPoint:location];
  NSTimeInterval eventTime = [event timestamp];
  NSTimeInterval doubleClickInterval = 0.5;
  NSUInteger clickedIndex = index;
  BOOL isDoubleClick = NO;
  BOOL topIconClicked = [self topIconContainsPoint:location];
  BOOL recyclerClicked = [self recyclerContainsPoint:location];

  _mouseDownPoint = location;
  _mouseDownItemIndex = index;

  if (eventTime <= 0.0)
    {
      eventTime = [NSDate timeIntervalSinceReferenceDate];
    }

  if (topIconClicked)
    {
      clickedIndex = DockTopIconClickIndex;
    }
  else if (recyclerClicked)
    {
      clickedIndex = DockRecyclerClickIndex;
    }

  if (clickedIndex != NSNotFound)
    {
      if ([event clickCount] >= 2)
	{
	  isDoubleClick = YES;
	}
      else if (clickedIndex == _lastMouseDownIndex &&
	       _lastMouseDownTime > 0.0 &&
	       eventTime - _lastMouseDownTime <= doubleClickInterval)
	{
	  isDoubleClick = YES;
	}
    }

  if (isDoubleClick)
    {
      if (topIconClicked)
	{
	  if ([_delegate respondsToSelector:@selector(dockViewDidActivateTopIcon)])
	    {
	      [_delegate dockViewDidActivateTopIcon];
	    }
	}
      else if (recyclerClicked)
	{
	  if ([_delegate respondsToSelector:@selector(dockViewDidActivateRecycler)])
	    {
	      [_delegate dockViewDidActivateRecycler];
	    }
	}
      else if ([_delegate respondsToSelector:@selector(dockViewDidActivateItem:)])
	{
	  [_delegate dockViewDidActivateItem:[_items objectAtIndex:index]];
	}
      _lastMouseDownIndex = NSNotFound;
      _lastMouseDownTime = 0.0;
      return;
    }

  _lastMouseDownIndex = clickedIndex;
  _lastMouseDownTime = eventTime;
}

@end
