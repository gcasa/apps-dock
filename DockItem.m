#import "DockItem.h"

@implementation DockItem

+ (id)applicationItemWithPath:(NSString *)path
{
  DockItem *item = [[[self alloc] init] autorelease];
  item->_kind = DockItemApplication;
  item->_path = [path copy];
  item->_title = [[[path lastPathComponent] stringByDeletingPathExtension] copy];
  return item;
}

+ (id)x11ItemWithTitle:(NSString *)title window:(unsigned long)xWindow
{
  DockItem *item = [[[self alloc] init] autorelease];
  item->_kind = DockItemX11Window;
  item->_xWindow = xWindow;
  item->_title = [[title length] ? title : [NSString stringWithFormat:@"0x%lx", xWindow] copy];
  return item;
}

- (void)dealloc
{
  [_title release];
  [_path release];
  [super dealloc];
}

- (DockItemKind)kind { return _kind; }
- (NSString *)title { return _title; }
- (NSString *)path { return _path; }
- (unsigned long)xWindow { return _xWindow; }

@end
