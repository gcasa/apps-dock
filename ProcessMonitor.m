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
#import <unistd.h>
#import <signal.h>
#import <pthread.h>

#if defined(__linux__)
#import <sys/syscall.h>
#import <poll.h>
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif
#define HAVE_PIDFD 1
#else
#define HAVE_PIDFD 0
#endif

#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
#import <sys/event.h>
#import <sys/time.h>
#define HAVE_KQUEUE 1
#else
#define HAVE_KQUEUE 0
#endif

static ProcessMonitor *sharedMonitor = nil;

@implementation ProcessMonitor

+ (instancetype)sharedMonitor
{
  if (sharedMonitor == nil)
    {
      sharedMonitor = [[ProcessMonitor alloc] init];
    }
  return sharedMonitor;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      pthread_mutex_init(&_mutex, NULL);
      _watchedPIDs = [NSMutableDictionary new];
      _running = YES;

      if (pipe(_wakeupPipe) != 0)
        {
          NSLog(@"ProcessMonitor: pipe() failed");
        }

      pthread_create(&_monitorThread, NULL, _monitorThreadMain, self);
      pthread_detach(_monitorThread);
    }
  return self;
}

- (void)dealloc
{
  _running = NO;
  if (_wakeupPipe[1] >= 0)
    {
      write(_wakeupPipe[1], "x", 1);
    }
  pthread_mutex_destroy(&_mutex);
  [super dealloc];
}

- (void)addPID:(pid_t)pid
         token:(id)token
      callback:(ProcessExitCallback)block
{
  if (pid <= 0)
    {
      return;
    }

  pthread_mutex_lock(&_mutex);
  NSNumber *key = [NSNumber numberWithInt:pid];
  ProcessExitCallback copiedBlock = Block_copy(block);
  [_watchedPIDs setObject:[NSDictionary dictionaryWithObjectsAndKeys:
    token, @"token",
    [NSValue valueWithPointer:copiedBlock], @"callback",
    nil] forKey:key];
  pthread_mutex_unlock(&_mutex);

  if (_wakeupPipe[1] >= 0)
    {
      write(_wakeupPipe[1], "w", 1);
    }
}

- (void)removePID:(pid_t)pid
{
  if (pid <= 0)
    {
      return;
    }

  pthread_mutex_lock(&_mutex);
  NSNumber *key = [NSNumber numberWithInt:pid];
  NSDictionary *entry = [_watchedPIDs objectForKey:key];
  if (entry)
    {
      ProcessExitCallback block = (ProcessExitCallback)[[entry objectForKey:@"callback"] pointerValue];
      if (block)
        {
          Block_release(block);
        }
    }
  [_watchedPIDs removeObjectForKey:key];
  pthread_mutex_unlock(&_mutex);

  if (_wakeupPipe[1] >= 0)
    {
      write(_wakeupPipe[1], "w", 1);
    }
}

- (BOOL)processAlive:(pid_t)pid
{
  if (pid <= 0)
    {
      return NO;
    }
  int result = kill(pid, 0);
  return (result == 0) || (errno == EPERM);
}

void *_monitorThreadMain(void *arg)
{
  ProcessMonitor *monitor = (ProcessMonitor *)arg;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

#if HAVE_PIDFD
  while (monitor->_running)
    {
      NSArray *pids;
      NSUInteger i;
      int pfds_count = 0;
      struct pollfd pfds[257];

      pthread_mutex_lock(&monitor->_mutex);
      pids = [monitor->_watchedPIDs allKeys];
      pthread_mutex_unlock(&monitor->_mutex);

      if ([pids count] == 0)
        {
          pfds[0].fd = monitor->_wakeupPipe[0];
          pfds[0].events = POLLIN;
          poll(pfds, 1, -1);
          continue;
        }

      for (i = 0; i < [pids count] && pfds_count < 256; i++)
        {
          pid_t pid = [[pids objectAtIndex:i] intValue];
          int pidfd = (int)syscall(__NR_pidfd_open, pid, 0);
          if (pidfd >= 0)
            {
              pfds[pfds_count].fd = pidfd;
              pfds[pfds_count].events = POLLIN;
              pfds_count++;
            }
        }

      pfds[pfds_count].fd = monitor->_wakeupPipe[0];
      pfds[pfds_count].events = POLLIN;
      pfds_count++;

      poll(pfds, pfds_count, 2000);

      int j;
      for (j = 0; j < pfds_count - 1; j++)
        {
          if (pfds[j].revents & (POLLIN | POLLHUP))
            {
              pid_t pid = 0;
              NSNumber *key = nil;

              pthread_mutex_lock(&monitor->_mutex);
              for (NSNumber *k in [monitor->_watchedPIDs allKeys])
                {
                  if ([[monitor->_watchedPIDs objectForKey:k] objectForKey:@"callback"])
                    {
                      key = k;
                      pid = [k intValue];
                      break;
                    }
                }

              if (key)
                {
                  NSDictionary *entry = [monitor->_watchedPIDs objectForKey:key];
                  ProcessExitCallback block = (ProcessExitCallback)[[entry objectForKey:@"callback"] pointerValue];
                  id token = [entry objectForKey:@"token"];
                  [monitor->_watchedPIDs removeObjectForKey:key];
                  pthread_mutex_unlock(&monitor->_mutex);

                  if (block)
                    {
                      block(pid, token);
                      Block_release(block);
                    }
                }
              else
                {
                  pthread_mutex_unlock(&monitor->_mutex);
                }

              close(pfds[j].fd);
            }
        }
    }
#elif HAVE_KQUEUE
  {
    int kq = kqueue();
    if (kq < 0)
      {
        NSLog(@"ProcessMonitor: kqueue() failed");
        [pool drain];
        return NULL;
      }

    while (monitor->_running)
      {
        NSArray *pids;
        NSUInteger i;
        struct kevent events[257];
        int nevents = 0;

        pthread_mutex_lock(&monitor->_mutex);
        pids = [monitor->_watchedPIDs allKeys];
        pthread_mutex_unlock(&monitor->_mutex);

        if ([pids count] == 0)
          {
            struct kevent change;
            EV_SET(&change, monitor->_wakeupPipe[0], EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
            kevent(kq, &change, 1, NULL, 0, NULL);
            nevents = kevent(kq, NULL, 0, events, 1, NULL);
            continue;
          }

        for (i = 0; i < [pids count]; i++)
          {
            pid_t pid = [[pids objectAtIndex:i] intValue];
            struct kevent change;
            EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ENABLE | NOTE_EXIT, 0, 0, NULL);
            kevent(kq, &change, 1, NULL, 0, NULL);
          }

        struct kevent wakeup;
        EV_SET(&wakeup, monitor->_wakeupPipe[0], EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
        kevent(kq, &wakeup, 1, NULL, 0, NULL);

        nevents = kevent(kq, NULL, 0, events, 256, NULL);

        for (i = 0; i < nevents; i++)
          {
            if (events[i].filter == EVFILT_PROC && (events[i].fflags & NOTE_EXIT))
              {
                pid_t pid = events[i].ident;
                NSNumber *key = [NSNumber numberWithInt:pid];

                pthread_mutex_lock(&monitor->_mutex);
                NSDictionary *entry = [monitor->_watchedPIDs objectForKey:key];
                [monitor->_watchedPIDs removeObjectForKey:key];
                pthread_mutex_unlock(&monitor->_mutex);

                if (entry)
                  {
                    ProcessExitCallback block = (ProcessExitCallback)[[entry objectForKey:@"callback"] pointerValue];
                    id token = [entry objectForKey:@"token"];
                    if (block)
                      {
                        block(pid, token);
                        Block_release(block);
                      }
                  }
              }
          }
      }

    close(kq);
  }
#else
  /* Fallback: poll with kill(pid, 0) every 500ms */
  while (monitor->_running)
    {
      NSArray *pids;
      NSUInteger i;

      pthread_mutex_lock(&monitor->_mutex);
      pids = [monitor->_watchedPIDs allKeys];
      pthread_mutex_unlock(&monitor->_mutex);

      if ([pids count] == 0)
        {
          usleep(500000);
          continue;
        }

      NSMutableArray *exitedKeys = [NSMutableArray array];

      for (i = 0; i < [pids count]; i++)
        {
          pid_t pid = [[pids objectAtIndex:i] intValue];
          int result = kill(pid, 0);
          if (result != 0 && errno != ESRCH)
            {
              [exitedKeys addObject:[pids objectAtIndex:i]];
            }
        }

      for (NSNumber *key in exitedKeys)
        {
          pthread_mutex_lock(&monitor->_mutex);
          NSDictionary *entry = [monitor->_watchedPIDs objectForKey:key];
          [monitor->_watchedPIDs removeObjectForKey:key];
          pthread_mutex_unlock(&monitor->_mutex);

          if (entry)
            {
              ProcessExitCallback block = (ProcessExitCallback)[[entry objectForKey:@"callback"] pointerValue];
              id token = [entry objectForKey:@"token"];
              pid_t pid = [key intValue];
              if (block)
                {
                  block(pid, token);
                  Block_release(block);
                }
            }
        }

      usleep(500000);
    }
#endif

  [pool drain];
  return NULL;
}

@end
