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

#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>

@interface DockTileIconView : NSView
{
  NSImage *_icon;
  NSString *_title;
}
- (void) setIcon: (NSImage *)icon;
- (void) setTitle: (NSString *)title;
@end

@interface DockItem (Private)
+ (BOOL) imageIsDrawable: (NSImage *)image;
+ (NSImage *) imageAtPath: (NSString *)path;
+ (NSImage *) imageNamed: (NSString *)name inApplicationPath: (NSString *)path;
+ (NSImage *) iconForApplicationPath: (NSString *)path;
+ (NSString *) desktopFileValueForKey: (NSString *)key lines: (NSArray *)lines;
+ (NSString *) firstCommandTokenFromString: (NSString *)string;
+ (NSString *) pathForExecutableCommand: (NSString *)command;
+ (NSImage *) iconForApplicationNamed: (NSString *)name inDirectories: (NSArray *)directories;
+ (NSArray *) desktopIconSearchDirectoriesForDesktopFile: (NSString *)path;
+ (NSImage *) iconForDesktopFile: (NSString *)path;
+ (NSImage *) fallbackApplicationIcon;
@end
