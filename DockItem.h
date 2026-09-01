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

typedef enum
  {
    DockItemApplication,
    DockItemX11Window
  } DockItemKind;

typedef enum
  {
    DockItemNotRunning,
    DockItemRunning,
    DockItemHidden
  } DockItemState;

@interface DockItem : NSObject
{
  DockItemKind _kind;
  DockItemState _state;
  NSString *_title;
  NSString *_path;
  NSString *_iconPath;
  NSString *_launchArguments;
  NSString *_badgeLabel;
  NSImage *_icon;
  NSImage *_originalIcon;
  NSDockTile *_dockTile;
  unsigned long _xWindow;
  BOOL _pinned;
}

+ (id) applicationItemWithPath: (NSString *)path;
+ (id) x11ItemWithTitle: (NSString *)title
                 window: (unsigned long)xWindow
                   icon: (NSImage *)icon
                 hidden: (BOOL)hidden;
+ (NSString *) applicationBundlePathForPath: (NSString *)path;

- (DockItemKind) kind;
- (DockItemState) state;
- (void) setState: (DockItemState)state;
- (NSString *) title;
- (NSString *) path;
- (NSString *) launchArguments;
- (void) setLaunchArguments: (NSString *)arguments;
- (NSString *) iconPath;
- (NSImage *) icon;
- (void) setIcon: (NSImage *)icon;
- (void) setIconPath: (NSString *)path;
- (void) setOriginalIcon: (NSImage *)icon;
- (void) restoreOriginalIcon;
- (NSString *) badgeLabel;
- (void) setBadgeLabel: (NSString *)label;
- (NSDockTile *) dockTile;
- (unsigned long) xWindow;
- (void) setXWindow: (unsigned long)xWindow;
- (BOOL) isPinned;
- (void) setPinned: (BOOL)pinned;

@end
