/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#import "RunningApplicationScanner.h"
#import "DockItem.h"
#import <ctype.h>
#import <limits.h>
#import <mntent.h>
#import <paths.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

@implementation RunningApplicationScanner

- (NSString *) normalizedPath: (NSString *)path
{
  if (![path length])
    {
      return nil;
    }

  return [path stringByResolvingSymlinksInPath];
}

- (NSArray *) commandSearchPathComponents
{
  NSString *pathEnvironment = [[[NSProcessInfo processInfo] environment]
				objectForKey:@"PATH"];
  NSMutableArray *components = [NSMutableArray array];

  if ([pathEnvironment length])
    {
      return [pathEnvironment componentsSeparatedByString:@":"];
    }

  {
    size_t length = confstr(_CS_PATH, NULL, 0);

    if (length > 0)
      {
	char *buffer = malloc(length);

	if (buffer)
	  {
	    if (confstr(_CS_PATH, buffer, length) > 0)
	      {
		NSString *fallbackPath =
		  [NSString stringWithUTF8String:buffer];

		if ([fallbackPath length])
		  {
		    [components addObjectsFromArray:
				  [fallbackPath componentsSeparatedByString:@":"]];
		  }
	      }
	    free(buffer);
	  }
      }
  }

  return components;
}

- (NSString *) procFilesystemPath
{
  FILE *mounts;
  struct mntent *entry;
  NSString *path = nil;

  mounts = setmntent(_PATH_MOUNTED, "r");
  if (!mounts)
    {
      return nil;
    }

  while ((entry = getmntent(mounts)) != NULL)
    {
      if (entry->mnt_type && strcmp(entry->mnt_type, "proc") == 0 &&
	  entry->mnt_dir)
	{
	  path = [NSString stringWithUTF8String:entry->mnt_dir];
	  break;
	}
    }

  endmntent(mounts);
  return [path length] ? path : nil;
}

- (NSString *) procPathForProcessIdentifierString: (NSString *)identifier
{
  NSString *procPath = [self procFilesystemPath];

  if (![procPath length] || ![identifier length])
    {
      return nil;
    }

  return [procPath stringByAppendingPathComponent:identifier];
}

- (BOOL) path: (NSString *)path isEqualToOrDescendantOfPath: (NSString *)parentPath
{
  NSArray *pathComponents;
  NSArray *parentComponents;
  NSUInteger i;

  path = [self normalizedPath:path];
  parentPath = [self normalizedPath:parentPath];
  if (![path length] || ![parentPath length])
    {
      return NO;
    }
  if ([path isEqualToString:parentPath])
    {
      return YES;
    }

  pathComponents = [path pathComponents];
  parentComponents = [parentPath pathComponents];
  if ([pathComponents count] <= [parentComponents count])
    {
      return NO;
    }

  for (i = 0; i < [parentComponents count]; i++)
    {
      if (![[pathComponents objectAtIndex:i]
	     isEqualToString:[parentComponents objectAtIndex:i]])
	{
	  return NO;
	}
    }

  return YES;
}

- (NSString *) executablePathForApplicationPath: (NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  BOOL isDir = NO;

  if (![path length])
    {
      return nil;
    }

  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if ([extension isEqualToString:@"app"] && isDir)
    {
      NSBundle *bundle = [NSBundle bundleWithPath:path];
      NSString *executablePath = [bundle executablePath];
      NSString *fallbackPath;

      if ([executablePath length])
	{
	  return [self normalizedPath:executablePath];
	}

      fallbackPath = [path stringByAppendingPathComponent:
			     [[path lastPathComponent] stringByDeletingPathExtension]];
      if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackPath])
	{
	  return [self normalizedPath:fallbackPath];
	}
    }

  if ([extension isEqualToString:@"desktop"])
    {
      NSString *desktopExecutable = [self executablePathForDesktopFile:path];
      if ([desktopExecutable length])
	{
	  return desktopExecutable;
	}
    }

  if (!isDir && [[NSFileManager defaultManager] isExecutableFileAtPath:path])
    {
      return [self normalizedPath:path];
    }

  return [self normalizedPath:path];
}

- (NSString *) firstCommandTokenFromString: (NSString *)string
{
  NSMutableString *token = [NSMutableString string];
  NSUInteger i;
  BOOL quoted = NO;
  unichar quote = 0;

  for (i = 0; i < [string length]; i++)
    {
      unichar ch = [string characterAtIndex:i];

      if (quoted)
	{
	  if (ch == quote)
	    {
	      quoted = NO;
	    }
	  else
	    {
	      [token appendFormat:@"%C", ch];
	    }
	}
      else if (ch == '"' || ch == '\'')
	{
	  quoted = YES;
	  quote = ch;
	}
      else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
		 characterIsMember:ch])
	{
	  if ([token length])
	    {
	      break;
	    }
	}
      else
	{
	  [token appendFormat:@"%C", ch];
	}
    }

  return [token length] ? token : nil;
}

- (NSString *) pathForExecutableCommand: (NSString *)command
{
  NSArray *pathComponents;
  NSUInteger i;

  if (![command length])
    {
      return nil;
    }

  if ([command isAbsolutePath] &&
      [[NSFileManager defaultManager] fileExistsAtPath:command])
    {
      return [self normalizedPath:command];
    }

  pathComponents = [self commandSearchPathComponents];

  for (i = 0; i < [pathComponents count]; i++)
    {
      NSString *candidate = [[pathComponents objectAtIndex:i]
			      stringByAppendingPathComponent:command];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate])
	{
	  return [self normalizedPath:candidate];
	}
    }

  return command;
}

- (NSString *) executablePathForDesktopFile: (NSString *)path
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
			       [NSCharacterSet newlineCharacterSet]];
  NSUInteger i;

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [lines objectAtIndex:i];
      if ([line hasPrefix:@"Exec="])
	{
	  NSString *command = [line substringFromIndex:5];
	  command = [[command componentsSeparatedByString:@"%"] objectAtIndex:0];
	  return [self pathForExecutableCommand:
			 [self firstCommandTokenFromString:command]];
	}
    }

  return nil;
}

- (BOOL) stringIsProcessIdentifier: (NSString *)string
{
  const char *chars = [string UTF8String];
  NSUInteger i;

  if (!chars || !chars[0])
    {
      return NO;
    }

  for (i = 0; chars[i]; i++)
    {
      if (!isdigit((unsigned char)chars[i]))
	{
	  return NO;
	}
    }

  return YES;
}

- (NSArray *) runningProcessExecutablePaths
{
  NSString *procPath = [self procFilesystemPath];
  NSArray *entries;
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableSet *seenPaths = [NSMutableSet set];
  NSUInteger i;

  if (![procPath length])
    {
      return paths;
    }
  entries = [[NSFileManager defaultManager] directoryContentsAtPath:procPath];

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *linkPath;
      char target[PATH_MAX];
      ssize_t length;

      if (![self stringIsProcessIdentifier:entry])
	{
	  continue;
	}

      linkPath = [[procPath stringByAppendingPathComponent:entry]
		   stringByAppendingPathComponent:@"exe"];
      length = readlink([linkPath fileSystemRepresentation],
			target,
			sizeof(target) - 1);
      if (length <= 0)
	{
	  continue;
	}

      target[length] = '\0';
      {
	NSString *path = [self normalizedPath:
				 [NSString stringWithUTF8String:target]];
	if ([path length] && ![seenPaths containsObject:path])
	  {
	    [seenPaths addObject:path];
	    [paths addObject:path];
	  }
      }
    }

  return paths;
}

- (NSString *) executablePathForProcessIdentifier: (NSNumber *)processIdentifier
{
  NSString *linkPath;
  char target[PATH_MAX];
  ssize_t length;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return nil;
    }

  linkPath = [[self procPathForProcessIdentifierString:
		      [processIdentifier stringValue]]
	       stringByAppendingPathComponent:@"exe"];
  length = readlink([linkPath fileSystemRepresentation],
		    target,
		    sizeof(target) - 1);
  if (length <= 0)
    {
      return nil;
    }

  target[length] = '\0';
  return [self normalizedPath:[NSString stringWithUTF8String:target]];
}

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  NSString *procPath = [self procFilesystemPath];
  NSArray *entries;
  NSMutableArray *processIds = [NSMutableArray array];
  NSUInteger i;

  if (![procPath length])
    {
      return processIds;
    }
  entries = [[NSFileManager defaultManager] directoryContentsAtPath:procPath];

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *linkPath;
      char target[PATH_MAX];
      ssize_t length;
      NSString *processPath;

      if (![self stringIsProcessIdentifier:entry])
	{
	  continue;
	}

      linkPath = [[procPath stringByAppendingPathComponent:entry]
		   stringByAppendingPathComponent:@"exe"];
      length = readlink([linkPath fileSystemRepresentation],
			target,
			sizeof(target) - 1);
      if (length <= 0)
	{
	  continue;
	}

      target[length] = '\0';
      processPath = [self normalizedPath:[NSString stringWithUTF8String:target]];
      if ([self applicationItem:item matchesRunningProcessPath:processPath])
	{
	  [processIds addObject:[NSNumber numberWithInt:[entry intValue]]];
	}
    }

  return processIds;
}

- (BOOL) applicationItem: (DockItem *)item matchesRunningProcessPath: (NSString *)processPath
{
  NSString *itemPath = [self normalizedPath:[item path]];
  NSString *executablePath = [self executablePathForApplicationPath:[item path]];
  NSString *processName = [[processPath lastPathComponent] lowercaseString];
  NSString *itemName = [[[[item path] lastPathComponent]
			  stringByDeletingPathExtension] lowercaseString];
  NSString *executableName = [[executablePath lastPathComponent] lowercaseString];

  if (![processPath length])
    {
      return NO;
    }

  if (([itemPath length] && [processPath isEqualToString:itemPath]) ||
      ([executablePath length] && [processPath isEqualToString:executablePath]) ||
      ([processName length] && [processName isEqualToString:itemName]) ||
      ([processName length] && [processName isEqualToString:executableName]) ||
      ([itemPath length] &&
       [[[itemPath pathExtension] lowercaseString] isEqualToString:@"app"] &&
       [self path:processPath isEqualToOrDescendantOfPath:itemPath]))
    {
      return YES;
    }

  return NO;
}

- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
				    paths: (NSArray *)processPaths
{
  NSUInteger i;

  for (i = 0; i < [processPaths count]; i++)
    {
      if ([self applicationItem:item
	matchesRunningProcessPath:[processPaths objectAtIndex:i]])
	{
	  return YES;
	}
    }

  return NO;
}

@end
