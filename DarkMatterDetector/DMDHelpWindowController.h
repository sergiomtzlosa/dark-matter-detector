#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Programmatic field guide for the simulator. The controller owns a single
 * reusable help window; closing it only orders the window out so it can be
 * reopened from the Help menu or the in-viewport help button.
 */
@interface DMDHelpWindowController : NSWindowController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
