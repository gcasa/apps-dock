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

#import "DockItemPrivate.h"

@implementation DockItem (Icons)

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
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  NSString *resources = [bundle resourcePath];
  NSArray *basePaths;
  NSArray *extensions;
  NSUInteger i, j;

  if (![name length])
    {
      return nil;
    }

  if ([resources length])
    {
      basePaths = [NSArray arrayWithObjects:
			     [resources stringByAppendingPathComponent:name],
			   [path stringByAppendingPathComponent:name],
			   name,
			   nil];
    }
  else
    {
      basePaths = [NSArray arrayWithObjects:
			     [path stringByAppendingPathComponent:name],
			   name,
			   nil];
    }
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

  while ([candidate length])
    {
      NSString *parent;

      if ([[[candidate pathExtension] lowercaseString] isEqualToString:@"app"] &&
	  [[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDir] &&
	  isDir)
	{
	  return candidate;
	}
      parent = [candidate stringByDeletingLastPathComponent];
      if (![parent length] || [parent isEqualToString:candidate])
	{
	  break;
	}
      candidate = parent;
    }

  return nil;
}


+ (NSImage *) iconForApplicationPath: (NSString *)path
{
  NSDictionary *info = [[NSBundle bundleWithPath:path] infoDictionary];
  NSArray *iconKeys = [NSArray arrayWithObjects:
				 @"NSIcon", @"ApplicationIcon", @"CFBundleIconFile", nil];
  NSUInteger j;

  if (info)
    {
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
      [directories addObject:[[[libraryDirectories objectAtIndex:i]
				  stringByAppendingPathComponent:@"WindowMaker"]
				  stringByAppendingPathComponent:@"Icons"]];
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


@end
