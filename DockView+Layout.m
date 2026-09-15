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

@implementation DockView (Layout)

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


- (NSRect) iconRectInCell: (NSRect)cell size: (CGFloat)size
{
  NSRect bounds = [self bounds];
  NSRect rect = NSMakeRect(NSMidX(cell) - size / 2.0,
			   NSMidY(cell) - size / 2.0,
			   size,
			   size);

  if (NSWidth(rect) > NSWidth(bounds))
    {
      rect.origin.x = NSMinX(bounds);
      rect.size.width = NSWidth(bounds);
    }
  else if (NSMinX(rect) < NSMinX(bounds))
    {
      rect.origin.x = NSMinX(bounds);
    }
  else if (NSMaxX(rect) > NSMaxX(bounds))
    {
      rect.origin.x = NSMaxX(bounds) - NSWidth(rect);
    }

  if (NSHeight(rect) > NSHeight(bounds))
    {
      rect.origin.y = NSMinY(bounds);
      rect.size.height = NSHeight(bounds);
    }
  else if (NSMinY(rect) < NSMinY(bounds))
    {
      rect.origin.y = NSMinY(bounds);
    }
  else if (NSMaxY(rect) > NSMaxY(bounds))
    {
      rect.origin.y = NSMaxY(bounds) - NSHeight(rect);
    }

  return rect;
}


- (CGFloat) iconSizeForItemAtIndex: (NSUInteger)index
{
  CGFloat size = 46.0;

  if (_magnifiesHoveredIcons &&
      _hoveredItemIndex == (NSInteger)index &&
      !_draggingPaths &&
      _draggedItemIndex == NSNotFound)
    {
      size *= _hoverIconScale;
    }

  return MIN(size, _cellSize);
}


@end
