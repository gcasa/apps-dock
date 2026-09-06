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

#import <AppKit/AppKit.h>
#import "DockView.h"
#import "X11DockManager.h"

@class DockItem;
@class SettingsController;

@protocol SettingsControllerDelegate
- (DockPlacement) settingsControllerDockPlacement: (SettingsController *)controller;
- (NSString *) settingsControllerCurrentDockCellSizeTitle: (SettingsController *)controller;
- (NSInteger) settingsControllerDockCellSizeMode: (SettingsController *)controller;
- (DockRunningIndicatorMode) settingsControllerRunningIndicatorMode: (SettingsController *)controller;
- (NSColor *) settingsControllerBackgroundColor: (SettingsController *)controller;
- (CGFloat) settingsControllerWindowAlpha: (SettingsController *)controller;
- (BOOL) settingsControllerUsesCellTileBackground: (SettingsController *)controller;
- (BOOL) settingsControllerShowsDockBorder: (SettingsController *)controller;
- (BOOL) settingsControllerMagnifiesHoveredIcons: (SettingsController *)controller;
- (CGFloat) settingsControllerHoverIconScale: (SettingsController *)controller;
- (BOOL) settingsControllerWigglesOnLaunch: (SettingsController *)controller;
- (BOOL) settingsControllerWigglesOnActivation: (SettingsController *)controller;
- (BOOL) settingsControllerWigglesOnAttentionRequest: (SettingsController *)controller;
- (BOOL) settingsControllerPlaysSoundOnRemove: (SettingsController *)controller;
- (BOOL) settingsControllerRecyclerHasContents: (SettingsController *)controller;
- (NSArray *) settingsControllerDockItems: (SettingsController *)controller;
- (NSUInteger) settingsControllerPinnedItemCount: (SettingsController *)controller;
- (BOOL) settingsController: (SettingsController *)controller
	       itemIsDockWM: (DockItem *)item;
- (BOOL) settingsController: (SettingsController *)controller
	 itemIsOpenAtLogin: (DockItem *)item;
- (void) settingsController: (SettingsController *)controller
     didChangeDockPlacement: (DockPlacement)placement;
- (void) settingsController: (SettingsController *)controller
   didChangeBackgroundColor: (NSColor *)color;
- (void) settingsController: (SettingsController *)controller
       didChangeWindowAlpha: (CGFloat)alpha;
- (void) settingsController: (SettingsController *)controller
    didChangeShowDockBorder: (BOOL)showBorder;
- (void) settingsController: (SettingsController *)controller
didChangeUseCellTileBackground: (BOOL)useCellTileBackground;
- (void) settingsController: (SettingsController *)controller
didChangeMagnifiesHoveredIcons: (BOOL)magnifiesHoveredIcons;
- (void) settingsController: (SettingsController *)controller
didChangeHoverIconScale: (CGFloat)scale;
- (void) settingsController: (SettingsController *)controller
  didChangeWigglesOnLaunch: (BOOL)wiggles;
- (void) settingsController: (SettingsController *)controller
didChangeWigglesOnActivation: (BOOL)wiggles;
- (void) settingsController: (SettingsController *)controller
didChangeWigglesOnAttentionRequest: (BOOL)wiggles;
- (void) settingsController: (SettingsController *)controller
didChangePlaysSoundOnRemove: (BOOL)playsSound;
- (void) settingsController: (SettingsController *)controller
  didChangeDockCellSizeMode: (NSInteger)mode;
- (void) settingsController: (SettingsController *)controller
didChangeRunningIndicatorMode: (DockRunningIndicatorMode)mode;
- (void) settingsController: (SettingsController *)controller
   didChangeLaunchArguments: (NSString *)arguments
		    forItem: (DockItem *)item;
- (void) settingsController: (SettingsController *)controller
       didChangeOpenAtLogin: (BOOL)openAtLogin
		    forItem: (DockItem *)item;
- (void) settingsController: (SettingsController *)controller
       didMoveItemFromIndex: (NSUInteger)fromIndex
		    toIndex: (NSUInteger)toIndex;
- (void) settingsController: (SettingsController *)controller
       didDeleteItemAtIndex: (NSUInteger)index;
- (void) settingsControllerDidEmptyRecycler: (SettingsController *)controller;
@end

@interface SettingsController : NSObject <NSWindowDelegate>
{
  id<SettingsControllerDelegate> _delegate;
  NSPanel *_panel;
  NSPopUpButton *_placementPopup;
  NSColorWell *_backgroundColorWell;
  NSSlider *_transparencySlider;
  NSButton *_currentCellSizeButton;
  NSButton *_cellSize64Button;
  NSButton *_runningDotButton;
  NSButton *_notRunningDotsButton;
  NSButton *_useCellTileButton;
  NSButton *_showBorderButton;
  NSButton *_magnifyHoveredIconsButton;
  NSSlider *_hoverIconScaleSlider;
  NSButton *_wiggleOnLaunchButton;
  NSButton *_wiggleOnActivationButton;
  NSButton *_wiggleOnAttentionRequestButton;
  NSButton *_playSoundOnRemoveButton;
  NSButton *_emptyRecyclerButton;
  NSPopUpButton *_applicationPopup;
  NSTextField *_applicationArgumentsField;
  NSButton *_applyApplicationButton;
  NSButton *_openAtLoginButton;
  NSButton *_moveApplicationUpButton;
  NSButton *_moveApplicationDownButton;
  NSButton *_deleteApplicationButton;
}

- (id) initWithDelegate: (id<SettingsControllerDelegate>)delegate;
- (void) showWindow: (id)sender;
- (void) showWindowForItem: (DockItem *)item;
- (void) updateControls;

@end
