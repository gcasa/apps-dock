include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = DockWM

DockWM_OBJC_FILES = \
main.m \
AppController.m \
AppController+Applications.m \
AppController+DockViewDelegate.m \
AppController+Icons.m \
AppController+Launching.m \
AppController+Layout.m \
AppController+Preferences.m \
AppController+Recycler.m \
AppController+Scanning.m \
AppController+Settings.m \
AppController+X11Delegate.m \
SettingsController.m \
DockPreferences.m \
RunningApplicationScanner.m \
RecyclerController.m \
DockApplicationStore.m \
ApplicationIconManager.m \
DockView.m \
DockItem.m \
X11DockManager.m

DockWM_APPLICATION_ICON = DockWM.tiff

DockWM_RESOURCE_FILES = \
Resources/DockWM.tiff \
Resources/GNUstep.tiff \
Resources/Recycler.GNUstep.xpm \
Resources/gnustep_whale.png \
Resources/GNUstep_circle.png

ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags x11 xext 2>/dev/null)
DockWM_TOOL_LIBS += $(shell pkg-config --libs x11 xext 2>/dev/null)

include $(GNUSTEP_MAKEFILES)/application.make
