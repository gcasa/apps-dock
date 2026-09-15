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

#import "SettingsController.h"
#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>

enum
{
  SettingsDockCellSizeModeCurrent = 0,
  SettingsDockCellSizeMode64 = 1
};

static inline CGFloat
SettingsClampedWindowAlpha(CGFloat alpha)
{
  if (alpha < 0.0)
    {
      return 0.0;
    }
  if (alpha > 1.0)
    {
      return 1.0;
    }
  return alpha;
}

@interface SettingsController (Private)
- (id) initWithDelegate: (id<SettingsControllerDelegate>)delegate;
- (void) dealloc;
- (NSTextField *) valueLabelWithFrame: (NSRect)frame;
- (void) updateTransparencyValueLabel;
- (void) updateHoverIconScaleValueLabel;
- (NSTextField *) labelWithTitle: (NSString *)title frame: (NSRect)frame;
- (NSButton *) buttonWithTitle: (NSString *)title
			 frame: (NSRect)frame
		    buttonType: (NSButtonType)buttonType
			action: (SEL)action;
- (void) createPanel;
- (NSUInteger) selectedApplicationIndex;
- (DockItem *) selectedApplicationItem;
- (void) selectApplicationItem: (DockItem *)item;
- (void) updateControls;
- (void) showWindow: (id)sender;
- (void) showWindowForItem: (DockItem *)item;
- (void) closePanel: (id)sender;
- (BOOL) windowShouldClose: (id)sender;
- (void) windowWillClose: (NSNotification *)notification;
- (void) placementChanged: (id)sender;
- (void) backgroundColorChanged: (id)sender;
- (void) transparencyChanged: (id)sender;
- (void) showBorderChanged: (id)sender;
- (void) useCellTileChanged: (id)sender;
- (void) magnifyHoveredIconsChanged: (id)sender;
- (void) hoverIconScaleChanged: (id)sender;
- (void) wiggleOnLaunchChanged: (id)sender;
- (void) wiggleOnActivationChanged: (id)sender;
- (void) wiggleOnAttentionRequestChanged: (id)sender;
- (void) playSoundOnRemoveChanged: (id)sender;
- (void) singleClickLaunchChanged: (id)sender;
- (void) dockCellSizeChanged: (id)sender;
- (void) runningIndicatorModeChanged: (id)sender;
- (void) applicationSelectionChanged: (id)sender;
- (void) applyApplicationArguments: (id)sender;
- (void) openAtLoginChanged: (id)sender;
- (void) useDockBehaviorDefaultsChanged: (id)sender;
- (void) applicationWiggleOnLaunchChanged: (id)sender;
- (void) applicationWiggleOnActivationChanged: (id)sender;
- (void) applicationWiggleOnAttentionRequestChanged: (id)sender;
- (void) moveApplicationUp: (id)sender;
- (void) moveApplicationDown: (id)sender;
- (void) deleteApplication: (id)sender;
- (void) emptyRecycler: (id)sender;
@end
