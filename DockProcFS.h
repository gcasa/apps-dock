/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#ifndef DOCK_PROCFS_H
#define DOCK_PROCFS_H

#import <Foundation/NSString.h>

/* Returns the mount point of the process filesystem, or nil when none is
 * mounted.  Linux mounts one as "proc" by default; the BSDs mount "procfs"
 * only when asked to, so callers must cope with nil.
 */
NSString *DockProcFilesystemPath(void);

#endif /* DOCK_PROCFS_H */
