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

@interface AppController : NSObject <DockViewDelegate, X11DockManagerDelegate, NSWindowDelegate>
{
  NSWindow *_window;
  NSPanel *_settingsPanel;
  NSPopUpButton *_settingsPlacementPopup;
  NSColorWell *_settingsBackgroundColorWell;
  NSButton *_settingsCurrentCellSizeButton;
  NSButton *_settings64CellSizeButton;
  NSButton *_settingsRunningDotButton;
  NSButton *_settingsNotRunningDotsButton;
  NSButton *_settingsUseCellTileButton;
  NSButton *_settingsShowBorderButton;
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
  NSInteger _dockCellSizeMode;
  DockRunningIndicatorMode _runningIndicatorMode;
  NSColor *_backgroundColor;
  BOOL _useCellTileBackground;
  BOOL _showDockBorder;
}

- (DockPlacement) savedDockPlacement;
- (NSColor *) savedBackgroundColor;
- (void) saveBackgroundColor;
- (BOOL) savedShowDockBorder;
- (void) saveShowDockBorder;
- (NSInteger) savedDockCellSizeMode;
- (void) saveDockCellSizeMode;
- (DockRunningIndicatorMode) savedRunningIndicatorMode;
- (void) saveRunningIndicatorMode;
- (BOOL) savedUseCellTileBackground;
- (void) saveUseCellTileBackground;
- (CGFloat) activeDockPad;
- (CGFloat) activeDockGap;
- (CGFloat) activeDockWindowWidth;
- (void) applyDockCellSizeToView;
- (void) loadPersistedApplications;
- (void) savePersistedApplications;
- (BOOL) dockHasApplicationPath: (NSString *)path;
- (NSUInteger) pinnedApplicationCount;
- (NSString *) normalizedPath: (NSString *)path;
- (NSArray *) commandSearchPathComponents;
- (NSString *) procFilesystemPath;
- (NSString *) procPathForProcessIdentifierString: (NSString *)identifier;
- (BOOL) path: (NSString *)path isEqualToOrDescendantOfPath: (NSString *)parentPath;
- (NSString *) executablePathForApplicationPath: (NSString *)path;
- (NSString *) firstCommandTokenFromString: (NSString *)string;
- (NSString *) pathForExecutableCommand: (NSString *)command;
- (NSString *) executablePathForDesktopFile: (NSString *)path;
- (BOOL) stringIsProcessIdentifier: (NSString *)string;
- (NSArray *) runningProcessExecutablePaths;
- (NSString *) executablePathForProcessIdentifier: (NSNumber *)processIdentifier;
- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item;
- (BOOL) applicationItem: (DockItem *)item
matchesRunningProcessPath: (NSString *)processPath;
- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
                                    paths: (NSArray *)processPaths;
- (DockItem *) transientApplicationItemMatchingBundlePath: (NSString *)path;
- (DockItem *) applicationItemMatchingProcessIdentifier: (NSNumber *)processIdentifier;
- (DockItem *) transientApplicationItemForProcessIdentifier: (NSNumber *)processIdentifier;
- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image;
- (NSString *) x11IconCacheDirectory;
- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier;
- (NSString *) storeX11Icon: (NSImage *)icon
                 identifier: (NSString *)identifier;
- (NSString *) x11IconIdentifierForTitle: (NSString *)title
                                    path: (NSString *)path
                                  window: (unsigned long)xWindow;
- (void) applyX11Icon: (NSImage *)icon
               toItem: (DockItem *)item
           identifier: (NSString *)identifier;
- (void) rememberApplicationIcon: (NSImage *)icon
                      badgeLabel: (NSString *)badgeLabel
               processIdentifier: (NSNumber *)processIdentifier;
- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update
                             toItem: (DockItem *)item;
- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item;
- (BOOL) activateRunningApplicationWithProcessIdentifiers: (NSArray *)processIdentifiers;
- (BOOL) shouldApplyX11Icon: (NSImage *)icon toItem: (DockItem *)item;
- (void) pruneApplicationIconUpdatesForExitedProcesses;
- (BOOL) applicationBundlePathIsDockWM: (NSString *)path;
- (void) rememberLaunchedApplicationPath: (NSString *)path;
- (BOOL) windowPathMatchesLaunchedApplication: (NSString *)path;
- (NSArray *) openAtLoginApplicationPaths;
- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path;
- (void) setApplicationPath: (NSString *)path openAtLogin: (BOOL)openAtLogin;
- (BOOL) launchApplicationAtPath: (NSString *)path;
- (void) terminateApplicationItemProcesses: (DockItem *)item;
- (void) launchOpenAtLoginApplications;
- (void) performInitialApplicationScans;
- (void) scanRunningApplications;
- (NSArray *) recyclerPaths;
- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path;
- (BOOL) recyclerHasContents;
- (NSString *) recyclerPathForDropping;
- (NSString *) recyclerDestinationPathForPath: (NSString *)path
                                 recyclerPath: (NSString *)recyclerPath;
- (BOOL) movePathToRecyclerFallback: (NSString *)path
                        recyclerPath: (NSString *)recyclerPath;
- (void) updateRecyclerState;
- (void) emptyRecyclerPath: (NSString *)path;
- (void) emptyRecycler: (id)sender;
- (NSRect) dockWindowFrameForPlacement: (DockPlacement)placement;
- (void) updateDockMenu;
- (NSMenu *) dockMenu;
- (NSTextField *) settingsLabelWithTitle: (NSString *)title
                                   frame: (NSRect)frame;
- (NSButton *) settingsButtonWithTitle: (NSString *)title
                                 frame: (NSRect)frame
                            buttonType: (NSButtonType)buttonType
                                action: (SEL)action;
- (void) createSettingsPanel;
- (void) updateSettingsPanelControls;
- (void) showSettingsPanel: (id)sender;
- (void) closeSettingsPanel: (id)sender;
- (void) settingsPlacementChanged: (id)sender;
- (void) settingsBackgroundColorChanged: (id)sender;
- (void) settingsShowBorderChanged: (id)sender;
- (void) settingsUseCellTileChanged: (id)sender;
- (void) settingsDockCellSizeChanged: (id)sender;
- (void) settingsRunningIndicatorModeChanged: (id)sender;
- (void) applyDockPlacement;
- (void) updateDockBackground;
- (void) quitDock: (id)sender;
- (void) refreshDock;
- (DockItem *) itemForXWindow: (unsigned long)xWindow;
- (DockItem *) itemForApplicationIconWindow: (unsigned long)xWindow;
- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item;
- (void) removeApplicationIconWindowsForItem: (DockItem *)item;
- (void) restoreApplicationItemAfterExit: (DockItem *)item;
- (NSUInteger) indexForItem: (DockItem *)targetItem;
- (DockItem *) applicationItemMatchingTitle: (NSString *)title;
- (DockItem *) applicationItemMatchingExecutablePath: (NSString *)path;
- (BOOL) launchDesktopFile: (NSString *)path;

@end
