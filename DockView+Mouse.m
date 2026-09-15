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

@implementation DockView (Mouse)

- (void) mouseMoved: (NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger hoverIndex = [self hoverIndexAtPoint:location];

  if (hoverIndex != _hoveredItemIndex)
    {
      _hoveredItemIndex = hoverIndex;
      [self scheduleTooltipForHoverIndex:hoverIndex];
      [self setNeedsDisplay:YES];
    }
}


- (void) mouseExited: (NSEvent *)event
{
  _hoveredItemIndex = DockHoverNone;
  [self hideTooltip];
  [self setNeedsDisplay:YES];
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

  if (index != NSNotFound)
    {
      [self acknowledgeWiggleForItem:[_items objectAtIndex:index]];
    }

  if (_singleClickLaunchesApplications && index != NSNotFound)
    {
      isDoubleClick = YES;
    }
  else if (clickedIndex != NSNotFound)
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
