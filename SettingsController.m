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

static CGFloat
SettingsClampedWindowAlpha(CGFloat alpha)
{
  if (alpha < 0.2)
    {
      return 0.2;
    }
  if (alpha > 1.0)
    {
      return 1.0;
    }
  return alpha;
}

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
  [_transparencySlider setMinValue:0.2];
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

- (NSUInteger) selectedApplicationIndex
{
  id selectedItem;
  id representedObject;
  NSArray *items;

  if (!_applicationPopup || [_applicationPopup numberOfItems] == 0)
    {
      return NSNotFound;
    }

  items = [_delegate settingsControllerDockItems:self];
  selectedItem = [_applicationPopup selectedItem];
  representedObject = [selectedItem representedObject];
  if ([representedObject respondsToSelector:@selector(unsignedIntegerValue)])
    {
      NSUInteger index = [representedObject unsignedIntegerValue];

      if (index < [items count])
	{
	  return index;
	}
    }

  return NSNotFound;
}

- (DockItem *) selectedApplicationItem
{
  NSArray *items = [_delegate settingsControllerDockItems:self];
  NSUInteger index = [self selectedApplicationIndex];

  if (index == NSNotFound || index >= [items count])
    {
      return nil;
    }

  return [items objectAtIndex:index];
}

- (void) selectApplicationItem: (DockItem *)item
{
  NSInteger i;
  NSArray *items;

  if (!_applicationPopup || !item)
    {
      return;
    }

  items = [_delegate settingsControllerDockItems:self];
  for (i = 0; i < [_applicationPopup numberOfItems]; i++)
    {
      id representedObject = [[_applicationPopup itemAtIndex:i] representedObject];

      if ([representedObject respondsToSelector:@selector(unsignedIntegerValue)] &&
	  [representedObject unsignedIntegerValue] < [items count] &&
	  [items objectAtIndex:[representedObject unsignedIntegerValue]] == item)
	{
	  [_applicationPopup selectItemAtIndex:i];
	  break;
	}
    }
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

  [_delegate settingsController:self didDeleteItemAtIndex:index];
  [self updateControls];
}

- (void) emptyRecycler: (id)sender
{
  [_delegate settingsControllerDidEmptyRecycler:self];
  [self updateControls];
}

@end
