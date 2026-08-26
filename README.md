# AppsDockWM

AppsDockWM is a small GNUstep/AppKit dock-style window manager shell inspired by
WindowMaker.

It supports two inputs:

- Dropping application bundles or executable paths from GNUstep tools such as
  apps-gworkspace onto the dock.
- Discovering small X11 top-level windows, including common WindowMaker
  dockapps, and reparenting them into an X11 dock host.

## Build

```sh
make
```

## Run

```sh
./AppsDockWM.app/AppsDockWM
```

The AppKit dock accepts filesystem drops. A companion X11 override-redirect host
window is created next to it for dockapps and other small X11 clients.
