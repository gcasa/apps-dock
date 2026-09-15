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

@implementation AppController (Settings)

- (void) updateDockMenu
{
  [_settingsController updateControls];
}

- (NSMenu *) dockMenu
{
  if (!_dockMenu)
    {
      NSMenuItem *item;

      _dockMenu = [[NSMenu alloc] initWithTitle:@"Dock"];

      item = [[NSMenuItem alloc] initWithTitle:@"Settings..."
					action:@selector(showSettingsPanel:)
				 keyEquivalent:@","];
      [item setTarget:self];
      [_dockMenu addItem:item];
      DESTROY(item);

      [_dockMenu addItem:[NSMenuItem separatorItem]];

      item = [[NSMenuItem alloc] initWithTitle:@"Quit"
					action:@selector(quitDock:)
				 keyEquivalent:@"q"];
      [item setTarget:self];
      [_dockMenu addItem:item];
      DESTROY(item);
    }

  [self updateDockMenu];
  return _dockMenu;
}

- (SettingsController *) settingsController
{
  if (!_settingsController)
    {
      _settingsController = [[SettingsController alloc] initWithDelegate:self];
    }

  return _settingsController;
}

- (void) showSettingsPanel: (id)sender
{
  [[self settingsController] showWindow:sender];
}

- (void) showSettingsForDockItem: (DockItem *)item
{
  [[self settingsController] showWindowForItem:item];
}

- (DockPlacement) settingsControllerDockPlacement: (SettingsController *)controller
{
  return _dockPlacement;
}

- (NSString *) settingsControllerCurrentDockCellSizeTitle: (SettingsController *)controller
{
  return [DockPreferences largerCellSizeTitle];
}

- (NSInteger) settingsControllerDockCellSizeMode: (SettingsController *)controller
{
  return _dockCellSizeMode;
}

- (DockRunningIndicatorMode) settingsControllerRunningIndicatorMode: (SettingsController *)controller
{
  return _runningIndicatorMode;
}

- (NSColor *) settingsControllerBackgroundColor: (SettingsController *)controller
{
  return [DockPreferences calibratedBackgroundColor:_backgroundColor];
}

- (CGFloat) settingsControllerWindowAlpha: (SettingsController *)controller
{
  return _windowAlpha;
}

- (BOOL) settingsControllerUsesCellTileBackground: (SettingsController *)controller
{
  return _useCellTileBackground;
}

- (BOOL) settingsControllerShowsDockBorder: (SettingsController *)controller
{
  return _showDockBorder;
}

- (BOOL) settingsControllerMagnifiesHoveredIcons: (SettingsController *)controller
{
  return _magnifiesHoveredIcons;
}

- (CGFloat) settingsControllerHoverIconScale: (SettingsController *)controller
{
  return _hoverIconScale;
}

- (BOOL) settingsControllerWigglesOnLaunch: (SettingsController *)controller
{
  return _wigglesOnLaunch;
}

- (BOOL) settingsControllerWigglesOnActivation: (SettingsController *)controller
{
  return _wigglesOnActivation;
}

- (BOOL) settingsControllerWigglesOnAttentionRequest: (SettingsController *)controller
{
  return _wigglesOnAttentionRequest;
}

- (BOOL) settingsControllerPlaysSoundOnRemove: (SettingsController *)controller
{
  return _playsSoundOnRemove;
}

- (BOOL) settingsControllerSingleClickLaunchesApplications: (SettingsController *)controller
{
  return _singleClickLaunchesApplications;
}

- (BOOL) settingsControllerRecyclerHasContents: (SettingsController *)controller
{
  return [self recyclerHasContents];
}

- (NSArray *) settingsControllerDockItems: (SettingsController *)controller
{
  [self resolvePathsForX11WindowItems];
  return _items;
}

- (NSUInteger) settingsControllerPinnedItemCount: (SettingsController *)controller
{
  return [self pinnedApplicationCount];
}

- (BOOL) settingsController: (SettingsController *)controller
	       itemIsDockWM: (DockItem *)item
{
  return [self applicationBundlePathIsDockWM:[item path]];
}

- (BOOL) settingsController: (SettingsController *)controller
	 itemIsOpenAtLogin: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return NO;
    }

  return [self applicationPathIsOpenAtLogin:[item path]];
}

- (BOOL) settingsController: (SettingsController *)controller
itemUsesDockBehaviorDefaults: (DockItem *)item
{
  return [item usesDockBehaviorDefaults];
}

- (BOOL) settingsController: (SettingsController *)controller
	itemWigglesOnLaunch: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ? _wigglesOnLaunch : [item wigglesOnLaunch];
}

- (BOOL) settingsController: (SettingsController *)controller
    itemWigglesOnActivation: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ?
    _wigglesOnActivation : [item wigglesOnActivation];
}

- (BOOL) settingsController: (SettingsController *)controller
itemWigglesOnAttentionRequest: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ?
    _wigglesOnAttentionRequest : [item wigglesOnAttentionRequest];
}

- (void) settingsController: (SettingsController *)controller
     didChangeDockPlacement: (DockPlacement)placement
{
  _dockPlacement = placement;
  [self applyDockPlacement];
}

- (void) settingsController: (SettingsController *)controller
   didChangeBackgroundColor: (NSColor *)color
{
  ASSIGN(_backgroundColor, [DockPreferences calibratedBackgroundColor:color]);
  [_dockView setBackgroundColor:_backgroundColor];
  [self saveBackgroundColor];
}

- (void) settingsController: (SettingsController *)controller
       didChangeWindowAlpha: (CGFloat)alpha
{
  _windowAlpha = alpha;
  [_window setAlphaValue:1.0];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [self saveWindowAlpha];
}

- (void) settingsController: (SettingsController *)controller
    didChangeShowDockBorder: (BOOL)showBorder
{
  _showDockBorder = showBorder;
  [_dockView setShowsBorder:_showDockBorder];
  [self saveShowDockBorder];
}

- (void) settingsController: (SettingsController *)controller
didChangeUseCellTileBackground: (BOOL)useCellTileBackground
{
  _useCellTileBackground = useCellTileBackground;
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [self saveUseCellTileBackground];
}

- (void) settingsController: (SettingsController *)controller
didChangeMagnifiesHoveredIcons: (BOOL)magnifiesHoveredIcons
{
  _magnifiesHoveredIcons = magnifiesHoveredIcons;
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_preferences saveMagnifiesHoveredIcons:_magnifiesHoveredIcons];
}

- (void) settingsController: (SettingsController *)controller
didChangeHoverIconScale: (CGFloat)scale
{
  if (scale < 1.0)
    {
      scale = 1.0;
    }
  else if (scale > 1.5)
    {
      scale = 1.5;
    }

  _hoverIconScale = scale;
  [_dockView setHoverIconScale:_hoverIconScale];
  [_preferences saveHoverIconScale:_hoverIconScale];
}

- (void) settingsController: (SettingsController *)controller
  didChangeWigglesOnLaunch: (BOOL)wiggles
{
  _wigglesOnLaunch = wiggles;
  [_preferences saveWigglesOnLaunch:_wigglesOnLaunch];
}

- (void) settingsController: (SettingsController *)controller
didChangeWigglesOnActivation: (BOOL)wiggles
{
  _wigglesOnActivation = wiggles;
  [_preferences saveWigglesOnActivation:_wigglesOnActivation];
}

- (void) settingsController: (SettingsController *)controller
didChangeWigglesOnAttentionRequest: (BOOL)wiggles
{
  _wigglesOnAttentionRequest = wiggles;
  [_preferences saveWigglesOnAttentionRequest:_wigglesOnAttentionRequest];
}

- (void) settingsController: (SettingsController *)controller
didChangePlaysSoundOnRemove: (BOOL)playsSound
{
  _playsSoundOnRemove = playsSound;
  [_preferences savePlaysSoundOnRemove:_playsSoundOnRemove];
}

- (void) settingsController: (SettingsController *)controller
didChangeSingleClickLaunchesApplications: (BOOL)singleClickLaunches
{
  _singleClickLaunchesApplications = singleClickLaunches;
  [_dockView setSingleClickLaunchesApplications:_singleClickLaunchesApplications];
  [_preferences saveSingleClickLaunchesApplications:_singleClickLaunchesApplications];
}

- (void) settingsController: (SettingsController *)controller
  didChangeDockCellSizeMode: (NSInteger)mode
{
  if (mode != DockCellSizeMode64)
    {
      mode = DockCellSizeModeCurrent;
    }

  if (_dockCellSizeMode != mode)
    {
      _dockCellSizeMode = mode;
      [self saveDockCellSizeMode];
      [self applyDockPlacement];
    }
}

- (void) settingsController: (SettingsController *)controller
didChangeRunningIndicatorMode: (DockRunningIndicatorMode)mode
{
  if (mode != DockRunningIndicatorModeNotRunningDots)
    {
      mode = DockRunningIndicatorModeRunningDot;
    }

  if (_runningIndicatorMode != mode)
    {
      _runningIndicatorMode = mode;
      [_dockView setRunningIndicatorMode:_runningIndicatorMode];
      [self saveRunningIndicatorMode];
    }
}

- (void) settingsController: (SettingsController *)controller
   didChangeLaunchArguments: (NSString *)arguments
		    forItem: (DockItem *)item
{
  if ([item kind] != DockItemApplication || ![[item path] length])
    {
      return;
    }

  [item setLaunchArguments:arguments];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
       didChangeOpenAtLogin: (BOOL)openAtLogin
		    forItem: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (!([item kind] == DockItemApplication ||
	[item kind] == DockItemX11Window) ||
      ![[item path] length])
    {
      return;
    }

  [self setApplicationPath:[item path] openAtLogin:openAtLogin];
}

- (void) settingsController: (SettingsController *)controller
didChangeUseDockBehaviorDefaults: (BOOL)usesDefaults
		    forItem: (DockItem *)item
{
  if (!([item kind] == DockItemApplication || [item kind] == DockItemX11Window))
    {
      return;
    }

  if (!usesDefaults && [item usesDockBehaviorDefaults])
    {
      [item setWigglesOnLaunch:_wigglesOnLaunch];
      [item setWigglesOnActivation:_wigglesOnActivation];
      [item setWigglesOnAttentionRequest:_wigglesOnAttentionRequest];
    }
  [item setUsesDockBehaviorDefaults:usesDefaults];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
 didChangeItemWigglesOnLaunch: (BOOL)wiggles
		    forItem: (DockItem *)item
{
  [item setUsesDockBehaviorDefaults:NO];
  [item setWigglesOnLaunch:wiggles];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
didChangeItemWigglesOnActivation: (BOOL)wiggles
		    forItem: (DockItem *)item
{
  [item setUsesDockBehaviorDefaults:NO];
  [item setWigglesOnActivation:wiggles];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
didChangeItemWigglesOnAttentionRequest: (BOOL)wiggles
		    forItem: (DockItem *)item
{
  [item setUsesDockBehaviorDefaults:NO];
  [item setWigglesOnAttentionRequest:wiggles];
  [self savePersistedApplications];
}

- (void) settingsController: (SettingsController *)controller
       didMoveItemFromIndex: (NSUInteger)fromIndex
		    toIndex: (NSUInteger)toIndex
{
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  DockItem *item;

  if (fromIndex >= [_items count] || toIndex >= [_items count])
    {
      return;
    }

  item = RETAIN([_items objectAtIndex:fromIndex]);
  if ([item isPinned] && toIndex >= pinnedCount)
    {
      DESTROY(item);
      return;
    }

  [_items removeObjectAtIndex:fromIndex];
  if (![item isPinned] && toIndex < pinnedCount)
    {
      [item setPinned:YES];
    }
  [_items insertObject:item atIndex:toIndex];
  [self savePersistedApplications];
  [self refreshDock];
  DESTROY(item);
}

- (void) settingsController: (SettingsController *)controller
       didDeleteItemAtIndex: (NSUInteger)index
{
  DockItem *item;

  if (index >= [_items count])
    {
      return;
    }

  item = [_items objectAtIndex:index];
  if (([item kind] == DockItemApplication ||
       [item kind] == DockItemX11Window) &&
      [[item path] length])
    {
      [self setApplicationPath:[item path] openAtLogin:NO];
    }
  [_items removeObjectAtIndex:index];
  [self savePersistedApplications];
  [self refreshDock];
  [self playDockRemovalSoundIfEnabled];
}

- (void) settingsControllerDidEmptyRecycler: (SettingsController *)controller
{
  [self emptyRecycler:self];
}

@end
