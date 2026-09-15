/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "DockService.h"
#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>

static NSString * const DockServiceName = @"DockIcon";

/* libs-base declares this accessor only in a private header. */
@interface NSMessagePort (DockServicePortName)
- (const unsigned char *) _name;
@end

/* Message ports are sockets which libs-base names "<pid>.<n>" after the
 * process that listens on them, so the reply port of a connection names the
 * calling application. */
static int
DockServiceProcessIdentifierForPort (NSPort *port)
{
  NSString *name;
  NSArray *components;

  if (![port isKindOfClass:[NSMessagePort class]])
    {
      return 0;
    }

  name = [[NSString stringWithUTF8String:
		      (const char *)[(NSMessagePort *)port _name]]
	   lastPathComponent];
  components = [name componentsSeparatedByString:@"."];
  if ([components count] != 2)
    {
      return 0;
    }
  return [[components objectAtIndex:0] intValue];
}

/* The root object of one client connection.  It knows the calling process,
 * so the calls themselves need not find out who sent them. */
@interface DockServiceClient : NSObject <DockService>
{
  DockService *_service;
  int _processIdentifier;
  int64_t _badgeCount;
  BOOL _countVisible;
}

- (id) initWithService: (DockService *)service
     processIdentifier: (int)processIdentifier;

@end

@implementation DockServiceClient

- (id) initWithService: (DockService *)service
     processIdentifier: (int)processIdentifier
{
  self = [super init];
  if (self)
    {
      _service = service;
      _processIdentifier = processIdentifier;
    }
  return self;
}

- (DockItem *) item
{
  return [[_service delegate] dockService:_service
		 itemForProcessIdentifier:_processIdentifier];
}

- (void) itemDidChange: (DockItem *)item
{
  [[_service delegate] dockService:_service didChangeItem:item];
}

- (void) updateBadgeOfItem: (DockItem *)item
{
  NSString *label = nil;

  if (_countVisible && _badgeCount > 0)
    {
      label = _badgeCount > 99 ? @"99+"
	: [NSString stringWithFormat:@"%lld", (long long)_badgeCount];
    }
  [item setBadgeLabel:label];
}

- (oneway void) setBadgeCount: (int64_t)count
{
  DockItem *item = [self item];

  _badgeCount = MAX(0, count);
  _countVisible = YES;
  if (item)
    {
      [self updateBadgeOfItem:item];
      [self itemDidChange:item];
    }
}

- (oneway void) setCountVisible: (BOOL)visible
{
  DockItem *item = [self item];

  _countVisible = visible;
  if (item)
    {
      [self updateBadgeOfItem:item];
      [self itemDidChange:item];
    }
}

- (oneway void) setProgressValue: (double)value
{
  DockItem *item = [self item];

  if (item)
    {
      /* Negative values stand for progress of unknown length. */
      [item setProgressValue:fmax(-1.0, fmin(1.0, value))];
      [item setProgressVisible:YES];
      [self itemDidChange:item];
    }
}

- (oneway void) setProgressVisible: (BOOL)visible
{
  DockItem *item = [self item];

  if (item)
    {
      [item setProgressVisible:visible];
      [self itemDidChange:item];
    }
}

- (oneway void) setUrgent: (BOOL)urgent
{
  DockItem *item = [self item];

  if (item)
    {
      [item setUrgent:urgent];
      [self itemDidChange:item];
    }
}

- (oneway void) clearAll
{
  DockItem *item = [self item];

  _countVisible = NO;
  if (item)
    {
      [self updateBadgeOfItem:item];
      [item setProgressVisible:NO];
      [item setUrgent:NO];
      [self itemDidChange:item];
    }
}

@end

@implementation DockService

- (id) initWithDelegate: (id<DockServiceDelegate>)delegate
{
  self = [super init];
  if (self)
    {
      _delegate = delegate;
    }
  return self;
}

- (void) dealloc
{
  [_connection invalidate];
  DESTROY(_connection);
  DEALLOC;
}

- (id<DockServiceDelegate>) delegate
{
  return _delegate;
}

- (BOOL) start
{
  _connection = [NSConnection new];
  [_connection setDelegate:self];
  /* Clients must be answered while a menu is open or a modal panel runs;
   * the connections made for new clients copy these modes. */
  [_connection addRequestMode:NSEventTrackingRunLoopMode];
  [_connection addRequestMode:NSModalPanelRunLoopMode];
  if (![_connection registerName:DockServiceName])
    {
      NSLog(@"Unable to register %@: another Dock provides it, so applications cannot show progress, badges or urgency in DockWM.",
	    DockServiceName);
      DESTROY(_connection);
      return NO;
    }
  return YES;
}

- (BOOL) connection: (NSConnection *)parentConnection
shouldMakeNewConnection: (NSConnection *)newConnection
{
  int processIdentifier =
    DockServiceProcessIdentifierForPort([newConnection sendPort]);
  DockServiceClient *client;

  if (processIdentifier <= 0)
    {
      NSLog(@"Refusing a %@ client whose process cannot be identified from port %@.",
	    DockServiceName, [newConnection sendPort]);
      return NO;
    }

  client = [[DockServiceClient alloc] initWithService:self
				    processIdentifier:processIdentifier];
  [newConnection setRootObject:client];
  RELEASE(client);
  return YES;
}

@end
