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

#import "AppControllerPrivate.h"

@implementation AppController (Preferences)

- (DockPlacement) savedDockPlacement
{
  return [_preferences savedDockPlacement];
}

- (NSColor *) savedBackgroundColor
{
  return [_preferences savedBackgroundColor];
}

- (void) saveBackgroundColor
{
  [_preferences saveBackgroundColor:_backgroundColor];
}

- (CGFloat) savedWindowAlpha
{
  return [_preferences savedWindowAlpha];
}

- (void) saveWindowAlpha
{
  [_preferences saveWindowAlpha:_windowAlpha];
}

- (BOOL) savedShowDockBorder
{
  return [_preferences savedShowDockBorder];
}

- (void) saveShowDockBorder
{
  [_preferences saveShowDockBorder:_showDockBorder];
}

- (NSInteger) savedDockCellSizeMode
{
  return [_preferences savedDockCellSizeMode];
}

- (void) saveDockCellSizeMode
{
  [_preferences saveDockCellSizeMode:_dockCellSizeMode];
}

- (DockRunningIndicatorMode) savedRunningIndicatorMode
{
  return [_preferences savedRunningIndicatorMode];
}

- (void) saveRunningIndicatorMode
{
  [_preferences saveRunningIndicatorMode:_runningIndicatorMode];
}

- (BOOL) savedUseCellTileBackground
{
  return [_preferences savedUseCellTileBackground];
}

- (void) saveUseCellTileBackground
{
  [_preferences saveUseCellTileBackground:_useCellTileBackground];
}

- (BOOL) savedSingleClickLaunchesApplications
{
  return [_preferences savedSingleClickLaunchesApplications];
}

- (CGFloat) activeDockPad
{
  return [DockPreferences padForCellSizeMode:_dockCellSizeMode];
}

- (CGFloat) activeDockGap
{
  return [DockPreferences gapForCellSizeMode:_dockCellSizeMode];
}

- (CGFloat) activeDockWindowWidth
{
  return [DockPreferences windowWidthForCellSizeMode:_dockCellSizeMode];
}

- (void) applyDockCellSizeToView
{
  if (_dockView)
    {
      [_dockView setIconCellSize:[DockPreferences dockCellSize]
			      gap:[self activeDockGap]
			  padding:[self activeDockPad]];
    }
}


@end
