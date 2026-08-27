include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Dock

Dock_OBJC_FILES = \
main.m \
AppController.m \
DockView.m \
DockItem.m \
X11DockManager.m

Dock_RESOURCE_FILES = \
Resources/GNUstep.tiff \
Resources/Recycler.GNUstep.xpm

ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags x11 xext 2>/dev/null)
Dock_TOOL_LIBS += $(shell pkg-config --libs x11 xext 2>/dev/null)

include $(GNUSTEP_MAKEFILES)/application.make
