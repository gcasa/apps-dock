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
  DESTROY(_openAtLoginButton);
  DESTROY(_applyApplicationButton);
  DESTROY(_applicationArgumentsField);
  DESTROY(_applicationPopup);
  DESTROY(_hoverIconScaleSlider);
  DESTROY(_magnifyHoveredIconsButton);
  DESTROY(_showBorderButton);
  DESTROY(_useCellTileButton);
  DESTROY(_notRunningDotsButton);
  DESTROY(_runningDotButton);
  DESTROY(_cellSize64Button);
  DESTROY(_currentCellSizeButton);
  DESTROY(_transparencySlider);
  DESTROY(_backgroundColorWell);
  DESTROY(_placementPopup);
  DESTROY(_panel);
  DEALLOC;
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
	     initWithContentRect:NSMakeRect(0, 0, 460, 570)
		       styleMask:NSTitledWindowMask | NSClosableWindowMask
			 backing:NSBackingStoreBuffered
			   defer:NO];
  [_panel setTitle:@"Dock Settings"];
  [_panel setReleasedWhenClosed:NO];
  [_panel setDelegate:self];

  contentView = [_panel contentView];

  label = [self labelWithTitle:@"Placement"
			 frame:NSMakeRect(18, 526, 110, 20)];
  [contentView addSubview:label];

  _placementPopup =
    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(132, 472, 170, 26)
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
  [contentView addSubview:_placementPopup];

  [_placementPopup setFrame:NSMakeRect(132, 522, 170, 26)];

  label = [self labelWithTitle:@"Color"
			 frame:NSMakeRect(18, 482, 110, 20)];
  [contentView addSubview:label];

  _backgroundColorWell =
    [[NSColorWell alloc] initWithFrame:NSMakeRect(132, 476, 58, 32)];
  [_backgroundColorWell setTarget:self];
  [_backgroundColorWell setAction:@selector(backgroundColorChanged:)];
  [contentView addSubview:_backgroundColorWell];
  colorPanel = [NSColorPanel sharedColorPanel];
  [colorPanel setShowsAlpha:NO];
  [colorPanel setContinuous:YES];

  label = [self labelWithTitle:@"Transparency"
			 frame:NSMakeRect(18, 448, 110, 20)];
  [contentView addSubview:label];

  _transparencySlider =
    [[NSSlider alloc] initWithFrame:NSMakeRect(132, 444, 300, 24)];
  [_transparencySlider setMinValue:0.2];
  [_transparencySlider setMaxValue:1.0];
  [_transparencySlider setContinuous:YES];
  [_transparencySlider setTarget:self];
  [_transparencySlider setAction:@selector(transparencyChanged:)];
  [contentView addSubview:_transparencySlider];

  label = [self labelWithTitle:@"Icon Cells"
			 frame:NSMakeRect(18, 426, 110, 20)];
  [contentView addSubview:label];

  _cellSize64Button =
    [self buttonWithTitle:@"64 x 64"
		    frame:NSMakeRect(132, 424, 160, 24)
	       buttonType:NSRadioButton
		   action:@selector(dockCellSizeChanged:)];
  [_cellSize64Button setTag:SettingsDockCellSizeMode64];
  [contentView addSubview:_cellSize64Button];

  _currentCellSizeButton =
    [self buttonWithTitle:[_delegate settingsControllerCurrentDockCellSizeTitle:self]
		    frame:NSMakeRect(132, 400, 160, 24)
	       buttonType:NSRadioButton
		   action:@selector(dockCellSizeChanged:)];
  [_currentCellSizeButton setTag:SettingsDockCellSizeModeCurrent];
  [contentView addSubview:_currentCellSizeButton];

  label = [self labelWithTitle:@"State Dots"
			 frame:NSMakeRect(18, 354, 110, 20)];
  [contentView addSubview:label];

  _runningDotButton =
    [self buttonWithTitle:@"Dot when running"
		    frame:NSMakeRect(132, 352, 170, 24)
	       buttonType:NSRadioButton
		   action:@selector(runningIndicatorModeChanged:)];
  [_runningDotButton setTag:DockRunningIndicatorModeRunningDot];
  [contentView addSubview:_runningDotButton];

  _notRunningDotsButton =
    [self buttonWithTitle:@"Dots when stopped"
		    frame:NSMakeRect(132, 328, 170, 24)
	       buttonType:NSRadioButton
		   action:@selector(runningIndicatorModeChanged:)];
  [_notRunningDotsButton setTag:DockRunningIndicatorModeNotRunningDots];
  [contentView addSubview:_notRunningDotsButton];

  _useCellTileButton =
    [self buttonWithTitle:@"Use common_Tile"
		    frame:NSMakeRect(18, 290, 170, 24)
	       buttonType:NSSwitchButton
		   action:@selector(useCellTileChanged:)];
  [contentView addSubview:_useCellTileButton];

  _showBorderButton =
    [self buttonWithTitle:@"Show Border"
		    frame:NSMakeRect(18, 264, 140, 24)
	       buttonType:NSSwitchButton
		   action:@selector(showBorderChanged:)];
  [contentView addSubview:_showBorderButton];

  _magnifyHoveredIconsButton =
    [self buttonWithTitle:@"Magnify Icons"
		    frame:NSMakeRect(18, 226, 160, 24)
	       buttonType:NSSwitchButton
		   action:@selector(magnifyHoveredIconsChanged:)];
  [contentView addSubview:_magnifyHoveredIconsButton];

  label = [self labelWithTitle:@"Hover Size"
			 frame:NSMakeRect(18, 194, 110, 20)];
  [contentView addSubview:label];

  _hoverIconScaleSlider =
    [[NSSlider alloc] initWithFrame:NSMakeRect(132, 190, 300, 24)];
  [_hoverIconScaleSlider setMinValue:1.0];
  [_hoverIconScaleSlider setMaxValue:1.5];
  [_hoverIconScaleSlider setContinuous:YES];
  [_hoverIconScaleSlider setTarget:self];
  [_hoverIconScaleSlider setAction:@selector(hoverIconScaleChanged:)];
  [contentView addSubview:_hoverIconScaleSlider];

  label = [self labelWithTitle:@"App"
			 frame:NSMakeRect(18, 168, 110, 20)];
  [contentView addSubview:label];

  _applicationPopup =
    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(132, 164, 300, 26)
			       pullsDown:NO];
  [_applicationPopup setTarget:self];
  [_applicationPopup setAction:@selector(applicationSelectionChanged:)];
  [contentView addSubview:_applicationPopup];

  label = [self labelWithTitle:@"Arguments"
			 frame:NSMakeRect(18, 126, 110, 20)];
  [contentView addSubview:label];

  _applicationArgumentsField =
    [[NSTextField alloc] initWithFrame:NSMakeRect(132, 124, 300, 24)];
  [_applicationArgumentsField setTarget:self];
  [_applicationArgumentsField setAction:@selector(applyApplicationArguments:)];
  [contentView addSubview:_applicationArgumentsField];

  _applyApplicationButton =
    [self buttonWithTitle:@"Apply"
		    frame:NSMakeRect(132, 88, 72, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(applyApplicationArguments:)];
  [_applyApplicationButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_applyApplicationButton];

  _openAtLoginButton =
    [self buttonWithTitle:@"Open At Login"
		    frame:NSMakeRect(212, 56, 160, 24)
	       buttonType:NSSwitchButton
		   action:@selector(openAtLoginChanged:)];
  [contentView addSubview:_openAtLoginButton];

  _moveApplicationUpButton =
    [self buttonWithTitle:@"Move Up"
		    frame:NSMakeRect(212, 88, 84, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(moveApplicationUp:)];
  [_moveApplicationUpButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_moveApplicationUpButton];

  _moveApplicationDownButton =
    [self buttonWithTitle:@"Move Down"
		    frame:NSMakeRect(304, 88, 96, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(moveApplicationDown:)];
  [_moveApplicationDownButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_moveApplicationDownButton];

  _deleteApplicationButton =
    [self buttonWithTitle:@"Delete"
		    frame:NSMakeRect(132, 54, 72, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(deleteApplication:)];
  [_deleteApplicationButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_deleteApplicationButton];

  _emptyRecyclerButton =
    [self buttonWithTitle:@"Empty Recycler"
		    frame:NSMakeRect(18, 16, 120, 28)
	       buttonType:NSMomentaryPushInButton
		   action:@selector(emptyRecycler:)];
  [_emptyRecyclerButton setBezelStyle:NSRoundedBezelStyle];
  [contentView addSubview:_emptyRecyclerButton];

  closeButton = [self buttonWithTitle:@"Close"
				frame:NSMakeRect(344, 16, 88, 28)
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

      [_applicationArgumentsField setStringValue:
	  ([item launchArguments] ? [item launchArguments] : @"")];
      [_applicationArgumentsField setEnabled:hasApplicationPath];
      [_applyApplicationButton setEnabled:hasApplicationPath];
      [_openAtLoginButton setState:(openAtLogin ? NSOnState : NSOffState)];
      [_openAtLoginButton setEnabled:hasOpenAtLoginPath];
      [_moveApplicationUpButton setEnabled:(selectedIndex > 0)];
      [_moveApplicationDownButton setEnabled:
	  (selectedIndex + 1 < [items count] &&
	   (![item isPinned] || selectedIndex + 1 < pinnedCount))];
      [_deleteApplicationButton setEnabled:YES];
    }
  else
    {
      [_applicationArgumentsField setStringValue:@""];
      [_applicationArgumentsField setEnabled:NO];
      [_applyApplicationButton setEnabled:NO];
      [_openAtLoginButton setState:NSOffState];
      [_openAtLoginButton setEnabled:NO];
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
