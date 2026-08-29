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

@interface AppController : NSObject <DockViewDelegate, X11DockManagerDelegate, NSWindowDelegate>
{
  NSWindow *_window;
  NSPanel *_settingsPanel;
  NSPopUpButton *_settingsPlacementPopup;
  NSColorWell *_settingsBackgroundColorWell;
  NSSlider *_settingsRedSlider;
  NSSlider *_settingsGreenSlider;
  NSSlider *_settingsBlueSlider;
  NSButton *_settingsEmptyRecyclerButton;
  DockView *_dockView;
  NSMutableArray *_items;
  NSMutableSet *_launchedApplicationPaths;
  NSMutableDictionary *_applicationIconWindowItems;
  NSMutableDictionary *_applicationIconUpdatesByProcessID;
  X11DockManager *_x11;
  NSTimer *_x11EventTimer;
  NSTimer *_scanTimer;
  NSTimer *_processScanTimer;
  NSMenu *_dockMenu;
  DockPlacement _dockPlacement;
  NSColor *_backgroundColor;
}

@end
