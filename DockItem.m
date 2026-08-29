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
  NSString *_badgeLabel;
}
- (void) setIcon: (NSImage *)icon;
- (void) setTitle: (NSString *)title;
- (void) setBadgeLabel: (NSString *)label;
@end

@implementation DockTileIconView

- (void) dealloc
{
  DESTROY(_icon);
  DESTROY(_title);
  DESTROY(_badgeLabel);
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

- (void) setBadgeLabel: (NSString *)label
{
  if (_badgeLabel != label &&
      !(_badgeLabel && label && [_badgeLabel isEqualToString:label]))
    {
      ASSIGNCOPY(_badgeLabel, label);
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

  if ([_badgeLabel length])
    {
      NSString *displayString = _badgeLabel;
      NSDictionary *attrs;
      NSSize textSize;
      NSSize badgeSize;
      NSRect badgeRect;
      CGFloat pad = MAX(4.0, size / 10.0);
      CGFloat minSide = MAX(14.0, size / 3.2);

      if ([displayString length] > 5)
	{
	  displayString = [NSString stringWithFormat:@"%@...%@",
				    [displayString substringToIndex:2],
				    [displayString substringFromIndex:
						    [displayString length] - 2]];
	}

      attrs = [NSDictionary dictionaryWithObjectsAndKeys:
			    [NSFont boldSystemFontOfSize:MAX(9.0, size / 5.0)],
			    NSFontAttributeName,
			    [NSColor whiteColor],
			    NSForegroundColorAttributeName,
			    nil];
      textSize = [displayString sizeWithAttributes:attrs];
      badgeSize = NSMakeSize(MAX(minSide, textSize.width + pad),
			     MAX(minSide, textSize.height + pad / 2.0));
      badgeRect = NSMakeRect(NSMaxX(iconRect) - badgeSize.width,
			     NSMaxY(iconRect) - badgeSize.height,
			     badgeSize.width,
			     badgeSize.height);

      [[NSColor colorWithCalibratedRed:0.82 green:0.05 blue:0.09 alpha:1.0] set];
      [[NSBezierPath bezierPathWithOvalInRect:badgeRect] fill];
      [displayString drawAtPoint:
		       NSMakePoint(NSMidX(badgeRect) - textSize.width / 2.0,
				   NSMidY(badgeRect) - textSize.height / 2.0)
			 withAttributes:attrs];
    }
}

@end

@implementation DockItem

+ (BOOL) imageIsDrawable: (NSImage *)image
{
  return image && ([[image representations] count] > 0 ||
                   [image isValid]);
}

+ (NSImage *) imageAtPath: (NSString *)path
{
  NSImage *image;

  if (![path length])
    {
      return nil;
    }

  image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile:path]);
  return [self imageIsDrawable:image] ? image : nil;
}

+ (NSImage *) imageNamed: (NSString *)name inApplicationPath: (NSString *)path
{
  NSString *resources = [path stringByAppendingPathComponent:@"Resources"];
  NSArray *basePaths;
  NSArray *extensions;
  NSUInteger i, j;

  if (![name length])
    {
      return nil;
    }

  basePaths = [NSArray arrayWithObjects:
			 [resources stringByAppendingPathComponent:name],
		       [path stringByAppendingPathComponent:name],
		       name,
		       nil];
  extensions = [NSArray arrayWithObjects:@"", @"tiff", @"tif", @"png", @"xpm", @"icns", nil];

  for (i = 0; i < [basePaths count]; i++)
    {
      NSString *base = [basePaths objectAtIndex:i];
      for (j = 0; j < [extensions count]; j++)
	{
	  NSString *extension = [extensions objectAtIndex:j];
	  NSString *candidate = [extension length] ? [base stringByAppendingPathExtension:extension] : base;
	  NSImage *image = [self imageAtPath:candidate];
	  if (image)
	    {
	      return image;
	    }
	}
    }

  return nil;
}

+ (NSString *) applicationBundlePathForPath: (NSString *)path
{
  NSString *candidate = path;
  BOOL isDir = NO;

  while ([candidate length] && ![candidate isEqualToString:@"/"])
    {
      if ([[[candidate pathExtension] lowercaseString] isEqualToString:@"app"] &&
	  [[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDir] &&
	  isDir)
	{
	  return candidate;
	}
      candidate = [candidate stringByDeletingLastPathComponent];
    }

  return nil;
}

+ (NSImage *) iconForApplicationPath: (NSString *)path
{
  NSArray *infoPaths = [NSArray arrayWithObjects:
				  [[path stringByAppendingPathComponent:@"Resources"] stringByAppendingPathComponent:@"Info-gnustep.plist"],
				[path stringByAppendingPathComponent:@"Info-gnustep.plist"],
				[path stringByAppendingPathComponent:@"Info.plist"],
				nil];
  NSArray *iconKeys = [NSArray arrayWithObjects:
				 @"NSIcon", @"ApplicationIcon", @"CFBundleIconFile", nil];
  NSUInteger i, j;

  for (i = 0; i < [infoPaths count]; i++)
    {
      NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[infoPaths objectAtIndex:i]];
      if (!info)
	{
	  continue;
	}

      for (j = 0; j < [iconKeys count]; j++)
	{
	  id iconName = [info objectForKey:[iconKeys objectAtIndex:j]];
	  NSImage *image;

	  if (![iconName isKindOfClass:[NSString class]])
	    {
	      continue;
	    }

	  image = [self imageNamed:iconName inApplicationPath:path];
	  if (image)
	    {
	      return image;
	    }
	}
    }

  return [self imageNamed:[[path lastPathComponent] stringByDeletingPathExtension]
	       inApplicationPath:path];
}

+ (NSString *) desktopFileValueForKey: (NSString *)key
				lines: (NSArray *)lines
{
  NSString *prefix = [key stringByAppendingString:@"="];
  NSUInteger i;

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [lines objectAtIndex:i];

      if ([line hasPrefix:prefix])
	{
	  return [line substringFromIndex:[prefix length]];
	}
    }

  return nil;
}

+ (NSString *) firstCommandTokenFromString: (NSString *)string
{
  NSMutableString *token = [NSMutableString string];
  NSUInteger i;
  BOOL quoted = NO;
  unichar quote = 0;

  for (i = 0; i < [string length]; i++)
    {
      unichar ch = [string characterAtIndex:i];

      if (quoted)
	{
	  if (ch == quote)
	    {
	      quoted = NO;
	    }
	  else
	    {
	      [token appendFormat:@"%C", ch];
	    }
	}
      else if (ch == '"' || ch == '\'')
	{
	  quoted = YES;
	  quote = ch;
	}
      else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
		     characterIsMember:ch])
	{
	  if ([token length])
	    {
	      break;
	    }
	}
      else
	{
	  [token appendFormat:@"%C", ch];
	}
    }

  return [token length] ? token : nil;
}

+ (NSString *) pathForExecutableCommand: (NSString *)command
{
  NSString *pathEnvironment;
  NSArray *pathComponents;
  NSUInteger i;

  if (![command length])
    {
      return nil;
    }

  if ([command isAbsolutePath])
    {
      return command;
    }

  pathEnvironment = [[[NSProcessInfo processInfo] environment]
		      objectForKey:@"PATH"];
  pathComponents = [pathEnvironment length]
    ? [pathEnvironment componentsSeparatedByString:@":"]
    : [NSArray array];

  for (i = 0; i < [pathComponents count]; i++)
    {
      NSString *candidate = [[pathComponents objectAtIndex:i]
				 stringByAppendingPathComponent:command];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate])
	{
	  return [candidate stringByResolvingSymlinksInPath];
	}
    }

  return nil;
}

+ (NSImage *) iconForApplicationNamed: (NSString *)name
                        inDirectories: (NSArray *)directories
{
  NSString *baseName;
  NSUInteger i;

  if (![name length])
    {
      return nil;
    }

  baseName = [[[name lastPathComponent] pathExtension] length]
    ? [[name lastPathComponent] stringByDeletingPathExtension]
    : [name lastPathComponent];

  for (i = 0; i < [directories count]; i++)
    {
      NSString *directory = [directories objectAtIndex:i];
      NSArray *candidates = [NSArray arrayWithObjects:
				       [directory stringByAppendingPathComponent:
						    [baseName stringByAppendingPathExtension:@"app"]],
				     [directory stringByAppendingPathComponent:[name lastPathComponent]],
				     nil];
      NSUInteger j;

      for (j = 0; j < [candidates count]; j++)
	{
	  NSString *candidate = [candidates objectAtIndex:j];
	  BOOL isDir = NO;

	  if ([[NSFileManager defaultManager] fileExistsAtPath:candidate
						   isDirectory:&isDir] &&
	      isDir &&
	      [[[candidate pathExtension] lowercaseString] isEqualToString:@"app"])
	    {
	      NSImage *image = [self iconForApplicationPath:candidate];
	      if (image)
		{
		  return image;
		}
	    }
	}
    }

  return nil;
}

+ (NSArray *) desktopIconSearchDirectoriesForDesktopFile: (NSString *)path
{
  NSMutableArray *directories = [NSMutableArray array];
  NSArray *applicationDirectories;
  NSArray *libraryDirectories;
  NSUInteger i;

  if ([[path stringByDeletingLastPathComponent] length])
    {
      [directories addObject:
		     [[path stringByDeletingLastPathComponent]
			  stringByAppendingPathComponent:@"Resources"]];
      [directories addObject:[path stringByDeletingLastPathComponent]];
    }

  applicationDirectories =
    NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
                                        NSAllDomainsMask,
                                        YES);
  [directories addObjectsFromArray:applicationDirectories];

  libraryDirectories =
    NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                        NSAllDomainsMask,
                                        YES);
  for (i = 0; i < [libraryDirectories count]; i++)
    {
      [directories addObject:[[libraryDirectories objectAtIndex:i]
				  stringByAppendingPathComponent:@"WindowMaker/Icons"]];
    }

  return directories;
}

+ (NSImage *) iconForDesktopFile: (NSString *)path
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
			       [NSCharacterSet newlineCharacterSet]];
  NSArray *searchPaths = [self desktopIconSearchDirectoriesForDesktopFile:path];
  NSString *bundlePath = [self applicationBundlePathForPath:path];
  NSString *exec = [self desktopFileValueForKey:@"Exec" lines:lines];
  NSString *execPath = [self pathForExecutableCommand:
			       [self firstCommandTokenFromString:
				       [[exec componentsSeparatedByString:@"%"] objectAtIndex:0]]];
  NSString *iconName = [self desktopFileValueForKey:@"Icon" lines:lines];
  NSImage *image;
  NSUInteger i;

  if ([bundlePath length])
    {
      image = [self iconForApplicationPath:bundlePath];
      if (image)
	{
	  return image;
	}
    }

  bundlePath = [self applicationBundlePathForPath:execPath];
  if ([bundlePath length])
    {
      image = [self iconForApplicationPath:bundlePath];
      if (image)
	{
	  return image;
	}
    }

  if ([iconName isAbsolutePath])
    {
      image = [self imageAtPath:iconName];
      if (image)
	{
	  return image;
	}
    }

  image = [self iconForApplicationNamed:iconName
                          inDirectories:
		  NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
						      NSAllDomainsMask,
						      YES)];
  if (image)
    {
      return image;
    }

  for (i = 0; i < [searchPaths count]; i++)
    {
      image = [self imageNamed:iconName inApplicationPath:[searchPaths objectAtIndex:i]];
      if (image)
	{
	  return image;
	}
    }

  return nil;
}

+ (NSImage *) fallbackApplicationIcon
{
  return [self imageIsDrawable:[NSImage imageNamed:@"NSApplicationIcon"]]
    ? [NSImage imageNamed:@"NSApplicationIcon"] : nil;
}

+ (id) applicationItemWithPath: (NSString *)path
{
  DockItem *item = AUTORELEASE([[self alloc] init]);
  NSImage *icon = nil;
  NSString *bundlePath = [self applicationBundlePathForPath:path];
  NSString *iconPath = bundlePath ? bundlePath : path;

  if (bundlePath)
    {
      icon = [self iconForApplicationPath:bundlePath];
    }
  if (!icon && [[[path pathExtension] lowercaseString] isEqualToString:@"desktop"])
    {
      icon = [self iconForDesktopFile:path];
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFileType:[path pathExtension]];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];
      if (![self imageIsDrawable:icon])
	{
	  icon = nil;
	}
    }
  if (!icon)
    {
      icon = [self fallbackApplicationIcon];
    }

  item->_kind = DockItemApplication;
  item->_state = DockItemNotRunning;
  item->_pinned = YES;
  ASSIGNCOPY(item->_path, path);
  ASSIGNCOPY(item->_iconPath, iconPath);
  ASSIGNCOPY(item->_title, [[path lastPathComponent] stringByDeletingPathExtension]);
  ASSIGN(item->_icon, icon);
  ASSIGN(item->_originalIcon, icon);
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = AUTORELEASE([[DockTileIconView alloc]
					       initWithFrame:NSMakeRect(0, 0, 46, 46)]);
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}

+ (id) x11ItemWithTitle: (NSString *)title window: (unsigned long)xWindow icon: (NSImage *)icon hidden: (BOOL)hidden
{
  DockItem *item = AUTORELEASE([[self alloc] init]);
  NSString *displayTitle;

  displayTitle = [title length] ? title : [NSString stringWithFormat:@"0x%lx", xWindow];
  item->_kind = DockItemX11Window;
  item->_state = hidden ? DockItemHidden : DockItemRunning;
  item->_xWindow = xWindow;
  item->_pinned = NO;
  ASSIGNCOPY(item->_title, displayTitle);
  ASSIGN(item->_icon, icon);
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = AUTORELEASE([[DockTileIconView alloc]
					       initWithFrame:NSMakeRect(0, 0, 46, 46)]);
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}

- (void) dealloc
{
  DESTROY(_title);
  DESTROY(_path);
  DESTROY(_iconPath);
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
      if ([[_dockTile contentView] respondsToSelector:@selector(setBadgeLabel:)])
	{
	  [(DockTileIconView *)[_dockTile contentView] setBadgeLabel:label];
	}
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

@end
