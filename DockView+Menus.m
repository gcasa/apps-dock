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

#import "DockViewPrivate.h"

@implementation DockView (Menus)

- (NSMenuItem *) menuItemWithTitle: (NSString *)title
                            action: (SEL)action
                              item: (DockItem *)item
{
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:title
						    action:action
					     keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menuItem setRepresentedObject:item];
  return menuItem;
}


- (NSMenu *) menuForDockItem: (DockItem *)item
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Application"]);
  NSMenuItem *menuItem;
  BOOL hasPath = [[item path] length] > 0;
  BOOL openAtLogin = NO;
  BOOL canShowSettings = NO;

  if ([_delegate respondsToSelector:
		 @selector(dockView:itemIsOpenAtLogin:)])
    {
      openAtLogin = [_delegate dockView:self itemIsOpenAtLogin:item];
    }
  if ([_delegate respondsToSelector:
		 @selector(dockView:canShowSettingsForItem:)])
    {
      canShowSettings = [_delegate dockView:self canShowSettingsForItem:item];
    }

  if ([item kind] == DockItemApplication && canShowSettings)
    {
      menuItem = [self menuItemWithTitle:@"Settings..."
				  action:@selector(showItemSettings:)
				    item:item];
      [menu addItem:menuItem];
      [menu addItem:[NSMenuItem separatorItem]];
    }

  menuItem = [self menuItemWithTitle:@"Open At Login"
                              action:@selector(toggleOpenAtLogin:)
                                item:item];
  [menuItem setState: (openAtLogin ? NSOnState : NSOffState)];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Show In File Viewer"
                              action:@selector(showItemInFileViewer:)
                                item:item];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Quit"
                              action:@selector(quitItem:)
                                item:item];
  [menu addItem:menuItem];

  return menu;
}


- (NSMenu *) menuForRecycler
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Recycler"]);
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:@"Empty Recycler"
                                                    action:@selector(emptyRecycler:)
                                             keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menu addItem:menuItem];
  return menu;
}


- (void) toggleOpenAtLogin: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didToggleOpenAtLoginForItem:)])
    {
      [_delegate dockView:self didToggleOpenAtLoginForItem:item];
    }
}


- (void) showItemInFileViewer: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didShowItemInFileViewer:)])
    {
      [_delegate dockView:self didShowItemInFileViewer:item];
    }
}


- (void) showItemSettings: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didShowSettingsForItem:)])
    {
      [_delegate dockView:self didShowSettingsForItem:item];
    }
}


- (void) quitItem: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:@selector(dockView:didQuitItem:)])
    {
      [_delegate dockView:self didQuitItem:item];
    }
}


- (void) emptyRecycler: (id)sender
{
  if ([_delegate respondsToSelector:@selector(dockViewDidEmptyRecycler:)])
    {
      [_delegate dockViewDidEmptyRecycler:self];
    }
}


@end
