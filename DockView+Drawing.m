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

@implementation DockView (Drawing)

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
  destRect = [self iconRectInCell:cell size:size];

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
  iconRect = [self iconRectInCell:cell size:size];

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
  NSColor *backgroundColor;
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  backgroundColor = DockViewCalibratedBackgroundColor(_backgroundColor);
  [backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha];
  NSRectFillUsingOperation(dirtyRect, NSCompositeClear);

  [[NSColor colorWithCalibratedRed:red
                             green:green
                              blue:blue
                             alpha:alpha * _backgroundAlpha] set];
  NSRectFill([self bounds]);

  [self drawTopTile];
  [self drawDockSeparators];

  for (i = 0; i < [_items count]; i++)
    {
      DockItem *item = [_items objectAtIndex:i];
      NSPoint origin = [self cellOriginAtIndex:i];
      NSRect cell = NSMakeRect(origin.x, origin.y, _cellSize, _cellSize);

      [self drawCellBackgroundInCell:cell];
      [self drawDockTileForItem:item
			 inCell:cell
			   size:[self iconSizeForItemAtIndex:i]];
      [self drawStateForItem:item inCell:cell];
    }

  [self drawDropIndicator];
  [self drawRecyclerTile];
  [self drawTooltip];
  [self drawDockBorder];
}


@end
