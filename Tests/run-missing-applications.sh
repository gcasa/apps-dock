#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
clang $(gnustep-config --objc-flags) Tests/MissingApplications.m \
  obj/DockWM.obj/DockApplicationStore.m.o \
  obj/DockWM.obj/DockItem.m.o \
  obj/DockWM.obj/DockItem+Factory.m.o \
  obj/DockWM.obj/DockItem+Icons.m.o \
  obj/DockWM.obj/DockPreferences.m.o \
  obj/DockWM.obj/RunningApplicationScanner.m.o \
  -o /tmp/dock-missing-tests $(gnustep-config --gui-libs)
xvfb-run -a /tmp/dock-missing-tests
