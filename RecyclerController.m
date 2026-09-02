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

#import "RecyclerController.h"
#import <dirent.h>
#import <string.h>

@implementation RecyclerController

- (NSArray *) recyclerPaths
{
  NSMutableArray *paths = [NSMutableArray array];
  NSString *homeTrashPath = [NSHomeDirectory()
			      stringByAppendingPathComponent:@".Trash"];
  NSArray *searchPaths;
  NSUInteger i;

  if ([homeTrashPath length])
    {
      [paths addObject:homeTrashPath];
    }

  searchPaths = NSSearchPathForDirectoriesInDomains(NSTrashDirectory,
						    NSAllDomainsMask,
						    YES);
  for (i = 0; i < [searchPaths count]; i++)
    {
      NSString *path = [searchPaths objectAtIndex:i];

      if ([path length] && ![paths containsObject:path])
	{
	  [paths addObject:path];
	}
    }

  return paths;
}

- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path
{
  DIR *directory;
  struct dirent *entry;

  if (![path length])
    {
      return NO;
    }

  directory = opendir([path fileSystemRepresentation]);
  if (!directory)
    {
      return NO;
    }

  while ((entry = readdir(directory)) != NULL)
    {
      if (strcmp(entry->d_name, ".") == 0 ||
	  strcmp(entry->d_name, "..") == 0 ||
	  strcmp(entry->d_name, ".gwdir") == 0)
	{
	  continue;
	}

      closedir(directory);
      return YES;
    }

  closedir(directory);
  return NO;
}

- (BOOL) recyclerHasContents
{
  NSArray *paths = [self recyclerPaths];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      if ([self directoryHasVisibleContentsAtPath:[paths objectAtIndex:i]])
	{
	  return YES;
	}
    }

  return NO;
}

- (NSString *) recyclerPathForDropping
{
  NSArray *paths = [self recyclerPaths];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      BOOL isDir = NO;

      if ([fileManager fileExistsAtPath:path isDirectory:&isDir] && isDir)
	{
	  return path;
	}
    }

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex:i];
      if ([fileManager createDirectoryAtPath:path
		 withIntermediateDirectories:YES
				  attributes:nil
				       error:NULL])
	{
	  return path;
	}
    }

  return nil;
}

- (NSString *) recyclerDestinationPathForPath: (NSString *)path
				 recyclerPath: (NSString *)recyclerPath
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *name = [path lastPathComponent];
  NSString *base;
  NSString *extension;
  NSString *candidate;
  NSUInteger i = 2;

  if (![name length])
    {
      return nil;
    }

  candidate = [recyclerPath stringByAppendingPathComponent:name];
  if (![fileManager fileExistsAtPath:candidate])
    {
      return candidate;
    }

  extension = [name pathExtension];
  base = [extension length] ? [name stringByDeletingPathExtension] : name;

  while (1)
    {
      NSString *numberedName = [NSString stringWithFormat:@"%@ %lu",
					 base, (unsigned long)i];
      if ([extension length])
	{
	  numberedName = [numberedName stringByAppendingPathExtension:extension];
	}

      candidate = [recyclerPath stringByAppendingPathComponent:numberedName];
      if (![fileManager fileExistsAtPath:candidate])
	{
	  return candidate;
	}
      i++;
    }
}

- (BOOL) movePathToRecyclerFallback: (NSString *)path
		       recyclerPath: (NSString *)recyclerPath
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *destination = [self recyclerDestinationPathForPath:path
						  recyclerPath:recyclerPath];

  if (![destination length])
    {
      return NO;
    }

  if ([fileManager movePath:path toPath:destination handler:nil])
    {
      return YES;
    }

  if ([fileManager copyPath:path toPath:destination handler:nil])
    {
      if ([fileManager removeFileAtPath:path handler:nil])
	{
	  return YES;
	}
      [fileManager removeFileAtPath:destination handler:nil];
    }

  return NO;
}

- (void) emptyRecyclerPath: (NSString *)path
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSArray *entries = [fileManager directoryContentsAtPath:path];
  NSUInteger i;

  for (i = 0; i < [entries count]; i++)
    {
      NSString *entry = [entries objectAtIndex:i];
      NSString *entryPath;

      if ([entry isEqualToString:@"."] ||
	  [entry isEqualToString:@".."] ||
	  [entry isEqualToString:@".gwdir"])
	{
	  continue;
	}

      entryPath = [path stringByAppendingPathComponent:entry];
      [fileManager removeFileAtPath:entryPath handler:nil];
    }
}

@end
