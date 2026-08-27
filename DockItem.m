#import "DockItem.h"

@interface DockTileIconView : NSView
{
  NSImage *_icon;
  NSString *_title;
}
- (void)setIcon:(NSImage *)icon;
- (void)setTitle:(NSString *)title;
@end

@implementation DockTileIconView

- (void)dealloc
{
  [_icon release];
  [_title release];
  [super dealloc];
}

- (void)setIcon:(NSImage *)icon
{
  if (_icon != icon) {
    [_icon release];
    _icon = [icon retain];
    [self setNeedsDisplay:YES];
  }
}

- (void)setTitle:(NSString *)title
{
  if (_title != title) {
    [_title release];
    _title = [title copy];
    [self setNeedsDisplay:YES];
  }
}

- (BOOL)drawImage:(NSImage *)image inRect:(NSRect)rect
{
  NSSize imageSize;
  NSImageRep *rep;
  NSRect sourceRect;

  if (!image || (![[image representations] count] && ![image isValid])) {
    return NO;
  }

  imageSize = [image size];
  if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
    rep = [[image representations] count] ? [[image representations] objectAtIndex:0] : nil;
    if (rep) {
      imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
      [image setSize:imageSize];
    }
  }

  if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
    return NO;
  }

  sourceRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);
  [image drawInRect:rect
           fromRect:sourceRect
          operation:NSCompositeSourceOver
           fraction:1.0];
  return YES;
}

- (void)drawFallbackInRect:(NSRect)rect
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

- (void)drawRect:(NSRect)rect
{
  NSRect bounds = [self bounds];
  CGFloat size = MIN(NSWidth(bounds), NSHeight(bounds));
  NSRect iconRect = NSMakeRect(NSMidX(bounds) - size / 2.0,
                               NSMidY(bounds) - size / 2.0,
                               size,
                               size);

  if (![self drawImage:_icon inRect:iconRect]) {
    [self drawFallbackInRect:bounds];
  }
}

@end

@implementation DockItem

+ (BOOL)imageIsDrawable:(NSImage *)image
{
  return image && ([[image representations] count] > 0 ||
                   [image isValid]);
}

+ (NSImage *)imageAtPath:(NSString *)path
{
  NSImage *image;

  if (![path length]) {
    return nil;
  }

  image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
  return [self imageIsDrawable:image] ? image : nil;
}

+ (NSImage *)imageNamed:(NSString *)name inApplicationPath:(NSString *)path
{
  NSString *resources = [path stringByAppendingPathComponent:@"Resources"];
  NSArray *basePaths;
  NSArray *extensions;
  NSUInteger i, j;

  if (![name length]) {
    return nil;
  }

  basePaths = [NSArray arrayWithObjects:
    [resources stringByAppendingPathComponent:name],
    [path stringByAppendingPathComponent:name],
    name,
    nil];
  extensions = [NSArray arrayWithObjects:@"", @"tiff", @"tif", @"png", @"xpm", @"icns", nil];

  for (i = 0; i < [basePaths count]; i++) {
    NSString *base = [basePaths objectAtIndex:i];
    for (j = 0; j < [extensions count]; j++) {
      NSString *extension = [extensions objectAtIndex:j];
      NSString *candidate = [extension length] ? [base stringByAppendingPathExtension:extension] : base;
      NSImage *image = [self imageAtPath:candidate];
      if (image) {
        return image;
      }
    }
  }

  return nil;
}

+ (NSString *)applicationBundlePathForPath:(NSString *)path
{
  NSString *candidate = path;
  BOOL isDir = NO;

  while ([candidate length] && ![candidate isEqualToString:@"/"]) {
    if ([[[candidate pathExtension] lowercaseString] isEqualToString:@"app"] &&
        [[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDir] &&
        isDir) {
      return candidate;
    }
    candidate = [candidate stringByDeletingLastPathComponent];
  }

  return nil;
}

+ (NSImage *)iconForApplicationPath:(NSString *)path
{
  NSArray *infoPaths = [NSArray arrayWithObjects:
    [[path stringByAppendingPathComponent:@"Resources"] stringByAppendingPathComponent:@"Info-gnustep.plist"],
    [path stringByAppendingPathComponent:@"Info-gnustep.plist"],
    [path stringByAppendingPathComponent:@"Info.plist"],
    nil];
  NSArray *iconKeys = [NSArray arrayWithObjects:
    @"NSIcon", @"ApplicationIcon", @"CFBundleIconFile", nil];
  NSUInteger i, j;

  for (i = 0; i < [infoPaths count]; i++) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[infoPaths objectAtIndex:i]];
    if (!info) {
      continue;
    }

    for (j = 0; j < [iconKeys count]; j++) {
      id iconName = [info objectForKey:[iconKeys objectAtIndex:j]];
      NSImage *image;

      if (![iconName isKindOfClass:[NSString class]]) {
        continue;
      }

      image = [self imageNamed:iconName inApplicationPath:path];
      if (image) {
        return image;
      }
    }
  }

  return [self imageNamed:[[path lastPathComponent] stringByDeletingPathExtension]
        inApplicationPath:path];
}

+ (NSImage *)iconForDesktopFile:(NSString *)path
{
  NSString *contents = [NSString stringWithContentsOfFile:path];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];
  NSArray *searchPaths = [NSArray arrayWithObjects:
    [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Resources"],
    [path stringByDeletingLastPathComponent],
    @"/usr/GNUstep/Local/Applications",
    @"/usr/GNUstep/System/Applications",
    @"/usr/GNUstep/Local/Library/WindowMaker/Icons",
    @"/usr/GNUstep/System/Library/WindowMaker/Icons",
    nil];
  NSUInteger i, j;

  for (i = 0; i < [lines count]; i++) {
    NSString *line = [lines objectAtIndex:i];
    NSString *iconName;

    if (![line hasPrefix:@"Icon="]) {
      continue;
    }

    iconName = [line substringFromIndex:5];
    if ([iconName isAbsolutePath]) {
      NSImage *image = [self imageAtPath:iconName];
      if (image) {
        return image;
      }
    }

    for (j = 0; j < [searchPaths count]; j++) {
      NSImage *image = [self imageNamed:iconName inApplicationPath:[searchPaths objectAtIndex:j]];
      if (image) {
        return image;
      }
    }
  }

  return nil;
}

+ (NSImage *)fallbackApplicationIcon
{
  NSArray *paths = [NSArray arrayWithObjects:
    @"/home/heron/Development/gs-wmaker/WindowMaker/Icons/GNUstep.tiff",
    @"/usr/GNUstep/Local/Library/WindowMaker/Icons/GNUstep.tiff",
    @"/usr/GNUstep/System/Library/WindowMaker/Icons/GNUstep.tiff",
    nil];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    NSImage *image = [self imageAtPath:[paths objectAtIndex:i]];
    if (image) {
      return image;
    }
  }

  return [self imageIsDrawable:[NSImage imageNamed:@"NSApplicationIcon"]]
    ? [NSImage imageNamed:@"NSApplicationIcon"] : nil;
}

+ (id)applicationItemWithPath:(NSString *)path
{
  DockItem *item = [[[self alloc] init] autorelease];
  NSImage *icon = nil;
  NSString *bundlePath = [self applicationBundlePathForPath:path];
  NSString *iconPath = bundlePath ? bundlePath : path;

  if (bundlePath) {
    icon = [self iconForApplicationPath:bundlePath];
  }
  if (!icon && [[[path pathExtension] lowercaseString] isEqualToString:@"desktop"]) {
    icon = [self iconForDesktopFile:path];
  }
  if (!icon) {
    icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    if (![self imageIsDrawable:icon]) {
      icon = nil;
    }
  }
  if (!icon) {
    icon = [[NSWorkspace sharedWorkspace] iconForFileType:[path pathExtension]];
    if (![self imageIsDrawable:icon]) {
      icon = nil;
    }
  }
  if (!icon) {
    icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"app"];
    if (![self imageIsDrawable:icon]) {
      icon = nil;
    }
  }
  if (!icon) {
    icon = [self fallbackApplicationIcon];
  }

  item->_kind = DockItemApplication;
  item->_state = DockItemNotRunning;
  item->_path = [path copy];
  item->_iconPath = [iconPath copy];
  item->_title = [[[path lastPathComponent] stringByDeletingPathExtension] copy];
  item->_icon = [icon retain];
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = [[[DockTileIconView alloc]
      initWithFrame:NSMakeRect(0, 0, 46, 46)] autorelease];
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}

+ (id)x11ItemWithTitle:(NSString *)title window:(unsigned long)xWindow icon:(NSImage *)icon hidden:(BOOL)hidden
{
  DockItem *item = [[[self alloc] init] autorelease];
  item->_kind = DockItemX11Window;
  item->_state = hidden ? DockItemHidden : DockItemRunning;
  item->_xWindow = xWindow;
  item->_title = [[title length] ? title : [NSString stringWithFormat:@"0x%lx", xWindow] copy];
  item->_icon = [icon retain];
  item->_dockTile = [[NSDockTile alloc] init];
  [item->_dockTile setOwner:item];
  {
    DockTileIconView *iconView = [[[DockTileIconView alloc]
      initWithFrame:NSMakeRect(0, 0, 46, 46)] autorelease];
    [iconView setIcon:icon];
    [iconView setTitle:item->_title];
    [item->_dockTile setContentView:iconView];
  }
  return item;
}

- (void)dealloc
{
  [_title release];
  [_path release];
  [_iconPath release];
  [_icon release];
  [_dockTile release];
  [super dealloc];
}

- (DockItemKind)kind { return _kind; }
- (DockItemState)state { return _state; }
- (void)setState:(DockItemState)state { _state = state; }
- (NSString *)title { return _title; }
- (NSString *)path { return _path; }
- (NSString *)iconPath { return _iconPath; }
- (NSImage *)icon { return _icon; }
- (BOOL)iconMatchesImage:(NSImage *)image
{
  NSData *currentData;
  NSData *newData;

  if (_icon == image) {
    return YES;
  }
  if (!_icon || !image) {
    return NO;
  }

  currentData = [_icon TIFFRepresentation];
  newData = [image TIFFRepresentation];
  return currentData && newData && [currentData isEqualToData:newData];
}

- (void)setIcon:(NSImage *)icon
{
  if (![self iconMatchesImage:icon]) {
    [_icon release];
    _icon = [icon retain];
    if ([[_dockTile contentView] respondsToSelector:@selector(setIcon:)]) {
      [(DockTileIconView *)[_dockTile contentView] setIcon:icon];
    }
    [_dockTile display];
  }
}
- (NSDockTile *)dockTile { return _dockTile; }
- (unsigned long)xWindow { return _xWindow; }
- (void)setXWindow:(unsigned long)xWindow { _xWindow = xWindow; }

@end
