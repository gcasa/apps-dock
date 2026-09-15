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

@implementation AppController

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  NSRect frame;

  _items = [NSMutableArray new];
  _recyclerController = [RecyclerController new];
  _preferences = [DockPreferences new];
  _applicationScanner = [RunningApplicationScanner new];
  _applicationStore = [[DockApplicationStore alloc]
			initWithScanner:_applicationScanner];
  _applicationIconManager = [[ApplicationIconManager alloc]
			      initWithScanner:_applicationScanner];
  _launchedApplicationPaths = [NSMutableSet new];
  _dockPlacement = [self savedDockPlacement];
  _dockCellSizeMode = [self savedDockCellSizeMode];
  _runningIndicatorMode = [self savedRunningIndicatorMode];
  _backgroundColor = RETAIN([self savedBackgroundColor]);
  _windowAlpha = [self savedWindowAlpha];
  _useCellTileBackground = [self savedUseCellTileBackground];
  _showDockBorder = [self savedShowDockBorder];
  _magnifiesHoveredIcons = [_preferences savedMagnifiesHoveredIcons];
  _hoverIconScale = [_preferences savedHoverIconScale];
  _wigglesOnLaunch = [_preferences savedWigglesOnLaunch];
  _wigglesOnActivation = [_preferences savedWigglesOnActivation];
  _wigglesOnAttentionRequest = [_preferences savedWigglesOnAttentionRequest];
  _playsSoundOnRemove = [_preferences savedPlaysSoundOnRemove];
  _singleClickLaunchesApplications = [self savedSingleClickLaunchesApplications];
  [self loadPersistedApplications];
  frame = [self dockWindowFrameForPlacement:_dockPlacement];

  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setLevel:NSDockWindowLevel];
  [_window setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary)];
  [_window setOpaque:NO];
  [_window setAlphaValue:1.0];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setTitle:@"AppsDockWM"];
  [_window setAcceptsMouseMovedEvents:YES];

  _dockView = [[DockView alloc] initWithFrame:NSMakeRect(0, 0,
                                                         NSWidth(frame),
                                                         NSHeight(frame))];
  [_dockView setDelegate:self];
  [_dockView setHorizontal:[DockPreferences placementIsHorizontal:_dockPlacement]];
  [self applyDockCellSizeToView];
  [_dockView setBackgroundColor:_backgroundColor];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [_dockView setShowsBorder:_showDockBorder];
  [_dockView setRunningIndicatorMode:_runningIndicatorMode];
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_dockView setHoverIconScale:_hoverIconScale];
  [_dockView setSingleClickLaunchesApplications:_singleClickLaunchesApplications];
  [_dockView setItems:_items];
  [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
  [_dockView setMenu:[self dockMenu]];
  [_window setContentView:_dockView];

  [self updateDockBackground];
  [_window makeKeyAndOrderFront:nil];
  [_window orderFrontRegardless];
  [_window display];

  _x11 = [[X11DockManager alloc] initWithDockView:_dockView];
  [_x11 setDelegate:self];
  if ([_x11 start])
    {
      [_x11 makeWindowSticky:(unsigned long)[_window windowNumber]];
      [_x11 setDockPlacement:_dockPlacement];
    }

  [self performSelector:@selector(performInitialApplicationScans)
	     withObject:nil
	     afterDelay:0.5];
}

- (void) dealloc
{
  [_x11EventTimer invalidate];
  [_scanTimer invalidate];
  [_processScanTimer invalidate];
  DESTROY(_settingsController);
  DESTROY(_recyclerController);
  DESTROY(_preferences);
  DESTROY(_dockMenu);
  DESTROY(_x11);
  DESTROY(_dockView);
  DESTROY(_window);
  DESTROY(_applicationStore);
  DESTROY(_applicationIconManager);
  DESTROY(_applicationScanner);
  DESTROY(_launchedApplicationPaths);
  DESTROY(_backgroundColor);
  DESTROY(_items);
  DEALLOC;
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)sender
{
  return NO;
}

- (void) applicationWillTerminate: (NSNotification *)notification
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
