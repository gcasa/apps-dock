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

@interface RecyclerController : NSObject

- (NSArray *) recyclerPaths;
- (BOOL) directoryHasVisibleContentsAtPath: (NSString *)path;
- (BOOL) recyclerHasContents;
- (NSString *) recyclerPathForDropping;
- (NSString *) recyclerDestinationPathForPath: (NSString *)path
				 recyclerPath: (NSString *)recyclerPath;
- (BOOL) movePathToRecyclerFallback: (NSString *)path
		       recyclerPath: (NSString *)recyclerPath;
- (void) emptyRecyclerPath: (NSString *)path;

@end
