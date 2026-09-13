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

typedef void (^ProcessExitCallback)(pid_t pid, id token);

@interface ProcessMonitor : NSObject
{
  pthread_mutex_t _mutex;
  pthread_t _monitorThread;
  BOOL _running;
  int _wakeupPipe[2];
  NSMutableDictionary *_watchedPIDs;
}

+ (instancetype)sharedMonitor;

- (void)addPID:(pid_t)pid
         token:(id)token
      callback:(ProcessExitCallback)block;
- (void)removePID:(pid_t)pid;
- (BOOL)processAlive:(pid_t)pid;

@end
