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

#import "DockItem.h"
#import <GNUstepBase/GNUstep.h>

@interface DockTileIconView : NSView
{
  NSImage *_icon;
  NSString *_title;
}
- (void) setIcon: (NSImage *)icon;
- (void) setTitle: (NSString *)title;
@end

@implementation DockTileIconView

- (void) dealloc
{
  DESTROY(_icon);
  DESTROY(_title);
  DEALLOC;
}

- (void) setIcon: (NSImage *)icon
{
  if (_icon != icon)
    {
      ASSIGN(_icon, icon);
      [self setNeedsDisplay:YES];
    }
}

- (void) setTitle: (NSString *)title
{
  if (_title != title)
    {
      ASSIGNCOPY(_title, title);
      [self setNeedsDisplay:YES];
    }
}

- (BOOL) drawImage: (NSImage *)image inRect: (NSRect)rect
{
  NSSize imageSize;
  NSImageRep *rep;
  NSRect sourceRect;

  if (!image || (![[image representations] count] && ![image isValid]))
    {
      return NO;
    }

  imageSize = [image size];
  if (imageSize.width <= 0.0 || imageSize.height <= 0.0)
    {
      rep = [[image representations] count] ? [[image representations] objectAtIndex:0] : nil;
      if (rep)
	{
	  imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
	  [image setSize:imageSize];
	}
    }

  if (imageSize.width <= 0.0 || imageSize.height <= 0.0)
    {
      return NO;
    }

  sourceRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);
  [image drawInRect:rect
           fromRect:sourceRect
          operation:NSCompositeSourceOver
           fraction:1.0];
  return YES;
}

- (void) drawFallbackInRect: (NSRect)rect
{
  NSString *title = [_title length] ? _title : @"?";
  NSString *label = [[title substringToIndex:MIN((NSUInteger)2, [title length])] uppercaseString];
  NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
				      [NSFont boldSystemFontOfSize:18], NSFontAttributeName,
				 [NSColor colorWithCalibratedWhite:0.95 alpha:1.0], NSForegroundColorAttributeName,
				      nil];
  NSSize size = [label sizeWithAttributes:attrs];

  [label drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0,
                                 NSMidY(rect) - size.height / 2.0)
      withAttributes:attrs];
}

- (void) drawRect: (NSRect)rect
{
  NSRect bounds = [self bounds];
  CGFloat size = MIN(NSWidth(bounds), NSHeight(bounds));
  NSRect iconRect = NSMakeRect(NSMidX(bounds) - size / 2.0,
                               NSMidY(bounds) - size / 2.0,
                               size,
                               size);

  if (![self drawImage:_icon inRect:iconRect])
    {
      [self drawFallbackInRect:bounds];
    }

}

@end

@implementation DockItem















- (void) dealloc
{
  DESTROY(_title);
  DESTROY(_path);
  DESTROY(_iconPath);
  DESTROY(_launchArguments);
  DESTROY(_badgeLabel);
  DESTROY(_icon);
  DESTROY(_originalIcon);
  DESTROY(_dockTile);
  DEALLOC;
}

- (DockItemKind) kind
{
  return _kind;
}

- (DockItemState) state
{
  return _state;
}

- (void) setState: (DockItemState)state
{
  _state = state;
}

- (NSString *) title
{
  return _title;
}

- (NSString *) path
{
  return _path;
}

- (void) setPath: (NSString *)path
{
  if (_path != path &&
      !(_path && path && [_path isEqualToString:path]))
    {
      ASSIGNCOPY(_path, path);
    }
}

- (NSString *) launchArguments
{
  return _launchArguments;
}

- (void) setLaunchArguments: (NSString *)arguments
{
  if (_launchArguments != arguments &&
      !(_launchArguments && arguments &&
	[_launchArguments isEqualToString:arguments]))
    {
      ASSIGNCOPY(_launchArguments, arguments);
    }
}

- (NSString *) iconPath
{
  return _iconPath;
}

- (NSImage *) icon
{
  return _icon;
}

- (NSString *) badgeLabel
{
  return _badgeLabel;
}

- (void) setBadgeLabel: (NSString *)label
{
  if (_badgeLabel != label &&
      !(_badgeLabel && label && [_badgeLabel isEqualToString:label]))
    {
      ASSIGNCOPY(_badgeLabel, label);
    }
}

- (BOOL) iconMatchesImage: (NSImage *)image
{
  return _icon == image;
}

- (void) setIcon: (NSImage *)icon
{
  if (![self iconMatchesImage:icon])
    {
      ASSIGN(_icon, icon);
      if ([[_dockTile contentView] respondsToSelector:@selector(setIcon:)])
	{
	  [(DockTileIconView *)[_dockTile contentView] setIcon:icon];
	}
    }
}

- (void) setIconPath: (NSString *)path
{
  if (_iconPath != path &&
      !(_iconPath && path && [_iconPath isEqualToString:path]))
    {
      ASSIGNCOPY(_iconPath, path);
    }
}

- (void) setOriginalIcon: (NSImage *)icon
{
  if (_originalIcon != icon)
    {
      ASSIGN(_originalIcon, icon);
    }
}

- (void) restoreOriginalIcon
{
  if (_originalIcon)
    {
      [self setIcon:_originalIcon];
    }
}

- (NSDockTile *) dockTile
{
  return _dockTile;
}

- (unsigned long) xWindow
{
  return _xWindow;
}

- (void) setXWindow: (unsigned long)xWindow
{
  _xWindow = xWindow;
}

- (BOOL) isPinned
{
  return _pinned;
}

- (void) setPinned: (BOOL)pinned
{
  _pinned = pinned;
}

- (BOOL) usesDockBehaviorDefaults
{
  return _usesDockBehaviorDefaults;
}

- (void) setUsesDockBehaviorDefaults: (BOOL)usesDefaults
{
  _usesDockBehaviorDefaults = usesDefaults;
}

- (BOOL) wigglesOnLaunch
{
  return _wigglesOnLaunch;
}

- (void) setWigglesOnLaunch: (BOOL)wiggles
{
  _wigglesOnLaunch = wiggles;
}

- (BOOL) wigglesOnActivation
{
  return _wigglesOnActivation;
}

- (void) setWigglesOnActivation: (BOOL)wiggles
{
  _wigglesOnActivation = wiggles;
}

- (BOOL) wigglesOnAttentionRequest
{
  return _wigglesOnAttentionRequest;
}

- (void) setWigglesOnAttentionRequest: (BOOL)wiggles
{
  _wigglesOnAttentionRequest = wiggles;
}

@end
