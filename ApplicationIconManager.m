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

#import "ApplicationIconManager.h"
#import "DockItem.h"
#import "RunningApplicationScanner.h"
#import <GNUstepBase/GNUstep.h>

@implementation ApplicationIconManager

- (id) initWithScanner: (RunningApplicationScanner *)scanner
{
  self = [super init];
  if (self)
    {
      _scanner = RETAIN(scanner);
      _applicationIconWindowItems = [NSMutableDictionary new];
      _applicationIconUpdatesByProcessID = [NSMutableDictionary new];
    }
  return self;
}

- (void) dealloc
{
  DESTROY(_applicationIconUpdatesByProcessID);
  DESTROY(_applicationIconWindowItems);
  DESTROY(_scanner);
  DEALLOC;
}

- (DockItem *) itemForApplicationIconWindow: (unsigned long)xWindow
{
  return [_applicationIconWindowItems objectForKey:
				       [NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item
{
  if (!item || !xWindow)
    {
      return;
    }

  [_applicationIconWindowItems setObject:item
				  forKey:[NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) removeApplicationIconWindowsForItem: (DockItem *)item
{
  NSArray *keys = [_applicationIconWindowItems allKeysForObject:item];
  NSUInteger i;

  for (i = 0; i < [keys count]; i++)
    {
      [_applicationIconWindowItems removeObjectForKey:[keys objectAtIndex:i]];
    }
}

- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image
{
  return [item icon] == image;
}

- (NSString *) x11IconCacheDirectory
{
  NSArray *libraryPaths =
    NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
					NSUserDomainMask,
					YES);
  NSString *libraryPath = [libraryPaths count] ? [libraryPaths objectAtIndex:0] : nil;
  NSString *cachePath;

  if (![libraryPath length])
    {
      libraryPath = NSHomeDirectory();
    }
  if (![libraryPath length])
    {
      return nil;
    }

  cachePath = [[libraryPath stringByAppendingPathComponent:@"DockWM"]
			   stringByAppendingPathComponent:@"X11Icons"];
  if ([[NSFileManager defaultManager] createDirectoryAtPath:cachePath
				withIntermediateDirectories:YES
						 attributes:nil
						      error:NULL])
    {
      return cachePath;
    }

  return nil;
}

- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier
{
  NSMutableString *name = [NSMutableString string];
  NSUInteger i;

  if (![identifier length])
    {
      identifier = @"x11-window";
    }

  for (i = 0; i < [identifier length] && [name length] < 80; i++)
    {
      unichar c = [identifier characterAtIndex:i];

      if ((c >= 'a' && c <= 'z') ||
	  (c >= 'A' && c <= 'Z') ||
	  (c >= '0' && c <= '9') ||
	  c == '.' || c == '_' || c == '-')
	{
	  [name appendFormat:@"%C", c];
	}
      else
	{
	  [name appendString:@"_"];
	}
    }

  if (![name length])
    {
      [name appendString:@"x11-window"];
    }

  return [NSString stringWithFormat:@"%@-%lx.tiff",
		   name,
		   (unsigned long)[identifier hash]];
}

- (NSString *) storeX11Icon: (NSImage *)icon identifier: (NSString *)identifier
{
  NSString *directory;
  NSString *fileName;
  NSString *path;
  NSData *data;

  if (!icon)
    {
      return nil;
    }

  data = [icon TIFFRepresentation];
  if (![data length])
    {
      return nil;
    }

  directory = [self x11IconCacheDirectory];
  if (![directory length])
    {
      return nil;
    }

  fileName = [self x11IconCacheFileNameForIdentifier:identifier];
  path = [directory stringByAppendingPathComponent:fileName];
  if ([data writeToFile:path atomically:YES])
    {
      return path;
    }

  return nil;
}

- (NSString *) x11IconIdentifierForTitle: (NSString *)title
				    path: (NSString *)path
				  window: (unsigned long)xWindow
{
  if ([path length])
    {
      return path;
    }
  if ([title length])
    {
      return title;
    }
  return [NSString stringWithFormat:@"0x%lx", xWindow];
}

- (BOOL) shouldApplyX11Icon: (NSImage *)icon toItem: (DockItem *)item
{
  NSString *bundlePath;

  if (!icon || !item)
    {
      return NO;
    }
  if ([item kind] != DockItemApplication)
    {
      return YES;
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  return ![bundlePath length];
}

- (void) applyX11Icon: (NSImage *)icon
	       toItem: (DockItem *)item
	   identifier: (NSString *)identifier
{
  NSString *iconPath;
  NSString *bundlePath;

  if (![self shouldApplyX11Icon:icon toItem:item])
    {
      return;
    }

  iconPath = [self storeX11Icon:icon identifier:identifier];
  [item setIcon:icon];
  if ([iconPath length])
    {
      [item setIconPath:iconPath];
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  if ([item kind] == DockItemApplication && ![bundlePath length])
    {
      [item setOriginalIcon:icon];
    }
}

- (void) rememberApplicationIcon: (NSImage *)icon
		      badgeLabel: (NSString *)badgeLabel
	       processIdentifier: (NSNumber *)processIdentifier
{
  NSMutableDictionary *update;
  BOOL updateHasBadge = [badgeLabel length] > 0;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return;
    }

  update = [NSMutableDictionary dictionary];
  if (icon && !updateHasBadge)
    {
      NSString *iconPath = [self storeX11Icon:icon
				   identifier:[NSString stringWithFormat:@"pid-%@",
							    processIdentifier]];
      [update setObject:icon forKey:@"icon"];
      if ([iconPath length])
	{
	  [update setObject:iconPath forKey:@"iconPath"];
	}
    }
  [update setObject:([badgeLabel length] ? badgeLabel : (id)[NSNull null])
	     forKey:@"badgeLabel"];
  [_applicationIconUpdatesByProcessID setObject:update
					 forKey:processIdentifier];
}

- (NSDictionary *) applicationIconUpdateForProcessIdentifier: (NSNumber *)processIdentifier
{
  return [_applicationIconUpdatesByProcessID objectForKey:processIdentifier];
}

- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update toItem: (DockItem *)item
{
  id icon = [update objectForKey:@"icon"];
  id iconPath = [update objectForKey:@"iconPath"];
  id badgeObject = [update objectForKey:@"badgeLabel"];
  NSString *badgeLabel = badgeObject == [NSNull null] ? nil : badgeObject;
  BOOL updateHasBadge = [badgeLabel length] > 0;
  BOOL changed = NO;

  if (updateHasBadge)
    {
      NSImage *currentIcon = [item icon];

      [item restoreOriginalIcon];
      if ([item icon] != currentIcon)
	{
	  changed = YES;
	}
    }

  if (!updateHasBadge &&
      [icon isKindOfClass:[NSImage class]] &&
      ![self item:item iconMatchesImage:icon])
    {
      [item setIcon:icon];
      changed = YES;
    }
  if (!updateHasBadge &&
      [iconPath isKindOfClass:[NSString class]] && [iconPath length] &&
      !([[item iconPath] isEqualToString:iconPath]))
    {
      [item setIconPath:iconPath];
      changed = YES;
    }

  if (([badgeLabel length] || [[item badgeLabel] length]) &&
      !(([item badgeLabel] == badgeLabel) ||
	([item badgeLabel] && badgeLabel &&
	 [[item badgeLabel] isEqualToString:badgeLabel])))
    {
      [item setBadgeLabel:badgeLabel];
      changed = YES;
    }

  return changed;
}

- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item
{
  NSArray *processIdentifiers = [_scanner runningProcessIdentifiersForApplicationItem:item];
  BOOL changed = NO;
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSDictionary *update = [_applicationIconUpdatesByProcessID
			       objectForKey:[processIdentifiers objectAtIndex:i]];

      if (update)
	{
	  changed = [self applyApplicationIconUpdate:update toItem:item] || changed;
	}
    }

  return changed;
}

- (void) pruneApplicationIconUpdatesForExitedProcesses
{
  NSArray *processIdentifiers = [_applicationIconUpdatesByProcessID allKeys];
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSNumber *processIdentifier = [processIdentifiers objectAtIndex:i];
      NSString *processPath = [_scanner procPathForProcessIdentifierString:
					  [processIdentifier stringValue]];

      if (![processPath length] ||
	  ![[NSFileManager defaultManager] fileExistsAtPath:processPath])
	{
	  [_applicationIconUpdatesByProcessID removeObjectForKey:processIdentifier];
	}
    }
}

@end
