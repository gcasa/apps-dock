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

#import "X11DockManager.h"
#import "DockView.h"
#import <Foundation/NSConnection.h>
#import <GNUstepBase/GNUstep.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#import <X11/extensions/shape.h>
#import <limits.h>
#import <paths.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#define DockGSWindowStyleAttr (1UL << 0)
#define DockNSIconWindowMask 64UL
#define DockNSMiniWindowMask 128UL
#define DockSmallIconWindowMaximumSize 70
#define DockHiddenIconWindowOffset 256
#define X11DockManagerEventScanInterval 1.0

@interface X11DockManager (Private)
- (id) initWithDockView: (DockView *)view;
- (void) dealloc;
- (void) setDelegate: (id)delegate;
- (BOOL) start;
- (void) registerIconManager;
- (BOOL) x11ErrorOccurred;
- (void) clearX11Error;
- (void) makeWindowSticky: (unsigned long)xWindow;
- (NSString *) procFilesystemPath;
- (void) setDockPlacement: (DockPlacement)placement;
- (NSRect) x11FrameForDockPlacement: (DockPlacement)placement;
- (unsigned char) componentFromPixel: (unsigned long)pixel mask: (unsigned long)mask;
- (void) processPendingEvents;
- (void) drainTransientIconEvents;
- (NSString *) titleForWindow: (Window)window;
- (BOOL) wmStateForWindow: (Window)window state: (long *)state;
- (int) processIdentifierForWindow: (Window)window;
- (BOOL) windowIsHidden: (Window)window;
- (NSData *) imageDataFromDrawable: (Drawable)drawable
                              mask: (Pixmap)mask
                             width: (unsigned int)width
                            height: (unsigned int)height;
- (NSImage *) imageFromData: (NSData *)imageData
                      width: (unsigned int)width
                     height: (unsigned int)height;
- (NSImage *) imageFromDrawable: (Drawable)drawable
                           mask: (Pixmap)mask
                          width: (unsigned int)width
                         height: (unsigned int)height;
- (NSImage *) imageFromPixmap: (Pixmap)pixmap mask: (Pixmap)mask;
- (NSImage *) imageFromWindowContents: (Window)window;
- (NSImage *) iconForWindow: (Window)window;
- (NSString *) executablePathForWindow: (Window)window;
- (BOOL) windowIsRegisteredIconWindow: (Window)window;
- (id) iconIdentifierForProcessIdentifier: (int)processIdentifier
                                    title: (NSString *)title;
- (NSImage *) iconForIdentifier: (id)identifier;
- (BOOL) windowHasGNUstepStyleMask: (unsigned long)styleMask
                             window: (Window)window;
- (BOOL) windowHasGNUstepIconStyle: (Window)window;
- (BOOL) windowIsIconSized: (Window)window;
- (BOOL) windowIsSmallIconSized: (Window)window;
- (BOOL) windowHasGNUstepMiniWindowStyle: (Window)window;
- (BOOL) windowIsGNUstepMainMenu: (Window)window;
- (BOOL) windowIsSmallGNUstepIconOrMiniWindow: (Window)window;
- (BOOL) windowIsSmallRootOverrideRedirectWindow: (Window)window;
- (BOOL) windowIsSmallDockedOverrideRedirectWindow: (Window)window;
- (BOOL) windowHasTransientForHint: (Window)window;
- (BOOL) windowIsDockAppIconChild: (Window)window;
- (BOOL) windowLooksLikeWindowMakerDockApp: (Window)window;
- (void) unmapIconWindow: (Window)window;
- (void) hideApplicationIconWindow: (Window)window;
- (void) handlePossiblyNewWindow: (Window)window;
- (BOOL) windowLooksLikeDockApp: (Window)window;
- (BOOL) windowIsKnownDockAppWindow: (Window)window;
- (BOOL) windowLooksManageable: (Window)window;
- (BOOL) windowHasIgnoredWindowType: (Window)window;
- (NSArray *) clientListWindows;
- (BOOL) knownWindowStillExists: (Window)window;
- (BOOL) windowExists: (unsigned long)xWindow;
- (BOOL) windowShouldBeIgnoredWithTitle: (NSString *)title path: (NSString *)path;
- (void) scanKnownWindows;
- (NSString *) classNameForWindow: (Window)window;
- (BOOL) windowHasDockAppClass: (Window)window;
- (Window) dockAppIconWindowForWindow: (Window)window;
- (BOOL) rememberApplicationIconWindow: (Window)window
                     processIdentifier: (int)processIdentifier
                                 title: (NSString *)title;
- (void) discoverApplicationIconWindows: (Window *)children
                                  count: (unsigned int)count;
- (void) scanApplicationIconWindows;
- (void) scanClientWindow: (Window)window;
- (void) scanForDockApps;
- (NSRect) setWindow: (unsigned int)aWindowNumber
        appProcessId: (int)aProcessId;
- (void) setApplicationIconData: (NSData *)data
                      badgeText: (NSString *)badgeText
                   appProcessId: (int)aProcessId;
- (void) requestUserAttention: (NSInteger)requestType
		 appProcessId: (int)aProcessId;
- (void) cancelUserAttentionRequest: (NSInteger)request
			appProcessId: (int)aProcessId;
- (void) removeWindow: (unsigned int)aWindowNumber;
- (NSSize) getSizeWindow;
- (NSRect) hiddenIconWindowFrame;
- (void) updateHostWindowShape;
- (void) dockWindow: (unsigned long)xWindow atIndex: (NSUInteger)index;
- (void) moveDockedWindow: (unsigned long)xWindow toIndex: (NSUInteger)index;
- (void) activateWindow: (unsigned long)xWindow;
- (void) deiconifyWindow: (Window)window;
- (NSUInteger) activateIconicWindowsForProcessIdentifiers: (NSArray *)processIdentifiers
					      underWindow: (Window)parentWindow;
- (Window) activatableWindowForProcessIdentifiers: (NSArray *)processIdentifiers
                                      underWindow: (Window)parentWindow;
- (BOOL) activateApplicationWithProcessIdentifiers: (NSArray *)processIdentifiers;
- (Window) mainMenuWindowForProcessIdentifiers: (NSArray *)processIdentifiers
                                  underWindow: (Window)parentWindow;
- (void) closeWindow: (unsigned long)xWindow;
@end
