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

#import <AppKit/AppKit.h>
#import "DockView.h"
#import "X11DockManager.h"

enum
{
  DockCellSizeModeCurrent = 0,
  DockCellSizeMode64 = 1
};

@interface DockPreferences : NSObject

+ (CGFloat) dockCellSize;
+ (CGFloat) padForCellSizeMode: (NSInteger)mode;
+ (CGFloat) gapForCellSizeMode: (NSInteger)mode;
+ (CGFloat) windowWidthForCellSizeMode: (NSInteger)mode;
+ (NSString *) largerCellSizeTitle;
+ (BOOL) placementIsHorizontal: (DockPlacement)placement;
+ (NSColor *) calibratedBackgroundColor: (NSColor *)color;

- (DockPlacement) savedDockPlacement;
- (NSColor *) savedBackgroundColor;
- (void) saveBackgroundColor: (NSColor *)color;
- (CGFloat) savedWindowAlpha;
- (void) saveWindowAlpha: (CGFloat)alpha;
- (BOOL) savedShowDockBorder;
- (void) saveShowDockBorder: (BOOL)showDockBorder;
- (NSInteger) savedDockCellSizeMode;
- (void) saveDockCellSizeMode: (NSInteger)mode;
- (DockRunningIndicatorMode) savedRunningIndicatorMode;
- (void) saveRunningIndicatorMode: (DockRunningIndicatorMode)mode;
- (BOOL) savedUseCellTileBackground;
- (void) saveUseCellTileBackground: (BOOL)useCellTileBackground;
- (BOOL) savedMagnifiesHoveredIcons;
- (void) saveMagnifiesHoveredIcons: (BOOL)magnifiesHoveredIcons;
- (CGFloat) savedHoverIconScale;
- (void) saveHoverIconScale: (CGFloat)scale;

@end
