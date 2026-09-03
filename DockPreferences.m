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

#import "DockPreferences.h"

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockCompactGap = 1.0;
static CGFloat DockPad = 10.0;
static CGFloat DockCompactPad = 0.0;
static NSString *DockBackgroundColorDefaultsKey = @"DockBackgroundColor";
static NSString *DockWindowAlphaDefaultsKey = @"DockWindowAlpha";
static NSString *DockShowBorderDefaultsKey = @"DockShowBorder";
static NSString *DockCellSizeModeDefaultsKey = @"DockCellSizeMode";
static NSString *DockUseCellTileBackgroundDefaultsKey = @"DockUseCellTileBackground";
static NSString *DockRunningIndicatorModeDefaultsKey = @"DockRunningIndicatorMode";
static NSString *DockMagnifiesHoveredIconsDefaultsKey = @"DockMagnifiesHoveredIcons";
static NSString *DockHoverIconScaleDefaultsKey = @"DockHoverIconScale";
static NSString *DockWigglesOnLaunchDefaultsKey = @"DockWigglesOnLaunch";
static NSString *DockWigglesOnActivationDefaultsKey = @"DockWigglesOnActivation";

@implementation DockPreferences

+ (CGFloat) dockCellSize
{
  return DockCell;
}

+ (CGFloat) padForCellSizeMode: (NSInteger)mode
{
  return mode == DockCellSizeMode64 ? DockCompactPad : DockPad;
}

+ (CGFloat) gapForCellSizeMode: (NSInteger)mode
{
  return mode == DockCellSizeMode64 ? DockCompactGap : DockGap;
}

+ (CGFloat) windowWidthForCellSizeMode: (NSInteger)mode
{
  return DockCell + [self padForCellSizeMode:mode] * 2.0;
}

+ (NSString *) largerCellSizeTitle
{
  CGFloat tileSize = DockCell + DockPad * 2.0;

  return [NSString stringWithFormat:@"%.0f x %.0f", tileSize, tileSize];
}

+ (BOOL) placementIsHorizontal: (DockPlacement)placement
{
  return placement == DockPlacementTopCenter || placement == DockPlacementBottomCenter;
}

+ (NSColor *) calibratedBackgroundColor: (NSColor *)color
{
  NSColor *rgbColor = nil;
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  if (!color)
    {
      return [NSColor blackColor];
    }

  NS_DURING
    rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (!rgbColor)
    {
      rgbColor = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
  if (rgbColor)
    {
      [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
    }
  NS_HANDLER
    rgbColor = nil;
  NS_ENDHANDLER

    if (!rgbColor)
      {
	return [NSColor blackColor];
      }

  return [NSColor colorWithCalibratedRed:red
                                   green:green
                                    blue:blue
                                   alpha:alpha];
}

- (DockPlacement) savedDockPlacement
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedPlacement = [defaults objectForKey:@"DockPlacement"];

  if (savedPlacement)
    {
      NSInteger placement = [defaults integerForKey:@"DockPlacement"];
      if (placement >= DockPlacementLeftTop && placement <= DockPlacementBottomCenter)
	{
	  return (DockPlacement)placement;
	}
    }

  if ([defaults boolForKey:@"DockOnRight"])
    {
      return [defaults boolForKey:@"DockCentered"] ? DockPlacementRightCenter : DockPlacementRightTop;
    }

  return [defaults boolForKey:@"DockCentered"] ? DockPlacementLeftCenter : DockPlacementLeftTop;
}

- (NSColor *) savedBackgroundColor
{
  id savedColor = [[NSUserDefaults standardUserDefaults]
		    objectForKey:DockBackgroundColorDefaultsKey];
  NSColor *color = nil;

  if ([savedColor isKindOfClass:[NSDictionary class]])
    {
      NSNumber *red = [savedColor objectForKey:@"Red"];
      NSNumber *green = [savedColor objectForKey:@"Green"];
      NSNumber *blue = [savedColor objectForKey:@"Blue"];
      NSNumber *alpha = [savedColor objectForKey:@"Alpha"];

      if (red && green && blue)
        {
          color = [NSColor colorWithCalibratedRed:[red doubleValue]
                                            green:[green doubleValue]
                                             blue:[blue doubleValue]
                                            alpha:alpha ? [alpha doubleValue] : 1.0];
        }
    }
  else if ([savedColor isKindOfClass:[NSData class]])
    {
      NS_DURING
        color = [NSUnarchiver unarchiveObjectWithData:savedColor];
      NS_HANDLER
        color = nil;
      NS_ENDHANDLER
	}

  return [DockPreferences calibratedBackgroundColor:color];
}

- (void) saveBackgroundColor: (NSColor *)backgroundColor
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSColor *color = [DockPreferences calibratedBackgroundColor:backgroundColor];
  NSMutableDictionary *components = [NSMutableDictionary dictionary];
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 1.0;

  [color getRed:&red green:&green blue:&blue alpha:&alpha];
  [components setObject:[NSNumber numberWithDouble:red] forKey:@"Red"];
  [components setObject:[NSNumber numberWithDouble:green] forKey:@"Green"];
  [components setObject:[NSNumber numberWithDouble:blue] forKey:@"Blue"];
  [components setObject:[NSNumber numberWithDouble:alpha] forKey:@"Alpha"];
  [defaults setObject:components forKey:DockBackgroundColorDefaultsKey];
}

- (CGFloat) savedWindowAlpha
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedAlpha = [defaults objectForKey:DockWindowAlphaDefaultsKey];
  CGFloat alpha;

  if (!savedAlpha)
    {
      return 1.0;
    }

  alpha = [defaults floatForKey:DockWindowAlphaDefaultsKey];
  if (alpha < 0.2)
    {
      alpha = 0.2;
    }
  else if (alpha > 1.0)
    {
      alpha = 1.0;
    }

  return alpha;
}

- (void) saveWindowAlpha: (CGFloat)alpha
{
  [[NSUserDefaults standardUserDefaults] setFloat:alpha
					   forKey:DockWindowAlphaDefaultsKey];
}

- (BOOL) savedShowDockBorder
{
  return [[NSUserDefaults standardUserDefaults]
	   boolForKey:DockShowBorderDefaultsKey];
}

- (void) saveShowDockBorder: (BOOL)showDockBorder
{
  [[NSUserDefaults standardUserDefaults] setBool:showDockBorder
					  forKey:DockShowBorderDefaultsKey];
}

- (NSInteger) savedDockCellSizeMode
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedMode = [defaults objectForKey:DockCellSizeModeDefaultsKey];

  if (savedMode)
    {
      NSInteger mode = [defaults integerForKey:DockCellSizeModeDefaultsKey];
      if (mode == DockCellSizeModeCurrent || mode == DockCellSizeMode64)
	{
	  return mode;
	}
    }

  return DockCellSizeMode64;
}

- (void) saveDockCellSizeMode: (NSInteger)mode
{
  [[NSUserDefaults standardUserDefaults] setInteger:mode
					     forKey:DockCellSizeModeDefaultsKey];
}

- (DockRunningIndicatorMode) savedRunningIndicatorMode
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedMode = [defaults objectForKey:DockRunningIndicatorModeDefaultsKey];

  if (savedMode)
    {
      NSInteger mode = [defaults integerForKey:DockRunningIndicatorModeDefaultsKey];
      if (mode == DockRunningIndicatorModeNotRunningDots)
	{
	  return DockRunningIndicatorModeNotRunningDots;
	}
    }

  return DockRunningIndicatorModeRunningDot;
}

- (void) saveRunningIndicatorMode: (DockRunningIndicatorMode)mode
{
  [[NSUserDefaults standardUserDefaults] setInteger:mode
					     forKey:DockRunningIndicatorModeDefaultsKey];
}

- (BOOL) savedUseCellTileBackground
{
  return [[NSUserDefaults standardUserDefaults]
	   boolForKey:DockUseCellTileBackgroundDefaultsKey];
}

- (void) saveUseCellTileBackground: (BOOL)useCellTileBackground
{
  [[NSUserDefaults standardUserDefaults] setBool:useCellTileBackground
					  forKey:DockUseCellTileBackgroundDefaultsKey];
}

- (BOOL) savedMagnifiesHoveredIcons
{
  return [[NSUserDefaults standardUserDefaults]
	   boolForKey:DockMagnifiesHoveredIconsDefaultsKey];
}

- (void) saveMagnifiesHoveredIcons: (BOOL)magnifiesHoveredIcons
{
  [[NSUserDefaults standardUserDefaults] setBool:magnifiesHoveredIcons
					  forKey:DockMagnifiesHoveredIconsDefaultsKey];
}

- (CGFloat) savedHoverIconScale
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedScale = [defaults objectForKey:DockHoverIconScaleDefaultsKey];
  CGFloat scale;

  if (!savedScale)
    {
      return 1.2;
    }

  scale = [defaults floatForKey:DockHoverIconScaleDefaultsKey];
  if (scale < 1.0)
    {
      scale = 1.0;
    }
  else if (scale > 1.5)
    {
      scale = 1.5;
    }

  return scale;
}

- (void) saveHoverIconScale: (CGFloat)scale
{
  if (scale < 1.0)
    {
      scale = 1.0;
    }
  else if (scale > 1.5)
    {
      scale = 1.5;
    }

  [[NSUserDefaults standardUserDefaults] setFloat:scale
					   forKey:DockHoverIconScaleDefaultsKey];
}

- (BOOL) savedWigglesOnLaunch
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  if (![defaults objectForKey:DockWigglesOnLaunchDefaultsKey])
    {
      return YES;
    }

  return [defaults boolForKey:DockWigglesOnLaunchDefaultsKey];
}

- (void) saveWigglesOnLaunch: (BOOL)wiggles
{
  [[NSUserDefaults standardUserDefaults] setBool:wiggles
					  forKey:DockWigglesOnLaunchDefaultsKey];
}

- (BOOL) savedWigglesOnActivation
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  if (![defaults objectForKey:DockWigglesOnActivationDefaultsKey])
    {
      return YES;
    }

  return [defaults boolForKey:DockWigglesOnActivationDefaultsKey];
}

- (void) saveWigglesOnActivation: (BOOL)wiggles
{
  [[NSUserDefaults standardUserDefaults] setBool:wiggles
					  forKey:DockWigglesOnActivationDefaultsKey];
}

@end
