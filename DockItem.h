#import <Foundation/Foundation.h>

typedef enum {
  DockItemApplication,
  DockItemX11Window
} DockItemKind;

@interface DockItem : NSObject
{
  DockItemKind _kind;
  NSString *_title;
  NSString *_path;
  unsigned long _xWindow;
}

+ (id)applicationItemWithPath:(NSString *)path;
+ (id)x11ItemWithTitle:(NSString *)title window:(unsigned long)xWindow;

- (DockItemKind)kind;
- (NSString *)title;
- (NSString *)path;
- (unsigned long)xWindow;

@end
