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

#import <Foundation/Foundation.h>

@class DockItem;
@class RunningApplicationScanner;

@interface DockApplicationStore : NSObject
{
  RunningApplicationScanner *_scanner;
}

- (id) initWithScanner: (RunningApplicationScanner *)scanner;
- (void) loadPersistedApplicationsIntoItems: (NSMutableArray *)items;
- (void) savePersistedApplicationsFromItems: (NSArray *)items;
- (id) persistedApplicationRecordForItem: (DockItem *)item;
- (NSString *) persistedApplicationPathFromRecord: (id)record;
- (NSString *) persistedApplicationArgumentsFromRecord: (id)record;
- (BOOL) items: (NSArray *)items haveApplicationPath: (NSString *)path;
- (NSArray *) openAtLoginApplicationPaths;
- (BOOL) applicationPathIsOpenAtLogin: (NSString *)path;
- (void) setApplicationPath: (NSString *)path openAtLogin: (BOOL)openAtLogin;

@end
