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

#import "DockApplicationStore.h"
#import "DockItem.h"
#import "RunningApplicationScanner.h"
#import <GNUstepBase/GNUstep.h>

static NSString *DockApplicationsDefaultsKey = @"DockApplications";
static NSString *DockApplicationPathKey = @"Path";
static NSString *DockApplicationArgumentsKey = @"Arguments";
static NSString *DockOpenAtLoginApplicationsDefaultsKey = @"DockOpenAtLoginApplications";

@implementation DockApplicationStore

- (id) initWithScanner: (RunningApplicationScanner *)scanner
{
  self = [super init];
  if (self)
    {
      _scanner = RETAIN(scanner);
    }
  return self;
}

- (void) dealloc
{
  DESTROY(_scanner);
  DEALLOC;
}

- (DockItem *) transientApplicationItemMatchingBundlePath: (NSString *)path
						   items: (NSArray *)items
{
  NSString *normalizedPath = [_scanner normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length])
    {
      return nil;
    }

  for (i = 0; i < [items count]; i++)
    {
      DockItem *item = [items objectAtIndex:i];
      NSString *itemBundlePath;

      if ([item kind] == DockItemApplication &&
	  ![item isPinned] &&
	  [[_scanner normalizedPath:[item path]] isEqualToString:normalizedPath])
	{
	  return item;
	}

      itemBundlePath = [DockItem applicationBundlePathForPath:[item path]];
      if ([item kind] == DockItemApplication &&
	  ![item isPinned] &&
	  [itemBundlePath length] &&
	  [[_scanner normalizedPath:itemBundlePath] isEqualToString:normalizedPath])
	{
	  return item;
	}
    }

  return nil;
}

- (void) loadPersistedApplicationsIntoItems: (NSMutableArray *)items
{
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
		     objectForKey:DockApplicationsDefaultsKey];
  NSUInteger i;

  if (![paths isKindOfClass:[NSArray class]])
    {
      return;
    }

  for (i = 0; i < [paths count]; i++)
    {
      id record = [paths objectAtIndex:i];
      NSString *path = [self persistedApplicationPathFromRecord:record];
      NSString *arguments = [self persistedApplicationArgumentsFromRecord:record];
      NSString *bundlePath;
      NSString *applicationPath;
      DockItem *transientItem;
      BOOL isDir = NO;

      if (![path length])
	{
	  continue;
	}

      bundlePath = [DockItem applicationBundlePathForPath:path];
      applicationPath = [bundlePath length] ? bundlePath : path;

      if ([[NSFileManager defaultManager] fileExistsAtPath:applicationPath
					       isDirectory:&isDir] &&
	  ![self items:items haveApplicationPath:applicationPath])
	{
	  transientItem = [self transientApplicationItemMatchingBundlePath:applicationPath
								    items:items];
	  if (transientItem)
	    {
	      [items removeObject:transientItem];
	    }
	  {
	    DockItem *item = [DockItem applicationItemWithPath:applicationPath];
	    [item setLaunchArguments:arguments];
	    [items addObject:item];
	  }
	}
    }
}

- (void) savePersistedApplicationsFromItems: (NSArray *)items
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableSet *savedPaths = [NSMutableSet set];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      DockItem *item = [items objectAtIndex:i];
      NSString *path = [item path];
      NSString *normalizedPath = [_scanner normalizedPath:path];

      if (![normalizedPath length])
	{
	  normalizedPath = path;
	}

      if ([item kind] == DockItemApplication &&
	  [item isPinned] &&
	  [path length] &&
	  ![savedPaths containsObject:normalizedPath])
	{
	  if ([normalizedPath length])
	    {
	      [savedPaths addObject:normalizedPath];
	    }
	  [paths addObject:[self persistedApplicationRecordForItem:item]];
	}
    }

  [defaults setObject:paths forKey:DockApplicationsDefaultsKey];
  [defaults synchronize];
}

- (id) persistedApplicationRecordForItem: (DockItem *)item
{
  NSString *path = [item path];
  NSString *arguments = [item launchArguments];

  if (![arguments length])
    {
      return path;
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
			 path, DockApplicationPathKey,
			 arguments, DockApplicationArgumentsKey,
			 nil];
}

- (NSString *) persistedApplicationPathFromRecord: (id)record
{
  if ([record isKindOfClass:[NSString class]])
    {
      return record;
    }
  if ([record isKindOfClass:[NSDictionary class]])
    {
      id path = [record objectForKey:DockApplicationPathKey];

      if ([path isKindOfClass:[NSString class]])
	{
	  return path;
	}
    }
  return nil;
}

- (NSString *) persistedApplicationArgumentsFromRecord: (id)record
{
  if ([record isKindOfClass:[NSDictionary class]])
    {
      id arguments = [record objectForKey:DockApplicationArgumentsKey];

      if ([arguments isKindOfClass:[NSString class]])
	{
	  return arguments;
	}
    }
  return nil;
}

- (BOOL) items: (NSArray *)items haveApplicationPath: (NSString *)path
{
  NSString *normalizedPath = [_scanner normalizedPath:path];
  NSUInteger i;

  if (![normalizedPath length])
    {
      return NO;
    }

  for (i = 0; i < [items count]; i++)
    {
      DockItem *item = [items objectAtIndex:i];
      if ([item kind] == DockItemApplication &&
	  [item isPinned] &&
	  [[_scanner normalizedPath:[item path]] isEqualToString:normalizedPath])
	{
	  return YES;
	}
    }

  return NO;
}

- (NSArray *) openAtLoginApplicationPaths
{
  NSArray *paths = [[NSUserDefaults standardUserDefaults]
		     objectForKey:DockOpenAtLoginApplicationsDefaultsKey];

  return [paths isKindOfClass:[NSArray class]] ? paths : [NSArray array];
}

- (BOOL) path: (NSString *)path matchesOpenAtLoginPath: (NSString *)savedPath
{
  NSString *normalizedPath = [_scanner normalizedPath:path];
  NSString *normalizedSavedPath = [_scanner normalizedPath:savedPath];
  NSString *executablePath = [_scanner executablePathForApplicationPath:path];
  NSString *savedExecutablePath = [_scanner executablePathForApplicationPath:savedPath];
  NSString *bundlePath = [DockItem applicationBundlePathForPath:path];
  NSString *savedBundlePath = [DockItem applicationBundlePathForPath:savedPath];

  executablePath = [_scanner normalizedPath:executablePath];
  savedExecutablePath = [_scanner normalizedPath:savedExecutablePath];
  bundlePath = [_scanner normalizedPath:bundlePath];
  savedBundlePath = [_scanner normalizedPath:savedBundlePath];

  if ([normalizedPath length] &&
      [normalizedPath isEqualToString:normalizedSavedPath])
    {
      return YES;
    }
  if ([executablePath length] &&
      [executablePath isEqualToString:normalizedSavedPath])
    {
      return YES;
    }
  if ([savedExecutablePath length] &&
      [savedExecutablePath isEqualToString:normalizedPath])
    {
      return YES;
    }
  if ([executablePath length] &&
      [executablePath isEqualToString:savedExecutablePath])
    {
      return YES;
    }
  if ([bundlePath length] &&
      [bundlePath isEqualToString:normalizedSavedPath])
    {
      return YES;
    }
  if ([savedBundlePath length] &&
      [savedBundlePath isEqualToString:normalizedPath])
    {
      return YES;
    }
  if ([bundlePath length] &&
      [bundlePath isEqualToString:savedBundlePath])
    {
      return YES;
    }

  return NO;
}

- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path
{
  NSArray *paths = [self openAtLoginApplicationPaths];
  NSUInteger i;

  if (![path length])
    {
      return NO;
    }

  for (i = 0; i < [paths count]; i++)
    {
      if ([self path:path matchesOpenAtLoginPath:[paths objectAtIndex:i]])
	{
	  return YES;
	}
    }

  return NO;
}

- (void) setApplicationPath: (NSString *)path openAtLogin: (BOOL)openAtLogin
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray *savedPaths = [self openAtLoginApplicationPaths];
  NSMutableArray *paths = [NSMutableArray array];
  NSString *normalizedPath = [_scanner normalizedPath:path];
  NSUInteger i;
  BOOL found = NO;

  if (![normalizedPath length])
    {
      return;
    }

  for (i = 0; i < [savedPaths count]; i++)
    {
      NSString *savedPath = [savedPaths objectAtIndex:i];

      if ([self path:path matchesOpenAtLoginPath:savedPath])
	{
	  found = YES;
	  if (openAtLogin)
	    {
	      [paths addObject:savedPath];
	    }
	}
      else
	{
	  [paths addObject:savedPath];
	}
    }

  if (openAtLogin && !found)
    {
      [paths addObject:path];
    }

  [defaults setObject:paths forKey:DockOpenAtLoginApplicationsDefaultsKey];
  [defaults synchronize];
}

@end
