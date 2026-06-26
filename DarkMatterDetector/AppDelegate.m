#import "AppDelegate.h"

#import "DMDHelpWindowController.h"
#import "ViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong, nullable) DMDHelpWindowController *helpWindowController;
@end

@implementation AppDelegate

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    (void)app;
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self buildMainMenu];

    // The original 1000x650 window left the 3D cutaway feeling cramped. Use
    // most of the current display while keeping a safety margin so the window
    // is still fully visible with the menu bar and Dock.
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    CGFloat contentWidth = 1440.0;
    CGFloat contentHeight = 792.0;
    if (screen) {
        NSRect visibleFrame = screen.visibleFrame;
        contentWidth = MIN(contentWidth, MAX(900.0, visibleFrame.size.width - 64.0));
        contentHeight = MIN(contentHeight, MAX(600.0, visibleFrame.size.height - 64.0));
    }

    NSRect contentRect = NSMakeRect(0.0, 0.0, contentWidth, contentHeight);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled
                                | NSWindowStyleMaskClosable
                                | NSWindowStyleMaskMiniaturizable
                                | NSWindowStyleMaskResizable;

    self.window = [[NSWindow alloc] initWithContentRect:contentRect
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Dark Matter Detector Application Simulator";
    self.window.minSize = NSMakeSize(MIN(1080.0, contentWidth),
                                     MIN(680.0, contentHeight + 28.0));
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.backgroundColor = [NSColor colorWithSRGBRed:0.031
                                                       green:0.051
                                                        blue:0.094
                                                       alpha:1.0];
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    ViewController *viewController = [[ViewController alloc] init];
    self.window.contentViewController = viewController;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    BOOL autoHelpByButton = [environment[@"DMD_AUTO_HELP_BUTTON"] boolValue];
    if (!autoHelpByButton &&
        ([environment[@"DMD_AUTO_HELP"] boolValue] ||
         environment[@"DMD_HELP_SNAPSHOT_PATH"].length > 0)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self showHelpWindow:self];
        });
    }

    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender;
    (void)flag;
    if (!self.window.isVisible) {
        [self.window makeKeyAndOrderFront:nil];
    }
    return YES;
}

- (IBAction)showHelpWindow:(id)sender {
    if (!self.helpWindowController) {
        self.helpWindowController = [[DMDHelpWindowController alloc] init];
    }

    [NSApp activateIgnoringOtherApps:YES];
    [self.helpWindowController showWindow:sender];
    if (self.helpWindowController.window.isMiniaturized) {
        [self.helpWindowController.window deminiaturize:sender];
    }
    [self.helpWindowController.window makeKeyAndOrderFront:sender];
}

#pragma mark - Menu

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Dark Matter Detector"];
    [appMenu addItemWithTitle:@"About Dark Matter Detector"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:@"Hide Dark Matter Detector"
                                                      action:@selector(hide:)
                                               keyEquivalent:@"h"];
    [appMenu addItem:hideItem];

    NSMenuItem *hideOthersItem = [[NSMenuItem alloc] initWithTitle:@"Hide Others"
                                                            action:@selector(hideOtherApplications:)
                                                     keyEquivalent:@"h"];
    hideOthersItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [appMenu addItem:hideOthersItem];

    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Dark Matter Detector"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    appMenuItem.submenu = appMenu;

    // Edit menu: the programmatic terminal remains selectable and copyable.
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
    NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo"
                                                      action:NSSelectorFromString(@"redo:")
                                               keyEquivalent:@"z"];
    redoItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:redoItem];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    // Window menu.
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window"
                                                           action:nil
                                                    keyEquivalent:@""];
    [mainMenu addItem:windowMenuItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowMenuItem.submenu = windowMenu;

    // Standard Help menu. The field guide is a separate reusable dark window
    // built entirely in code; the standard Help shortcut (⌘?) opens it.
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] initWithTitle:@"Help"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:helpMenuItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *howItWorksItem = [[NSMenuItem alloc]
        initWithTitle:@"How This Simulator Works"
               action:@selector(showHelpWindow:)
        keyEquivalent:@"?"];
    howItWorksItem.target = self;
    [helpMenu addItem:howItWorksItem];
    helpMenuItem.submenu = helpMenu;

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
    NSApp.helpMenu = helpMenu;
}

@end
