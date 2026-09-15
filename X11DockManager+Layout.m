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

#import "X11DockManagerPrivate.h"

@implementation X11DockManager (Layout)

- (NSRect) x11FrameForDockPlacement: (DockPlacement)placement
{
  Display *display = (Display *)_display;
  int screen;
  int screenWidth;
  int screenHeight;
  unsigned int width = (unsigned int)NSWidth([_dockView bounds]);
  unsigned int height = (unsigned int)NSHeight([_dockView bounds]);
  int x;
  int y;

  if (!display)
    {
      return NSZeroRect;
    }

  screen = DefaultScreen(display);
  screenWidth = DisplayWidth(display, screen);
  screenHeight = DisplayHeight(display, screen);
  if (width > (unsigned int)screenWidth)
    {
      width = (unsigned int)screenWidth;
    }
  if (height > (unsigned int)screenHeight)
    {
      height = (unsigned int)screenHeight;
    }

  switch (placement)
    {
    case DockPlacementRightTop:
    case DockPlacementRightCenter:
      x = screenWidth - (int)width;
      break;
    case DockPlacementTopCenter:
    case DockPlacementBottomCenter:
      x = (screenWidth - (int)width) / 2;
      break;
    case DockPlacementLeftTop:
    case DockPlacementLeftCenter:
    default:
      x = 0;
      break;
    }

  switch (placement)
    {
    case DockPlacementLeftCenter:
    case DockPlacementRightCenter:
      y = (screenHeight - (int)height) / 2;
      break;
    case DockPlacementBottomCenter:
      y = screenHeight - (int)height;
      break;
    case DockPlacementLeftTop:
    case DockPlacementRightTop:
    case DockPlacementTopCenter:
    default:
      y = 0;
      break;
    }

  return NSMakeRect(x, y, width, height);
}


- (NSRect) hiddenIconWindowFrame
{
  Display *display = (Display *)_display;
  int screen;

  if (!display)
    {
      return NSMakeRect(0, 0, 64, 64);
    }

  screen = DefaultScreen(display);
  return NSMakeRect(DisplayWidth(display, screen) + DockHiddenIconWindowOffset,
		    DisplayHeight(display, screen) + DockHiddenIconWindowOffset,
		    64, 64);
}


- (void) updateHostWindowShape
{
  Display *display = (Display *)_display;
  NSArray *frames;
  XRectangle *rectangles = NULL;
  int eventBase;
  int errorBase;
  NSUInteger count;
  NSUInteger i;

  if (!display || !_hostWindow ||
      !XShapeQueryExtension(display, &eventBase, &errorBase))
    {
      return;
    }

  frames = [_dockedWindowFrames allValues];
  count = [frames count];
  if (count > 0)
    {
      rectangles = malloc(sizeof(XRectangle) * count);
      if (!rectangles)
	{
	  return;
	}
      for (i = 0; i < count; i++)
	{
	  NSRect rect = [[frames objectAtIndex:i] rectValue];

	  rectangles[i].x = (short)NSMinX(rect);
	  rectangles[i].y = (short)NSMinY(rect);
	  rectangles[i].width = (unsigned short)NSWidth(rect);
	  rectangles[i].height = (unsigned short)NSHeight(rect);
	}
    }

  XShapeCombineRectangles(display, (Window)_hostWindow, ShapeBounding,
			  0, 0, rectangles, (int)count, ShapeSet, YXBanded);
  XShapeCombineRectangles(display, (Window)_hostWindow, ShapeInput,
			  0, 0, rectangles, (int)count, ShapeSet, YXBanded);
  if (rectangles)
    {
      free(rectangles);
    }
  XFlush(display);
}


- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;
  int x;
  int y;

  if (!display || !_hostWindow) return;
  if (![self windowIsRegisteredIconWindow:(Window)xWindow] &&
      ![self windowIsKnownDockAppWindow:(Window)xWindow] &&
      ![self windowLooksLikeWindowMakerDockApp:(Window)xWindow])
    {
      return;
    }
  origin = [_dockView cellOriginAtIndex:index];
  x = (int)origin.x;
  y = (int)(NSHeight([_dockView bounds]) - origin.y - 64.0);
  [_dockedWindowFrames setObject:[NSValue valueWithRect:NSMakeRect(x, y, 64, 64)]
			   forKey:[NSNumber numberWithUnsignedLong:xWindow]];
  [self updateHostWindowShape];
  XRaiseWindow(display, (Window)_hostWindow);
  XReparentWindow(display, (Window)xWindow, (Window)_hostWindow, x, y);
  XResizeWindow(display, (Window)xWindow, 64, 64);
  XMapRaised(display, (Window)xWindow);
  XFlush(display);
}


- (void) moveDockedWindow: (unsigned long)xWindow toIndex: (NSUInteger)index
{
  Display *display = (Display *)_display;
  NSPoint origin;
  int x;
  int y;

  if (!display || !_hostWindow) return;
  origin = [_dockView cellOriginAtIndex:index];
  x = (int)origin.x;
  y = (int)(NSHeight([_dockView bounds]) - origin.y - 64.0);
  [_dockedWindowFrames setObject:[NSValue valueWithRect:NSMakeRect(x, y, 64, 64)]
			   forKey:[NSNumber numberWithUnsignedLong:xWindow]];
  [self updateHostWindowShape];
  XRaiseWindow(display, (Window)_hostWindow);
  XMoveWindow(display, (Window)xWindow, x, y);
  XFlush(display);
}


@end
