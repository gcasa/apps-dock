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

#import "SettingsControllerPrivate.h"
#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>

@implementation SettingsController

- (id) initWithDelegate: (id<SettingsControllerDelegate>)delegate
{
  self = [super init];
  if (self)
    {
      _delegate = delegate;
    }
  return self;
}

- (void) dealloc
{
  DESTROY(_emptyRecyclerButton);
  DESTROY(_deleteApplicationButton);
  DESTROY(_moveApplicationDownButton);
  DESTROY(_moveApplicationUpButton);
  DESTROY(_applicationWiggleOnAttentionRequestButton);
  DESTROY(_applicationWiggleOnActivationButton);
  DESTROY(_applicationWiggleOnLaunchButton);
  DESTROY(_useDockBehaviorDefaultsButton);
  DESTROY(_openAtLoginButton);
  DESTROY(_applyApplicationButton);
  DESTROY(_applicationArgumentsField);
  DESTROY(_applicationPathField);
  DESTROY(_applicationPopup);
  DESTROY(_singleClickLaunchButton);
  DESTROY(_wiggleOnAttentionRequestButton);
  DESTROY(_playSoundOnRemoveButton);
  DESTROY(_wiggleOnActivationButton);
  DESTROY(_wiggleOnLaunchButton);
  DESTROY(_hoverIconScaleSlider);
  DESTROY(_hoverIconScaleValueLabel);
  DESTROY(_hoverIconScaleLabel);
  DESTROY(_magnifyHoveredIconsButton);
  DESTROY(_showBorderButton);
  DESTROY(_useCellTileButton);
  DESTROY(_notRunningDotsButton);
  DESTROY(_runningDotButton);
  DESTROY(_cellSize64Button);
  DESTROY(_currentCellSizeButton);
  DESTROY(_transparencyValueLabel);
  DESTROY(_transparencySlider);
  DESTROY(_transparencyLabel);
  DESTROY(_backgroundColorWell);
  DESTROY(_placementPopup);
  DESTROY(_panel);
  DEALLOC;
}











- (void) showWindow: (id)sender
{
  [self createPanel];
  [self updateControls];
  [_panel center];
  [_panel makeKeyAndOrderFront:sender];
}

- (void) showWindowForItem: (DockItem *)item
{
  [self createPanel];
  [self updateControls];
  [self selectApplicationItem:item];
  [self updateControls];
  [_panel center];
  [_panel makeKeyAndOrderFront:self];
}





























@end
