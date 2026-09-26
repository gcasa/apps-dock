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
#import <mntent.h>
#import <paths.h>
#import <string.h>

@implementation RecyclerController

- (NSDictionary *) mountEntryForPath: (NSString *)path
{
  FILE *mounts;
  struct mntent *entry;
  NSString *normalizedPath;
  NSDictionary *result = nil;

  if (![path length])
    {
      return nil;
    }

  normalizedPath = [[path stringByStandardizingPath]
			 stringByResolvingSymlinksInPath];
  mounts = setmntent(_PATH_MOUNTED, "r");
  if (!mounts)
    {
      return nil;
    }

  while ((entry = getmntent(mounts)) != NULL)
    {
      NSString *mountPath;

      if (!entry->mnt_dir)
	{
	  continue;
	}

      mountPath = [[[NSString stringWithUTF8String:entry->mnt_dir]
			 stringByStandardizingPath] stringByResolvingSymlinksInPath];
      if ([normalizedPath isEqualToString:mountPath])
	{
	  NSString *type = entry->mnt_type
	    ? [NSString stringWithUTF8String:entry->mnt_type] : @"";

	  result = [NSDictionary dictionaryWithObjectsAndKeys:
			 mountPath, @"path", type, @"type", nil];
	  break;
	}
    }

  endmntent(mounts);
  return result;
}

- (BOOL) pathIsMountPoint: (NSString *)path
{
  return [self mountEntryForPath:path] != nil;
}

- (BOOL) mountPathIsProtected: (NSString *)path type: (NSString *)type
{
  static NSArray *protectedPaths = nil;
  static NSArray *protectedPathTrees = nil;
  static NSArray *protectedTypes = nil;
  NSUInteger i;

  if (!protectedPaths)
    {
      protectedPaths = [[NSArray alloc] initWithObjects:
	@"/", @"/boot", @"/dev", @"/proc", @"/sys", @"/run", nil];
      protectedPathTrees = [[NSArray alloc] initWithObjects:
	@"/boot", @"/dev", @"/proc", @"/sys", nil];
      protectedTypes = [[NSArray alloc] initWithObjects:
	@"proc", @"sysfs", @"devtmpfs", @"devpts", @"securityfs",
	@"cgroup", @"cgroup2", @"debugfs", @"tracefs", @"configfs",
	@"pstore", @"efivarfs", @"mqueue", @"hugetlbfs", nil];
    }

  if ([protectedTypes containsObject:type])
    {
      return YES;
    }

  for (i = 0; i < [protectedPaths count]; i++)
    {
      NSString *protectedPath = [protectedPaths objectAtIndex:i];

      if ([path isEqualToString:protectedPath])
	{
	  return YES;
	}
    }

  for (i = 0; i < [protectedPathTrees count]; i++)
    {
      NSString *protectedPath = [protectedPathTrees objectAtIndex:i];

      if ([path hasPrefix:[protectedPath stringByAppendingString:@"/"]])
	{
	  return YES;
	}
    }

  return NO;
}

- (BOOL) unmountPath: (NSString *)path error: (NSString **)errorMessage
{
  NSDictionary *entry = [self mountEntryForPath:path];
  NSString *mountPath = [entry objectForKey:@"path"];
  NSString *type = [entry objectForKey:@"type"];
  NSString *gioPath = @"/usr/bin/gio";
  NSTask *task;
  NSPipe *errorPipe;
  NSData *errorData;
  NSString *taskError = nil;

  if (![mountPath length])
    {
      if (errorMessage)
	{
	  *errorMessage = @"The dropped item is no longer a mounted filesystem.";
	}
      return NO;
    }

  if ([self mountPathIsProtected:mountPath type:type])
    {
      if (errorMessage)
	{
	  *errorMessage = [NSString stringWithFormat:
	    @"The system mount at %@ cannot be unmounted from the Recycler.",
	    mountPath];
	}
      return NO;
    }

  if (![[NSFileManager defaultManager] isExecutableFileAtPath:gioPath])
    {
      if (errorMessage)
	{
	  *errorMessage = @"The GIO unmount service is not installed.";
	}
      return NO;
    }

  task = AUTORELEASE([[NSTask alloc] init]);
  errorPipe = [NSPipe pipe];
  [task setLaunchPath:gioPath];
  [task setArguments:[NSArray arrayWithObjects:@"mount", @"-u",
			 [[NSURL fileURLWithPath:mountPath] absoluteString], nil]];
  [task setStandardError:errorPipe];

  NS_DURING
    {
      [task launch];
      [task waitUntilExit];
    }
  NS_HANDLER
    {
      taskError = [localException reason];
    }
  NS_ENDHANDLER

  errorData = taskError ? nil
    : [[[errorPipe fileHandleForReading] readDataToEndOfFile] retain];
  if ([errorData length])
    {
      NSString *output = AUTORELEASE([[NSString alloc] initWithData:errorData
							 encoding:NSUTF8StringEncoding]);
      output = [output stringByTrimmingCharactersInSet:
			 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([output length])
	{
	  taskError = output;
	}
    }
  RELEASE(errorData);

  if (!taskError && [task terminationStatus] == 0)
    {
      return YES;
    }

  if (errorMessage)
    {
      *errorMessage = [taskError length] ? taskError
	: [NSString stringWithFormat:@"GIO could not unmount %@.", mountPath];
    }
  return NO;
}

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
