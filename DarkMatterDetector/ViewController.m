#import "ViewController.h"

#import <SceneKit/SceneKit.h>

#import "AppDelegate.h"
#import "DMDComponentOverlayView.h"
#import "DMDDetectorPart.h"
#import "DMDPhysicsConstants.h"
#import "DetectorSceneBuilder.h"
#import "DetectorSimulationEngine.h"

typedef NS_ENUM(NSInteger, DMDLogKind) {
    DMDLogKindInfo,
    DMDLogKindDetail,
    DMDLogKindTrigger,
    DMDLogKindWarning,
    DMDLogKindAlert,
    DMDLogKindVeto,
    DMDLogKindSuccess
};

static NSColor *DMDInterfaceColor(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:(CGFloat)((rgb >> 16) & 0xFF) / 255.0
                                green:(CGFloat)((rgb >> 8) & 0xFF) / 255.0
                                 blue:(CGFloat)(rgb & 0xFF) / 255.0
                                alpha:alpha];
}

static double DMDUniform01(void) {
    return (double)arc4random() / (double)UINT32_MAX;
}

static NSFont *DMDMonospacedFont(CGFloat size, NSFontWeight weight) {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

/** The HUD must never steal orbit/zoom drags from the SCNView. */
@interface DMDPassthroughView : NSView
@end

@implementation DMDPassthroughView

- (nullable NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

@end

@interface ViewController ()

@property (nonatomic, strong) DetectorSimulationEngine *engine;
@property (nonatomic, strong) DMDDetectorSceneContext *sceneContext;
@property (nonatomic, strong) SCNView *sceneView;
@property (nonatomic, strong) DMDComponentOverlayView *componentOverlay;
@property (nonatomic, strong, nullable) DMDDetectorPart *selectedPart;
@property (nonatomic, strong, nullable) SCNNode *selectionMarker;
@property (nonatomic, strong, nullable) NSTimer *overlayTimer;

@property (nonatomic, strong) NSPopUpButton *particlePopup;
@property (nonatomic, strong) NSSlider *densitySlider;
@property (nonatomic, strong) NSSlider *fieldSlider;
@property (nonatomic, strong) NSTextField *densityValueLabel;
@property (nonatomic, strong) NSTextField *fieldValueLabel;
@property (nonatomic, strong) NSTextField *derivedLabel;
@property (nonatomic, strong) NSButton *fireButton;
@property (nonatomic, strong) NSButton *centerViewButton;
@property (nonatomic, strong) NSButton *helpButton;
@property (nonatomic, strong) NSTextView *terminalTextView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *hudTitleLabel;
@property (nonatomic, strong) NSTextField *hudDetailLabel;
@property (nonatomic, strong) NSTextField *componentInfoLabel;

@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, assign) BOOL eventInProgress;
@property (nonatomic, assign) BOOL continuousFiring;
@property (nonatomic, assign) NSUInteger eventSerial;
@property (nonatomic, assign) BOOL driftStarted;
@property (nonatomic, assign) BOOL s2FlashStarted;
@property (nonatomic, assign) BOOL didScheduleSnapshot;

- (void)updateFireButtonAppearance;
- (void)startContinuousFiring;
- (void)stopContinuousFiring;
- (void)triggerEventIfIdle;
- (void)beginSingleEvent;

@end

@implementation ViewController

#pragma mark - Lifecycle and root layout

- (void)loadView {
    // This app intentionally has no storyboard or XIB. The root view, the
    // sidebar, every control, and every constraint are created here.
    NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1440.0, 792.0)];
    rootView.wantsLayer = YES;
    rootView.layer.backgroundColor = DMDInterfaceColor(0x060B14, 1.0).CGColor;
    rootView.autoresizesSubviews = YES;
    self.view = rootView;

    [self buildSceneView];
    [self buildComponentOverlay];
    [self buildHUD];

    [NSLayoutConstraint activateConstraints:@[
        [self.sceneView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
        [self.sceneView.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [self.sceneView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
    ]];

    // 280 pt configuration sidebar plus a 1 pt high-contrast divider.
    NSView *divider = [[NSView alloc] initWithFrame:NSZeroRect];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = DMDInterfaceColor(0x1B3042, 1.0).CGColor;
    [rootView addSubview:divider];

    NSView *sidebar = [[NSView alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.wantsLayer = YES;
    sidebar.layer.backgroundColor = DMDInterfaceColor(0x0B1320, 1.0).CGColor;
    [rootView addSubview:sidebar];

    [NSLayoutConstraint activateConstraints:@[
        [self.sceneView.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],

        [divider.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        [divider.widthAnchor constraintEqualToConstant:1.0],

        [sidebar.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [sidebar.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:280.0],
    ]];

    // The sidebar stack is pinned inside the container, then every arranged
    // child is stretched to the stack width. This keeps the controls aligned
    // while still allowing the terminal to consume the remaining height.
    NSStackView *stack = [self buildSidebarStack];
    [sidebar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:16.0],
        [stack.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-14.0],
    ]];

    [self buildSceneOverlaysInRoot:rootView];
}

- (void)viewDidAppear {
    [super viewDidAppear];

    [self startOverlayTimerIfNeeded];

    // Debug-only visual QA hook. When the environment variable is set, the
    // app writes both the composited UI and a native SceneKit render to PNG
    // and exits. This has no effect during normal use.
    NSString *snapshotPath = NSProcessInfo.processInfo.environment[@"DMD_SNAPSHOT_PATH"];
    if (snapshotPath.length == 0 || self.didScheduleSnapshot) {
        return;
    }
    self.didScheduleSnapshot = YES;

    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    if ([environment[@"DMD_AUTO_FIRE"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self beginSingleEvent];
        });
    }

    if ([environment[@"DMD_AUTO_HELP_BUTTON"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.helpButton performClick:nil];
        });
    }

    if ([environment[@"DMD_AUTO_CONTINUOUS_FIRE"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.fireButton performClick:nil];
        });
    }

    if (environment[@"DMD_AUTO_STOP_FIRE_AFTER"].length > 0) {
        double stopDelay = MAX(0.8, environment[@"DMD_AUTO_STOP_FIRE_AFTER"].doubleValue);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stopDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self.continuousFiring) {
                [self.fireButton performClick:nil];
            }
        });
    }

    if ([environment[@"DMD_AUTO_CAMERA_OFFSET"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SCNNode *cameraNode = self.sceneContext.cameraNode;
            cameraNode.position = SCNVector3Make(-9.0, 7.5, 19.0);
            [cameraNode lookAt:SCNVector3Make(1.5, 0.2, 0.0)];
            cameraNode.camera.fieldOfView = 52.0;
        });
    }

    if ([environment[@"DMD_AUTO_CENTER"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.centerViewButton performClick:nil];
        });
    }

    if ([environment[@"DMD_AUTO_LIVE_SLIDERS"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self.densitySlider.doubleValue = 3.70;
            [self.densitySlider sendAction:self.densitySlider.action
                                        to:self.densitySlider.target];
            self.fieldSlider.doubleValue = 1.45;
            [self.fieldSlider sendAction:self.fieldSlider.action
                                      to:self.fieldSlider.target];
        });
    }

    if (environment[@"DMD_AUTO_INSPECT"].length > 0) {
        NSInteger index = environment[@"DMD_AUTO_INSPECT"].integerValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self inspectPartAtIndex:index];
        });
    }

    double delay = 2.0;
    if (environment[@"DMD_SNAPSHOT_DELAY"].length > 0) {
        delay = MAX(0.5, environment[@"DMD_SNAPSHOT_DELAY"].doubleValue);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self writeDebugSnapshotToPath:snapshotPath];
        [NSApp terminate:nil];
    });
}

- (void)writeDebugSnapshotToPath:(NSString *)path {
    NSString *base = path.stringByDeletingPathExtension;
    NSString *extension = path.pathExtension.length > 0 ? path.pathExtension : @"png";

    NSView *rootView = self.view;
    NSBitmapImageRep *uiRep = [rootView bitmapImageRepForCachingDisplayInRect:rootView.bounds];
    if (uiRep) {
        [rootView cacheDisplayInRect:rootView.bounds toBitmapImageRep:uiRep];
        NSData *uiData = [uiRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [uiData writeToFile:[NSString stringWithFormat:@"%@-ui.%@", base, extension] atomically:YES];
    }

    NSImage *sceneImage = [self.sceneView snapshot];
    NSData *tiffData = sceneImage.TIFFRepresentation;
    if (tiffData) {
        NSBitmapImageRep *sceneRep = [NSBitmapImageRep imageRepWithData:tiffData];
        NSData *sceneData = [sceneRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [sceneData writeToFile:[NSString stringWithFormat:@"%@-scene.%@", base, extension] atomically:YES];
    }

    // Core Animation-backed SCNView content is omitted by cacheDisplayInRect,
    // so the debug UI image alone is black in the 3D region. Compose the native
    // scene render back underneath the sibling AppKit overlays for visual QA.
    NSImage *composite = [[NSImage alloc] initWithSize:rootView.bounds.size];
    [composite lockFocus];
    [DMDInterfaceColor(0x060B14, 1.0) setFill];
    NSRectFill(rootView.bounds);
    NSRect sceneFrame = [self.sceneView convertRect:self.sceneView.bounds toView:rootView];
    [sceneImage drawInRect:sceneFrame
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0];
    for (NSView *subview in rootView.subviews) {
        if (subview == self.sceneView || subview.hidden) {
            continue;
        }
        NSBitmapImageRep *rep = [subview bitmapImageRepForCachingDisplayInRect:subview.bounds];
        if (!rep) {
            continue;
        }
        [subview cacheDisplayInRect:subview.bounds toBitmapImageRep:rep];
        NSImage *image = [[NSImage alloc] initWithSize:subview.bounds.size];
        [image addRepresentation:rep];
        NSRect frame = [subview convertRect:subview.bounds toView:rootView];
        [image drawInRect:frame
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1.0];
    }
    [composite unlockFocus];
    NSBitmapImageRep *compositeRep = [NSBitmapImageRep imageRepWithData:composite.TIFFRepresentation];
    NSData *compositeData = [compositeRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [compositeData writeToFile:[NSString stringWithFormat:@"%@-composite.%@", base, extension] atomically:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.engine = [[DetectorSimulationEngine alloc] init];
    self.timeFormatter = [[NSDateFormatter alloc] init];
    self.timeFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    self.timeFormatter.dateFormat = @"HH:mm:ss.SSS";

    DetectorSceneBuilder *builder = [[DetectorSceneBuilder alloc] init];
    self.sceneContext = [builder buildScene];
    self.sceneView.scene = self.sceneContext.scene;
    self.sceneView.pointOfView = self.sceneContext.cameraNode;
    self.sceneView.backgroundColor = self.sceneContext.backgroundColor;

    self.componentOverlay.sceneView = self.sceneView;
    self.componentOverlay.detectorRoot = self.sceneContext.detectorRoot;
    self.componentOverlay.parts = self.sceneContext.parts;
    [self.componentOverlay refreshProjection];

    [self refreshConfigurationReadout];
    [self appendBootSequence];
    [self setStatus:@"READY" color:DMDInterfaceColor(0x69E5FF, 1.0)];
}

- (void)dealloc {
    [self.overlayTimer invalidate];
}

- (void)startOverlayTimerIfNeeded {
    if (self.overlayTimer) {
        return;
    }
    // A main-run-loop timer keeps callouts glued to their 3D anchors while the
    // camera orbits. Common modes are required so drag tracking does not pause
    // projection updates mid-gesture.
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                           repeats:YES
                                             block:^(NSTimer *strongTimer) {
        (void)strongTimer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.componentOverlay refreshProjection];
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.overlayTimer = timer;
}

#pragma mark - Programmatic scene view

- (void)buildSceneView {
    self.sceneView = [[SCNView alloc] initWithFrame:NSZeroRect];
    self.sceneView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sceneView.backgroundColor = DMDInterfaceColor(0x050B16, 1.0);
    self.sceneView.allowsCameraControl = YES;
    self.sceneView.autoenablesDefaultLighting = NO;
    self.sceneView.showsStatistics = NO;
    self.sceneView.preferredFramesPerSecond = 60;
    self.sceneView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    self.sceneView.rendersContinuously = YES;
    [self.view addSubview:self.sceneView];
}

- (void)buildComponentOverlay {
    self.componentOverlay = [[DMDComponentOverlayView alloc] initWithFrame:NSZeroRect];
    self.componentOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.componentOverlay];

    __weak typeof(self) weakSelf = self;
    self.componentOverlay.partSelectedHandler = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf inspectPartAtIndex:index];
    };

    [NSLayoutConstraint activateConstraints:@[
        [self.componentOverlay.leadingAnchor constraintEqualToAnchor:self.sceneView.leadingAnchor],
        [self.componentOverlay.trailingAnchor constraintEqualToAnchor:self.sceneView.trailingAnchor],
        [self.componentOverlay.topAnchor constraintEqualToAnchor:self.sceneView.topAnchor],
        [self.componentOverlay.bottomAnchor constraintEqualToAnchor:self.sceneView.bottomAnchor],
    ]];
}

#pragma mark - Programmatic sidebar

- (NSStackView *)buildSidebarStack {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 10.0;
    stack.detachesHiddenViews = YES;

    NSTextField *eyebrow = [self makeLabel:@"LIQUID XENON TPC"
                                    font:DMDMonospacedFont(9.0, NSFontWeightSemibold)
                                   color:DMDInterfaceColor(0x53DDF5, 1.0)];
    [stack addArrangedSubview:eyebrow];

    NSTextField *title = [self makeLabel:@"LZ Dark Matter Simulator"
                                   font:[NSFont systemFontOfSize:20.0 weight:NSFontWeightBold]
                                  color:DMDInterfaceColor(0xF4F8FF, 1.0)];
    title.maximumNumberOfLines = 2;
    title.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:title];
    [stack setCustomSpacing:2.0 afterView:title];

    NSTextField *subtitle = [self makeLabel:@"LUX-ZEPLIN–inspired event simulator"
                                      font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]
                                     color:DMDInterfaceColor(0x8295AD, 1.0)];
    subtitle.maximumNumberOfLines = 2;
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:subtitle];
    [stack setCustomSpacing:12.0 afterView:subtitle];

    NSView *topDivider = [self makeDivider];
    [stack addArrangedSubview:topDivider];
    [stack setCustomSpacing:9.0 afterView:topDivider];

    NSTextField *particleTitle = [self makeSectionTitle:@"INCIDENT PARTICLE"];
    [stack addArrangedSubview:particleTitle];
    [stack setCustomSpacing:5.0 afterView:particleTitle];

    self.particlePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.particlePopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.particlePopup.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    self.particlePopup.controlSize = NSControlSizeRegular;
    self.particlePopup.accessibilityIdentifier = @"particlePopup";
    [self.particlePopup addItemsWithTitles:@[
        @"WIMP",
        @"Background Neutron",
        @"Cosmic Ray Electron"
    ]];
    [self.particlePopup selectItemAtIndex:0];
    self.particlePopup.target = self;
    self.particlePopup.action = @selector(particleTypeChanged:);
    [stack addArrangedSubview:self.particlePopup];
    [stack setCustomSpacing:11.0 afterView:self.particlePopup];

    self.densityValueLabel = [self makeValueLabel];
    NSView *densityRow = [self makeValueRowWithTitle:@"LIQUID XENON DENSITY"
                                          valueLabel:self.densityValueLabel];
    [stack addArrangedSubview:densityRow];
    [stack setCustomSpacing:5.0 afterView:densityRow];

    self.densitySlider = [NSSlider sliderWithValue:DMDReferenceDensityGPerCm3
                                         minValue:DMDDensityMinGPerCm3
                                         maxValue:DMDDensityMaxGPerCm3
                                           target:self
                                           action:@selector(densitySliderChanged:)];
    self.densitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    // Continuous actions keep the value labels, derived drift readout, HUD,
    // and next-shot configuration live while the thumb is dragged.
    self.densitySlider.continuous = YES;
    self.densitySlider.controlSize = NSControlSizeSmall;
    self.densitySlider.numberOfTickMarks = 0;
    self.densitySlider.accessibilityIdentifier = @"densitySlider";
    [stack addArrangedSubview:self.densitySlider];
    [stack setCustomSpacing:11.0 afterView:self.densitySlider];

    self.fieldValueLabel = [self makeValueLabel];
    NSView *fieldRow = [self makeValueRowWithTitle:@"DRIFT FIELD VOLTAGE"
                                       valueLabel:self.fieldValueLabel];
    [stack addArrangedSubview:fieldRow];
    [stack setCustomSpacing:5.0 afterView:fieldRow];

    self.fieldSlider = [NSSlider sliderWithValue:DMDReferenceFieldKVPerCm
                                       minValue:DMDDriftFieldMinKVPerCm
                                       maxValue:DMDDriftFieldMaxKVPerCm
                                         target:self
                                         action:@selector(fieldSliderChanged:)];
    self.fieldSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.fieldSlider.continuous = YES;
    self.fieldSlider.controlSize = NSControlSizeSmall;
    self.fieldSlider.numberOfTickMarks = 0;
    self.fieldSlider.accessibilityIdentifier = @"fieldSlider";
    [stack addArrangedSubview:self.fieldSlider];
    [stack setCustomSpacing:8.0 afterView:self.fieldSlider];

    self.derivedLabel = [self makeLabel:@"V_DRIFT  -- mm/µs\nΔt_MAX   -- µs"
                                   font:DMDMonospacedFont(9.5, NSFontWeightRegular)
                                  color:DMDInterfaceColor(0x7E95AA, 1.0)];
    self.derivedLabel.maximumNumberOfLines = 2;
    self.derivedLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.derivedLabel];
    [stack setCustomSpacing:9.0 afterView:self.derivedLabel];

    self.fireButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.fireButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.fireButton.bordered = NO;
    self.fireButton.bezelStyle = NSBezelStyleRegularSquare;
    self.fireButton.buttonType = NSButtonTypePushOnPushOff;
    self.fireButton.wantsLayer = YES;
    self.fireButton.layer.backgroundColor = DMDInterfaceColor(0x64E5FF, 1.0).CGColor;
    self.fireButton.layer.cornerRadius = 8.0;
    self.fireButton.layer.masksToBounds = YES;
    self.fireButton.accessibilityIdentifier = @"fireButton";
    self.fireButton.keyEquivalent = @"\r";
    self.fireButton.target = self;
    self.fireButton.action = @selector(fireParticle:);
    [stack addArrangedSubview:self.fireButton];
    [stack setCustomSpacing:11.0 afterView:self.fireButton];

    NSView *logHeader = [self makeLogHeaderRow];
    [stack addArrangedSubview:logHeader];
    [stack setCustomSpacing:5.0 afterView:logHeader];

    NSScrollView *logScrollView = [self makeTerminalScrollView];
    logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    logScrollView.accessibilityIdentifier = @"terminalScrollView";
    [logScrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                               forOrientation:NSLayoutConstraintOrientationVertical];
    [logScrollView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                            forOrientation:NSLayoutConstraintOrientationVertical];
    [stack addArrangedSubview:logScrollView];
    [logScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:150.0].active = YES;
    [stack setCustomSpacing:8.0 afterView:logScrollView];

    NSTextField *footer = [self makeLabel:@"FOR EDUCATIONAL USE  •  SIMULATED DATA"
                                     font:DMDMonospacedFont(8.0, NSFontWeightRegular)
                                    color:DMDInterfaceColor(0x516579, 1.0)];
    [stack addArrangedSubview:footer];

    for (NSView *arrangedView in stack.arrangedSubviews) {
        [arrangedView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    [self.fireButton.heightAnchor constraintEqualToConstant:38.0].active = YES;
    [self.particlePopup.heightAnchor constraintEqualToConstant:26.0].active = YES;
    [self.densitySlider.heightAnchor constraintEqualToConstant:18.0].active = YES;
    [self.fieldSlider.heightAnchor constraintEqualToConstant:18.0].active = YES;

    [self updateFireButtonAppearance];

    return stack;
}

- (NSAttributedString *)actionButtonTitle:(NSString *)title
                                fontSize:(CGFloat)fontSize
                                   color:(NSColor *)color {
    return [[NSAttributedString alloc] initWithString:title
                                            attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(0.35)
    }];
}

- (NSTextField *)makeLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.drawsBackground = NO;
    label.bezeled = NO;
    label.editable = NO;
    label.selectable = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                   forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

- (NSTextField *)makeSectionTitle:(NSString *)text {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 0.0;
    NSAttributedString *attributed = [[NSAttributedString alloc]
        initWithString:text
            attributes:@{
                NSFontAttributeName: DMDMonospacedFont(8.5, NSFontWeightSemibold),
                NSForegroundColorAttributeName: DMDInterfaceColor(0x68DDF3, 1.0),
                NSKernAttributeName: @(1.1),
                NSParagraphStyleAttributeName: paragraph
            }];
    NSTextField *label = [NSTextField labelWithAttributedString:attributed];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByClipping;
    return label;
}

- (NSView *)makeDivider {
    NSView *divider = [[NSView alloc] initWithFrame:NSZeroRect];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = DMDInterfaceColor(0x1B2B3B, 1.0).CGColor;
    [divider.heightAnchor constraintEqualToConstant:1.0].active = YES;
    return divider;
}

- (NSTextField *)makeValueLabel {
    NSTextField *value = [self makeLabel:@"--"
                                    font:DMDMonospacedFont(10.0, NSFontWeightMedium)
                                   color:DMDInterfaceColor(0xE9F3FF, 1.0)];
    value.alignment = NSTextAlignmentRight;
    value.maximumNumberOfLines = 1;
    return value;
}

- (NSView *)makeValueRowWithTitle:(NSString *)title valueLabel:(NSTextField *)value {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleLabel = [self makeSectionTitle:title];
    [row addSubview:titleLabel];
    [row addSubview:value];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [value.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [value.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [value.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:6.0],
        [row.heightAnchor constraintEqualToConstant:14.0],
    ]];

    return row;
}

- (NSView *)makeLogHeaderRow {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [self makeSectionTitle:@"EVENT TELEMETRY"];
    NSButton *clearButton = [NSButton buttonWithTitle:@"CLEAR"
                                               target:self
                                               action:@selector(clearLog:)];
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    clearButton.bordered = NO;
    clearButton.font = DMDMonospacedFont(8.0, NSFontWeightMedium);
    clearButton.contentTintColor = DMDInterfaceColor(0x6E879E, 1.0);
    clearButton.toolTip = @"Clear the telemetry log.";
    [row addSubview:label];
    [row addSubview:clearButton];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [clearButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:16.0],
    ]];
    return row;
}

- (NSScrollView *)makeTerminalScrollView {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = DMDInterfaceColor(0x05090F, 1.0);
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.scrollerStyle = NSScrollerStyleOverlay;
    scrollView.borderType = NSNoBorder;
    scrollView.wantsLayer = YES;
    scrollView.layer.backgroundColor = DMDInterfaceColor(0x05090F, 1.0).CGColor;
    scrollView.layer.cornerRadius = 7.0;
    scrollView.layer.masksToBounds = YES;
    scrollView.layer.borderWidth = 1.0;
    scrollView.layer.borderColor = DMDInterfaceColor(0x1A3242, 1.0).CGColor;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 248.0, 200.0)];
    textView.drawsBackground = YES;
    textView.backgroundColor = DMDInterfaceColor(0x05090F, 1.0);
    textView.textColor = DMDInterfaceColor(0x9BCDC9, 1.0);
    textView.font = DMDMonospacedFont(10.0, NSFontWeightRegular);
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = YES;
    textView.usesFontPanel = NO;
    textView.usesFindPanel = NO;
    textView.insertionPointColor = DMDInterfaceColor(0x69E5FF, 1.0);
    textView.textContainerInset = NSMakeSize(8.0, 8.0);
    textView.textContainer.lineFragmentPadding = 0.0;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(248.0, CGFLOAT_MAX);
    textView.minSize = NSMakeSize(0.0, 0.0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.accessibilityIdentifier = @"terminalTextView";
    scrollView.documentView = textView;

    self.terminalTextView = textView;
    return scrollView;
}

#pragma mark - HUD overlay

- (void)buildHUD {
    // HUDs are added to their own passthrough containers so the SCNView keeps
    // receiving mouse-drag orbit gestures everywhere except the sidebar.
    DMDPassthroughView *hud = [[DMDPassthroughView alloc] initWithFrame:NSZeroRect];
    hud.translatesAutoresizingMaskIntoConstraints = NO;
    hud.wantsLayer = YES;
    hud.layer.backgroundColor = DMDInterfaceColor(0x08111D, 0.82).CGColor;
    hud.layer.cornerRadius = 8.0;
    hud.layer.borderWidth = 1.0;
    hud.layer.borderColor = DMDInterfaceColor(0x1C3A4A, 0.9).CGColor;

    self.hudTitleLabel = [self makeLabel:@"DARK MATTER DETECTOR  /  LZ TPC"
                                    font:DMDMonospacedFont(9.0, NSFontWeightSemibold)
                                   color:DMDInterfaceColor(0x5EE7FF, 1.0)];
    self.hudTitleLabel.maximumNumberOfLines = 1;
    self.hudDetailLabel = [self makeLabel:@"TPC ACTIVE  •  -- kV/cm  •  -- g/cm³"
                                     font:DMDMonospacedFont(9.0, NSFontWeightRegular)
                                    color:DMDInterfaceColor(0xB6C7D7, 1.0)];
    self.hudDetailLabel.maximumNumberOfLines = 2;
    self.componentInfoLabel = [self makeLabel:@"8 SYSTEMS LABELED  •  CLICK A LABEL TO ISOLATE A PART"
                                         font:DMDMonospacedFont(8.5, NSFontWeightRegular)
                                        color:DMDInterfaceColor(0x7F96AA, 1.0)];
    self.componentInfoLabel.maximumNumberOfLines = 2;
    self.componentInfoLabel.preferredMaxLayoutWidth = 326.0;

    [hud addSubview:self.hudTitleLabel];
    [hud addSubview:self.hudDetailLabel];
    [hud addSubview:self.componentInfoLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.hudTitleLabel.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:11.0],
        [self.hudTitleLabel.topAnchor constraintEqualToAnchor:hud.topAnchor constant:8.0],
        [self.hudTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:hud.trailingAnchor constant:-11.0],
        [self.hudDetailLabel.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:11.0],
        [self.hudDetailLabel.topAnchor constraintEqualToAnchor:self.hudTitleLabel.bottomAnchor constant:3.0],
        [self.hudDetailLabel.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-11.0],
        [self.componentInfoLabel.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:11.0],
        [self.componentInfoLabel.topAnchor constraintEqualToAnchor:self.hudDetailLabel.bottomAnchor constant:3.0],
        [self.componentInfoLabel.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-11.0],
        [self.componentInfoLabel.bottomAnchor constraintEqualToAnchor:hud.bottomAnchor constant:-8.0],
        [hud.widthAnchor constraintGreaterThanOrEqualToConstant:270.0],
        [hud.widthAnchor constraintLessThanOrEqualToConstant:348.0],
    ]];
    [self.view addSubview:hud];
    [NSLayoutConstraint activateConstraints:@[
        [hud.leadingAnchor constraintEqualToAnchor:self.sceneView.leadingAnchor constant:18.0],
        [hud.topAnchor constraintEqualToAnchor:self.sceneView.topAnchor constant:18.0],
    ]];

    DMDPassthroughView *statusView = [[DMDPassthroughView alloc] initWithFrame:NSZeroRect];
    statusView.translatesAutoresizingMaskIntoConstraints = NO;
    statusView.wantsLayer = YES;
    statusView.layer.backgroundColor = DMDInterfaceColor(0x08111D, 0.82).CGColor;
    statusView.layer.cornerRadius = 13.0;
    statusView.layer.borderWidth = 1.0;
    statusView.layer.borderColor = DMDInterfaceColor(0x1C3A4A, 0.9).CGColor;

    self.statusLabel = [self makeLabel:@"● READY"
                                  font:DMDMonospacedFont(9.0, NSFontWeightSemibold)
                                 color:DMDInterfaceColor(0x69E5FF, 1.0)];
    self.statusLabel.maximumNumberOfLines = 1;
    [statusView addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusView.leadingAnchor constant:11.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:statusView.trailingAnchor constant:-11.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:statusView.topAnchor constant:6.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:statusView.bottomAnchor constant:-6.0],
        [statusView.heightAnchor constraintGreaterThanOrEqualToConstant:26.0],
    ]];
    [self.view addSubview:statusView];
    [NSLayoutConstraint activateConstraints:@[
        [statusView.trailingAnchor constraintEqualToAnchor:self.sceneView.trailingAnchor constant:-18.0],
        [statusView.topAnchor constraintEqualToAnchor:self.sceneView.topAnchor constant:18.0],
    ]];

    self.helpButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.helpButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.helpButton.bordered = NO;
    self.helpButton.bezelStyle = NSBezelStyleRegularSquare;
    self.helpButton.wantsLayer = YES;
    self.helpButton.layer.backgroundColor = DMDInterfaceColor(0x08111D, 0.82).CGColor;
    self.helpButton.layer.cornerRadius = 13.0;
    self.helpButton.layer.borderWidth = 1.0;
    self.helpButton.layer.borderColor = DMDInterfaceColor(0x1C3A4A, 0.9).CGColor;
    self.helpButton.layer.masksToBounds = YES;
    self.helpButton.focusRingType = NSFocusRingTypeNone;
    self.helpButton.target = self;
    self.helpButton.action = @selector(showHelpFromViewer:);
    self.helpButton.toolTip = @"How this simulator works — open the field guide (⌘?).";
    self.helpButton.accessibilityIdentifier = @"helpButton";
    self.helpButton.accessibilityLabel = @"How this simulator works";
    [self.helpButton setAttributedTitle:
        [self actionButtonTitle:@"?" fontSize:13.0 color:DMDInterfaceColor(0x8FE9F7, 1.0)]];
    [self.view addSubview:self.helpButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.helpButton.trailingAnchor constraintEqualToAnchor:statusView.leadingAnchor constant:-8.0],
        [self.helpButton.centerYAnchor constraintEqualToAnchor:statusView.centerYAnchor],
        [self.helpButton.widthAnchor constraintEqualToConstant:28.0],
        [self.helpButton.heightAnchor constraintEqualToConstant:28.0],
    ]];

    DMDPassthroughView *hint = [[DMDPassthroughView alloc] initWithFrame:NSZeroRect];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *hintLabel = [self makeLabel:@"DRAG TO ORBIT  •  SCROLL TO ZOOM"
                                        font:DMDMonospacedFont(8.5, NSFontWeightRegular)
                                       color:DMDInterfaceColor(0x6E8499, 1.0)];
    hintLabel.maximumNumberOfLines = 1;
    [hint addSubview:hintLabel];
    [NSLayoutConstraint activateConstraints:@[
        [hintLabel.leadingAnchor constraintEqualToAnchor:hint.leadingAnchor],
        [hintLabel.trailingAnchor constraintEqualToAnchor:hint.trailingAnchor],
        [hintLabel.topAnchor constraintEqualToAnchor:hint.topAnchor],
        [hintLabel.bottomAnchor constraintEqualToAnchor:hint.bottomAnchor],
    ]];
    [self.view addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:self.sceneView.leadingAnchor constant:20.0],
        [hint.bottomAnchor constraintEqualToAnchor:self.sceneView.bottomAnchor constant:-16.0],
    ]];

    // Recenter control inside the 3D viewport. Unlike the HUD containers this
    // is a real button, so it deliberately intercepts clicks in its own frame.
    self.centerViewButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.centerViewButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.centerViewButton.bordered = NO;
    self.centerViewButton.bezelStyle = NSBezelStyleRegularSquare;
    self.centerViewButton.wantsLayer = YES;
    self.centerViewButton.layer.backgroundColor = DMDInterfaceColor(0x08111D, 0.84).CGColor;
    self.centerViewButton.layer.cornerRadius = 13.0;
    self.centerViewButton.layer.borderWidth = 1.0;
    self.centerViewButton.layer.borderColor = DMDInterfaceColor(0x2E596B, 0.9).CGColor;
    self.centerViewButton.layer.masksToBounds = YES;
    self.centerViewButton.focusRingType = NSFocusRingTypeNone;
    self.centerViewButton.target = self;
    self.centerViewButton.action = @selector(centerSceneView:);
    self.centerViewButton.keyEquivalent = @"0";
    self.centerViewButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    self.centerViewButton.toolTip = @"Center the detector in the viewport and reset orbit/zoom (⌘0).";
    self.centerViewButton.accessibilityIdentifier = @"centerSceneButton";
    [self.centerViewButton setAttributedTitle:
        [self actionButtonTitle:@"⌖  CENTER 3D"
                       fontSize:9.5
                          color:DMDInterfaceColor(0x8FE9F7, 1.0)]];
    [self.view addSubview:self.centerViewButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.centerViewButton.trailingAnchor constraintEqualToAnchor:self.sceneView.trailingAnchor constant:-18.0],
        [self.centerViewButton.bottomAnchor constraintEqualToAnchor:self.sceneView.bottomAnchor constant:-16.0],
        [self.centerViewButton.widthAnchor constraintEqualToConstant:126.0],
        [self.centerViewButton.heightAnchor constraintEqualToConstant:28.0],
    ]];
}

- (void)buildSceneOverlaysInRoot:(NSView *)rootView {
    (void)rootView;
    // Kept as a named hook for layout changes. HUD construction intentionally
    // occurs after the scene view exists so constraints can bind to it.
}

- (void)showHelpFromViewer:(id)sender {
    id delegate = NSApp.delegate;
    if ([delegate isKindOfClass:AppDelegate.class]) {
        [(AppDelegate *)delegate showHelpWindow:sender];
    }
}

- (void)centerSceneView:(id)sender {
    (void)sender;
    if (!self.sceneContext || !self.sceneView) {
        return;
    }

    SCNNode *cameraNode = self.sceneContext.cameraNode;
    SCNCameraController *cameraController = self.sceneView.defaultCameraController;
    [cameraController stopInertia];
    cameraController.automaticTarget = NO;
    cameraController.target = self.sceneContext.cameraHomeTarget;
    cameraController.pointOfView = cameraNode;
    self.sceneView.pointOfView = cameraNode;

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:reduceMotion ? 0.0 : 0.28];
    cameraNode.pivot = SCNMatrix4Identity;
    cameraNode.position = self.sceneContext.cameraHomePosition;
    cameraNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
    [cameraNode lookAt:self.sceneContext.cameraHomeTarget];
    cameraNode.camera.fieldOfView = self.sceneContext.cameraHomeFieldOfView;
    [SCNTransaction commit];

    [self.componentOverlay refreshProjection];
}

#pragma mark - Configuration UI

- (void)refreshConfigurationReadout {
    if (!self.engine) {
        return;
    }

    double velocity = [self.engine calculateDriftVelocity];
    double maximumDriftTime = [self.engine calculateDriftTimeForDepth:DMDTPCHeightMM];

    self.densityValueLabel.stringValue = [NSString stringWithFormat:@"%.2f g/cm³", self.engine.xenonDensity];
    self.fieldValueLabel.stringValue = [NSString stringWithFormat:@"%.2f kV/cm", self.engine.driftFieldVoltage];
    self.derivedLabel.stringValue = [NSString stringWithFormat:
        @"V_DRIFT  %5.2f mm/µs\nΔt_MAX   %5.1f µs @ 1500 mm",
        velocity,
        maximumDriftTime];

    if (self.selectedPart) {
        [self updateHUDForPart:self.selectedPart];
        return;
    }

    self.hudTitleLabel.stringValue = @"DARK MATTER DETECTOR  /  LZ TPC";
    self.hudTitleLabel.textColor = DMDInterfaceColor(0x5EE7FF, 1.0);
    self.hudDetailLabel.stringValue = [NSString stringWithFormat:
        @"TPC ACTIVE  •  %.2f kV/cm  •  %.2f g/cm³",
        self.engine.driftFieldVoltage,
        self.engine.xenonDensity];
    self.componentInfoLabel.stringValue = @"8 SYSTEMS LABELED  •  CLICK A LABEL TO ISOLATE A PART";
}

#pragma mark - Component inspector

- (void)inspectPartAtIndex:(NSInteger)index {
    if (self.continuousFiring) {
        [self stopContinuousFiring];
    }
    if (self.eventInProgress || !self.sceneContext) {
        return;
    }
    if (index < 0 || index >= (NSInteger)self.sceneContext.parts.count) {
        return;
    }

    DMDDetectorPart *part = self.sceneContext.parts[(NSUInteger)index];
    if (self.selectedPart == part) {
        [self clearPartSelection];
        return;
    }

    self.selectedPart = part;
    self.componentOverlay.selectedIndex = index;
    [self applyPartIsolationAnimated:YES];
    [self installSelectionMarkerForPart:part];
    [self updateHUDForPart:part];
}

- (void)clearPartSelection {
    if (!self.selectedPart) {
        return;
    }
    self.selectedPart = nil;
    self.componentOverlay.selectedIndex = -1;
    [self.selectionMarker removeAllActions];
    [self.selectionMarker removeFromParentNode];
    self.selectionMarker = nil;
    [self applyPartIsolationAnimated:YES];
    [self refreshConfigurationReadout];
}

- (void)applyPartIsolationAnimated:(BOOL)animated {
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:(animated && !reduceMotion) ? 0.24 : 0.0];
    for (DMDDetectorPart *part in self.sceneContext.parts) {
        part.contentNode.opacity = (self.selectedPart == nil || part == self.selectedPart) ? 1.0 : 0.13;
    }
    [SCNTransaction commit];
}

- (void)updateHUDForPart:(DMDDetectorPart *)part {
    self.hudTitleLabel.stringValue = [NSString stringWithFormat:@"COMPONENT  /  %@", part.displayName];
    self.hudTitleLabel.textColor = part.accentColor;
    self.hudDetailLabel.stringValue = part.specification;
    self.componentInfoLabel.stringValue = part.detail;
}

- (void)installSelectionMarkerForPart:(DMDDetectorPart *)part {
    [self.selectionMarker removeAllActions];
    [self.selectionMarker removeFromParentNode];

    SCNNode *marker = [SCNNode node];
    marker.position = part.anchor;
    marker.renderingOrder = 150;
    marker.name = @"componentSelectionMarker";

    SCNPlane *haloGeometry = [SCNPlane planeWithWidth:0.5 height:0.5];
    SCNMaterial *haloMaterial = [SCNMaterial material];
    haloMaterial.lightingModelName = SCNLightingModelConstant;
    haloMaterial.diffuse.contents = self.sceneContext.particleGlowImage;
    haloMaterial.emission.contents = part.accentColor;
    haloMaterial.emission.intensity = 1.4;
    haloMaterial.transparency = 0.92;
    haloMaterial.blendMode = SCNBlendModeAdd;
    haloMaterial.writesToDepthBuffer = NO;
    haloMaterial.doubleSided = YES;
    haloGeometry.materials = @[haloMaterial];
    SCNNode *haloNode = [SCNNode nodeWithGeometry:haloGeometry];
    haloNode.constraints = @[[SCNBillboardConstraint billboardConstraint]];
    haloNode.renderingOrder = 150;
    [marker addChildNode:haloNode];

    SCNSphere *coreGeometry = [SCNSphere sphereWithRadius:0.045];
    coreGeometry.segmentCount = 12;
    SCNMaterial *coreMaterial = [SCNMaterial material];
    coreMaterial.lightingModelName = SCNLightingModelConstant;
    coreMaterial.diffuse.contents = NSColor.whiteColor;
    coreMaterial.emission.contents = part.accentColor;
    coreMaterial.emission.intensity = 2.4;
    coreMaterial.writesToDepthBuffer = NO;
    coreGeometry.materials = @[coreMaterial];
    SCNNode *coreNode = [SCNNode nodeWithGeometry:coreGeometry];
    coreNode.renderingOrder = 151;
    [marker addChildNode:coreNode];

    SCNAction *pulse = [SCNAction repeatActionForever:[SCNAction sequence:@[
        [SCNAction group:@[
            [SCNAction scaleTo:1.45 duration:0.85],
            [SCNAction fadeOpacityTo:0.45 duration:0.85]
        ]],
        [SCNAction group:@[
            [SCNAction scaleTo:1.0 duration:0.0],
            [SCNAction fadeOpacityTo:1.0 duration:0.0]
        ]]
    ]]];
    [marker runAction:pulse];
    [self.sceneContext.detectorRoot addChildNode:marker];
    self.selectionMarker = marker;
}

- (void)particleTypeChanged:(NSPopUpButton *)sender {
    // Configuration remains live even while an event is on screen: the
    // in-flight result is already snapshotted, and the next shot uses this
    // newly selected particle.
    self.engine.particleType = (DMDParticleType)sender.indexOfSelectedItem;
}

- (void)densitySliderChanged:(NSSlider *)sender {
    self.engine.xenonDensity = sender.doubleValue;
    [self refreshConfigurationReadout];
}

- (void)fieldSliderChanged:(NSSlider *)sender {
    self.engine.driftFieldVoltage = sender.doubleValue;
    [self refreshConfigurationReadout];
}

#pragma mark - Boot, status, and terminal

- (void)appendBootSequence {
    [self appendLog:@"SYSTEM ONLINE — liquid xenon TPC simulation ready" kind:DMDLogKindSuccess];
    [self appendLog:[NSString stringWithFormat:@"TPC volume 1500 mm high • 1 scene unit = %.0f mm • top interface y=+3.00",
                     DMDMillimetersPerSceneUnit]
               kind:DMDLogKindDetail];
    [self appendLog:[NSString stringWithFormat:@"Reference configuration: ρ=%.2f g/cm³ • E=%.2f kV/cm • v_drift=%.2f mm/µs",
                     self.engine.xenonDensity,
                     self.engine.driftFieldVoltage,
                     [self.engine calculateDriftVelocity]]
               kind:DMDLogKindDetail];
    [self appendLog:@"Time-lapse: 1.0 s = 1000 µs (clamped 0.35–3.0 s for visibility)" kind:DMDLogKindDetail];
    [self appendLog:@"3D SYSTEMS — water shield • cryostat • LXe TPC • PMT arrays • field cage • Gd veto • DAQ" kind:DMDLogKindDetail];
    [self appendLog:@"SITE — Sanford Underground Research Facility • ~1.5 km rock overburden" kind:DMDLogKindDetail];
    [self appendLog:@"Click any 3D callout to isolate and inspect a detector subsystem." kind:DMDLogKindInfo];
}

- (void)clearLog:(id)sender {
    (void)sender;
    [self.terminalTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
    [self appendLog:@"LOG CLEARED — telemetry buffer ready" kind:DMDLogKindDetail];
}

- (void)appendLog:(NSString *)message kind:(DMDLogKind)kind {
    if (!self.terminalTextView) {
        return;
    }

    NSColor *color = DMDInterfaceColor(0xA9C6D8, 1.0);
    switch (kind) {
        case DMDLogKindInfo:
            color = DMDInterfaceColor(0xA9C6D8, 1.0);
            break;
        case DMDLogKindDetail:
            color = DMDInterfaceColor(0x728AA0, 1.0);
            break;
        case DMDLogKindTrigger:
            color = DMDInterfaceColor(0x61E5FF, 1.0);
            break;
        case DMDLogKindWarning:
            color = DMDInterfaceColor(0xFFC46B, 1.0);
            break;
        case DMDLogKindAlert:
            color = DMDInterfaceColor(0xFF7D83, 1.0);
            break;
        case DMDLogKindVeto:
            color = DMDInterfaceColor(0xFFA36B, 1.0);
            break;
        case DMDLogKindSuccess:
            color = DMDInterfaceColor(0x7DFFC0, 1.0);
            break;
    }

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.0;
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: DMDMonospacedFont(10.0, NSFontWeightRegular),
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph
    };
    NSString *timestamp = [self.timeFormatter stringFromDate:NSDate.date];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSAttributedString *attributedLine = [[NSAttributedString alloc] initWithString:line
                                                                          attributes:attributes];

    [self.terminalTextView.textStorage appendAttributedString:attributedLine];
    [self.terminalTextView scrollRangeToVisible:NSMakeRange(self.terminalTextView.string.length, 0)];
}

- (void)setStatus:(NSString *)status color:(NSColor *)color {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"● %@", status];
    self.statusLabel.textColor = color;
}

- (void)updateFireButtonAppearance {
    if (!self.fireButton) {
        return;
    }

    BOOL active = self.continuousFiring;
    NSColor *accent = active ? DMDInterfaceColor(0xFFB35F, 1.0)
                             : DMDInterfaceColor(0x64E5FF, 1.0);
    NSColor *titleColor = DMDInterfaceColor(0x03111A, 1.0);
    NSString *title = active ? @"■  STOP FIRING" : @"FIRE PARTICLE / TRIGGER EVENT";

    self.fireButton.layer.backgroundColor = accent.CGColor;
    self.fireButton.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    self.fireButton.enabled = YES;
    self.fireButton.alphaValue = 1.0;
    self.fireButton.toolTip = active
        ? @"Continuous firing is active. Click again to stop after the current event."
        : @"Start continuous firing. The button stays latched until you stop it.";
    self.fireButton.accessibilityLabel = active ? @"Stop firing" : @"Fire particle";
    self.fireButton.accessibilityValue = active ? @"Continuous firing active" : @"Idle";
    [self.fireButton setAttributedTitle:
        [self actionButtonTitle:title fontSize:11.0 color:titleColor]];
}

#pragma mark - Event trigger

- (IBAction)fireParticle:(id)sender {
    (void)sender;
    if (!self.engine || !self.sceneContext) {
        return;
    }

    if (self.continuousFiring) {
        [self stopContinuousFiring];
    } else {
        [self startContinuousFiring];
    }
}

- (void)startContinuousFiring {
    if (!self.engine || !self.sceneContext) {
        return;
    }

    self.continuousFiring = YES;
    [self updateFireButtonAppearance];
    [self appendLog:@"▶ CONTINUOUS FIRE ENGAGED — click STOP FIRING to end the run."
               kind:DMDLogKindInfo];
    [self triggerEventIfIdle];
}

- (void)stopContinuousFiring {
    if (!self.continuousFiring) {
        return;
    }

    self.continuousFiring = NO;
    [self updateFireButtonAppearance];

    if (self.eventInProgress) {
        [self appendLog:@"■ CONTINUOUS FIRE STOPPED — current event will finish."
                   kind:DMDLogKindDetail];
    } else {
        [self appendLog:@"■ CONTINUOUS FIRE STOPPED" kind:DMDLogKindDetail];
        [self setStatus:@"READY" color:DMDInterfaceColor(0x69E5FF, 1.0)];
    }
}

- (void)triggerEventIfIdle {
    if (self.continuousFiring && !self.eventInProgress) {
        [self beginSingleEvent];
    }
}

- (void)beginSingleEvent {
    if (self.eventInProgress || !self.engine || !self.sceneContext) {
        return;
    }

    [self clearPartSelection];

    self.eventInProgress = YES;
    self.driftStarted = NO;
    self.s2FlashStarted = NO;
    self.eventSerial += 1;
    NSUInteger serial = self.eventSerial;

    self.engine.particleType = (DMDParticleType)self.particlePopup.indexOfSelectedItem;
    self.engine.xenonDensity = self.densitySlider.doubleValue;
    self.engine.driftFieldVoltage = self.fieldSlider.doubleValue;

    // Rejection-free uniform sampling of a circle: r = R * sqrt(U) gives an
    // area-uniform point in the TPC cross-section. The smaller radius keeps
    // the event in the fiducial volume used by the WIMP discrimination.
    double radius = 2.30 * sqrt(DMDUniform01());
    double theta = 2.0 * M_PI * DMDUniform01();
    double x = radius * cos(theta);
    double z = radius * sin(theta);
    double y = -2.72 + 5.44 * DMDUniform01();

    double xMM = x * DMDMillimetersPerSceneUnit;
    double yMM = y * DMDMillimetersPerSceneUnit;
    double zMM = z * DMDMillimetersPerSceneUnit;
    // Depth is measured downward from the liquid-gas interface at y = +3.0.
    double depthMM = (DMDTPCTopYScene - y) * DMDMillimetersPerSceneUnit;

    DMDEventResult *result = [self.engine simulateEventAtXMillimeters:xMM
                                                          yMillimeters:yMM
                                                          zMillimeters:zMM
                                                     depthMillimeters:depthMM];

    [self removeTransientEventNodes];
    [self appendLog:[NSString stringWithFormat:@"⚡ TRIGGER — %@  |  ρ=%.2f g/cm³  |  E=%.2f kV/cm",
                     result.particleName,
                     result.xenonDensity,
                     result.driftField]
               kind:DMDLogKindTrigger];
    [self appendLog:[NSString stringWithFormat:@"   S1 FLASH @ x=%+.0f mm  y=%+.0f mm  z=%+.0f mm  (depth %.1f mm)",
                     result.xMillimeters,
                     result.yMillimeters,
                     result.zMillimeters,
                     result.depthMillimeters]
               kind:DMDLogKindInfo];
    [self appendLog:[NSString stringWithFormat:@"   v_drift = %.3f mm/µs  •  Δt = %.2f µs  •  S1 = %.1f PE",
                     result.driftVelocity,
                     result.driftTimeMicroseconds,
                     result.s1PE]
               kind:DMDLogKindDetail];

    [self setStatus:@"S1 FLASH" color:DMDInterfaceColor(0xE9FAFF, 1.0)];

    SCNVector3 hitPosition = SCNVector3Make(x, y, z);
    __weak typeof(self) weakSelf = self;
    [self playS1FlashAtPosition:hitPosition completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.eventInProgress || strongSelf.eventSerial != serial) {
            return;
        }
        [strongSelf beginDriftForResult:result startPosition:hitPosition];
    }];

    // Defense against a dropped SceneKit completion handler. The serial check
    // is essential in continuous mode: an older event's watchdog must never
    // finalize the newer event that is currently on screen.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf.eventInProgress && strongSelf.eventSerial == serial) {
            [strongSelf finalizeEventWithResult:result];
        }
    });
}

- (void)removeTransientEventNodes {
    NSArray<SCNNode *> *nodes = [self.sceneContext.eventRoot childNodes];
    for (SCNNode *node in [nodes copy]) {
        [node removeAllActions];
        [node removeAllParticleSystems];
        [node removeFromParentNode];
    }
}

#pragma mark - S1 flash

- (void)playS1FlashAtPosition:(SCNVector3)position
                   completion:(void (^)(void))completion {
    SCNSphere *sphere = [SCNSphere sphereWithRadius:0.12];
    sphere.segmentCount = 24;
    NSColor *flashColor = DMDInterfaceColor(0xDDF8FF, 1.0);
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = flashColor;
    material.emission.contents = flashColor;
    material.emission.intensity = 2.0;
    material.transparency = 1.0;
    material.blendMode = SCNBlendModeAdd;
    material.writesToDepthBuffer = NO;
    sphere.materials = @[material];

    SCNNode *flashNode = [SCNNode nodeWithGeometry:sphere];
    flashNode.position = position;
    flashNode.renderingOrder = 100;
    flashNode.castsShadow = NO;
    flashNode.scale = SCNVector3Make(0.15, 0.15, 0.15);

    SCNLight *light = [SCNLight light];
    light.type = SCNLightTypeOmni;
    light.color = DMDInterfaceColor(0x9BEFFF, 1.0);
    light.intensity = 1600.0;
    SCNNode *lightNode = [SCNNode node];
    lightNode.light = light;
    [flashNode addChildNode:lightNode];

    [self.sceneContext.eventRoot addChildNode:flashNode];

    SCNAction *expand = [SCNAction scaleTo:2.4 duration:0.20];
    expand.timingMode = SCNActionTimingModeEaseOut;
    SCNAction *fade = [SCNAction fadeOutWithDuration:0.38];
    SCNAction *finish = [SCNAction removeFromParentNode];
    [flashNode runAction:[SCNAction sequence:@[[SCNAction group:@[expand, fade]], finish]]
             completionHandler:^{
        // SceneKit invokes action completion blocks on its display-link queue.
        // All AppKit and scene-graph mutation must return to the main thread.
        dispatch_async(dispatch_get_main_queue(), completion);
    }];
}

#pragma mark - Drift and S2

- (void)beginDriftForResult:(DMDEventResult *)result
              startPosition:(SCNVector3)startPosition {
    if (!self.eventInProgress || self.driftStarted) {
        return;
    }
    self.driftStarted = YES;
    NSUInteger serial = self.eventSerial;

    SCNNode *eventRoot = self.sceneContext.eventRoot;
    CGFloat topY = self.sceneContext.tpcTopY;
    CGFloat travelDistance = topY - startPosition.y;

    SCNSphere *tracerSphere = [SCNSphere sphereWithRadius:0.045];
    tracerSphere.segmentCount = 14;
    NSColor *tracerColor = DMDInterfaceColor(0xFFE58A, 1.0);
    SCNMaterial *tracerMaterial = [SCNMaterial material];
    tracerMaterial.lightingModelName = SCNLightingModelConstant;
    tracerMaterial.diffuse.contents = tracerColor;
    tracerMaterial.emission.contents = tracerColor;
    tracerMaterial.emission.intensity = 2.0;
    tracerMaterial.blendMode = SCNBlendModeAdd;
    tracerMaterial.writesToDepthBuffer = NO;
    tracerSphere.materials = @[tracerMaterial];

    SCNNode *tracer = [SCNNode nodeWithGeometry:tracerSphere];
    tracer.position = startPosition;
    tracer.renderingOrder = 101;
    [eventRoot addChildNode:tracer];

    SCNParticleSystem *driftParticles = [self makeDriftParticleSystem];
    [tracer addParticleSystem:driftParticles];

    SCNCylinder *pathGeometry = [SCNCylinder cylinderWithRadius:0.018
                                                         height:MAX(0.02, travelDistance)];
    pathGeometry.radialSegmentCount = 8;
    SCNMaterial *pathMaterial = [self glowMaterialWithColor:DMDInterfaceColor(0xFFD86B, 1.0)
                                                     opacity:0.25];
    pathGeometry.materials = @[pathMaterial];
    SCNNode *pathNode = [SCNNode nodeWithGeometry:pathGeometry];
    pathNode.position = SCNVector3Make(startPosition.x,
                                       (startPosition.y + topY) * 0.5,
                                       startPosition.z);
    pathNode.renderingOrder = 99;
    [eventRoot addChildNode:pathNode];

    // Time-lapse: the exact time of flight is reported in microseconds, while
    // the wall-clock action is clamped so both 86 µs and 3 ms events remain
    // legible. 1 second of animation represents 1000 µs of simulated drift.
    CGFloat visualDuration = (CGFloat)DMDClampedDouble(result.driftTimeMicroseconds / 1000.0,
                                                        0.35,
                                                        3.0);
    [self setStatus:[NSString stringWithFormat:@"DRIFTING · %.0f µs", result.driftTimeMicroseconds]
             color:DMDInterfaceColor(0xFFD86B, 1.0)];
    [self appendLog:[NSString stringWithFormat:@"↑ ELECTRON DRIFT — %.1f mm at %.3f mm/µs  (Δ=%.2f µs)",
                     result.depthMillimeters,
                     result.driftVelocity,
                     result.driftTimeMicroseconds]
               kind:DMDLogKindInfo];

    SCNAction *move = [SCNAction moveTo:SCNVector3Make(startPosition.x, topY, startPosition.z)
                               duration:visualDuration];
    // Constant drift velocity ⇒ constant visual speed.
    move.timingMode = SCNActionTimingModeLinear;

    __weak typeof(self) weakSelf = self;
    [tracer runAction:move completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.eventInProgress ||
                strongSelf.eventSerial != serial) {
                return;
            }

            [tracer removeAllParticleSystems];
            [tracer removeFromParentNode];
            [pathNode runAction:[SCNAction sequence:@[
                [SCNAction fadeOutWithDuration:0.18],
                [SCNAction removeFromParentNode]
            ]]];

            [strongSelf finishDriftForResult:result];
        });
    }];
}

- (SCNParticleSystem *)makeDriftParticleSystem {
    SCNParticleSystem *particles = [[SCNParticleSystem alloc] init];
    particles.birthRate = 230.0;
    particles.birthRateVariation = 60.0;
    particles.particleLifeSpan = 0.42;
    particles.particleLifeSpanVariation = 0.22;
    particles.particleSize = 0.075;
    particles.particleSizeVariation = 0.04;
    particles.particleColor = DMDInterfaceColor(0xFFD76A, 1.0);
    particles.particleColorVariation = SCNVector4Make(0.02, 0.08, 0.08, 0.0);
    particles.particleVelocity = 0.45;
    particles.particleVelocityVariation = 0.2;
    particles.emittingDirection = SCNVector3Make(0.0, 1.0, 0.0);
    particles.spreadingAngle = 16.0;
    particles.acceleration = SCNVector3Make(0.0, 0.45, 0.0);
    particles.emitterShape = [SCNSphere sphereWithRadius:0.035];
    particles.birthLocation = SCNParticleBirthLocationSurface;
    particles.birthDirection = SCNParticleBirthDirectionConstant;
    particles.blendMode = SCNParticleBlendModeAdditive;
    particles.particleIntensity = 1.4;
    particles.particleImage = self.sceneContext.particleGlowImage;
    particles.loops = YES;
    particles.emissionDuration = 1.0;
    return particles;
}

- (void)finishDriftForResult:(DMDEventResult *)result {
    if (!self.eventInProgress || self.s2FlashStarted) {
        return;
    }
    self.s2FlashStarted = YES;
    NSUInteger serial = self.eventSerial;

    [self appendLog:[NSString stringWithFormat:@"↑ BOUNDARY — electrons reached the liquid-gas interface at y=%+.2f u",
                     self.sceneContext.tpcTopY]
               kind:DMDLogKindInfo];
    [self appendLog:[NSString stringWithFormat:@"   S2 ELECTROLUMINESCENCE @ top PMT array  •  S1=%.1f PE  •  S2=%.1f PE  •  S2/S1=%.1f",
                     result.s1PE,
                     result.s2PE,
                     result.s2s1Ratio]
               kind:DMDLogKindWarning];
    [self setStatus:@"S2 FLASH" color:DMDInterfaceColor(0xFFB35F, 1.0)];

    __weak typeof(self) weakSelf = self;
    [self playS2FlashAtX:result.xMillimeters / DMDMillimetersPerSceneUnit
                      z:result.zMillimeters / DMDMillimetersPerSceneUnit
               completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.eventInProgress ||
            strongSelf.eventSerial != serial) {
            return;
        }
        [strongSelf finalizeEventWithResult:result];
    }];
}

- (void)playS2FlashAtX:(CGFloat)x
                    z:(CGFloat)z
             completion:(void (^)(void))completion {
    SCNNode *eventRoot = self.sceneContext.eventRoot;
    CGFloat topY = self.sceneContext.tpcTopY + 0.03;

    SCNSphere *sphere = [SCNSphere sphereWithRadius:0.22];
    sphere.segmentCount = 32;
    NSColor *s2Color = DMDInterfaceColor(0xFFB35A, 1.0);
    SCNMaterial *s2Material = [SCNMaterial material];
    s2Material.lightingModelName = SCNLightingModelConstant;
    s2Material.diffuse.contents = s2Color;
    s2Material.emission.contents = s2Color;
    s2Material.emission.intensity = 2.5;
    s2Material.blendMode = SCNBlendModeAdd;
    s2Material.writesToDepthBuffer = NO;
    sphere.materials = @[s2Material];

    SCNNode *flashNode = [SCNNode nodeWithGeometry:sphere];
    flashNode.position = SCNVector3Make(x, topY, z);
    flashNode.renderingOrder = 102;
    [eventRoot addChildNode:flashNode];

    SCNLight *light = [SCNLight light];
    light.type = SCNLightTypeOmni;
    light.color = DMDInterfaceColor(0xFFA24D, 1.0);
    light.intensity = 3400.0;
    SCNNode *lightNode = [SCNNode node];
    lightNode.light = light;
    [flashNode addChildNode:lightNode];

    SCNAction *expand = [SCNAction scaleTo:3.4 duration:0.38];
    expand.timingMode = SCNActionTimingModeEaseOut;
    SCNAction *fade = [SCNAction fadeOutWithDuration:0.55];
    [flashNode runAction:[SCNAction sequence:@[
        expand,
        [SCNAction waitForDuration:0.10],
        fade,
        [SCNAction removeFromParentNode]
    ]]];

    // A second, expanding ring makes the top-boundary hit read even from an
    // oblique camera angle.
    SCNTorus *ringGeometry = [SCNTorus torusWithRingRadius:0.24 pipeRadius:0.024];
    ringGeometry.ringSegmentCount = 64;
    ringGeometry.pipeSegmentCount = 10;
    SCNMaterial *ringMaterial = [self glowMaterialWithColor:DMDInterfaceColor(0xFFC26D, 1.0)
                                                     opacity:0.9];
    ringGeometry.materials = @[ringMaterial];
    SCNNode *ringNode = [SCNNode nodeWithGeometry:ringGeometry];
    ringNode.position = SCNVector3Make(x, topY + 0.01, z);
    ringNode.renderingOrder = 103;
    ringNode.scale = SCNVector3Make(0.35, 0.35, 0.35);
    [eventRoot addChildNode:ringNode];
    SCNAction *ringExpand = [SCNAction scaleTo:4.0 duration:0.72];
    ringExpand.timingMode = SCNActionTimingModeEaseOut;
    [ringNode runAction:[SCNAction sequence:@[
        [SCNAction group:@[ringExpand, [SCNAction fadeOutWithDuration:0.72]]],
        [SCNAction removeFromParentNode]
    ]]];

    // Nearby PMTs briefly brighten (node scale only; shared material colors
    // remain untouched).
    for (SCNNode *pmt in self.sceneContext.topPMTNodes) {
        CGFloat dx = pmt.position.x - x;
        CGFloat dz = pmt.position.z - z;
        if (dx * dx + dz * dz <= 1.2 * 1.2) {
            [pmt runAction:[SCNAction sequence:@[
                [SCNAction scaleTo:1.32 duration:0.12],
                [SCNAction scaleTo:1.0 duration:0.30]
            ]]];
        }
    }

    SCNNode *timerNode = [SCNNode node];
    [eventRoot addChildNode:timerNode];
    [timerNode runAction:[SCNAction sequence:@[
        // Slightly longer than the combined S2 flash + fade so the event is
        // fully over before the controls re-enable and the status resets.
        [SCNAction waitForDuration:1.08],
        [SCNAction removeFromParentNode]
    ]]
          completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), completion);
    }];
}

#pragma mark - Completion

- (void)finalizeEventWithResult:(DMDEventResult *)result {
    if (!self.eventInProgress) {
        return;
    }
    self.eventInProgress = NO;
    [self updateFireButtonAppearance];

    if (self.continuousFiring) {
        [self setStatus:@"FIRING · LIVE" color:DMDInterfaceColor(0xFFB35F, 1.0)];
    } else {
        [self setStatus:@"READY" color:DMDInterfaceColor(0x69E5FF, 1.0)];
    }

    [self appendLog:[NSString stringWithFormat:
        @"   SUMMARY — (x=%+.0f, y=%+.0f, z=%+.0f) mm  •  depth=%.1f mm  •  v=%.3f mm/µs  •  Δt=%.2f µs",
        result.xMillimeters,
        result.yMillimeters,
        result.zMillimeters,
        result.depthMillimeters,
        result.driftVelocity,
        result.driftTimeMicroseconds]
               kind:DMDLogKindDetail];
    [self appendLog:[NSString stringWithFormat:@"   S1=%.1f PE  •  S2=%.1f PE  •  S2/S1=%.1f  •  fiducial=%@",
                     result.s1PE,
                     result.s2PE,
                     result.s2s1Ratio,
                     result.isInFiducial ? @"YES" : @"NO"]
               kind:DMDLogKindDetail];

    if (result.isCandidate) {
        [self appendLog:@"⚠️ ALERT: CONFIRMED DARK MATTER CANDIDATE DETECTED! ⚠️"
                   kind:DMDLogKindAlert];
        [self appendLog:[NSString stringWithFormat:@"   %.1f%% confidence — %@",
                         result.confidence * 100.0,
                         result.reason]
                   kind:DMDLogKindSuccess];
    } else {
        [self appendLog:@"✕ BACKGROUND EVENT (VETOED)" kind:DMDLogKindVeto];
        [self appendLog:[NSString stringWithFormat:@"   %.1f%% confidence — %@",
                         result.confidence * 100.0,
                         result.reason]
                   kind:DMDLogKindDetail];
    }

    [self refreshConfigurationReadout];

    if (self.continuousFiring) {
        // Keep the button latched and start the next shot after a short beat.
        // The latest slider/popup values are snapshotted by beginSingleEvent.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf triggerEventIfIdle];
        });
    }
}

#pragma mark - Small helpers

- (SCNMaterial *)glowMaterialWithColor:(NSColor *)color opacity:(CGFloat)opacity {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = color;
    material.emission.contents = color;
    material.emission.intensity = 1.5;
    material.transparency = opacity;
    material.blendMode = SCNBlendModeAdd;
    material.writesToDepthBuffer = NO;
    material.doubleSided = YES;
    return material;
}

@end
