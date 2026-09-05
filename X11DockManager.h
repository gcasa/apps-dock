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

#import <AppKit/AppKit.h>

@class DockView;
@class DockItem;

typedef enum
  {
    DockPlacementLeftTop = 0,
    DockPlacementLeftCenter,
    DockPlacementRightTop,
    DockPlacementRightCenter,
    DockPlacementTopCenter,
    DockPlacementBottomCenter
  } DockPlacement;

@protocol X11DockManagerDelegate
- (void) x11DockManagerDidDiscoverWindowWithTitle: (NSString *)title
                                           window: (unsigned long)xWindow
                                           hidden: (BOOL)hidden
                                             icon: (NSImage *)icon
                                             path: (NSString *)path
                                          dockApp: (BOOL)dockApp;
- (void) x11DockManagerDidUpdateWindow: (unsigned long)xWindow
                                hidden: (BOOL)hidden
                                  icon: (NSImage *)icon;
- (void) x11DockManagerDidUpdateApplicationIcon: (NSImage *)icon
                              processIdentifier: (int)processIdentifier
                                          title: (NSString *)title;
- (void) x11DockManagerDidUpdateApplicationIcon: (NSImage *)icon
                                     badgeLabel: (NSString *)badgeLabel
                              processIdentifier: (int)processIdentifier;
- (void) x11DockManagerDidRequestUserAttentionForProcessIdentifier: (int)processIdentifier
						       requestType: (NSInteger)requestType;
@end

@interface X11DockManager : NSObject
{
  id _delegate;
  DockView *_dockView;
  void *_display;
  unsigned long _hostWindow;
  NSMutableSet *_knownWindows;
  NSConnection *_iconConnection;
  NSMutableDictionary *_iconWindowsByProcessID;
  NSMutableDictionary *_iconImageDataByProcessID;
  NSMutableDictionary *_dockedWindowFrames;
  NSMutableSet *_dockAppWindows;
  BOOL _scanPending;
  NSTimeInterval _lastEventScanTime;
}

- (id) initWithDockView: (DockView *)view;
- (void) setDelegate: (id)delegate;
- (BOOL) start;
- (void) setDockPlacement: (DockPlacement)placement;
- (void) makeWindowSticky: (unsigned long)xWindow;
- (void) processPendingEvents;
- (void) drainTransientIconEvents;
- (void) scanForDockApps;
- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index;
- (void) moveDockedWindow: (unsigned long)xWindow toIndex: (NSUInteger)index;
- (void) activateWindow: (unsigned long)xWindow;
- (BOOL) windowExists: (unsigned long)xWindow;
- (BOOL) activateApplicationWithProcessIdentifiers: (NSArray *)processIdentifiers;
- (void) closeWindow: (unsigned long)xWindow;

@end
