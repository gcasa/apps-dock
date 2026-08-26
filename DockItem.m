#import "DockItem.h"

@implementation DockItem

+ (id)applicationItemWithPath:(NSString *)path
{
  DockItem *item = [[[self alloc] init] autorelease];
  item->_kind = DockItemApplication;
  item->_state = DockItemNotRunning;
  item->_path = [path copy];
  item->_title = [[[path lastPathComponent] stringByDeletingPathExtension] copy];
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
  return item;
}

- (void)dealloc
{
  [_title release];
  [_path release];
  [_icon release];
  [super dealloc];
}

- (DockItemKind)kind { return _kind; }
- (DockItemState)state { return _state; }
- (void)setState:(DockItemState)state { _state = state; }
- (NSString *)title { return _title; }
- (NSString *)path { return _path; }
- (NSImage *)icon { return _icon; }
- (void)setIcon:(NSImage *)icon
{
  if (_icon != icon) {
    [_icon release];
    _icon = [icon retain];
  }
}
- (unsigned long)xWindow { return _xWindow; }
- (void)setXWindow:(unsigned long)xWindow { _xWindow = xWindow; }

@end
