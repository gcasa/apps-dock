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

@interface RunningApplicationScanner : NSObject

- (NSString *) normalizedPath: (NSString *)path;
- (NSArray *) commandSearchPathComponents;
- (NSString *) procFilesystemPath;
- (NSString *) procPathForProcessIdentifierString: (NSString *)identifier;
- (BOOL) path: (NSString *)path isEqualToOrDescendantOfPath: (NSString *)parentPath;
- (NSString *) executablePathForApplicationPath: (NSString *)path;
- (NSString *) firstCommandTokenFromString: (NSString *)string;
- (NSString *) pathForExecutableCommand: (NSString *)command;
- (NSString *) executablePathForDesktopFile: (NSString *)path;
- (BOOL) stringIsProcessIdentifier: (NSString *)string;
- (NSArray *) runningProcessExecutablePaths;
- (NSString *) executablePathForProcessIdentifier: (NSNumber *)processIdentifier;
- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item;
- (BOOL) applicationItem: (DockItem *)item
matchesRunningProcessPath: (NSString *)processPath;
- (BOOL) applicationItemHasRunningProcess: (DockItem *)item
				    paths: (NSArray *)processPaths;

@end
