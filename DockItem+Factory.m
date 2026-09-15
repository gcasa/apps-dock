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

#import "DockItemPrivate.h"

@implementation DockItem (Factory)

+ (id) applicationItemWithPath: (NSString *)path
{
  DockItem *item = AUTORELEASE([[self alloc] init]);
  NSImage *icon = nil;
  NSString *bundlePath = [self applicationBundlePathForPath:path];
  NSString *iconPath = bundlePath ? bundlePath : path;

  if (bundlePath)
    {
      icon = [self iconForApplicationPath:bundlePath];
    }
  if (!icon && [[[path pathExtension] lowercaseString] isEqualToString:@"desktop"])
    {
      icon = [self iconForDesktopFile:path];
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFileType:[path pathExtension]];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [self fallbackApplicationIcon];
    }

  item->_kind = DockItemApplication;
  item->_state = DockItemNotRunning;
  item->_pinned = YES;
  item->_usesDockBehaviorDefaults = YES;
  item->_wigglesOnLaunch = YES;
  item->_wigglesOnActivation = YES;
  item->_wigglesOnAttentionRequest = YES;
  ASSIGNCOPY(item->_path, path);
  ASSIGNCOPY(item->_iconPath, iconPath);
  ASSIGNCOPY(item->_title, [[path lastPathComponent] stringByDeletingPathExtension]);
  ASSIGN(item->_icon, icon);
  ASSIGN(item->_originalIcon, icon);
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = AUTORELEASE([[DockTileIconView alloc]
					       initWithFrame:NSMakeRect(0, 0, 46, 46)]);
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}


+ (id) x11ItemWithTitle: (NSString *)title window: (unsigned long)xWindow icon: (NSImage *)icon hidden: (BOOL)hidden
{
  DockItem *item = AUTORELEASE([[self alloc] init]);
  NSString *displayTitle;

  displayTitle = [title length] ? title : [NSString stringWithFormat:@"0x%lx", xWindow];
  item->_kind = DockItemX11Window;
  item->_state = hidden ? DockItemHidden : DockItemRunning;
  item->_xWindow = xWindow;
  item->_pinned = NO;
  item->_usesDockBehaviorDefaults = YES;
  item->_wigglesOnLaunch = YES;
  item->_wigglesOnActivation = YES;
  item->_wigglesOnAttentionRequest = YES;
  ASSIGNCOPY(item->_title, displayTitle);
  ASSIGN(item->_icon, icon);
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = AUTORELEASE([[DockTileIconView alloc]
					       initWithFrame:NSMakeRect(0, 0, 46, 46)]);
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}


@end
