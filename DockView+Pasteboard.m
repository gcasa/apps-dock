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

#import "DockViewPrivate.h"

@implementation DockView (Pasteboard)

- (NSArray *) pathsFromPasteboard: (NSPasteboard *)pb
{
  NSArray *types = [pb types];
  NSArray *paths;
  NSMutableArray *collectedPaths = [NSMutableArray array];
  NSString *string;
  NSURL *url;
  NSUInteger i;

  if ([types containsObject:NSFilenamesPboardType])
    {
      paths = [pb propertyListForType:NSFilenamesPboardType];
      if ([paths count])
	{
	  return paths;
	}
    }

  if ([types containsObject:NSURLPboardType])
    {
      url = [NSURL URLFromPasteboard:pb];
      if ([url isFileURL] && [[url path] length])
	{
	  return [NSArray arrayWithObject:[url path]];
	}
    }

  if ([types containsObject:GWRemoteFilenamesPboardType])
    {
      NSData *data = [pb dataForType:GWRemoteFilenamesPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
				     toArray:collectedPaths];
	}
    }

  if ([types containsObject:GWLSFolderPboardType])
    {
      NSData *data = [pb dataForType:GWLSFolderPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
				     toArray:collectedPaths];
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"path"]
				     toArray:collectedPaths];
	}
    }

  if ([types containsObject:GWDockIconPboardType])
    {
      NSData *data = [pb dataForType:GWDockIconPboardType];
      id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
      if ([dict isKindOfClass:[NSDictionary class]])
	{
	  [self addPathsFromPasteboardObject:[dict objectForKey:@"path"]
				     toArray:collectedPaths];
	}
    }

  for (i = 0; i < [types count]; i++)
    {
      NSString *type = [types objectAtIndex:i];
      id plist = [pb propertyListForType:type];

      [self addPathsFromPasteboardObject:plist toArray:collectedPaths];

      string = [pb stringForType:type];
      if ([string length])
	{
	  [self addPathsFromPasteboardString:string toArray:collectedPaths];
	}
    }

  if ([collectedPaths count])
    {
      return collectedPaths;
    }

  return nil;
}


- (BOOL) pasteboardHasSupportedType: (NSPasteboard *)pb
{
  NSArray *supportedTypes = [NSArray arrayWithObjects:NSFilenamesPboardType,
				     NSURLPboardType,
				     NSStringPboardType,
				     @"text/uri-list",
				     @"text/plain",
				     GWRemoteFilenamesPboardType,
				     GWLSFolderPboardType,
				     GWDockIconPboardType,
				     nil];
  return [pb availableTypeFromArray:supportedTypes] != nil;
}


- (void) addPathsFromPasteboardObject: (id)object toArray: (NSMutableArray *)paths
{
  if ([object isKindOfClass:[NSString class]])
    {
      [self addPathsFromPasteboardString:object toArray:paths];
    }
  else if ([object isKindOfClass:[NSArray class]])
    {
      NSUInteger i;
      for (i = 0; i < [object count]; i++)
	{
	  [self addPathsFromPasteboardObject:[object objectAtIndex:i] toArray:paths];
	}
    }
  else if ([object isKindOfClass:[NSDictionary class]])
    {
      NSEnumerator *enumerator = [object objectEnumerator];
      id value;

      while ((value = [enumerator nextObject]))
	{
	  [self addPathsFromPasteboardObject:value toArray:paths];
	}
    }
}


- (void) addPathsFromPasteboardString: (NSString *)string toArray: (NSMutableArray *)paths
{
  NSArray *lines;
  NSUInteger i;

  if (![string length])
    {
      return;
    }

  lines = [string componentsSeparatedByCharactersInSet:
		    [NSCharacterSet newlineCharacterSet]];

  for (i = 0; i < [lines count]; i++)
    {
      NSString *line = [[lines objectAtIndex:i]
			    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSString *path = nil;

      if (![line length] || [line hasPrefix:@"#"])
	{
	  continue;
	}

      if ([line hasPrefix:@"\""] && [line hasSuffix:@"\""] && [line length] > 1)
	{
	  line = [line substringWithRange:NSMakeRange(1, [line length] - 2)];
	}

      if ([line hasPrefix:@"file:"])
	{
	  NSURL *fileURL = [NSURL URLWithString:line];
	  if ([fileURL isFileURL])
	    {
	      path = [fileURL path];
	    }
	}
      else if ([line isAbsolutePath])
	{
	  path = line;
	}

      if ([path length] && ![paths containsObject:path])
	{
	  [paths addObject:path];
	}
    }
}


- (NSDragOperation) dragOperationForSender: (id <NSDraggingInfo>)sender
{
  return NSDragOperationEvery;
}


- (BOOL) pasteboardHasReorderType: (NSPasteboard *)pb
{
  return [[pb types] containsObject:DockReorderPboardType];
}


@end
