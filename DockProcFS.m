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

#import "DockProcFS.h"

#ifdef __linux__
#import <mntent.h>
#import <paths.h>
#import <stdio.h>
#else
#import <sys/param.h>
#import <sys/ucred.h>
#import <sys/mount.h>
#endif
#import <string.h>

NSString *
DockProcFilesystemPath(void)
{
#ifdef __linux__
  FILE *mounts;
  struct mntent *entry;
  NSString *path = nil;

  mounts = setmntent(_PATH_MOUNTED, "r");
  if (!mounts)
    {
      return nil;
    }

  while ((entry = getmntent(mounts)) != NULL)
    {
      if (entry->mnt_type && strcmp(entry->mnt_type, "proc") == 0 &&
	  entry->mnt_dir)
	{
	  path = [NSString stringWithUTF8String:entry->mnt_dir];
	  break;
	}
    }

  endmntent(mounts);
  return [path length] ? path : nil;
#else
  /* The BSDs have no mntent(3).  getmntinfo(3) hands back a statically
   * allocated array that must not be freed, and names the filesystem
   * "procfs" where Linux names it "proc".
   */
  struct statfs *mounts;
  int count;
  int i;

  count = getmntinfo(&mounts, MNT_NOWAIT);
  for (i = 0; i < count; i++)
    {
      if (strcmp(mounts[i].f_fstypename, "procfs") == 0)
	{
	  return [NSString stringWithUTF8String:mounts[i].f_mntonname];
	}
    }

  return nil;
#endif
}
