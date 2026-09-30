#import <AppKit/AppKit.h>
#import "DockApplicationStore.h"
#import "DockItem.h"
#import "DockPreferences.h"
#import "RunningApplicationScanner.h"
#include <stdlib.h>

/* Run under an isolated X server; use volatile defaults, never DockWM's domain. */
int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  NSSetUncaughtExceptionHandler(NULL);
  char directory[] = "/tmp/dock-missing-tests-XXXXXX";
  NSCAssert(mkdtemp(directory) != NULL, @"Create fixture directory");
  NSString *root = [NSString stringWithUTF8String:directory];
  NSString *first = [root stringByAppendingPathComponent:@"First.app"];
  NSString *missing = [root stringByAppendingPathComponent:@"Missing.app"];
  NSString *last = [root stringByAppendingPathComponent:@"Last.app"];
  NSFileManager *files = [NSFileManager defaultManager];
  [files createDirectoryAtPath:first withIntermediateDirectories:YES attributes:nil error:NULL];
  [files createDirectoryAtPath:last withIntermediateDirectories:YES attributes:nil error:NULL];
  NSDictionary *record = [NSDictionary dictionaryWithObjectsAndKeys:
    missing, @"Path", @"--test argument", @"Arguments",
    [NSNumber numberWithBool:NO], @"UseBehaviorDefaults",
    [NSNumber numberWithBool:NO], @"WigglesOnLaunch", nil];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithObject:
    [NSArray arrayWithObjects:first, record, last, nil] forKey:@"DockApplications"];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeVolatileDomainForName:NSArgumentDomain];
  [defaults setVolatileDomain:domain forName:NSArgumentDomain];
  DockPreferences *preferences = [DockPreferences new];
  NSCAssert([preferences savedKeepsMissingApplications], @"Enabled by default");
  RunningApplicationScanner *scanner = [RunningApplicationScanner new];
  DockApplicationStore *store = [[DockApplicationStore alloc] initWithScanner:scanner];
  NSMutableArray *items = [NSMutableArray array];
  [store loadPersistedApplicationsIntoItems:items];
  NSCAssert([items count] == 3, @"Missing entry retained");
  DockItem *item = [items objectAtIndex:1];
  NSCAssert([[item path] isEqual:missing] && [item isMissing] && [item isPinned], @"Placeholder retains position and path");
  NSCAssert([[item launchArguments] isEqual:@"--test argument"] && ![item wigglesOnLaunch], @"Settings preserved");
  NSDictionary *saved = [store persistedApplicationRecordForItem:item];
  NSCAssert([[saved objectForKey:@"Path"] isEqual:missing] && [[saved objectForKey:@"Arguments"] isEqual:@"--test argument"], @"Missing entry serializes");
  [store loadPersistedApplicationsIntoItems:items];
  NSCAssert([items count] == 3, @"No duplicates on reload");
  [files createDirectoryAtPath:missing withIntermediateDirectories:YES attributes:nil error:NULL];
  NSCAssert([item refreshMissingState] && ![item isMissing] && [item icon], @"Restored application regains icon");
  NSString *moved = [root stringByAppendingPathComponent:@"Moved.app"];
  [files moveItemAtPath:missing toPath:moved error:NULL];
  NSCAssert([item refreshMissingState] && [item isMissing], @"Moving an application is detected");
  NSCAssert(![item refreshMissingState], @"Unchanged scans do not trigger refreshes");
  [domain setObject:[NSNumber numberWithBool:NO] forKey:@"DockKeepsMissingApplications"];
  [defaults removeVolatileDomainForName:NSArgumentDomain];
  [defaults setVolatileDomain:domain forName:NSArgumentDomain];
  NSCAssert(![preferences savedKeepsMissingApplications], @"Opt-out is read");
  [items removeAllObjects];
  [store loadPersistedApplicationsIntoItems:items];
  NSCAssert([items count] == 2 && [[[items objectAtIndex:1] path] isEqual:last], @"Disabled setting omits missing entries");
  [files removeItemAtPath:root error:NULL];
  [store release];
  [scanner release];
  [preferences release];
  NSLog(@"Missing application tests passed");
  [pool drain];
  return 0;
}
