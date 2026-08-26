#import <AppKit/AppKit.h>

typedef enum {
  DockItemApplication,
  DockItemX11Window
} DockItemKind;

typedef enum {
  DockItemNotRunning,
  DockItemRunning,
  DockItemHidden
} DockItemState;

@interface DockItem : NSObject
{
  DockItemKind _kind;
  DockItemState _state;
  NSString *_title;
  NSString *_path;
  NSString *_iconPath;
  NSImage *_icon;
  unsigned long _xWindow;
}

+ (id)applicationItemWithPath:(NSString *)path;
+ (id)x11ItemWithTitle:(NSString *)title window:(unsigned long)xWindow icon:(NSImage *)icon hidden:(BOOL)hidden;

- (DockItemKind)kind;
- (DockItemState)state;
- (void)setState:(DockItemState)state;
- (NSString *)title;
- (NSString *)path;
- (NSString *)iconPath;
- (NSImage *)icon;
- (void)setIcon:(NSImage *)icon;
- (unsigned long)xWindow;
- (void)setXWindow:(unsigned long)xWindow;

@end
