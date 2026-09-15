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

#import "SettingsControllerPrivate.h"

@implementation SettingsController (Applications)

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


@end
