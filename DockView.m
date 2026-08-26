#import "DockView.h"
#import "DockItem.h"

static CGFloat DockCell = 64.0;
static CGFloat DockGap = 2.0;
static CGFloat DockPad = 10.0;

@implementation DockView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    _items = [NSMutableArray new];
    _highlightIndex = -1;
    _gnustepIcon = [[self loadGNUstepIcon] retain];
    [self registerForDraggedTypes:
      [NSArray arrayWithObjects:NSFilenamesPboardType, NSURLPboardType, nil]];
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

- (NSSize)cellSize
{
  return NSMakeSize(DockCell, DockCell);
}

- (NSRect)topTileRect
{
  NSRect bounds = [self bounds];
  return NSMakeRect(DockPad,
                    NSMaxY(bounds) - DockPad - DockCell,
                    DockCell,
                    DockCell);
}

- (NSPoint)cellOriginAtIndex:(NSUInteger)index
{
  NSRect topTile = [self topTileRect];
  return NSMakePoint(DockPad,
                     NSMinY(topTile) - DockGap - DockCell
                       - index * (DockCell + DockGap));
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

- (NSArray *)pathsFromPasteboard:(NSPasteboard *)pb
{
  NSArray *types = [pb types];
  NSArray *paths;
  NSURL *url;

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

  return nil;
}

- (void)drawTileInRect:(NSRect)cell highlighted:(BOOL)highlighted
{
  NSRect inner = NSInsetRect(cell, 2.0, 2.0);

  [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] set];
  NSRectFill(cell);

  [[NSColor colorWithCalibratedWhite:(highlighted ? 0.42 : 0.28) alpha:1.0] set];
  NSRectFill(inner);

  [[NSColor colorWithCalibratedWhite:(highlighted ? 0.68 : 0.58) alpha:1.0] set];
  NSRectFill(NSInsetRect(inner, 3.0, 3.0));

  [[NSColor colorWithCalibratedWhite:(highlighted ? 0.82 : 0.70) alpha:1.0] set];
  NSFrameRect(cell);
}

- (void)drawImage:(NSImage *)image inCell:(NSRect)cell size:(CGFloat)size
{
  if (!image) {
    return;
  }

  [image drawInRect:NSMakeRect(NSMidX(cell) - size / 2.0,
                               NSMidY(cell) - size / 2.0,
                               size,
                               size)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0];
}

- (void)drawStateForItem:(DockItem *)item inCell:(NSRect)cell
{
  NSUInteger count = 0;
  NSUInteger i;
  CGFloat dotSize = 4.0;
  CGFloat gap = 3.0;
  CGFloat width;
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

  width = count * dotSize + (count - 1) * gap;
  x = NSMidX(cell) - width / 2.0;

  [[NSColor colorWithCalibratedWhite:0.08 alpha:1.0] set];
  for (i = 0; i < count; i++) {
    NSRect dot = NSMakeRect(x + i * (dotSize + gap), y, dotSize, dotSize);
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
  }
}

- (void)drawTopTile
{
  NSRect cell = [self topTileRect];

  [self drawTileInRect:cell highlighted:NO];
  [self drawImage:_gnustepIcon inCell:cell size:50.0];
}

- (void)drawRect:(NSRect)dirtyRect
{
  NSUInteger i;
  NSRect bounds = [self bounds];
  [[NSColor colorWithCalibratedWhite:0.10 alpha:0.96] set];
  NSRectFill(bounds);

  [self drawTopTile];

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSPoint origin = [self cellOriginAtIndex:i];
    NSRect cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);

    [self drawTileInRect:cell highlighted:((NSInteger)i == _highlightIndex)];

    if ([item kind] == DockItemApplication) {
      NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:[item path]];
      [self drawImage:icon inCell:cell size:46.0];
    } else {
      NSImage *icon = [item icon];
      if (!icon) {
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];
      }
      [self drawImage:icon inCell:cell size:46.0];
    }
    [self drawStateForItem:item inCell:cell];
  }

  if (_highlightIndex == (NSInteger)[_items count]) {
    NSPoint origin = [self cellOriginAtIndex:[_items count]];
    [self drawTileInRect:NSMakeRect(origin.x, origin.y, DockCell, DockCell)
             highlighted:YES];
  }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  if ([[self pathsFromPasteboard:[sender draggingPasteboard]] count]) {
    _highlightIndex = [_items count];
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
  }
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  return [self draggingEntered:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  _highlightIndex = -1;
  [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSArray *paths = [self pathsFromPasteboard:[sender draggingPasteboard]];
  _highlightIndex = -1;
  [self setNeedsDisplay:YES];

  if ([paths count] && [_delegate respondsToSelector:@selector(dockViewDidReceivePaths:)]) {
    [_delegate dockViewDidReceivePaths:paths];
    return YES;
  }
  return NO;
}

- (void)mouseDown:(NSEvent *)event
{
  NSUInteger index = [self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if (index != NSNotFound && [_delegate respondsToSelector:@selector(dockViewDidActivateItem:)]) {
    [_delegate dockViewDidActivateItem:[_items objectAtIndex:index]];
  }
}

@end
