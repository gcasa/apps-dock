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

@implementation SettingsController (Panel)

- (NSTextField *) valueLabelWithFrame: (NSRect)frame
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];

  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setAlignment:NSRightTextAlignment];
  [label setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
  return label;
}


- (NSTextField *) labelWithTitle: (NSString *)title frame: (NSRect)frame
{
  NSTextField *label = AUTORELEASE([[NSTextField alloc] initWithFrame:frame]);

  [label setStringValue:title];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
  return label;
}


- (NSButton *) buttonWithTitle: (NSString *)title
			 frame: (NSRect)frame
		    buttonType: (NSButtonType)buttonType
			action: (SEL)action
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];

  [button setTitle:title];
  [button setButtonType:buttonType];
  [button setTarget:self];
  [button setAction:action];
  return button;
}


- (void) createPanel
{
  NSView *contentView;
  NSView *dockView;
  NSView *appearanceView;
  NSView *behaviorView;
  NSView *applicationsView;
  NSTabView *tabView;
  NSTabViewItem *tabItem;
  NSTextField *label;
  NSButton *closeButton;
  NSColorPanel *colorPanel;
  NSArray *placements;
  NSUInteger i;

  if (_panel)
    {
      return;
    }

  _panel = [[NSPanel alloc]
	     initWithContentRect:NSMakeRect(0, 0, 460, 452)
		       styleMask:NSTitledWindowMask | NSClosableWindowMask
			 backing:NSBackingStoreBuffered
			   defer:NO];
  [_panel setTitle:@"Dock Settings"];
  [_panel setReleasedWhenClosed:NO];
  [_panel setDelegate:self];

  contentView = [_panel contentView];

  tabView = AUTORELEASE([[NSTabView alloc]
			  initWithFrame:NSMakeRect(12, 56, 436, 384)]);
  [contentView addSubview:tabView];

  dockView = AUTORELEASE([[NSView alloc]
			   initWithFrame:NSMakeRect(0, 0, 420, 340)]);
  tabItem = AUTORELEASE([[NSTabViewItem alloc] initWithIdentifier:@"Dock"]);
  [tabItem setLabel:@"Dock"];
  [tabItem setView:dockView];
  [tabView addTabViewItem:tabItem];

  appearanceView = AUTORELEASE([[NSView alloc]
				 initWithFrame:NSMakeRect(0, 0, 420, 340)]);
  tabItem = AUTORELEASE([[NSTabViewItem alloc] initWithIdentifier:@"Appearance"]);
  [tabItem setLabel:@"Appearance"];
  [tabItem setView:appearanceView];
  [tabView addTabViewItem:tabItem];

  behaviorView = AUTORELEASE([[NSView alloc]
			       initWithFrame:NSMakeRect(0, 0, 420, 340)]);
  tabItem = AUTORELEASE([[NSTabViewItem alloc] initWithIdentifier:@"Behavior"]);
  [tabItem setLabel:@"Behavior"];
  [tabItem setView:behaviorView];
  [tabView addTabViewItem:tabItem];

  applicationsView = AUTORELEASE([[NSView alloc]
				   initWithFrame:NSMakeRect(0, 0, 420, 340)]);
  tabItem = AUTORELEASE([[NSTabViewItem alloc] initWithIdentifier:@"Applications"]);
  [tabItem setLabel:@"Applications"];
  [tabItem setView:applicationsView];
  [tabView addTabViewItem:tabItem];

  label = [self labelWithTitle:@"Placement"
			 frame:NSMakeRect(18, 264, 110, 20)];
  [dockView addSubview:label];

  _placementPopup =
    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(132, 260, 170, 26)
			       pullsDown:NO];
  placements = [NSArray arrayWithObjects:
			  @"Left Top",
			@"Left Center",
			@"Right Top",
			@"Right Center",
			@"Top Center",
			@"Bottom Center",
			nil];
  for (i = 0; i < [placements count]; i++)
    {
      [_placementPopup addItemWithTitle:[placements objectAtIndex:i]];
      [[_placementPopup itemAtIndex:i] setTag:(NSInteger)i];
    }
  [_placementPopup setTarget:self];
  [_placementPopup setAction:@selector(placementChanged:)];
  [dockView addSubview:_placementPopup];

  [_placementPopup setFrame:NSMakeRect(132, 260, 170, 26)];

  label = [self labelWithTitle:@"Icon Cells"
			 frame:NSMakeRect(18, 218, 110, 20)];
  [dockView addSubview:label];

  _cellSize64Button =
    [self buttonWithTitle:@"64 x 64"
		    frame:NSMakeRect(132, 216, 160, 24)
	       buttonType:NSRadioButton
		   action:@selector(dockCellSizeChanged:)];
  [_cellSize64Button setTag:SettingsDockCellSizeMode64];
  [dockView addSubview:_cellSize64Button];

  _currentCellSizeButton =
    [self buttonWithTitle:[_delegate settingsControllerCurrentDockCellSizeTitle:self]
		    frame:NSMakeRect(132, 192, 160, 24)
	       buttonType:NSRadioButton
		   action:@selector(dockCellSizeChanged:)];
  [_currentCellSizeButton setTag:SettingsDockCellSizeModeCurrent];
  [dockView addSubview:_currentCellSizeButton];

  label = [self labelWithTitle:@"State Dots"
			 frame:NSMakeRect(18, 144, 110, 20)];
  [dockView addSubview:label];

  _runningDotButton =
    [self buttonWithTitle:@"Dot when running"
		    frame:NSMakeRect(132, 142, 170, 24)
	       buttonType:NSRadioButton
		   action:@selector(runningIndicatorModeChanged:)];
  [_runningDotButton setTag:DockRunningIndicatorModeRunningDot];
  [dockView addSubview:_runningDotButton];

  _notRunningDotsButton =
    [self buttonWithTitle:@"Dots when stopped"
		    frame:NSMakeRect(132, 118, 170, 24)
	       buttonType:NSRadioButton
		   action:@selector(runningIndicatorModeChanged:)];
  [_notRunningDotsButton setTag:DockRunningIndicatorModeNotRunningDots];
  [dockView addSubview:_notRunningDotsButton];

  label = [self labelWithTitle:@"Color"
			 frame:NSMakeRect(18, 264, 110, 20)];
  [appearanceView addSubview:label];

  _backgroundColorWell =
    [[NSColorWell alloc] initWithFrame:NSMakeRect(132, 258, 58, 32)];
  [_backgroundColorWell setTarget:self];
  [_backgroundColorWell setAction:@selector(backgroundColorChanged:)];
  [appearanceView addSubview:_backgroundColorWell];
  colorPanel = [NSColorPanel sharedColorPanel];
  [colorPanel setShowsAlpha:NO];
  [colorPanel setContinuous:YES];

  _transparencyLabel =
    [self labelWithTitle:@"Transparency"
		   frame:NSMakeRect(18, 222, 130, 20)];
  RETAIN(_transparencyLabel);
  [appearanceView addSubview:_transparencyLabel];

  _transparencySlider =
    [[NSSlider alloc] initWithFrame:NSMakeRect(150, 218, 220, 24)];
  [_transparencySlider setMinValue:0.0];
  [_transparencySlider setMaxValue:1.0];
  [_transparencySlider setContinuous:YES];
  [_transparencySlider setTarget:self];
  [_transparencySlider setAction:@selector(transparencyChanged:)];
  [appearanceView addSubview:_transparencySlider];
  _transparencyValueLabel =
    [self valueLabelWithFrame:NSMakeRect(378, 220, 54, 20)];
  [appearanceView addSubview:_transparencyValueLabel];

  _useCellTileButton =
    [self buttonWithTitle:@"Use common_Tile"
		    frame:NSMakeRect(18, 174, 170, 24)
	       buttonType:NSSwitchButton
		   action:@selector(useCellTileChanged:)];
  [appearanceView addSubview:_useCellTileButton];

  _showBorderButton =
    [self buttonWithTitle:@"Show Border"
		    frame:NSMakeRect(18, 148, 140, 24)
	       buttonType:NSSwitchButton
		   action:@selector(showBorderChanged:)];
  [appearanceView addSubview:_showBorderButton];

  _magnifyHoveredIconsButton =
    [self buttonWithTitle:@"Magnify Icons"
		    frame:NSMakeRect(18, 106, 160, 24)
	       buttonType:NSSwitchButton
		   action:@selector(magnifyHoveredIconsChanged:)];
  [appearanceView addSubview:_magnifyHoveredIconsButton];

  _hoverIconScaleLabel =
    [self labelWithTitle:@"Hover Size"
		   frame:NSMakeRect(18, 72, 130, 20)];
  RETAIN(_hoverIconScaleLabel);
  [appearanceView addSubview:_hoverIconScaleLabel];

  _hoverIconScaleSlider =
    [[NSSlider alloc] initWithFrame:NSMakeRect(150, 68, 220, 24)];
  [_hoverIconScaleSlider setMinValue:1.0];
  [_hoverIconScaleSlider setMaxValue:1.5];
  [_hoverIconScaleSlider setContinuous:YES];
  [_hoverIconScaleSlider setTarget:self];
  [_hoverIconScaleSlider setAction:@selector(hoverIconScaleChanged:)];
  [appearanceView addSubview:_hoverIconScaleSlider];
  _hoverIconScaleValueLabel =
    [self valueLabelWithFrame:NSMakeRect(378, 70, 54, 20)];
  [appearanceView addSubview:_hoverIconScaleValueLabel];

  _wiggleOnLaunchButton =
    [self buttonWithTitle:@"Wiggle On Launch"
		    frame:NSMakeRect(18, 264, 180, 24)
	       buttonType:NSSwitchButton
		   action:@selector(wiggleOnLaunchChanged:)];
  [behaviorView addSubview:_wiggleOnLaunchButton];

  _wiggleOnActivationButton =
    [self buttonWithTitle:@"Wiggle On Activate"
		    frame:NSMakeRect(18, 238, 180, 24)
	       buttonType:NSSwitchButton
		   action:@selector(wiggleOnActivationChanged:)];
  [behaviorView addSubview:_wiggleOnActivationButton];

  _wiggleOnAttentionRequestButton =
    [self buttonWithTitle:@"Wiggle On Attention"
		    frame:NSMakeRect(18, 212, 200, 24)
	       buttonType:NSSwitchButton
		   action:@selector(wiggleOnAttentionRequestChanged:)];
  [behaviorView addSubview:_wiggleOnAttentionRequestButton];

  _playSoundOnRemoveButton =
    [self buttonWithTitle:@"Sound On Remove"
		    frame:NSMakeRect(18, 174, 200, 24)
	       buttonType:NSSwitchButton
		   action:@selector(playSoundOnRemoveChanged:)];
  [behaviorView addSubview:_playSoundOnRemoveButton];

  _singleClickLaunchButton =
    [self buttonWithTitle:@"Single Click To Launch"
		    frame:NSMakeRect(18, 136, 220, 24)
	       buttonType:NSSwitchButton
		   action:@selector(singleClickLaunchChanged:)];
  [behaviorView addSubview:_singleClickLaunchButton];

  label = [self labelWithTitle:@"App"
			 frame:NSMakeRect(18, 296, 110, 20)];
  [applicationsView addSubview:label];

  _applicationPopup =
    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(132, 292, 280, 26)
			       pullsDown:NO];
  [_applicationPopup setTarget:self];
  [_applicationPopup setAction:@selector(applicationSelectionChanged:)];
  [applicationsView addSubview:_applicationPopup];

  label = [self labelWithTitle:@"Path"
			 frame:NSMakeRect(18, 254, 110, 20)];
  [applicationsView addSubview:label];

  _applicationPathField =
    [[NSTextField alloc] initWithFrame:NSMakeRect(132, 252, 280, 24)];
  [_applicationPathField setEditable:NO];
  [_applicationPathField setSelectable:YES];
  [applicationsView addSubview:_applicationPathField];

  label = [self labelWithTitle:@"Arguments"
			 frame:NSMakeRect(18, 222, 110, 20)];
  [applicationsView addSubview:label];

  _applicationArgumentsField =
    [[NSTextField alloc] initWithFrame:NSMakeRect(132, 220, 280, 24)];
  [_applicationArgumentsField setTarget:self];
  [_applicationArgumentsField setAction:@selector(applyApplicationArguments:)];
  [applicationsView addSubview:_applicationArgumentsField];

  _applyApplicationButton =
    [self buttonWithTitle:@"Apply"
		    frame:NSMakeRect(132, 184, 72, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(applyApplicationArguments:)];
  [_applyApplicationButton setBezelStyle:NSRoundedBezelStyle];
  [applicationsView addSubview:_applyApplicationButton];

  _openAtLoginButton =
    [self buttonWithTitle:@"Open At Login"
		    frame:NSMakeRect(132, 144, 160, 24)
	       buttonType:NSSwitchButton
		   action:@selector(openAtLoginChanged:)];
  [applicationsView addSubview:_openAtLoginButton];

  label = [self labelWithTitle:@"App Behavior"
			 frame:NSMakeRect(18, 82, 110, 20)];
  [applicationsView addSubview:label];

  _useDockBehaviorDefaultsButton =
    [self buttonWithTitle:@"Use Dock Defaults"
		    frame:NSMakeRect(132, 80, 180, 24)
	       buttonType:NSSwitchButton
		   action:@selector(useDockBehaviorDefaultsChanged:)];
  [applicationsView addSubview:_useDockBehaviorDefaultsButton];

  _applicationWiggleOnLaunchButton =
    [self buttonWithTitle:@"Wiggle On Launch"
		    frame:NSMakeRect(132, 58, 180, 24)
	       buttonType:NSSwitchButton
		   action:@selector(applicationWiggleOnLaunchChanged:)];
  [applicationsView addSubview:_applicationWiggleOnLaunchButton];

  _applicationWiggleOnActivationButton =
    [self buttonWithTitle:@"Wiggle On Activate"
		    frame:NSMakeRect(132, 36, 180, 24)
	       buttonType:NSSwitchButton
		   action:@selector(applicationWiggleOnActivationChanged:)];
  [applicationsView addSubview:_applicationWiggleOnActivationButton];

  _applicationWiggleOnAttentionRequestButton =
    [self buttonWithTitle:@"Wiggle On Attention"
		    frame:NSMakeRect(132, 14, 190, 24)
	       buttonType:NSSwitchButton
		   action:@selector(applicationWiggleOnAttentionRequestChanged:)];
  [applicationsView addSubview:_applicationWiggleOnAttentionRequestButton];

  _moveApplicationUpButton =
    [self buttonWithTitle:@"Move Up"
		    frame:NSMakeRect(212, 184, 84, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(moveApplicationUp:)];
  [_moveApplicationUpButton setBezelStyle:NSRoundedBezelStyle];
  [applicationsView addSubview:_moveApplicationUpButton];

  _moveApplicationDownButton =
    [self buttonWithTitle:@"Move Down"
		    frame:NSMakeRect(304, 184, 96, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(moveApplicationDown:)];
  [_moveApplicationDownButton setBezelStyle:NSRoundedBezelStyle];
  [applicationsView addSubview:_moveApplicationDownButton];

  _deleteApplicationButton =
    [self buttonWithTitle:@"Delete"
		    frame:NSMakeRect(132, 102, 72, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(deleteApplication:)];
  [_deleteApplicationButton setBezelStyle:NSRoundedBezelStyle];
  [applicationsView addSubview:_deleteApplicationButton];

  _emptyRecyclerButton =
    [self buttonWithTitle:@"Empty Recycler"
		    frame:NSMakeRect(212, 102, 120, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(emptyRecycler:)];
  [_emptyRecyclerButton setBezelStyle:NSRoundedBezelStyle];
  [applicationsView addSubview:_emptyRecyclerButton];

  closeButton = [self buttonWithTitle:@"Close"
				frame:NSMakeRect(360, 16, 72, 28)
			   buttonType:NSMomentaryPushInButton
			       action:@selector(closePanel:)];
  [closeButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:closeButton];
  DESTROY(closeButton);

  [self updateControls];
}


@end
