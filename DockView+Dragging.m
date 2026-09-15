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

@implementation DockView (Dragging)

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


@end
