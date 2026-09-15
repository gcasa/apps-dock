/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class DockItem;
@class DockService;

/* The Dock tile protocol of the Workspace Dock, vended under the same
 * Distributed Objects name, so that applications - and the Eau theme, which
 * mirrors progress indicators into the Dock - work with either Dock.  The
 * service identifies the calling application itself.  oneway: a client must
 * never wait for a busy Dock. */
@protocol DockService <NSObject>
- (oneway void) setBadgeCount: (int64_t)count;
- (oneway void) setCountVisible: (BOOL)visible;
- (oneway void) setProgressValue: (double)value;
- (oneway void) setProgressVisible: (BOOL)visible;
- (oneway void) setUrgent: (BOOL)urgent;
- (oneway void) clearAll;
@end

@protocol DockServiceDelegate
- (DockItem *) dockService: (DockService *)service
  itemForProcessIdentifier: (int)processIdentifier;
- (void) dockService: (DockService *)service didChangeItem: (DockItem *)item;
@end

@interface DockService : NSObject
{
  id<DockServiceDelegate> _delegate;
  NSConnection *_connection;
}

- (id) initWithDelegate: (id<DockServiceDelegate>)delegate;
- (id<DockServiceDelegate>) delegate;
- (BOOL) start;

@end
