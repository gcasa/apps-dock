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

@implementation AppController (Recycler)

- (NSArray *) recyclerPaths
{
  return [_recyclerController recyclerPaths];
}

- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path
{
  return [_recyclerController directoryHasVisibleContentsAtPath:path];
}

- (BOOL) recyclerHasContents
{
  return [_recyclerController recyclerHasContents];
}

- (NSString *) recyclerPathForDropping
{
  return [_recyclerController recyclerPathForDropping];
}

- (NSString *) recyclerDestinationPathForPath: (NSString *)path
				 recyclerPath: (NSString *)recyclerPath
{
  return [_recyclerController recyclerDestinationPathForPath:path
						recyclerPath:recyclerPath];
}

- (BOOL) movePathToRecyclerFallback: (NSString *)path
                       recyclerPath: (NSString *)recyclerPath
{
  return [_recyclerController movePathToRecyclerFallback:path
					    recyclerPath:recyclerPath];
}

- (void) dockViewDidReceivePathsInRecycler: (NSArray *)paths
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *recyclerPath = [self recyclerPathForDropping];
  NSString *normalizedRecyclerPath = [self normalizedPath:recyclerPath];
  BOOL recycled = NO;
  NSUInteger i;

  if (![recyclerPath length])
    {
      NSBeep();
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      NSString *normalizedPath = [self normalizedPath:path];

      if (![normalizedPath length] ||
	  ![fileManager fileExistsAtPath:normalizedPath])
	{
	  continue;
	}

      if ([self path:normalizedPath
	isEqualToOrDescendantOfPath:normalizedRecyclerPath])
	{
	  continue;
	}

      if ([self movePathToRecyclerFallback:normalizedPath recyclerPath:recyclerPath])
	{
	  recycled = YES;
	}
    }

  if (recycled)
    {
      [self updateRecyclerState];
      [_dockView startRecyclerWiggle];
      [self refreshDock];
      [[NSSound soundNamed:@"Pop"] play];
    }
  else
    {
      NSBeep();
    }
}

- (void) updateRecyclerState
{
  [_dockView setRecyclerHasContents:[self recyclerHasContents]];
  [_settingsController updateControls];
}

- (void) emptyRecyclerPath: (NSString *)path
{
  [_recyclerController emptyRecyclerPath:path];
}

- (void) emptyRecycler: (id)sender
{
  NSArray *paths = [self recyclerPaths];
  NSUInteger i;
  int result;

  result = NSRunAlertPanel(@"Empty Recycler",
                           @"Are you sure you want to permanently remove the items in the Recycler?",
                           @"Empty Recycler",
                           @"Cancel",
                           nil);
  if (result != NSAlertDefaultReturn)
    {
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      [self emptyRecyclerPath:[paths objectAtIndex:i]];
    }

  [self updateRecyclerState];
  [_dockView startRecyclerWiggle];
  [self refreshDock];
  [[NSSound soundNamed:@"Glass"] play];
}

@end
