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

@implementation DockView (Tooltip)

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


@end
