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

@implementation AppController (Launching)

- (BOOL) launchApplicationAtPath: (NSString *)path
{
  DockItem *item = [DockItem applicationItemWithPath:path];
  return [self launchApplicationItem:item useIconManager:YES];
}

- (BOOL) launchApplicationItem: (DockItem *)item
{
  return [self launchApplicationItem:item useIconManager:NO];
}

- (BOOL) launchApplicationItem: (DockItem *)item useIconManager: (BOOL)useIconManager
{
  NSString *path = [item path];
  NSArray *arguments = [self launchArgumentsFromString:[item launchArguments]];
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"desktop"])
    {
      return [self launchDesktopFile:path
			    arguments:arguments
		       useIconManager:useIconManager];
    }
  else if ([extension isEqualToString:@"app"])
    {
      NSString *executablePath = [self executablePathForApplicationPath:path];

      if ([[NSFileManager defaultManager] isExecutableFileAtPath:executablePath])
	{
	  [self launchTaskWithLaunchPath:executablePath
			       arguments:arguments
			  useIconManager:useIconManager];
	  return YES;
	}
      if (![arguments count] &&
	  [[NSWorkspace sharedWorkspace] launchApplication:path])
	{
	  return YES;
	}
      return [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else if (isDir)
    {
      return [[NSWorkspace sharedWorkspace] openFile:path];
    }
  else if ([[NSFileManager defaultManager] isExecutableFileAtPath:path])
    {
      [self launchTaskWithLaunchPath:path
			       arguments:arguments
			  useIconManager:useIconManager];
      return YES;
    }

  return [[NSWorkspace sharedWorkspace] openFile:path];
}

- (NSString *) defaultsDomainForApplicationPath: (NSString *)path
{
  NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
  NSDictionary *info = nil;
  NSString *identifier = nil;

  if ([bundlePath length])
    {
      info = [[NSBundle bundleWithPath:bundlePath] infoDictionary];
      identifier = [info objectForKey:@"CFBundleIdentifier"];
      if (![identifier isKindOfClass:[NSString class]] || ![identifier length])
	{
	  identifier = [info objectForKey:@"NSExecutable"];
	}
    }
  if (![identifier isKindOfClass:[NSString class]] || ![identifier length])
    {
      identifier = [[path lastPathComponent] stringByDeletingPathExtension];
    }

  return identifier;
}

- (void) enableIconManagerForApplicationPath: (NSString *)path
{
  NSString *domain = [self defaultsDomainForApplicationPath:path];
  NSUserDefaults *defaults;
  NSDictionary *existingValues;
  NSMutableDictionary *values;

  if (![domain length])
    {
      return;
    }

  defaults = AUTORELEASE([[NSUserDefaults alloc] initWithUser:NSUserName()]);
  existingValues = [defaults persistentDomainForName:domain];
  values = existingValues
    ? [NSMutableDictionary dictionaryWithDictionary:existingValues]
    : [NSMutableDictionary dictionary];
  [values setObject:[NSNumber numberWithBool:YES] forKey:@"GSUseIconManager"];
  [defaults setPersistentDomain:values forName:domain];
  [defaults synchronize];
}

- (void) launchTaskWithLaunchPath: (NSString *)path
			arguments: (NSArray *)arguments
		   useIconManager: (BOOL)useIconManager
{
  NSTask *task = [NSTask new];

  [task setLaunchPath:path];
  [task setArguments:arguments];
  if (useIconManager)
    {
      [self enableIconManagerForApplicationPath:path];
    }
  [task launch];
  RELEASE(task);
}

- (NSArray *) launchArgumentsFromString: (NSString *)arguments
{
  NSMutableArray *tokens = [NSMutableArray array];
  NSMutableString *token = [NSMutableString string];
  NSUInteger i;
  BOOL inSingleQuote = NO;
  BOOL inDoubleQuote = NO;
  BOOL escaping = NO;

  for (i = 0; i < [arguments length]; i++)
    {
      unichar character = [arguments characterAtIndex:i];

      if (escaping)
	{
	  [token appendFormat:@"%C", character];
	  escaping = NO;
	  continue;
	}
      if (character == '\\' && !inSingleQuote)
	{
	  escaping = YES;
	  continue;
	}
      if (character == '\'' && !inDoubleQuote)
	{
	  inSingleQuote = !inSingleQuote;
	  continue;
	}
      if (character == '"' && !inSingleQuote)
	{
	  inDoubleQuote = !inDoubleQuote;
	  continue;
	}
      if (!inSingleQuote && !inDoubleQuote &&
	  [[NSCharacterSet whitespaceAndNewlineCharacterSet]
	    characterIsMember:character])
	{
	  if ([token length])
	    {
	      [tokens addObject:[[token copy] autorelease]];
	      [token setString:@""];
	    }
	  continue;
	}

      [token appendFormat:@"%C", character];
    }

  if (escaping)
    {
      [token appendString:@"\\"];
    }
  if ([token length])
    {
      [tokens addObject:[[token copy] autorelease]];
    }

  return tokens;
}

- (NSString *) shellQuotedArgument: (NSString *)argument
{
  return [NSString stringWithFormat:@"'%@'",
		   [argument stringByReplacingOccurrencesOfString:@"'"
						       withString:@"'\\''"]];
}

- (void) terminateApplicationItemProcesses: (DockItem *)item
{
  NSArray *processIds = [self runningProcessIdentifiersForApplicationItem:item];
  NSUInteger i;

  for (i = 0; i < [processIds count]; i++)
    {
      int processId = [[processIds objectAtIndex:i] intValue];

      if (processId > 0 && processId != getpid())
	{
	  kill((pid_t)processId, SIGTERM);
	}
    }
}

- (void) launchOpenAtLoginApplications
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSArray *processPaths = [self runningProcessExecutablePaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      DockItem *item;
      NSUInteger itemIndex;

      if (![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
	  continue;
	}

      item = [DockItem applicationItemWithPath:path];
      for (itemIndex = 0; itemIndex < [_items count]; itemIndex++)
	{
	  DockItem *candidate = [_items objectAtIndex:itemIndex];

	  if ([candidate kind] == DockItemApplication &&
	      [[self normalizedPath:[candidate path]]
		isEqualToString:[self normalizedPath:path]])
	    {
	      item = candidate;
	      break;
	    }
	}
      if ([self applicationItemHasRunningProcess:item paths:processPaths])
	{
	  continue;
	}

      [self rememberLaunchedApplicationPath:path];
      [self launchApplicationItem:item useIconManager:YES];
      [_x11 drainTransientIconEvents];
    }
}

- (BOOL) launchDesktopFile: (NSString *)path
		 arguments: (NSArray *)arguments
	    useIconManager: (BOOL)useIconManager
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
			       [NSCharacterSet newlineCharacterSet]];
  NSString *executablePath = [self executablePathForDesktopFile:path];
  NSUInteger i;

  if (![contents length])
    {
      return NO;
    }

  if (useIconManager && [executablePath length])
    {
      [self enableIconManagerForApplicationPath:executablePath];
    }

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [lines objectAtIndex:i];
      if ([line hasPrefix:@"Exec="])
	{
	  NSString *command = [line substringFromIndex:5];
	  command = [[command componentsSeparatedByString:@"%"] objectAtIndex:0];
	  if ([command length])
	    {
	      NSString *shellPath = [self pathForExecutableCommand:@"sh"];
	      NSUInteger j;

	      if ([shellPath length])
		{
		  for (j = 0; j < [arguments count]; j++)
		    {
		      command = [command stringByAppendingFormat:@" %@",
				 [self shellQuotedArgument:
					 [arguments objectAtIndex:j]]];
		    }
		  [self launchTaskWithLaunchPath:shellPath
				       arguments:[NSArray arrayWithObjects:@"-lc", command, nil]
				  useIconManager:NO];
		  return YES;
		}
	    }
	  return NO;
	}
    }

  return NO;
}

@end
