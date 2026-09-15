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

#import <Foundation/Foundation.h>

/* Tells its target the moment a watched process exits.  A thread of its own
 * waits for the exit notification of the kernel (pidfd on Linux, kqueue on
 * the BSDs), so nothing has to poll the process table.  The action is sent
 * on the main thread with the process identifier as an NSNumber. */
@interface ProcessMonitor : NSObject
{
  id _target;
  SEL _action;
  NSLock *_lock;
  NSMutableSet *_requestedProcessIdentifiers;
  NSMutableDictionary *_watchedProcessIdentifiers;
  int _wakeupPipe[2];
  int _queue;
  BOOL _running;
}

- (id) initWithTarget: (id)target action: (SEL)action;
/* Replaces the watched processes by the given NSNumber identifiers. */
- (void) setProcessIdentifiers: (NSSet *)processIdentifiers;
- (void) stop;

@end
