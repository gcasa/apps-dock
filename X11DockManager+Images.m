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

@implementation X11DockManager (Images)

- (unsigned char) componentFromPixel: (unsigned long)pixel mask: (unsigned long)mask
{
  unsigned long value;
  unsigned int shift = 0;
  unsigned int bits = 0;

  if (!mask)
    {
      return 0;
    }

  while (((mask >> shift) & 1UL) == 0)
    {
      shift++;
    }

  value = (pixel & mask) >> shift;
  while (((mask >> (shift + bits)) & 1UL) != 0)
    {
      bits++;
    }

  if (bits >= 8)
    {
      return (unsigned char)(value >> (bits - 8));
    }

  return (unsigned char)((value * 255UL) / ((1UL << bits) - 1UL));
}


- (NSData *) imageDataFromDrawable: (Drawable)drawable
                              mask: (Pixmap)mask
                             width: (unsigned int)width
                            height: (unsigned int)height
{
  Display *display = (Display *)_display;
  XImage *ximage;
  XImage *maskImage = NULL;
  NSMutableData *imageData;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;
  NSInteger x;
  NSInteger y;
  BOOL sawVisiblePixel = NO;

  if (!display || !drawable || width == 0 || height == 0 ||
      width > 128 || height > 128)
    {
      return nil;
    }

  XSync(display, False);
  [self clearX11Error];
  ximage = XGetImage(display, drawable, 0, 0, width, height,
                     AllPlanes, ZPixmap);
  if (!ximage || [self x11ErrorOccurred])
    {
      if (ximage)
	{
	  XDestroyImage(ximage);
	}
      return nil;
    }

  if (mask)
    {
      [self clearX11Error];
      maskImage = XGetImage(display, mask, 0, 0, width, height,
			    AllPlanes, ZPixmap);
      if ([self x11ErrorOccurred])
	{
	  if (maskImage)
	    {
	      XDestroyImage(maskImage);
	    }
	  maskImage = NULL;
	}
    }

  bytesPerRow = (NSInteger)width * 4;
  imageData = [NSMutableData dataWithLength:bytesPerRow * (NSInteger)height];
  if (!imageData)
    {
      XDestroyImage(ximage);
      if (maskImage)
	{
	  XDestroyImage(maskImage);
	}
      return nil;
    }

  bitmapData = [imageData mutableBytes];
  for (y = 0; y < (NSInteger)height; y++)
    {
      for (x = 0; x < (NSInteger)width; x++)
	{
	  unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
	  unsigned char alpha = 255;
	  unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

	  if (maskImage && XGetPixel(maskImage, (int)x, (int)y) == 0)
	    {
	      alpha = 0;
	    }

	  dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
	  dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
	  dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
	  dst[3] = alpha;
	  if (alpha && (dst[0] || dst[1] || dst[2]))
	    {
	      sawVisiblePixel = YES;
	    }
	}
    }

  XDestroyImage(ximage);
  if (maskImage)
    {
      XDestroyImage(maskImage);
    }

  if (!sawVisiblePixel)
    {
      return nil;
    }

  return imageData;
}


- (NSImage *) imageFromData: (NSData *)imageData
                      width: (unsigned int)width
                     height: (unsigned int)height
{
  NSBitmapImageRep *rep;
  NSImage *image;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;

  if (![imageData length] || width == 0 || height == 0)
    {
      return nil;
    }

  bytesPerRow = (NSInteger)width * 4;
  if ([imageData length] < bytesPerRow * (NSInteger)height)
    {
      return nil;
    }

  rep = [[NSBitmapImageRep alloc]
	  initWithBitmapDataPlanes:NULL
			pixelsWide: (NSInteger)width
			pixelsHigh: (NSInteger)height
		     bitsPerSample:8
		   samplesPerPixel:4
			  hasAlpha:YES
			  isPlanar:NO
		    colorSpaceName:NSDeviceRGBColorSpace
		       bytesPerRow:bytesPerRow
		      bitsPerPixel:32];
  rep = AUTORELEASE(rep);
  if (!rep)
    {
      return nil;
    }

  bitmapData = [rep bitmapData];
  memcpy(bitmapData, [imageData bytes], bytesPerRow * (NSInteger)height);

  image = AUTORELEASE([[NSImage alloc]
			initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
}


- (NSImage *) imageFromDrawable: (Drawable)drawable
                           mask: (Pixmap)mask
                          width: (unsigned int)width
                         height: (unsigned int)height
{
  NSData *imageData = [self imageDataFromDrawable:drawable
					     mask:mask
					    width:width
					   height:height];

  return [self imageFromData:imageData width:width height:height];
}


- (NSImage *) imageFromPixmap: (Pixmap)pixmap mask: (Pixmap)mask
{
  Display *display = (Display *)_display;
  Window root;
  int x;
  int y;
  unsigned int width;
  unsigned int height;
  unsigned int borderWidth;
  unsigned int depth;

  if (!display || !pixmap)
    {
      return nil;
    }

  [self clearX11Error];
  if (!XGetGeometry(display, pixmap, &root, &x, &y,
                    &width, &height, &borderWidth, &depth) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }

  return [self imageFromDrawable:pixmap mask:mask width:width height:height];
}


- (NSImage *) imageFromWindowContents: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }
  if (attr.width <= 0 || attr.height <= 0 ||
      attr.width > 128 || attr.height > 128)
    {
      return nil;
    }

  return [self imageFromDrawable:window
                            mask:None
                           width:(unsigned int)attr.width
                          height:(unsigned int)attr.height];
}


- (NSImage *) iconForWindow: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_ICON", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  NSImage *netWmIcon = nil;
  NSImage *hintIcon = nil;
  NSImage *icon = nil;
  XWMHints *hints;
  NSImage *managedIcon;
  int pid;
  NSString *className;

  pid = [self processIdentifierForWindow:window];
  className = [self classNameForWindow:window];
  managedIcon = [self iconForIdentifier:
			[self iconIdentifierForProcessIdentifier:pid title:className]];
  if (managedIcon)
    {
      return managedIcon;
    }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints)
    {
      if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	{
	  hintIcon = [self imageFromWindowContents:hints->icon_window];
	}

      if (!hintIcon &&
	  (hints->flags & IconPixmapHint) &&
	  hints->icon_pixmap != None)
	{
	  Pixmap mask = None;

	  if ((hints->flags & IconMaskHint) && hints->icon_mask != None)
	    {
	      mask = hints->icon_mask;
	    }
	  hintIcon = [self imageFromPixmap:hints->icon_pixmap mask:mask];
	}

      XFree(hints);
    }
  else if (hints)
    {
      XFree(hints);
    }

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 65536, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if ([self x11ErrorOccurred])
	{
	  if (data) XFree(data);
	  return icon;
	}
      if (actualFormat == 32 && itemCount >= 3)
	{
	  unsigned long *values = (unsigned long *)data;
	  unsigned long offset = 0;
	  unsigned long bestOffset = 0;
	  unsigned long bestWidth = 0;
	  unsigned long bestHeight = 0;
	  unsigned long bestScore = ~0UL;

	  while (offset + 2 < itemCount)
	    {
	      unsigned long width = values[offset];
	      unsigned long height = values[offset + 1];
	      unsigned long pixelCount = width * height;
	      unsigned long score;

	      if (!width || !height || pixelCount > itemCount - offset - 2)
		{
		  break;
		}

	      score = labs((long)width - 48) + labs((long)height - 48);
	      if (score < bestScore)
		{
		  bestScore = score;
		  bestOffset = offset + 2;
		  bestWidth = width;
		  bestHeight = height;
		}

	      offset += 2 + pixelCount;
	    }

	  if (bestWidth && bestHeight)
	    {
	      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
					       initWithBitmapDataPlanes:NULL
							     pixelsWide: (NSInteger)bestWidth
							     pixelsHigh: (NSInteger)bestHeight
							  bitsPerSample:8
							samplesPerPixel:4
							       hasAlpha:YES
							       isPlanar:NO
							 colorSpaceName:NSCalibratedRGBColorSpace
							    bytesPerRow: (NSInteger)bestWidth * 4
							   bitsPerPixel:32];
	      rep = AUTORELEASE(rep);
	      unsigned char *bitmap = [rep bitmapData];
	      unsigned long i;

	      for (i = 0; i < bestWidth * bestHeight; i++)
		{
		  unsigned long argb = values[bestOffset + i];
		  bitmap[i * 4 + 0] = (argb >> 16) & 0xff;
		  bitmap[i * 4 + 1] = (argb >> 8) & 0xff;
		  bitmap[i * 4 + 2] = argb & 0xff;
		  bitmap[i * 4 + 3] = (argb >> 24) & 0xff;
		}

	      netWmIcon = AUTORELEASE([[NSImage alloc]
					initWithSize:NSMakeSize(bestWidth, bestHeight)]);
	      [netWmIcon addRepresentation:rep];
	    }
	}
      XFree(data);
    }

  if (netWmIcon)
    {
      return netWmIcon;
    }
  if (hintIcon)
    {
      return hintIcon;
    }
  return icon;
}


- (NSImage *) iconForIdentifier: (id)identifier
{
  if (!identifier)
    {
      return nil;
    }

  return nil;
}


@end
