#import "DockView.h"
#import "DockItem.h"
#import <math.h>

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;

static NSString *GWRemoteFilenamesPboardType = @"GWRemoteFilenamesPboardType";
static NSString *GWLSFolderPboardType = @"GWLSFolderPboardType";
static NSString *GWDockIconPboardType = @"DockIconPboardType";
static NSString *DockReorderPboardType = @"DockWMReorderPboardType";
static NSUInteger DockTopIconClickIndex = NSUIntegerMax - 1;
static NSInteger DockHoverNone = -1;
static NSInteger DockHoverTopIcon = -2;
static NSInteger DockHoverRecycler = -3;

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
    _hoveredItemIndex = DockHoverNone;
    _tooltipItemIndex = DockHoverNone;
    _trackingRectTag = 0;
    _mouseDownItemIndex = NSNotFound;
    _draggedItemIndex = NSNotFound;
    _dropIndex = NSNotFound;
    _backgroundMode = DockBackgroundBlack;
    _gnustepIcon = [[self loadGNUstepIcon] retain];
    _recyclerIcon = [[self loadRecyclerIcon] retain];
    [self registerForDraggedTypes:
      [NSArray arrayWithObjects:NSFilenamesPboardType,
                                NSURLPboardType,
                                NSStringPboardType,
                                @"text/uri-list",
                                @"text/plain",
                                DockReorderPboardType,
                                GWRemoteFilenamesPboardType,
                                GWLSFolderPboardType,
                                GWDockIconPboardType,
                                nil]];
  }
  return self;
}

- (void)dealloc
{
  [_tooltipTimer invalidate];
  [_tooltipTimer release];
  if (_trackingRectTag) {
    [self removeTrackingRect:_trackingRectTag];
  }
  [_backgroundImage release];
  [_gnustepIcon release];
  [_recyclerIcon release];
  [_items release];
  [super dealloc];
}

- (NSImage *)loadGNUstepIcon
{
  NSString *path = [[NSBundle mainBundle] pathForResource:@"GNUstep"
                                                   ofType:@"tiff"];
  NSImage *image;

  if (![path length]) {
    path = [[@"Resources" stringByAppendingPathComponent:@"GNUstep"]
      stringByAppendingPathExtension:@"tiff"];
  }

  image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
  if (image) {
    return image;
  }

  return [NSImage imageNamed:@"GNUstep"];
}

- (NSImage *)loadRecyclerIcon
{
  NSString *path = [[NSBundle mainBundle] pathForResource:@"Recycler.GNUstep"
                                                   ofType:@"xpm"];
  NSImage *image;

  if (![path length]) {
    path = [[@"Resources" stringByAppendingPathComponent:@"Recycler.GNUstep"]
      stringByAppendingPathExtension:@"xpm"];
  }

  image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
  if (image) {
    return image;
  }

  return nil;
}

- (void)updateTrackingRect
{
  if (_trackingRectTag) {
    [self removeTrackingRect:_trackingRectTag];
    _trackingRectTag = 0;
  }

  _trackingRectTag = [self addTrackingRect:[self bounds]
                                     owner:self
                                  userData:NULL
                              assumeInside:NO];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self updateTrackingRect];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame:frame];
  [self updateTrackingRect];
}

- (void)setDelegate:(id)delegate
{
  _delegate = delegate;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)setItems:(NSArray *)items
{
  [_items setArray:items];
  [self hideTooltip];
  [self setNeedsDisplay:YES];
}

- (void)setBackgroundImage:(NSImage *)image
{
  if (_backgroundImage != image) {
    [_backgroundImage release];
    _backgroundImage = [image retain];
    [self setNeedsDisplay:YES];
  }
}

- (void)setBackgroundMode:(DockBackgroundMode)mode
{
  if (_backgroundMode != mode) {
    _backgroundMode = mode;
    [self setNeedsDisplay:YES];
  }
}

- (void)setRecyclerHasContents:(BOOL)hasContents
{
  if (_recyclerHasContents != hasContents) {
    _recyclerHasContents = hasContents;
    [self setNeedsDisplay:YES];
  }
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

- (NSRect)recyclerTileRect
{
  NSPoint origin = [self cellOriginAtIndex:[_items count]];
  return NSMakeRect(origin.x, origin.y, DockCell, DockCell);
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

- (BOOL)recyclerContainsPoint:(NSPoint)p
{
  return NSPointInRect(p, [self recyclerTileRect]);
}

- (NSUInteger)insertionIndexAtPoint:(NSPoint)p
{
  NSUInteger i;

  if (![_items count]) {
    return 0;
  }

  for (i = 0; i < [_items count]; i++) {
    NSPoint origin = [self cellOriginAtIndex:i];
    NSRect cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);

    if (_horizontal) {
      if (p.x < NSMidX(cell)) {
        return i;
      }
    } else {
      if (p.y > NSMidY(cell)) {
        return i;
      }
    }
  }

  return [_items count];
}

- (BOOL)topIconContainsPoint:(NSPoint)p
{
  return NSPointInRect(p, [self topTileRect]);
}

- (NSInteger)hoverIndexAtPoint:(NSPoint)p
{
  NSUInteger index;

  if ([self topIconContainsPoint:p]) {
    return DockHoverTopIcon;
  }

  if ([self recyclerContainsPoint:p]) {
    return DockHoverRecycler;
  }

  index = [self indexAtPoint:p];
  return index == NSNotFound ? DockHoverNone : (NSInteger)index;
}

- (NSRect)cellRectForHoverIndex:(NSInteger)index
{
  if (index == DockHoverTopIcon) {
    return [self topTileRect];
  }

  if (index == DockHoverRecycler) {
    return [self recyclerTileRect];
  }

  if (index >= 0 && index < (NSInteger)[_items count]) {
    NSPoint origin = [self cellOriginAtIndex:(NSUInteger)index];
    return NSMakeRect(origin.x, origin.y, DockCell, DockCell);
  }

  return NSZeroRect;
}

- (NSString *)tooltipTitleForHoverIndex:(NSInteger)index
{
  if (index == DockHoverTopIcon) {
    return @"GWorkspace";
  }

  if (index == DockHoverRecycler) {
    return @"Recycler";
  }

  if (index >= 0 && index < (NSInteger)[_items count]) {
    DockItem *item = [_items objectAtIndex:(NSUInteger)index];
    return [[item title] length] ? [item title] : [[item path] lastPathComponent];
  }

  return nil;
}

- (void)hideTooltip
{
  [_tooltipTimer invalidate];
  [_tooltipTimer release];
  _tooltipTimer = nil;
  if (_tooltipItemIndex != DockHoverNone) {
    _tooltipItemIndex = DockHoverNone;
    [self setNeedsDisplay:YES];
  }
}

- (void)scheduleTooltipForHoverIndex:(NSInteger)index
{
  [_tooltipTimer invalidate];
  [_tooltipTimer release];
  _tooltipTimer = nil;
  _tooltipItemIndex = DockHoverNone;

  if (index == DockHoverNone) {
    [self setNeedsDisplay:YES];
    return;
  }

  _tooltipTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                    target:self
                                                  selector:@selector(showTooltip:)
                                                  userInfo:nil
                                                   repeats:NO] retain];
  [self setNeedsDisplay:YES];
}

- (void)drawTooltip
{
  NSString *title = [self tooltipTitleForHoverIndex:_tooltipItemIndex];
  NSRect cell;
  NSDictionary *attrs;
  NSSize textSize;
  CGFloat padX = 7.0;
  CGFloat padY = 4.0;
  NSRect tooltipRect;
  NSPoint textPoint;
  NSRect bounds = [self bounds];

  if (![title length]) {
    return;
  }

  cell = [self cellRectForHoverIndex:_tooltipItemIndex];
  if (NSIsEmptyRect(cell)) {
    return;
  }

  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont systemFontOfSize:11.0], NSFontAttributeName,
    [NSColor whiteColor], NSForegroundColorAttributeName,
    nil];
  textSize = [title sizeWithAttributes:attrs];

  tooltipRect = NSMakeRect(0.0, 0.0,
                           textSize.width + padX * 2.0,
                           textSize.height + padY * 2.0);
  if (_horizontal) {
    tooltipRect.origin.x = NSMidX(cell) - NSWidth(tooltipRect) / 2.0;
    tooltipRect.origin.y = NSMaxY(cell) - NSHeight(tooltipRect) - 2.0;
  } else {
    tooltipRect.origin.x = NSMaxX(cell) - NSWidth(tooltipRect) - 2.0;
    tooltipRect.origin.y = NSMidY(cell) - NSHeight(tooltipRect) / 2.0;
  }

  if (NSMinX(tooltipRect) < NSMinX(bounds) + 2.0) {
    tooltipRect.origin.x = NSMinX(bounds) + 2.0;
  }
  if (NSMaxX(tooltipRect) > NSMaxX(bounds) - 2.0) {
    tooltipRect.origin.x = NSMaxX(bounds) - NSWidth(tooltipRect) - 2.0;
  }
  if (NSMinY(tooltipRect) < NSMinY(bounds) + 2.0) {
    tooltipRect.origin.y = NSMinY(bounds) + 2.0;
  }
  if (NSMaxY(tooltipRect) > NSMaxY(bounds) - 2.0) {
    tooltipRect.origin.y = NSMaxY(bounds) - NSHeight(tooltipRect) - 2.0;
  }

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.82] set];
  [[NSBezierPath bezierPathWithRoundedRect:tooltipRect
                                   xRadius:4.0
                                   yRadius:4.0] fill];

  textPoint = NSMakePoint(NSMinX(tooltipRect) + padX,
                          NSMinY(tooltipRect) + padY);
  [title drawAtPoint:textPoint withAttributes:attrs];
}

- (void)showTooltip:(NSTimer *)timer
{
  [_tooltipTimer release];
  _tooltipTimer = nil;

  if (_hoveredItemIndex != DockHoverNone) {
    _tooltipItemIndex = _hoveredItemIndex;
    [self setNeedsDisplay:YES];
  }
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
  return NSDragOperationEvery;
}

- (BOOL)pasteboardHasReorderType:(NSPasteboard *)pb
{
  return [[pb types] containsObject:DockReorderPboardType];
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
  CGFloat dotSize = 5.0;
  CGFloat x;
  CGFloat y = NSMinY(cell) + 2.0;

  if ([item kind] != DockItemApplication ||
      [item state] == DockItemNotRunning) {
    return;
  }

  x = NSMidX(cell) - dotSize / 2.0;

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.65] set];
  [[NSBezierPath bezierPathWithOvalInRect:
    NSMakeRect(x - 1.0, y - 1.0, dotSize + 2.0, dotSize + 2.0)] fill];

  [[NSColor colorWithCalibratedWhite:0.92 alpha:0.95] set];
  [[NSBezierPath bezierPathWithOvalInRect:
    NSMakeRect(x, y, dotSize, dotSize)] fill];
}

- (void)drawTopTile
{
  NSRect cell = [self topTileRect];

  [self drawImage:_gnustepIcon inCell:cell size:50.0];
}

- (void)drawRecyclerFallbackInCell:(NSRect)cell
{
  NSPoint center = NSMakePoint(NSMidX(cell), NSMidY(cell));
  CGFloat radius = 18.0;
  NSUInteger i;

  [[NSColor colorWithCalibratedWhite:0.88 alpha:0.95] set];

  for (i = 0; i < 3; i++) {
    CGFloat angle = (CGFloat)i * 120.0;
    CGFloat start = angle + 18.0;
    CGFloat end = angle + 92.0;
    CGFloat arrowAngle = end * M_PI / 180.0;
    NSBezierPath *arc = [NSBezierPath bezierPath];
    NSPoint arrowPoint = NSMakePoint(center.x + cos(arrowAngle) * radius,
                                     center.y + sin(arrowAngle) * radius);
    NSBezierPath *head = [NSBezierPath bezierPath];

    [arc appendBezierPathWithArcWithCenter:center
                                    radius:radius
                                startAngle:start
                                  endAngle:end];
    [arc setLineWidth:3.0];
    [arc stroke];

    [head moveToPoint:arrowPoint];
    [head relativeLineToPoint:NSMakePoint(-8.0 * sin(arrowAngle) -
                                          4.0 * cos(arrowAngle),
                                          8.0 * cos(arrowAngle) -
                                          4.0 * sin(arrowAngle))];
    [head relativeLineToPoint:NSMakePoint(8.0 * cos(arrowAngle),
                                          8.0 * sin(arrowAngle))];
    [head closePath];
    [head fill];
  }
}

- (void)drawRecyclerContentsIndicatorInCell:(NSRect)cell
{
  CGFloat dotSize = 8.0;
  CGFloat x = NSMidX(cell) - dotSize / 2.0;
  CGFloat y = NSMidY(cell) - dotSize / 2.0;

  if (!_recyclerHasContents) {
    return;
  }

  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.70] set];
  [[NSBezierPath bezierPathWithOvalInRect:
    NSMakeRect(x - 1.0, y - 1.0, dotSize + 2.0, dotSize + 2.0)] fill];

  [[NSColor colorWithCalibratedRed:0.10
                             green:0.80
                              blue:0.35
                             alpha:0.96] set];
  [[NSBezierPath bezierPathWithOvalInRect:
    NSMakeRect(x, y, dotSize, dotSize)] fill];
}

- (void)drawRecyclerTile
{
  NSRect cell = [self recyclerTileRect];

  if (![self drawImage:_recyclerIcon inCell:cell size:46.0]) {
    [self drawRecyclerFallbackInCell:cell];
  }
  [self drawRecyclerContentsIndicatorInCell:cell];
}

- (void)drawDropIndicator
{
  NSRect cell;
  CGFloat thickness = 3.0;

  if (_draggedItemIndex == NSNotFound ||
      _dropIndex == NSNotFound ||
      _dropIndex > [_items count]) {
    return;
  }

  if (_dropIndex < [_items count]) {
    NSPoint origin = [self cellOriginAtIndex:_dropIndex];
    cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);
  } else {
    cell = [self recyclerTileRect];
  }

  [[NSColor colorWithCalibratedWhite:0.95 alpha:0.95] set];
  if (_horizontal) {
    NSRectFill(NSMakeRect(NSMinX(cell) - DockGap / 2.0 - thickness / 2.0,
                          NSMinY(cell) + 8.0,
                          thickness,
                          NSHeight(cell) - 16.0));
  } else {
    NSRectFill(NSMakeRect(NSMinX(cell) + 8.0,
                          NSMaxY(cell) + DockGap / 2.0 - thickness / 2.0,
                          NSWidth(cell) - 16.0,
                          thickness));
  }
}

- (void)drawRect:(NSRect)dirtyRect
{
  NSUInteger i;

  if (_backgroundMode == DockBackgroundSimulatedTransparency &&
      _backgroundImage) {
    [_backgroundImage drawInRect:[self bounds]
                         fromRect:NSMakeRect(0, 0,
                                             [_backgroundImage size].width,
                                             [_backgroundImage size].height)
                        operation:NSCompositeSourceOver
                         fraction:1.0];
  } else if (_backgroundMode == DockBackgroundBlack) {
    [[NSColor blackColor] set];
    NSRectFill([self bounds]);
  }

  [self drawTopTile];

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSPoint origin = [self cellOriginAtIndex:i];
    NSRect cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);

    [self drawDockTileForItem:item inCell:cell size:46.0];
    [self drawStateForItem:item inCell:cell];
  }

  [self drawDropIndicator];
  [self drawRecyclerTile];
  [self drawTooltip];
}

- (void)mouseMoved:(NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger hoverIndex = [self hoverIndexAtPoint:location];

  if (hoverIndex != _hoveredItemIndex) {
    _hoveredItemIndex = hoverIndex;
    [self scheduleTooltipForHoverIndex:hoverIndex];
  }
}

- (void)mouseExited:(NSEvent *)event
{
  _hoveredItemIndex = DockHoverNone;
  [self hideTooltip];
}

- (NSImage *)dragImageForItemAtIndex:(NSUInteger)index
{
  NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(DockCell, DockCell)] autorelease];
  NSRect cell = NSMakeRect(0.0, 0.0, DockCell, DockCell);

  if (index >= [_items count]) {
    return nil;
  }

  [image lockFocus];
  [self drawDockTileForItem:[_items objectAtIndex:index] inCell:cell size:46.0];
  [self drawStateForItem:[_items objectAtIndex:index] inCell:cell];
  [image unlockFocus];
  return image;
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
  CGFloat dx = location.x - _mouseDownPoint.x;
  CGFloat dy = location.y - _mouseDownPoint.y;

  if (_mouseDownItemIndex == NSNotFound ||
      _mouseDownItemIndex >= [_items count] ||
      (dx * dx + dy * dy) < 16.0) {
    return;
  }

  _draggedItemIndex = _mouseDownItemIndex;
  _dropIndex = _mouseDownItemIndex;
  [self hideTooltip];

  {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    NSImage *dragImage = [self dragImageForItemAtIndex:_mouseDownItemIndex];
    NSPoint dragPoint = NSMakePoint(location.x - DockCell / 2.0,
                                    location.y - DockCell / 2.0);

    [pasteboard declareTypes:[NSArray arrayWithObject:DockReorderPboardType]
                       owner:nil];
    [pasteboard setString:[NSString stringWithFormat:@"%lu",
                                                    (unsigned long)_mouseDownItemIndex]
                  forType:DockReorderPboardType];
    [self dragImage:dragImage
                 at:dragPoint
             offset:NSZeroSize
              event:event
         pasteboard:pasteboard
             source:self
          slideBack:YES];
  }
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
  return NSDragOperationMove | NSDragOperationDelete;
}

- (BOOL)screenPointIsInsideDock:(NSPoint)screenPoint
{
  NSPoint windowPoint;
  NSPoint viewPoint;

  if (![self window]) {
    return NO;
  }

  windowPoint = [[self window] convertScreenToBase:screenPoint];
  viewPoint = [self convertPoint:windowPoint fromView:nil];
  return NSPointInRect(viewPoint, [self bounds]);
}

- (void)finishDraggingItemWithRemove:(BOOL)remove
{
  NSUInteger draggedIndex = _draggedItemIndex;

  if (remove &&
      draggedIndex != NSNotFound &&
      draggedIndex < [_items count] &&
      [_delegate respondsToSelector:
        @selector(dockViewDidRemoveItemAtIndex:)]) {
    [_delegate dockViewDidRemoveItemAtIndex:draggedIndex];
  }

  _mouseDownItemIndex = NSNotFound;
  _draggedItemIndex = NSNotFound;
  _dropIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (void)draggedImage:(NSImage *)image
             endedAt:(NSPoint)screenPoint
           operation:(NSDragOperation)operation
{
  [self finishDraggingItemWithRemove:
    ![self screenPointIsInsideDock:screenPoint]];
}

- (void)draggedImage:(NSImage *)image
             endedAt:(NSPoint)screenPoint
           deposited:(BOOL)flag
{
  [self finishDraggingItemWithRemove:
    ![self screenPointIsInsideDock:screenPoint]];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
  NSPasteboard *pasteboard = [sender draggingPasteboard];

  [self hideTooltip];

  if ([self pasteboardHasReorderType:pasteboard]) {
    _dropIndex = [self insertionIndexAtPoint:location];
    [self setNeedsDisplay:YES];
    return NSDragOperationMove;
  }

  if ([self recyclerContainsPoint:location]) {
    return NSDragOperationNone;
  }

  if ([self pasteboardHasSupportedType:pasteboard]) {
    _draggingPaths = YES;
    _performedDragOperation = NO;
    _dropIndex = [self insertionIndexAtPoint:location];
    [self setNeedsDisplay:YES];
    return [self dragOperationForSender:sender];
  }
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];

  if ([self pasteboardHasReorderType:[sender draggingPasteboard]]) {
    _dropIndex = [self insertionIndexAtPoint:location];
    [self setNeedsDisplay:YES];
    return NSDragOperationMove;
  }

  if ([self pasteboardHasSupportedType:[sender draggingPasteboard]]) {
    if ([self recyclerContainsPoint:location]) {
      _dropIndex = NSNotFound;
      [self setNeedsDisplay:YES];
      return NSDragOperationNone;
    }
    _dropIndex = [self insertionIndexAtPoint:location];
    [self setNeedsDisplay:YES];
    return [self dragOperationForSender:sender];
  }

  return [self draggingEntered:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  _draggingPaths = NO;
  _performedDragOperation = NO;
  _dropIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];

  if ([self pasteboardHasReorderType:[sender draggingPasteboard]]) {
    return YES;
  }

  return ![self recyclerContainsPoint:location] &&
    [self pasteboardHasSupportedType:[sender draggingPasteboard]];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
  NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
  NSPasteboard *pasteboard = [sender draggingPasteboard];
  _draggingPaths = NO;
  [self setNeedsDisplay:YES];

  if ([self pasteboardHasReorderType:pasteboard]) {
    NSString *indexString = [pasteboard stringForType:DockReorderPboardType];
    NSUInteger fromIndex = (NSUInteger)[indexString integerValue];
    NSUInteger toIndex = [self insertionIndexAtPoint:location];

    _dropIndex = NSNotFound;
    _draggedItemIndex = NSNotFound;
    _performedDragOperation = YES;
    if (fromIndex < [_items count] &&
        toIndex <= [_items count] &&
        [_delegate respondsToSelector:
          @selector(dockViewDidMoveItemFromIndex:toIndex:)]) {
      [_delegate dockViewDidMoveItemFromIndex:fromIndex toIndex:toIndex];
      return YES;
    }
    return NO;
  }

  if ([self recyclerContainsPoint:location]) {
    return NO;
  }

  if ([paths count] && [_delegate respondsToSelector:@selector(dockViewDidReceivePaths:)]) {
    NSUInteger toIndex = [self insertionIndexAtPoint:location];

    if ([_delegate respondsToSelector:
          @selector(dockViewDidReceivePaths:atIndex:)]) {
      [_delegate dockViewDidReceivePaths:paths atIndex:toIndex];
    } else {
      [_delegate dockViewDidReceivePaths:paths];
    }
    _performedDragOperation = YES;
    _dropIndex = NSNotFound;
    return YES;
  }
  return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  if (!_performedDragOperation) {
    NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
    NSPoint location = [self convertPoint:[sender draggingLocation] fromView:nil];
    if (![self pasteboardHasReorderType:[sender draggingPasteboard]] &&
        ![self recyclerContainsPoint:location] &&
        [paths count]) {
      NSUInteger toIndex = [self insertionIndexAtPoint:location];

      if ([_delegate respondsToSelector:
            @selector(dockViewDidReceivePaths:atIndex:)]) {
        [_delegate dockViewDidReceivePaths:paths atIndex:toIndex];
      } else if ([_delegate respondsToSelector:
                   @selector(dockViewDidReceivePaths:)]) {
        [_delegate dockViewDidReceivePaths:paths];
      }
    }
  }

  _draggingPaths = NO;
  _performedDragOperation = NO;
  _dropIndex = NSNotFound;
  _draggedItemIndex = NSNotFound;
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

  _mouseDownPoint = location;
  _mouseDownItemIndex = index;

  if (eventTime <= 0.0) {
    eventTime = [NSDate timeIntervalSinceReferenceDate];
  }

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

  if (isDoubleClick) {
    if (topIconClicked) {
      if ([_delegate respondsToSelector:@selector(dockViewDidActivateTopIcon)]) {
        [_delegate dockViewDidActivateTopIcon];
      }
    } else if ([_delegate respondsToSelector:@selector(dockViewDidActivateItem:)]) {
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
