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

@implementation AppController (DockViewDelegate)

- (void) applyDockPlacement
{
  [[NSUserDefaults standardUserDefaults] setInteger:_dockPlacement forKey:@"DockPlacement"];
  [self applyDockCellSizeToView];
  [_dockView setHorizontal:[DockPreferences placementIsHorizontal:_dockPlacement]];
  [_window setFrame:[self dockWindowFrameForPlacement:_dockPlacement]
            display:YES];
  [_dockView setFrame:NSMakeRect(0, 0,
                                 NSWidth([_window frame]),
                                 NSHeight([_window frame]))];
  [_x11 setDockPlacement:_dockPlacement];
  [self updateDockBackground];
  [self updateDockMenu];
}

- (void) updateDockBackground
{
  [_dockView setBackgroundColor:_backgroundColor];
  [_dockView setBackgroundAlpha:_windowAlpha];
  [_dockView setUsesCellBackgroundTile:_useCellTileBackground];
  [_dockView setShowsBorder:_showDockBorder];
  [_dockView setRunningIndicatorMode:_runningIndicatorMode];
  [_dockView setMagnifiesHoveredIcons:_magnifiesHoveredIcons];
  [_dockView setHoverIconScale:_hoverIconScale];
}

- (void) startLaunchWiggleForItem: (DockItem *)item
{
  if ([self itemWigglesOnLaunch:item])
    {
      [_dockView startWiggleForItem:item];
    }
}

- (void) startActivationWiggleForItem: (DockItem *)item
{
  if ([self itemWigglesOnActivation:item])
    {
      [_dockView startWiggleForItem:item];
    }
}

- (void) startAttentionWiggleForItem: (DockItem *)item
{
  if ([self itemWigglesOnAttentionRequest:item])
    {
      [_dockView startAttentionWiggleForItem:item];
    }
}

- (void) cancelAttentionWiggleForItem: (DockItem *)item
{
  [_dockView acknowledgeWiggleForItem:item];
}

- (BOOL) itemWigglesOnLaunch: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ? _wigglesOnLaunch : [item wigglesOnLaunch];
}

- (BOOL) itemWigglesOnActivation: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ?
    _wigglesOnActivation : [item wigglesOnActivation];
}

- (BOOL) itemWigglesOnAttentionRequest: (DockItem *)item
{
  return [item usesDockBehaviorDefaults] ?
    _wigglesOnAttentionRequest : [item wigglesOnAttentionRequest];
}

- (void) quitDock: (id)sender
{
  [self savePersistedApplications];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [NSApp terminate:sender];
}

- (void) refreshDock
{
  [_dockView setItems:_items];
  [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
  [self applyDockPlacement];
}

- (void) dockViewDidReceivePaths: (NSArray *)paths
{
  [self dockViewDidReceivePaths:paths atIndex:[_items count]];
}

- (void) dockViewDidReceivePaths: (NSArray *)paths
			 atIndex: (NSUInteger)index
{
  NSUInteger i;
  BOOL added = NO;
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  NSUInteger insertionIndex = MIN(index, pinnedCount);

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
      NSString *applicationPath = [bundlePath length] ? bundlePath : path;
      DockItem *transientItem;
      NSUInteger transientIndex;
      BOOL isDir = NO;

      if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] &&
	  ![self dockHasApplicationPath:applicationPath])
	{
	  DockItem *item = [DockItem applicationItemWithPath:applicationPath];

	  transientItem = [self transientApplicationItemMatchingBundlePath:applicationPath];
	  transientIndex = transientItem ? [self indexForItem:transientItem] : NSNotFound;
	  if (transientIndex != NSNotFound)
	    {
	      [_items removeObjectAtIndex:transientIndex];
	      if (transientIndex < insertionIndex && insertionIndex > 0)
		{
		  insertionIndex--;
		}
	    }

	  [item setPinned:YES];
	  [_items insertObject:item atIndex:insertionIndex];
	  insertionIndex++;
	  added = YES;
	}
    }

  if (added)
    {
      [self savePersistedApplications];
      [self refreshDock];
    }
}

- (void) dockViewDidMoveItemFromIndex: (NSUInteger)fromIndex
                              toIndex: (NSUInteger)toIndex
{
  DockItem *item;
  NSUInteger pinnedCount = [self pinnedApplicationCount];
  BOOL promoteItem = NO;

  if (fromIndex >= [_items count] || toIndex > [_items count])
    {
      return;
    }

  if (fromIndex < pinnedCount && toIndex > pinnedCount)
    {
      toIndex = pinnedCount;
    }
  else if (fromIndex >= pinnedCount && toIndex <= pinnedCount)
    {
      promoteItem = YES;
    }

  if (toIndex > fromIndex)
    {
      toIndex--;
    }

  if (fromIndex == toIndex && !promoteItem)
    {
      return;
    }

  item = RETAIN([_items objectAtIndex:fromIndex]);
  [_items removeObjectAtIndex:fromIndex];
  if (promoteItem)
    {
      [item setPinned:YES];
    }
  [_items insertObject:item atIndex:toIndex];
  DESTROY(item);

  [self savePersistedApplications];
  [self refreshDock];
}

- (void) dockViewDidRemoveItemAtIndex: (NSUInteger)index
{
  DockItem *item;

  if (index >= [_items count])
    {
      return;
    }

  item = [_items objectAtIndex:index];
  if (![self canRemoveDockItemAtIndex:index])
    {
      return;
    }

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

- (BOOL) dockView: (id)dockView canRemoveItemAtIndex: (NSUInteger)index
{
  return [self canRemoveDockItemAtIndex:index];
}

- (BOOL) dockView: (id)dockView itemIsOpenAtLogin: (DockItem *)item
{
  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return NO;
    }

  return [self applicationPathIsOpenAtLogin:[item path]];
}

- (void) dockView: (id)dockView didToggleOpenAtLoginForItem: (DockItem *)item
{
  BOOL openAtLogin;

  [self resolvePathForX11WindowItem:item];
  if (![[item path] length])
    {
      return;
    }

  openAtLogin = ![self applicationPathIsOpenAtLogin:[item path]];
  [self setApplicationPath:[item path] openAtLogin:openAtLogin];
}

- (void) dockView: (id)dockView didShowItemInFileViewer: (DockItem *)item
{
  NSString *path = [item path];
  NSString *directory;

  if (![path length])
    {
      return;
    }

  directory = [path stringByDeletingLastPathComponent];
  [[NSWorkspace sharedWorkspace] selectFile:path
                   inFileViewerRootedAtPath:directory];
}

- (void) dockView: (id)dockView didQuitItem: (DockItem *)item
{
  NSUInteger index;

  if ([item kind] == DockItemApplication)
    {
      [self terminateApplicationItemProcesses:item];
      [self restoreApplicationItemAfterExit:item];
    }
  else if ([item xWindow])
    {
      [_x11 closeWindow:[item xWindow]];
      [item setState:DockItemNotRunning];
    }
  if (![item isPinned])
    {
      index = [self indexForItem:item];
      if (index != NSNotFound)
	{
	  [_items removeObjectAtIndex:index];
	}
    }

  [self refreshDock];
}

- (void) dockViewDidEmptyRecycler: (id)dockView
{
  [self emptyRecycler:dockView];
}

- (void) dockViewDidActivateRecycler
{
  NSString *path = [self recyclerPathForDropping];

  if ([path length])
    {
      [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else
    {
      NSBeep();
    }
}

- (BOOL) dockView: (id)dockView canShowSettingsForItem: (DockItem *)item
{
  return ([item kind] == DockItemApplication ||
	  [item kind] == DockItemX11Window) &&
    ![self applicationBundlePathIsDockWM:[item path]];
}

- (void) dockView: (id)dockView didShowSettingsForItem: (DockItem *)item
{
  if ([self dockView:dockView canShowSettingsForItem:item])
    {
      [self showSettingsForDockItem:item];
    }
}

- (void) dockViewDidActivateItem: (DockItem *)item
{
  if ([item kind] == DockItemApplication)
    {
      NSString *path = [item path];
      NSArray *processIds;
      BOOL launched = NO;

      processIds = [self runningProcessIdentifiersForApplicationItem:item];
      if ([processIds count])
	{
	  if ([self activateRunningApplicationWithProcessIdentifiers:processIds])
	    {
	      [_x11 drainTransientIconEvents];
	      [_x11 activateApplicationWithProcessIdentifiers:processIds];
	      [_x11 drainTransientIconEvents];
	      [item setState:DockItemRunning];
	      [self startActivationWiggleForItem:item];
	      [self refreshDock];
	      return;
	    }

	  [_x11 drainTransientIconEvents];
	  if ([_x11 activateApplicationWithProcessIdentifiers:processIds])
	    {
	      [_x11 drainTransientIconEvents];
	      [item setState:DockItemRunning];
	      [self startActivationWiggleForItem:item];
	      [self refreshDock];
	      return;
	    }
	  [_x11 drainTransientIconEvents];
	}

      if ([item xWindow] && [item state] != DockItemNotRunning)
	{
	  [_x11 drainTransientIconEvents];
	  [_x11 activateWindow:[item xWindow]];
	  [_x11 drainTransientIconEvents];
	  [self startActivationWiggleForItem:item];
	  return;
	}

      [self rememberLaunchedApplicationPath:path];
      launched = [self launchApplicationItem:item useIconManager:YES];
      [_x11 drainTransientIconEvents];

      if (launched)
	{
	  [item setState:DockItemRunning];
	  [self startLaunchWiggleForItem:item];
	  [self refreshDock];
	}
    }
  else
    {
      [_x11 drainTransientIconEvents];
      [_x11 activateWindow:[item xWindow]];
      [_x11 drainTransientIconEvents];
      [self startActivationWiggleForItem:item];
    }
}

- (void) dockViewDidActivateTopIcon
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
						       NSAllDomainsMask,
						       YES);
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [[paths objectAtIndex:i]
			 stringByAppendingPathComponent:@"GWorkspace.app"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:path])
	{
	  NSString *executablePath = [self executablePathForApplicationPath:path];
	  BOOL launched = NO;

	  [self rememberLaunchedApplicationPath:path];
	  if ([[NSFileManager defaultManager]
		isExecutableFileAtPath:executablePath])
	    {
	      [self launchTaskWithLaunchPath:executablePath
				   arguments:[NSArray array]
			      useIconManager:YES];
	      launched = YES;
	    }
	  else
	    {
	      launched = [[NSWorkspace sharedWorkspace] launchApplication:path];
	    }
	  if (!launched)
	    {
	      [[NSWorkspace sharedWorkspace] openFile:path];
	    }
	  [_x11 drainTransientIconEvents];
	  return;
	}
    }
}

@end
