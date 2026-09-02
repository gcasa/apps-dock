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

#import <AppKit/AppKit.h>

@class DockItem;
@class RunningApplicationScanner;

@interface ApplicationIconManager : NSObject
{
  NSMutableDictionary *_applicationIconWindowItems;
  NSMutableDictionary *_applicationIconUpdatesByProcessID;
  RunningApplicationScanner *_scanner;
}

- (id) initWithScanner: (RunningApplicationScanner *)scanner;
- (DockItem *) itemForApplicationIconWindow: (unsigned long)xWindow;
- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item;
- (void) removeApplicationIconWindowsForItem: (DockItem *)item;
- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image;
- (NSString *) x11IconCacheDirectory;
- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier;
- (NSString *) storeX11Icon: (NSImage *)icon identifier: (NSString *)identifier;
- (NSString *) x11IconIdentifierForTitle: (NSString *)title
				    path: (NSString *)path
				  window: (unsigned long)xWindow;
- (BOOL) shouldApplyX11Icon: (NSImage *)icon toItem: (DockItem *)item;
- (void) applyX11Icon: (NSImage *)icon
	       toItem: (DockItem *)item
	   identifier: (NSString *)identifier;
- (void) rememberApplicationIcon: (NSImage *)icon
		      badgeLabel: (NSString *)badgeLabel
	       processIdentifier: (NSNumber *)processIdentifier;
- (NSDictionary *) applicationIconUpdateForProcessIdentifier: (NSNumber *)processIdentifier;
- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update toItem: (DockItem *)item;
- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item;
- (void) pruneApplicationIconUpdatesForExitedProcesses;

@end
