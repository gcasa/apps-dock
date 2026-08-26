#import "DockView.h"
#import "DockItem.h"

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;

static NSString *GWRemoteFilenamesPboardType = @"GWRemoteFilenamesPboardType";
static NSString *GWLSFolderPboardType = @"GWLSFolderPboardType";
static NSString *GWDockIconPboardType = @"DockIconPboardType";
static NSUInteger DockTopIconClickIndex = NSUIntegerMax - 1;

@implementation DockView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    _items = [NSMutableArray new];
    _draggingPaths = NO;
    _performedDragOperation = NO;
    _lastMouseDownIndex = NSNotFound;
    _lastMouseDownTime = 0.0;
    _gnustepIcon = [[self loadGNUstepIcon] retain];
    [self registerForDraggedTypes:
      [NSArray arrayWithObjects:NSFilenamesPboardType,
                                NSURLPboardType,
                                NSStringPboardType,
                                @"text/uri-list",
                                @"text/plain",
                                GWRemoteFilenamesPboardType,
                                GWLSFolderPboardType,
                                GWDockIconPboardType,
                                nil]];
  }
  return self;
}

- (void)dealloc
{
  [_gnustepIcon release];
  [_items release];
  [super dealloc];
}

- (NSImage *)loadGNUstepIcon
{
  NSArray *paths = [NSArray arrayWithObjects:
    @"/home/heron/Development/gs-wmaker/WindowMaker/Icons/GNUstep.tiff",
    @"/usr/GNUstep/Local/Library/WindowMaker/Icons/GNUstep.tiff",
    @"/usr/GNUstep/System/Library/WindowMaker/Icons/GNUstep.tiff",
    nil];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    NSImage *image = [[[NSImage alloc] initWithContentsOfFile:
      [paths objectAtIndex:i]] autorelease];
    if (image) {
      return image;
    }
  }

  return [NSImage imageNamed:@"GNUstep"];
}

- (void)setDelegate:(id)delegate
{
  _delegate = delegate;
}

- (void)setItems:(NSArray *)items
{
  [_items setArray:items];
  [self setNeedsDisplay:YES];
}

- (void)setHorizontal:(BOOL)horizontal
{
  if (_horizontal != horizontal) {
    _horizontal = horizontal;
    [self setNeedsDisplay:YES];
  }
}

- (BOOL)isHorizontal
{
  return _horizontal;
}

- (NSSize)cellSize
{
  return NSMakeSize(DockCell, DockCell);
}

- (NSRect)topTileRect
{
  NSRect bounds = [self bounds];
  if (_horizontal) {
    return NSMakeRect(DockPad,
                      DockPad,
                      DockCell,
                      DockCell);
  } else {
    return NSMakeRect(DockPad,
                      NSMaxY(bounds) - DockPad - DockCell,
                      DockCell,
                      DockCell);
  }
}

- (NSPoint)cellOriginAtIndex:(NSUInteger)index
{
  NSRect topTile = [self topTileRect];
  if (_horizontal) {
    return NSMakePoint(NSMaxX(topTile) + DockGap + index * (DockCell + DockGap),
                       NSMinY(topTile));
  } else {
    return NSMakePoint(DockPad,
                       NSMinY(topTile) - DockGap - DockCell
                         - index * (DockCell + DockGap));
  }
}

- (NSUInteger)indexAtPoint:(NSPoint)p
{
  NSUInteger i;
  for (i = 0; i < [_items count]; i++) {
    NSRect r = NSMakeRect([self cellOriginAtIndex:i].x,
                         [self cellOriginAtIndex:i].y,
                         DockCell, DockCell);
    if (NSPointInRect(p, r)) {
      return i;
    }
  }
  return NSNotFound;
}

- (BOOL)topIconContainsPoint:(NSPoint)p
{
  return NSPointInRect(p, [self topTileRect]);
}

- (NSArray *)pathsFromPasteboard:(NSPasteboard *)pb
{
  NSArray *types = [pb types];
  NSArray *paths;
  NSMutableArray *collectedPaths = [NSMutableArray array];
  NSString *string;
  NSURL *url;
  NSUInteger i;

  if ([types containsObject:NSFilenamesPboardType]) {
    paths = [pb propertyListForType:NSFilenamesPboardType];
    if ([paths count]) {
      return paths;
    }
  }

  if ([types containsObject:NSURLPboardType]) {
    url = [NSURL URLFromPasteboard:pb];
    if ([url isFileURL] && [[url path] length]) {
      return [NSArray arrayWithObject:[url path]];
    }
  }

  if ([types containsObject:GWRemoteFilenamesPboardType]) {
    NSData *data = [pb dataForType:GWRemoteFilenamesPboardType];
    id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
    if ([dict isKindOfClass:[NSDictionary class]]) {
      [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
                                 toArray:collectedPaths];
    }
  }

  if ([types containsObject:GWLSFolderPboardType]) {
    NSData *data = [pb dataForType:GWLSFolderPboardType];
    id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
    if ([dict isKindOfClass:[NSDictionary class]]) {
      [self addPathsFromPasteboardObject:[dict objectForKey:@"paths"]
                                 toArray:collectedPaths];
    }
  }

  if ([types containsObject:GWDockIconPboardType]) {
    NSData *data = [pb dataForType:GWDockIconPboardType];
    id dict = data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
    if ([dict isKindOfClass:[NSDictionary class]]) {
      [self addPathsFromPasteboardObject:[dict objectForKey:@"path"]
                                 toArray:collectedPaths];
    }
  }

  for (i = 0; i < [types count]; i++) {
    NSString *type = [types objectAtIndex:i];
    id plist = [pb propertyListForType:type];

    [self addPathsFromPasteboardObject:plist toArray:collectedPaths];

    string = [pb stringForType:type];
    if ([string length]) {
      [self addPathsFromPasteboardString:string toArray:collectedPaths];
    }
  }

  if ([collectedPaths count]) {
    return collectedPaths;
  }

  return nil;
}

- (BOOL)pasteboardHasSupportedType:(NSPasteboard *)pb
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

- (void)addPathsFromPasteboardObject:(id)object toArray:(NSMutableArray *)paths
{
  if ([object isKindOfClass:[NSString class]]) {
    [self addPathsFromPasteboardString:object toArray:paths];
  } else if ([object isKindOfClass:[NSArray class]]) {
    NSUInteger i;
    for (i = 0; i < [object count]; i++) {
      [self addPathsFromPasteboardObject:[object objectAtIndex:i] toArray:paths];
    }
  } else if ([object isKindOfClass:[NSDictionary class]]) {
    NSEnumerator *enumerator = [object objectEnumerator];
    id value;

    while ((value = [enumerator nextObject])) {
      [self addPathsFromPasteboardObject:value toArray:paths];
    }
  }
}

- (void)addPathsFromPasteboardString:(NSString *)string toArray:(NSMutableArray *)paths
{
  NSArray *lines;
  NSUInteger i;

  if (![string length]) {
    return;
  }

  lines = [string componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];

  for (i = 0; i < [lines count]; i++) {
    NSString *line = [[lines objectAtIndex:i]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *path = nil;

    if (![line length] || [line hasPrefix:@"#"]) {
      continue;
    }

    if ([line hasPrefix:@"\""] && [line hasSuffix:@"\""] && [line length] > 1) {
      line = [line substringWithRange:NSMakeRange(1, [line length] - 2)];
    }

    if ([line hasPrefix:@"file:"]) {
      NSURL *fileURL = [NSURL URLWithString:line];
      if ([fileURL isFileURL]) {
        path = [fileURL path];
      }
    } else if ([line isAbsolutePath]) {
      path = line;
    }

    if ([path length] && ![paths containsObject:path]) {
      [paths addObject:path];
    }
  }
}

- (NSDragOperation)dragOperationForSender:(id <NSDraggingInfo>)sender
{
  NSDragOperation mask = [sender draggingSourceOperationMask];

  if (mask & NSDragOperationCopy) {
    return NSDragOperationCopy;
  }
  if (mask & NSDragOperationLink) {
    return NSDragOperationLink;
  }
  if (mask & NSDragOperationGeneric) {
    return NSDragOperationGeneric;
  }
  if (mask & NSDragOperationPrivate) {
    return NSDragOperationPrivate;
  }
  if (mask & NSDragOperationMove) {
    return NSDragOperationMove;
  }

  return NSDragOperationCopy;
}

- (BOOL)drawImage:(NSImage *)image inCell:(NSRect)cell size:(CGFloat)size
{
  NSSize imageSize;
  NSRect sourceRect;
  NSRect destRect;

  if (!image || (![[image representations] count] && ![image isValid])) {
    return NO;
  }

  imageSize = [image size];
  if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
    NSImageRep *rep = [[image representations] count]
      ? [[image representations] objectAtIndex:0] : nil;
    if (rep) {
      imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
      [image setSize:imageSize];
    }
  }

  if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
    return NO;
  }

  sourceRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);
  destRect = NSMakeRect(NSMidX(cell) - size / 2.0,
                        NSMidY(cell) - size / 2.0,
                        size,
                        size);

  [image drawInRect:destRect
           fromRect:sourceRect
          operation:NSCompositeSourceOver
           fraction:1.0];
  return YES;
}

- (void)drawFallbackIconForItem:(DockItem *)item inCell:(NSRect)cell
{
  NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont boldSystemFontOfSize:18], NSFontAttributeName,
    [NSColor colorWithCalibratedWhite:0.95 alpha:1.0], NSForegroundColorAttributeName,
    nil];
  NSString *title = [[item title] length] ? [item title] : @"?";
  NSString *label = [[title substringToIndex:MIN((NSUInteger)2, [title length])] uppercaseString];
  NSSize size = [label sizeWithAttributes:attrs];

  [label drawAtPoint:NSMakePoint(NSMidX(cell) - size.width / 2.0,
                                 NSMidY(cell) - size.height / 2.0)
      withAttributes:attrs];
}

- (void)drawDockTileForItem:(DockItem *)item inCell:(NSRect)cell size:(CGFloat)size
{
  NSImage *icon = [item icon];

  if (![self drawImage:icon inCell:cell size:size]) {
    [self drawFallbackIconForItem:item inCell:cell];
  }
}

- (void)drawStateForItem:(DockItem *)item inCell:(NSRect)cell
{
  NSUInteger count = 0;
  NSUInteger i;
  CGFloat dotSize = 4.0;
  CGFloat gap = 3.0;
  CGFloat x;
  CGFloat y = NSMinY(cell) + 6.0;

  if ([item state] == DockItemNotRunning) {
    count = 3;
  } else if ([item state] == DockItemHidden) {
    count = 1;
  }

  if (!count) {
    return;
  }

  x = NSMinX(cell) + 8.0;

  [[NSColor colorWithCalibratedWhite:0.08 alpha:1.0] set];
  for (i = 0; i < count; i++) {
    NSRect dot = NSMakeRect(x + i * (dotSize + gap), y, dotSize, dotSize);
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
  }
}

- (void)drawTopTile
{
  NSRect cell = [self topTileRect];

  [self drawImage:_gnustepIcon inCell:cell size:50.0];
}

- (void)drawRect:(NSRect)dirtyRect
{
  NSUInteger i;

  [self drawTopTile];

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSPoint origin = [self cellOriginAtIndex:i];
    NSRect cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);

    [self drawDockTileForItem:item inCell:cell size:46.0];
    [self drawStateForItem:item inCell:cell];
  }

}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  if ([self pasteboardHasSupportedType:[sender draggingPasteboard]]) {
    _draggingPaths = YES;
    _performedDragOperation = NO;
    [self setNeedsDisplay:YES];
    return [self dragOperationForSender:sender];
  }
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  return [self draggingEntered:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  _draggingPaths = NO;
  _performedDragOperation = NO;
  [self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return [self pasteboardHasSupportedType:[sender draggingPasteboard]];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
  _draggingPaths = NO;
  [self setNeedsDisplay:YES];

  if ([paths count] && [_delegate respondsToSelector:@selector(dockViewDidReceivePaths:)]) {
    [_delegate dockViewDidReceivePaths:paths];
    _performedDragOperation = YES;
    return YES;
  }
  return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  if (!_performedDragOperation) {
    NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
    if ([paths count] &&
        [_delegate respondsToSelector:@selector(dockViewDidReceivePaths:)]) {
      [_delegate dockViewDidReceivePaths:paths];
    }
  }

  _draggingPaths = NO;
  _performedDragOperation = NO;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSUInteger index = [self indexAtPoint:location];
  NSTimeInterval eventTime = [event timestamp];
  NSTimeInterval doubleClickInterval = 0.5;
  NSUInteger clickedIndex = index;
  BOOL isDoubleClick = NO;
  BOOL topIconClicked = [self topIconContainsPoint:location];

  if (topIconClicked) {
    clickedIndex = DockTopIconClickIndex;
  }

  if (clickedIndex != NSNotFound) {
    if ([event clickCount] >= 2) {
      isDoubleClick = YES;
    } else if (clickedIndex == _lastMouseDownIndex &&
               _lastMouseDownTime > 0.0 &&
               eventTime - _lastMouseDownTime <= doubleClickInterval) {
      isDoubleClick = YES;
    }
  }

  if (isDoubleClick &&
      [_delegate respondsToSelector:@selector(dockViewDidActivateItem:)]) {
    if (topIconClicked) {
      if ([_delegate respondsToSelector:@selector(dockViewDidActivateTopIcon)]) {
        [_delegate dockViewDidActivateTopIcon];
      }
    } else {
      [_delegate dockViewDidActivateItem:[_items objectAtIndex:index]];
    }
    _lastMouseDownIndex = NSNotFound;
    _lastMouseDownTime = 0.0;
    return;
  }

  _lastMouseDownIndex = clickedIndex;
  _lastMouseDownTime = eventTime;
}

@end
