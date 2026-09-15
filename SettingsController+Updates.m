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

@implementation SettingsController (Updates)

- (void) updateTransparencyValueLabel
{
  NSInteger percent =
    (NSInteger)([_transparencySlider floatValue] * 100.0 + 0.5);

  [_transparencyValueLabel setStringValue:
      [NSString stringWithFormat:@"%ld%%", (long)percent]];
  [_transparencyLabel setStringValue:
      [NSString stringWithFormat:@"Transparency %ld%%", (long)percent]];
}


- (void) updateHoverIconScaleValueLabel
{
  NSInteger percent =
    (NSInteger)(([_hoverIconScaleSlider floatValue] - 1.0) * 100.0 + 0.5);

  [_hoverIconScaleValueLabel setStringValue:
      [NSString stringWithFormat:@"+%ld%%", (long)percent]];
  [_hoverIconScaleLabel setStringValue:
      [NSString stringWithFormat:@"Hover Size +%ld%%", (long)percent]];
}


- (void) updateControls
{
  NSColor *color;
  DockItem *selectedItem = nil;
  NSUInteger selectedIndex = NSNotFound;
  NSUInteger i;
  NSUInteger selectedPopupIndex = NSNotFound;
  NSArray *items;
  NSInteger cellSizeMode;
  DockRunningIndicatorMode runningIndicatorMode;

  if (!_panel)
    {
      return;
    }

  items = [_delegate settingsControllerDockItems:self];
  selectedIndex = [self selectedApplicationIndex];
  if (selectedIndex != NSNotFound)
    {
      selectedItem = [items objectAtIndex:selectedIndex];
    }

  [_placementPopup selectItemWithTag:
		     (NSInteger)[_delegate settingsControllerDockPlacement:self]];

  cellSizeMode = [_delegate settingsControllerDockCellSizeMode:self];
  [_currentCellSizeButton setTitle:
			    [_delegate settingsControllerCurrentDockCellSizeTitle:self]];
  [_currentCellSizeButton setState:
      (cellSizeMode == SettingsDockCellSizeModeCurrent ? NSOnState : NSOffState)];
  [_cellSize64Button setState:
      (cellSizeMode == SettingsDockCellSizeMode64 ? NSOnState : NSOffState)];

  runningIndicatorMode = [_delegate settingsControllerRunningIndicatorMode:self];
  [_runningDotButton setState:
      (runningIndicatorMode == DockRunningIndicatorModeRunningDot ?
       NSOnState : NSOffState)];
  [_notRunningDotsButton setState:
      (runningIndicatorMode == DockRunningIndicatorModeNotRunningDots ?
       NSOnState : NSOffState)];

  [_useCellTileButton setState:
      ([_delegate settingsControllerUsesCellTileBackground:self] ?
       NSOnState : NSOffState)];
  [_transparencySlider setFloatValue:
      [_delegate settingsControllerWindowAlpha:self]];
  [self updateTransparencyValueLabel];
  if (![_panel isVisible])
    {
      color = [_delegate settingsControllerBackgroundColor:self];
      [_backgroundColorWell setColor:color ? color : [NSColor blackColor]];
    }
  [_showBorderButton setState:
      ([_delegate settingsControllerShowsDockBorder:self] ?
       NSOnState : NSOffState)];
  [_magnifyHoveredIconsButton setState:
      ([_delegate settingsControllerMagnifiesHoveredIcons:self] ?
       NSOnState : NSOffState)];
  [_hoverIconScaleSlider setFloatValue:
      [_delegate settingsControllerHoverIconScale:self]];
  [_hoverIconScaleSlider setEnabled:
      [_delegate settingsControllerMagnifiesHoveredIcons:self]];
  [self updateHoverIconScaleValueLabel];
  [_wiggleOnLaunchButton setState:
      ([_delegate settingsControllerWigglesOnLaunch:self] ?
       NSOnState : NSOffState)];
  [_wiggleOnActivationButton setState:
      ([_delegate settingsControllerWigglesOnActivation:self] ?
       NSOnState : NSOffState)];
  [_wiggleOnAttentionRequestButton setState:
      ([_delegate settingsControllerWigglesOnAttentionRequest:self] ?
       NSOnState : NSOffState)];
  [_playSoundOnRemoveButton setState:
      ([_delegate settingsControllerPlaysSoundOnRemove:self] ?
       NSOnState : NSOffState)];
  [_singleClickLaunchButton setState:
      ([_delegate settingsControllerSingleClickLaunchesApplications:self] ?
       NSOnState : NSOffState)];
  [_emptyRecyclerButton setEnabled:
      [_delegate settingsControllerRecyclerHasContents:self]];

  [_applicationPopup removeAllItems];
  for (i = 0; i < [items count]; i++)
    {
      DockItem *item = [items objectAtIndex:i];

      if (([item kind] == DockItemApplication ||
	   [item kind] == DockItemX11Window) &&
	  ![_delegate settingsController:self itemIsDockWM:item])
	{
	  NSString *title = [item title];

	  if (![item isPinned])
	    {
	      title = [NSString stringWithFormat:@"%@ (Not Docked)", title];
	    }
	  if ([item kind] == DockItemX11Window)
	    {
	      title = [NSString stringWithFormat:@"%@ (WindowMaker)", title];
	    }

	  [_applicationPopup addItemWithTitle:title];
	  [[_applicationPopup lastItem]
	    setRepresentedObject:[NSNumber numberWithUnsignedInteger:i]];
	  if (item == selectedItem)
	    {
	      selectedPopupIndex = [_applicationPopup numberOfItems] - 1;
	    }
	}
    }

  if (selectedPopupIndex != NSNotFound)
    {
      [_applicationPopup selectItemAtIndex:selectedPopupIndex];
    }
  else if ([_applicationPopup numberOfItems] > 0)
    {
      [_applicationPopup selectItemAtIndex:0];
    }

  selectedIndex = [self selectedApplicationIndex];
  if (selectedIndex != NSNotFound)
    {
      DockItem *item = [items objectAtIndex:selectedIndex];
      NSUInteger pinnedCount = [_delegate settingsControllerPinnedItemCount:self];
      BOOL openAtLogin = [_delegate settingsController:self itemIsOpenAtLogin:item];
      BOOL hasApplicationPath = [item kind] == DockItemApplication &&
	[[item path] length] > 0;
      BOOL hasOpenAtLoginPath =
	([item kind] == DockItemApplication || [item kind] == DockItemX11Window) &&
	[[item path] length] > 0;
      BOOL hasPersistedApplicationSettings =
	[item kind] == DockItemApplication && [item isPinned] &&
	[[item path] length] > 0;
      BOOL usesDockBehaviorDefaults =
	[_delegate settingsController:self itemUsesDockBehaviorDefaults:item];

      [_applicationPathField setStringValue:
	  ([item path] ? [item path] : @"")];
      [_applicationPathField setToolTip:
	  ([item path] ? [item path] : @"")];
      [_applicationArgumentsField setStringValue:
	  ([item launchArguments] ? [item launchArguments] : @"")];
      [_applicationArgumentsField setEnabled:hasApplicationPath];
      [_applyApplicationButton setEnabled:hasApplicationPath];
      [_openAtLoginButton setState:(openAtLogin ? NSOnState : NSOffState)];
      [_openAtLoginButton setEnabled:hasOpenAtLoginPath];
      [_useDockBehaviorDefaultsButton setState:
	  (usesDockBehaviorDefaults ? NSOnState : NSOffState)];
      [_useDockBehaviorDefaultsButton setEnabled:hasPersistedApplicationSettings];
      [_applicationWiggleOnLaunchButton setState:
	  ([_delegate settingsController:self itemWigglesOnLaunch:item] ?
	   NSOnState : NSOffState)];
      [_applicationWiggleOnLaunchButton setEnabled:
	  hasPersistedApplicationSettings && !usesDockBehaviorDefaults];
      [_applicationWiggleOnActivationButton setState:
	  ([_delegate settingsController:self itemWigglesOnActivation:item] ?
	   NSOnState : NSOffState)];
      [_applicationWiggleOnActivationButton setEnabled:
	  hasPersistedApplicationSettings && !usesDockBehaviorDefaults];
      [_applicationWiggleOnAttentionRequestButton setState:
	  ([_delegate settingsController:self itemWigglesOnAttentionRequest:item] ?
	   NSOnState : NSOffState)];
      [_applicationWiggleOnAttentionRequestButton setEnabled:
	  hasPersistedApplicationSettings && !usesDockBehaviorDefaults];
      [_moveApplicationUpButton setEnabled:(selectedIndex > 0)];
      [_moveApplicationDownButton setEnabled:
	  (selectedIndex + 1 < [items count] &&
	   (![item isPinned] || selectedIndex + 1 < pinnedCount))];
      [_deleteApplicationButton setEnabled:YES];
    }
  else
    {
      [_applicationPathField setStringValue:@""];
      [_applicationPathField setToolTip:@""];
      [_applicationArgumentsField setStringValue:@""];
      [_applicationArgumentsField setEnabled:NO];
      [_applyApplicationButton setEnabled:NO];
      [_openAtLoginButton setState:NSOffState];
      [_openAtLoginButton setEnabled:NO];
      [_useDockBehaviorDefaultsButton setState:NSOffState];
      [_useDockBehaviorDefaultsButton setEnabled:NO];
      [_applicationWiggleOnLaunchButton setState:NSOffState];
      [_applicationWiggleOnLaunchButton setEnabled:NO];
      [_applicationWiggleOnActivationButton setState:NSOffState];
      [_applicationWiggleOnActivationButton setEnabled:NO];
      [_applicationWiggleOnAttentionRequestButton setState:NSOffState];
      [_applicationWiggleOnAttentionRequestButton setEnabled:NO];
      [_moveApplicationUpButton setEnabled:NO];
      [_moveApplicationDownButton setEnabled:NO];
      [_deleteApplicationButton setEnabled:NO];
    }
}


@end
