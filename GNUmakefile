include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = DockWM

DockWM_OBJC_FILES = \
main.m \
AppController.m \
DockView.m \
DockItem.m \
X11DockManager.m

DockWM_RESOURCE_FILES = \
Resources/GNUstep.tiff \
Resources/Recycler.GNUstep.xpm \
Resources/gnustep_whale.png \
Resources/GNUstep_circle.png

ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags x11 xext 2>/dev/null)
DockWM_TOOL_LIBS += $(shell pkg-config --libs x11 xext 2>/dev/null)

include $(GNUSTEP_MAKEFILES)/application.make
