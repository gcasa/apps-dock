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

#import "AppController.h"
#import "ApplicationIconManager.h"
#import "DockApplicationStore.h"
#import "DockItem.h"
#import "DockPreferences.h"
#import "RecyclerController.h"
#import "RunningApplicationScanner.h"
#import <GNUstepBase/GNUstep.h>
#import <signal.h>
#import <unistd.h>

@interface AppController (SettingsDelegate) <SettingsControllerDelegate>
@end

@interface AppController (X11Delegate) <X11DockManagerDelegate>
@end

@interface AppController (Private)
- (DockPlacement) savedDockPlacement;
- (NSColor *) savedBackgroundColor;
- (void) saveBackgroundColor;
- (CGFloat) savedWindowAlpha;
- (void) saveWindowAlpha;
- (BOOL) savedShowDockBorder;
- (void) saveShowDockBorder;
- (NSInteger) savedDockCellSizeMode;
- (void) saveDockCellSizeMode;
- (DockRunningIndicatorMode) savedRunningIndicatorMode;
- (void) saveRunningIndicatorMode;
- (BOOL) savedUseCellTileBackground;
- (void) saveUseCellTileBackground;
- (BOOL) savedSingleClickLaunchesApplications;
- (CGFloat) activeDockPad;
- (CGFloat) activeDockGap;
- (CGFloat) activeDockWindowWidth;
- (void) applyDockCellSizeToView;
- (void) loadPersistedApplications;
- (void) savePersistedApplications;
- (void) playDockRemovalSoundIfEnabled;
- (id) persistedApplicationRecordForItem: (DockItem *)item;
- (NSString *) persistedApplicationPathFromRecord: (id)record;
- (NSString *) persistedApplicationArgumentsFromRecord: (id)record;
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
- (NSString *) executablePathForX11WindowTitle: (NSString *)title;
- (void) resolvePathForX11WindowItem: (DockItem *)item;
- (void) resolvePathsForX11WindowItems;
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
- (BOOL) canRemoveDockItemAtIndex: (NSUInteger)index;
- (BOOL) launchApplicationAtPath: (NSString *)path;
- (BOOL) launchApplicationItem: (DockItem *)item;
- (BOOL) launchApplicationItem: (DockItem *)item useIconManager: (BOOL)useIconManager;
- (NSArray *) iconManagerLaunchArgumentsByAddingToArguments: (NSArray *)arguments;
- (NSDictionary *) explicitApplicationLaunchEnvironment;
- (void) launchTaskWithLaunchPath: (NSString *)path
			arguments: (NSArray *)arguments
		   useIconManager: (BOOL)useIconManager;
- (NSArray *) launchArgumentsFromString: (NSString *)arguments;
- (NSString *) shellQuotedArgument: (NSString *)argument;
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
- (SettingsController *) settingsController;
- (void) showSettingsPanel: (id)sender;
- (void) showSettingsForDockItem: (DockItem *)item;
- (void) applyDockPlacement;
- (void) updateDockBackground;
- (void) startLaunchWiggleForItem: (DockItem *)item;
- (void) startActivationWiggleForItem: (DockItem *)item;
- (void) startAttentionWiggleForItem: (DockItem *)item;
- (void) cancelAttentionWiggleForItem: (DockItem *)item;
- (BOOL) itemWigglesOnLaunch: (DockItem *)item;
- (BOOL) itemWigglesOnActivation: (DockItem *)item;
- (BOOL) itemWigglesOnAttentionRequest: (DockItem *)item;
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
- (BOOL) launchDesktopFile: (NSString *)path
		 arguments: (NSArray *)arguments
	    useIconManager: (BOOL)useIconManager;
@end
