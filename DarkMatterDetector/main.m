#import <Cocoa/Cocoa.h>

#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];

        // The delegate is deliberately kept alive for the entire run loop.
        // NSApplication's delegate property is weak, so a stack local alone
        // would be unsafe if the application ever reloaded its delegate.
        static AppDelegate *appDelegate = nil;
        appDelegate = [[AppDelegate alloc] init];
        application.delegate = appDelegate;

        [application run];
    }

    return EXIT_SUCCESS;
}
