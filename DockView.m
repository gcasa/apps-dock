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
    [self registerForDraggedTypes:
      [NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
  }
  return self;
}

- (void)dealloc
{
  [_items release];
  [super dealloc];
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

- (NSPoint)cellOriginAtIndex:(NSUInteger)index
{
  NSRect bounds = [self bounds];
  return NSMakePoint(DockPad,
                     NSMaxY(bounds) - DockPad - DockCell
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

- (void)drawTileInRect:(NSRect)cell highlighted:(BOOL)highlighted
{
  NSRect inner = NSInsetRect(cell, 1.0, 1.0);
  NSBezierPath *shadowPath;
  NSBezierPath *innerPath;

  [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] set];
  NSRectFill(cell);

  [[NSColor colorWithCalibratedWhite:0.74 alpha:1.0] set];
  NSFrameRect(cell);
  [[NSColor colorWithCalibratedWhite:0.00 alpha:1.0] set];
  NSFrameRect(NSInsetRect(cell, 1.0, 1.0));

  shadowPath = [NSBezierPath bezierPathWithRect:inner];
  [[NSColor colorWithCalibratedWhite:(highlighted ? 0.42 : 0.28) alpha:1.0] set];
  [shadowPath fill];

  innerPath = [NSBezierPath bezierPathWithRect:NSInsetRect(inner, 3.0, 3.0)];
  [[NSColor colorWithCalibratedWhite:(highlighted ? 0.68 : 0.58) alpha:1.0] set];
  [innerPath fill];

  [[NSColor colorWithCalibratedWhite:0.82 alpha:1.0] set];
  NSFrameRect(NSInsetRect(inner, 3.0, 3.0));
  [[NSColor colorWithCalibratedWhite:0.18 alpha:1.0] set];
  NSFrameRect(NSInsetRect(inner, 4.0, 4.0));
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

- (void)drawRect:(NSRect)dirtyRect
{
  NSUInteger i;
  NSRect bounds = [self bounds];
  [[NSColor colorWithCalibratedWhite:0.10 alpha:0.96] set];
  NSRectFill(bounds);

  for (i = 0; i < [_items count]; i++) {
    DockItem *item = [_items objectAtIndex:i];
    NSPoint origin = [self cellOriginAtIndex:i];
    NSRect cell = NSMakeRect(origin.x, origin.y, DockCell, DockCell);

    [self drawTileInRect:cell highlighted:((NSInteger)i == _highlightIndex)];

    if ([item kind] == DockItemApplication) {
      NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:[item path]];
      [self drawImage:icon inCell:cell size:48.0];
    } else {
      NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:18], NSFontAttributeName,
        [NSColor colorWithCalibratedRed:0.86 green:0.91 blue:0.98 alpha:1.0],
        NSForegroundColorAttributeName, nil];
      [@"X11" drawAtPoint:NSMakePoint(NSMinX(cell) + 15, NSMinY(cell) + 22)
           withAttributes:attrs];
    }
  }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb = [sender draggingPasteboard];
  if ([[pb types] containsObject:NSFilenamesPboardType]) {
    _highlightIndex = [_items count];
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
  }
  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  _highlightIndex = -1;
  [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray *paths = [pb propertyListForType:NSFilenamesPboardType];
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
