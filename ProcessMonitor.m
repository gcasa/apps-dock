/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "ProcessMonitor.h"
#import <GNUstepBase/GNUstep.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#if defined(__linux__)
#import <sys/syscall.h>
/* Older C libraries lack the constant; new system calls share one number
 * on every Linux architecture. */
#ifndef SYS_pidfd_open
#define SYS_pidfd_open 434
#endif
#elif defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) \
  || defined(__DragonFly__)
#define PROCESS_MONITOR_USES_KQUEUE 1
#import <sys/types.h>
#import <sys/event.h>
#import <sys/time.h>
#else
#error "ProcessMonitor needs pidfd (Linux) or kqueue (BSD) process exit notifications"
#endif

@interface ProcessMonitor (Private)
- (void) wakeUp;
- (void) monitorProcesses: (id)unused;
- (void) updateWatchedProcesses;
- (void) waitForExits;
- (void) processDidExit: (NSNumber *)processIdentifier;
- (void) reportExit: (NSNumber *)processIdentifier;
@end

@implementation ProcessMonitor

- (id) initWithTarget: (id)target action: (SEL)action
{
  self = [super init];
  if (self)
    {
      _target = target;
      _action = action;
      _lock = [NSLock new];
      _requestedProcessIdentifiers = [NSMutableSet new];
      _watchedProcessIdentifiers = [NSMutableDictionary new];
      _queue = -1;
      if (pipe(_wakeupPipe) != 0)
	{
	  NSLog(@"ProcessMonitor: unable to create its wakeup pipe: %s",
		strerror(errno));
	  DESTROY(self);
	  return nil;
	}
      /* Non-blocking: a full pipe already holds a pending wakeup, and the
       * monitor thread drains it without ever waiting in read(). */
      fcntl(_wakeupPipe[0], F_SETFL, fcntl(_wakeupPipe[0], F_GETFL) | O_NONBLOCK);
      fcntl(_wakeupPipe[1], F_SETFL, fcntl(_wakeupPipe[1], F_GETFL) | O_NONBLOCK);
#if PROCESS_MONITOR_USES_KQUEUE
      _queue = kqueue();
      if (_queue < 0)
	{
	  NSLog(@"ProcessMonitor: unable to create a kqueue: %s",
		strerror(errno));
	  DESTROY(self);
	  return nil;
	}
#endif
      _running = YES;
      /* The thread retains the monitor until it has finished, so the
       * descriptors it waits on stay open as long as it uses them. */
      [NSThread detachNewThreadSelector:@selector(monitorProcesses:)
			       toTarget:self
			     withObject:nil];
    }
  return self;
}

- (void) dealloc
{
  if (_wakeupPipe[0] >= 0)
    {
      close(_wakeupPipe[0]);
      close(_wakeupPipe[1]);
    }
  if (_queue >= 0)
    {
      close(_queue);
    }
  DESTROY(_watchedProcessIdentifiers);
  DESTROY(_requestedProcessIdentifiers);
  DESTROY(_lock);
  DEALLOC;
}

- (void) setProcessIdentifiers: (NSSet *)processIdentifiers
{
  [_lock lock];
  [_requestedProcessIdentifiers setSet:processIdentifiers];
  [_lock unlock];
  [self wakeUp];
}

- (void) stop
{
  [_lock lock];
  _running = NO;
  _target = nil;
  [_lock unlock];
  [self wakeUp];
}

@end

@implementation ProcessMonitor (Private)

- (void) wakeUp
{
  char byte = 0;

  if (write(_wakeupPipe[1], &byte, 1) < 0 && errno != EAGAIN)
    {
      NSLog(@"ProcessMonitor: unable to wake its thread: %s", strerror(errno));
    }
}

- (void) monitorProcesses: (id)unused
{
  BOOL running = YES;

  while (running)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];

      [self updateWatchedProcesses];
      [self waitForExits];
      [_lock lock];
      running = _running;
      [_lock unlock];
      RELEASE(pool);
    }

#if !PROCESS_MONITOR_USES_KQUEUE
  {
    NSEnumerator *enumerator = [_watchedProcessIdentifiers objectEnumerator];
    NSNumber *descriptor;

    while ((descriptor = [enumerator nextObject]) != nil)
      {
	close([descriptor intValue]);
      }
  }
#endif
  [_watchedProcessIdentifiers removeAllObjects];
}

/* Runs on the monitor thread only, which alone opens and closes the
 * descriptors it waits on. */
- (void) updateWatchedProcesses
{
  NSSet *requested;
  NSArray *watched;
  NSEnumerator *enumerator;
  NSNumber *processIdentifier;

  [_lock lock];
  requested = AUTORELEASE([_requestedProcessIdentifiers copy]);
  [_lock unlock];

  watched = [_watchedProcessIdentifiers allKeys];
  enumerator = [watched objectEnumerator];
  while ((processIdentifier = [enumerator nextObject]) != nil)
    {
      if ([requested containsObject:processIdentifier])
	{
	  continue;
	}
#if PROCESS_MONITOR_USES_KQUEUE
      {
	struct kevent change;

	EV_SET(&change, (uintptr_t)[processIdentifier intValue], EVFILT_PROC,
	       EV_DELETE, 0, 0, NULL);
	kevent(_queue, &change, 1, NULL, 0, NULL);
      }
#else
      close([[_watchedProcessIdentifiers objectForKey:processIdentifier] intValue]);
#endif
      [_watchedProcessIdentifiers removeObjectForKey:processIdentifier];
    }

  enumerator = [requested objectEnumerator];
  while ((processIdentifier = [enumerator nextObject]) != nil)
    {
      pid_t pid = (pid_t)[processIdentifier intValue];

      if ([_watchedProcessIdentifiers objectForKey:processIdentifier] || pid <= 0)
	{
	  continue;
	}
#if PROCESS_MONITOR_USES_KQUEUE
      {
	struct kevent change;

	EV_SET(&change, (uintptr_t)pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
	if (kevent(_queue, &change, 1, NULL, 0, NULL) == 0)
	  {
	    [_watchedProcessIdentifiers setObject:[NSNull null]
					   forKey:processIdentifier];
	    continue;
	  }
      }
#else
      {
	int descriptor = (int)syscall(SYS_pidfd_open, pid, 0);

	if (descriptor >= 0)
	  {
	    [_watchedProcessIdentifiers setObject:[NSNumber numberWithInt:descriptor]
					   forKey:processIdentifier];
	    continue;
	  }
      }
#endif
      if (errno == ESRCH)
	{
	  [self processDidExit:processIdentifier];
	}
      else
	{
	  NSLog(@"ProcessMonitor: unable to watch process %d: %s",
		(int)pid, strerror(errno));
	}
    }
}

- (void) waitForExits
{
  NSUInteger count = 1;
  struct pollfd *descriptors;
  char buffer[64];
#if !PROCESS_MONITOR_USES_KQUEUE
  NSArray *processIdentifiers = [_watchedProcessIdentifiers allKeys];
  NSUInteger i;

  count += [processIdentifiers count];
#else
  count += 1;
#endif

  descriptors = calloc(count, sizeof(struct pollfd));
  if (!descriptors)
    {
      NSLog(@"ProcessMonitor: out of memory");
      return;
    }
  descriptors[0].fd = _wakeupPipe[0];
  descriptors[0].events = POLLIN;
#if PROCESS_MONITOR_USES_KQUEUE
  descriptors[1].fd = _queue;
  descriptors[1].events = POLLIN;
#else
  for (i = 0; i < [processIdentifiers count]; i++)
    {
      descriptors[i + 1].fd = [[_watchedProcessIdentifiers objectForKey:
			      [processIdentifiers objectAtIndex:i]] intValue];
      descriptors[i + 1].events = POLLIN;
    }
#endif

  if (poll(descriptors, (nfds_t)count, -1) < 0)
    {
      if (errno != EINTR)
	{
	  NSLog(@"ProcessMonitor: poll failed: %s", strerror(errno));
	}
      free(descriptors);
      return;
    }

  while (read(_wakeupPipe[0], buffer, sizeof(buffer)) > 0)
    {
    }

#if PROCESS_MONITOR_USES_KQUEUE
  if (descriptors[1].revents & POLLIN)
    {
      struct kevent events[32];
      struct timespec noWait = { 0, 0 };
      int eventCount = kevent(_queue, NULL, 0, events, 32, &noWait);
      int j;

      for (j = 0; j < eventCount; j++)
	{
	  if (events[j].filter == EVFILT_PROC && (events[j].fflags & NOTE_EXIT))
	    {
	      NSNumber *processIdentifier =
		[NSNumber numberWithInt:(int)events[j].ident];

	      /* The kernel drops the event of an exited process by itself. */
	      [_watchedProcessIdentifiers removeObjectForKey:processIdentifier];
	      [self processDidExit:processIdentifier];
	    }
	}
    }
#else
  for (i = 0; i < [processIdentifiers count]; i++)
    {
      if (descriptors[i + 1].revents & (POLLIN | POLLHUP | POLLERR))
	{
	  NSNumber *processIdentifier = [processIdentifiers objectAtIndex:i];

	  close(descriptors[i + 1].fd);
	  [_watchedProcessIdentifiers removeObjectForKey:processIdentifier];
	  [self processDidExit:processIdentifier];
	}
    }
#endif

  free(descriptors);
}

- (void) processDidExit: (NSNumber *)processIdentifier
{
  /* Not watched again until the owner asks for it anew. */
  [_lock lock];
  [_requestedProcessIdentifiers removeObject:processIdentifier];
  [_lock unlock];
  [self performSelectorOnMainThread:@selector(reportExit:)
			 withObject:processIdentifier
		      waitUntilDone:NO];
}

- (void) reportExit: (NSNumber *)processIdentifier
{
  id target;

  [_lock lock];
  target = _target;
  [_lock unlock];
  [target performSelector:_action withObject:processIdentifier];
}

@end
