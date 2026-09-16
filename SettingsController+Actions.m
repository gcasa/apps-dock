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

@implementation SettingsController (Actions)

- (void) closePanel: (id)sender
{
  [[NSUserDefaults standardUserDefaults] synchronize];
  [_panel orderOut:sender];
}


- (BOOL) windowShouldClose: (id)sender
{
  if (sender == _panel)
    {
      [self closePanel:sender];
      return NO;
    }

  return YES;
}


- (void) windowWillClose: (NSNotification *)notification
{
}


- (void) placementChanged: (id)sender
{
  [_delegate settingsController:self
	 didChangeDockPlacement:(DockPlacement)[sender selectedTag]];
}


- (void) backgroundColorChanged: (id)sender
{
  [_delegate settingsController:self
       didChangeBackgroundColor:[_backgroundColorWell color]];
  [_backgroundColorWell setColor:
      [_delegate settingsControllerBackgroundColor:self]];
}


- (void) transparencyChanged: (id)sender
{
  CGFloat alpha = SettingsClampedWindowAlpha([(NSSlider *)sender floatValue]);

  [_delegate settingsController:self didChangeWindowAlpha:alpha];
  [_transparencySlider setFloatValue:
      [_delegate settingsControllerWindowAlpha:self]];
  [self updateTransparencyValueLabel];
}


- (void) showBorderChanged: (id)sender
{
  [_delegate settingsController:self
	didChangeShowDockBorder:[(NSButton *)sender state] == NSOnState];
}


- (void) useCellTileChanged: (id)sender
{
  [_delegate settingsController:self
didChangeUseCellTileBackground:[(NSButton *)sender state] == NSOnState];
}


- (void) magnifyHoveredIconsChanged: (id)sender
{
  [_delegate settingsController:self
 didChangeMagnifiesHoveredIcons:[(NSButton *)sender state] == NSOnState];
  [self updateControls];
}


- (void) hoverIconScaleChanged: (id)sender
{
  [_delegate settingsController:self
	didChangeHoverIconScale:[(NSSlider *)sender floatValue]];
  [_hoverIconScaleSlider setFloatValue:
      [_delegate settingsControllerHoverIconScale:self]];
  [self updateHoverIconScaleValueLabel];
}


- (void) wiggleOnLaunchChanged: (id)sender
{
  [_delegate settingsController:self
	didChangeWigglesOnLaunch:[(NSButton *)sender state] == NSOnState];
}


- (void) wiggleOnActivationChanged: (id)sender
{
  [_delegate settingsController:self
     didChangeWigglesOnActivation:[(NSButton *)sender state] == NSOnState];
}


- (void) wiggleOnAttentionRequestChanged: (id)sender
{
  [_delegate settingsController:self
didChangeWigglesOnAttentionRequest:[(NSButton *)sender state] == NSOnState];
}


- (void) playSoundOnRemoveChanged: (id)sender
{
  [_delegate settingsController:self
 didChangePlaysSoundOnRemove:[(NSButton *)sender state] == NSOnState];
}


- (void) singleClickLaunchChanged: (id)sender
{
  [_delegate settingsController:self
didChangeSingleClickLaunchesApplications:[(NSButton *)sender state] == NSOnState];
}


- (void) dockCellSizeChanged: (id)sender
{
  NSInteger mode = [sender tag];

  if (mode != SettingsDockCellSizeMode64)
    {
      mode = SettingsDockCellSizeModeCurrent;
    }

  [_delegate settingsController:self didChangeDockCellSizeMode:mode];
  [self updateControls];
}


- (void) runningIndicatorModeChanged: (id)sender
{
  NSInteger mode = [sender tag];

  if (mode != DockRunningIndicatorModeNotRunningDots)
    {
      mode = DockRunningIndicatorModeRunningDot;
    }

  [_delegate settingsController:self
  didChangeRunningIndicatorMode:(DockRunningIndicatorMode)mode];
  [self updateControls];
}


- (void) applicationSelectionChanged: (id)sender
{
  [self updateControls];
}


- (void) applyApplicationArguments: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
       didChangeLaunchArguments:[_applicationArgumentsField stringValue]
			 forItem:item];
  [self updateControls];
}


- (void) openAtLoginChanged: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
	   didChangeOpenAtLogin:[_openAtLoginButton state] == NSOnState
			forItem:item];
  [self updateControls];
}


- (void) useDockBehaviorDefaultsChanged: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
didChangeUseDockBehaviorDefaults:[_useDockBehaviorDefaultsButton state] == NSOnState
			forItem:item];
  [self updateControls];
}


- (void) applicationWiggleOnLaunchChanged: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
 didChangeItemWigglesOnLaunch:[_applicationWiggleOnLaunchButton state] == NSOnState
			forItem:item];
  [self updateControls];
}


- (void) applicationWiggleOnActivationChanged: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
didChangeItemWigglesOnActivation:[_applicationWiggleOnActivationButton state] == NSOnState
			forItem:item];
  [self updateControls];
}


- (void) applicationWiggleOnAttentionRequestChanged: (id)sender
{
  DockItem *item = [self selectedApplicationItem];

  if (!item)
    {
      return;
    }

  [_delegate settingsController:self
didChangeItemWigglesOnAttentionRequest:[_applicationWiggleOnAttentionRequestButton state] == NSOnState
			forItem:item];
  [self updateControls];
}


- (void) moveApplicationUp: (id)sender
{
  NSUInteger index = [self selectedApplicationIndex];
  DockItem *item;

  if (index == NSNotFound || index == 0)
    {
      return;
    }

  item = RETAIN([self selectedApplicationItem]);
  [_delegate settingsController:self didMoveItemFromIndex:index toIndex:index - 1];
  [self updateControls];
  [self selectApplicationItem:item];
  [self updateControls];
  DESTROY(item);
}


- (void) moveApplicationDown: (id)sender
{
  NSArray *items = [_delegate settingsControllerDockItems:self];
  NSUInteger index = [self selectedApplicationIndex];
  DockItem *item;

  if (index == NSNotFound || index + 1 >= [items count])
    {
      return;
    }

  item = RETAIN([self selectedApplicationItem]);
  [_delegate settingsController:self didMoveItemFromIndex:index toIndex:index + 1];
  [self updateControls];
  [self selectApplicationItem:item];
  [self updateControls];
  DESTROY(item);
}


- (void) deleteApplication: (id)sender
{
  NSUInteger index = [self selectedApplicationIndex];

  if (index == NSNotFound)
    {
      return;
    }

  if (![_delegate settingsController:self canDeleteItemAtIndex:index])
    {
      return;
    }

  [_delegate settingsController:self didDeleteItemAtIndex:index];
  [self updateControls];
}


- (void) emptyRecycler: (id)sender
{
  [_delegate settingsControllerDidEmptyRecycler:self];
  [self updateControls];
}


@end
