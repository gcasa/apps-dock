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

#import "X11DockManagerPrivate.h"

@implementation X11DockManager (IconManager)

- (NSRect) setWindow: (unsigned int)aWindowNumber
        appProcessId: (int)aProcessId
{
  if (aWindowNumber == 0 || aProcessId <= 0)
    {
      return NSZeroRect;
    }
  if (![self windowHasGNUstepIconStyle:(Window)aWindowNumber] ||
      ![self windowIsIconSized:(Window)aWindowNumber])
    {
      return NSZeroRect;
    }

  if ([self rememberApplicationIconWindow:(Window)aWindowNumber
                        processIdentifier:aProcessId
                                    title:nil])
    {
      return [self hiddenIconWindowFrame];
    }

  return NSZeroRect;
}


- (void) setApplicationIconData: (NSData *)data
                      badgeText: (NSString *)badgeText
                   appProcessId: (int)aProcessId
{
  NSImage *icon = nil;

  if (aProcessId <= 0)
    {
      return;
    }

  if ([data length])
    {
      icon = AUTORELEASE([[NSImage alloc] initWithData:data]);
    }

  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidUpdateApplicationIcon:badgeLabel:processIdentifier:)])
    {
      [_delegate x11DockManagerDidUpdateApplicationIcon:icon
					     badgeLabel:badgeText
				      processIdentifier:aProcessId];
    }
}


- (void) requestUserAttention: (NSInteger)requestType
		 appProcessId: (int)aProcessId
{
  if (aProcessId <= 0)
    {
      return;
    }

  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidRequestUserAttentionForProcessIdentifier:requestType:)])
    {
      [_delegate x11DockManagerDidRequestUserAttentionForProcessIdentifier:aProcessId
							 requestType:requestType];
    }
}


- (void) cancelUserAttentionRequest: (NSInteger)request
			appProcessId: (int)aProcessId
{
  if (aProcessId <= 0)
    {
      return;
    }

  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidCancelUserAttentionRequest:forProcessIdentifier:)])
    {
      [_delegate x11DockManagerDidCancelUserAttentionRequest:request
					forProcessIdentifier:aProcessId];
    }
}


- (void) removeWindow: (unsigned int)aWindowNumber
{
  NSArray *processKeys = [_iconWindowsByProcessID allKeys];
  NSNumber *windowKey =
    [NSNumber numberWithUnsignedLong:(unsigned long)aWindowNumber];
  NSUInteger i;

  for (i = 0; i < [processKeys count]; i++)
    {
      NSNumber *processKey = [processKeys objectAtIndex:i];

      if ([[_iconWindowsByProcessID objectForKey:processKey]
	    isEqual:windowKey])
	{
	  [_iconWindowsByProcessID removeObjectForKey:processKey];
	  [_iconImageDataByProcessID removeObjectForKey:processKey];
	  break;
	}
    }
}


- (NSSize) getSizeWindow
{
  return NSMakeSize(64, 64);
}


@end
