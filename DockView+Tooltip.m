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


- (void) updateToolTips
{
  NSInteger index;
  NSString *title;
  NSRect rect;

  [self removeAllToolTips];

  for (index = DockHoverRecycler; index < (NSInteger)[_items count]; index++)
    {
      if (index == DockHoverNone)
        {
          continue;
        }

      title = [self tooltipTitleForHoverIndex:index];
      rect = NSIntersectionRect([self cellRectForHoverIndex:index], [self bounds]);
      if ([title length] && !NSIsEmptyRect(rect))
        {
          [self addToolTipRect:rect
                        owner:self
                     userData:(void *)(intptr_t)index];
        }
    }
}


- (NSString *) view: (NSView *)view
 stringForToolTip: (NSToolTipTag)tag
             point: (NSPoint)point
          userData: (void *)userData
{
  NSInteger index = (NSInteger)(intptr_t)userData;

  return [self tooltipTitleForHoverIndex:index];
}


@end
