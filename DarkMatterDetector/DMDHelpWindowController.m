#import "DMDHelpWindowController.h"

#import "DMDPhysicsConstants.h"

static NSColor *DMDHelpColor(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:(CGFloat)((rgb >> 16) & 0xFF) / 255.0
                                green:(CGFloat)((rgb >> 8) & 0xFF) / 255.0
                                 blue:(CGFloat)(rgb & 0xFF) / 255.0
                                alpha:alpha];
}

static NSFont *DMDHelpMonoFont(CGFloat size, NSFontWeight weight) {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

@interface DMDHelpWindowController ()

@property (nonatomic, strong) NSTextView *helpTextView;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign) BOOL didScheduleDebugSnapshot;

@end

@implementation DMDHelpWindowController

- (instancetype)init {
    NSRect contentRect = NSMakeRect(0.0, 0.0, 800.0, 660.0);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled
                                | NSWindowStyleMaskClosable
                                | NSWindowStyleMaskMiniaturizable
                                | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                  styleMask:styleMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"How This Simulator Works";
    window.contentMinSize = NSMakeSize(600.0, 460.0);
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.releasedWhenClosed = NO;
    window.restorable = NO;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor = DMDHelpColor(0x060B14, 1.0);

    self = [super initWithWindow:window];
    if (self) {
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];

    NSString *snapshotPath = NSProcessInfo.processInfo.environment[@"DMD_HELP_SNAPSHOT_PATH"];
    if (snapshotPath.length == 0 || self.didScheduleDebugSnapshot) {
        return;
    }
    self.didScheduleDebugSnapshot = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSView *content = self.window.contentView;
        [content layoutSubtreeIfNeeded];
        if ([NSProcessInfo.processInfo.environment[@"DMD_HELP_SNAPSHOT_BOTTOM"] boolValue]) {
            [self.helpTextView scrollRangeToVisible:NSMakeRange(self.helpTextView.string.length, 0)];
            [content layoutSubtreeIfNeeded];
        }
        NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
        if (rep) {
            [content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];
            NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [data writeToFile:snapshotPath atomically:YES];
        }
        [NSApp terminate:nil];
    });
}

- (void)buildContent {
    NSView *content = self.window.contentView;
    if (!content) {
        return;
    }
    content.wantsLayer = YES;
    content.layer.backgroundColor = DMDHelpColor(0x060B14, 1.0).CGColor;

    NSView *accent = [[NSView alloc] initWithFrame:NSZeroRect];
    accent.translatesAutoresizingMaskIntoConstraints = NO;
    accent.wantsLayer = YES;
    accent.layer.backgroundColor = DMDHelpColor(0x5EE7FF, 0.82).CGColor;
    [content addSubview:accent];

    NSTextField *eyebrow = [self makeLabel:@"DARK MATTER DETECTOR  /  FIELD GUIDE"
                                      font:DMDHelpMonoFont(9.0, NSFontWeightSemibold)
                                     color:DMDHelpColor(0x5EE7FF, 1.0)];
    [eyebrow setContentHuggingPriority:NSLayoutPriorityRequired
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addSubview:eyebrow];

    NSTextField *title = [self makeLabel:@"How this simulator works"
                                    font:[NSFont systemFontOfSize:26.0 weight:NSFontWeightSemibold]
                                   color:DMDHelpColor(0xF2FAFF, 1.0)];
    title.maximumNumberOfLines = 1;
    [content addSubview:title];

    NSTextField *subtitle = [self makeLabel:
        @"The detector layers, the S1 → drift → S2 event loop, and the simplified physics behind the terminal."
                                          font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]
                                         color:DMDHelpColor(0x8DA7BA, 1.0)];
    subtitle.maximumNumberOfLines = 2;
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:subtitle];

    NSView *badge = [[NSView alloc] initWithFrame:NSZeroRect];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.wantsLayer = YES;
    badge.layer.backgroundColor = DMDHelpColor(0x2A2111, 0.92).CGColor;
    badge.layer.cornerRadius = 10.0;
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor = DMDHelpColor(0xC5914D, 0.65).CGColor;
    NSTextField *badgeLabel = [self makeLabel:@"EDUCATIONAL MODEL"
                                        font:DMDHelpMonoFont(8.0, NSFontWeightSemibold)
                                       color:DMDHelpColor(0xFFC46B, 1.0)];
    [badge addSubview:badgeLabel];
    [content addSubview:badge];

    NSView *divider = [[NSView alloc] initWithFrame:NSZeroRect];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = DMDHelpColor(0x1A3242, 1.0).CGColor;
    [content addSubview:divider];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = DMDHelpColor(0x05090F, 1.0);
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.scrollerStyle = NSScrollerStyleOverlay;
    scrollView.borderType = NSNoBorder;
    scrollView.wantsLayer = YES;
    scrollView.layer.backgroundColor = DMDHelpColor(0x05090F, 1.0).CGColor;
    scrollView.layer.cornerRadius = 8.0;
    scrollView.layer.masksToBounds = YES;
    scrollView.layer.borderWidth = 1.0;
    scrollView.layer.borderColor = DMDHelpColor(0x1A3242, 1.0).CGColor;
    [content addSubview:scrollView];

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 748.0, 460.0)];
    textView.drawsBackground = YES;
    textView.backgroundColor = DMDHelpColor(0x05090F, 1.0);
    textView.textColor = DMDHelpColor(0xAFC4D5, 1.0);
    textView.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = YES;
    textView.usesFontPanel = NO;
    textView.usesFindPanel = YES;
    textView.insertionPointColor = DMDHelpColor(0x69E5FF, 1.0);
    textView.textContainerInset = NSMakeSize(20.0, 18.0);
    textView.textContainer.lineFragmentPadding = 0.0;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(748.0, CGFLOAT_MAX);
    textView.minSize = NSMakeSize(0.0, 0.0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.accessibilityIdentifier = @"helpTextView";
    textView.textStorage.attributedString = [self helpContent];
    scrollView.documentView = textView;
    self.helpTextView = textView;

    self.closeButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeButton.bordered = NO;
    self.closeButton.bezelStyle = NSBezelStyleRegularSquare;
    self.closeButton.wantsLayer = YES;
    self.closeButton.layer.backgroundColor = DMDHelpColor(0x64E5FF, 1.0).CGColor;
    self.closeButton.layer.cornerRadius = 7.0;
    self.closeButton.layer.masksToBounds = YES;
    self.closeButton.focusRingType = NSFocusRingTypeNone;
    self.closeButton.keyEquivalent = @"\e";
    self.closeButton.target = self;
    self.closeButton.action = @selector(closeHelp:);
    self.closeButton.toolTip = @"Close this field guide (Esc).";
    self.closeButton.accessibilityIdentifier = @"closeHelpButton";
    self.closeButton.accessibilityLabel = @"Close help";
    [self.closeButton setAttributedTitle:
        [self actionTitle:@"CLOSE" fontSize:10.0 color:DMDHelpColor(0x03111A, 1.0)]];
    [content addSubview:self.closeButton];

    NSTextField *footer = [self makeLabel:@"SIMULATED DATA  •  FOR EDUCATION AND EXPLORATION"
                                     font:DMDHelpMonoFont(8.0, NSFontWeightRegular)
                                    color:DMDHelpColor(0x60788C, 1.0)];
    footer.maximumNumberOfLines = 1;
    footer.lineBreakMode = NSLineBreakByTruncatingTail;
    [content addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [accent.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [accent.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [accent.topAnchor constraintEqualToAnchor:content.topAnchor],
        [accent.heightAnchor constraintEqualToConstant:2.0],

        [eyebrow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [eyebrow.topAnchor constraintEqualToAnchor:content.topAnchor constant:24.0],

        [badge.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26.0],
        [badge.centerYAnchor constraintEqualToAnchor:eyebrow.centerYAnchor],
        [badge.heightAnchor constraintEqualToConstant:22.0],
        [badgeLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:9.0],
        [badgeLabel.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-9.0],
        [badgeLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-26.0],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-26.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5.0],

        [divider.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [divider.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26.0],
        [divider.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:16.0],
        [divider.heightAnchor constraintEqualToConstant:1.0],

        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26.0],
        [scrollView.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:12.0],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.closeButton.topAnchor constant:-14.0],
        [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:220.0],

        [self.closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26.0],
        [self.closeButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18.0],
        [self.closeButton.widthAnchor constraintEqualToConstant:96.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:30.0],

        [footer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26.0],
        [footer.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-12.0],
        [footer.centerYAnchor constraintEqualToAnchor:self.closeButton.centerYAnchor],
    ]];
}

- (NSTextField *)makeLabel:(NSString *)text
                      font:(NSFont *)font
                     color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.lineBreakMode = NSLineBreakByClipping;
    return label;
}

- (NSAttributedString *)actionTitle:(NSString *)title
                           fontSize:(CGFloat)fontSize
                              color:(NSColor *)color {
    return [[NSAttributedString alloc] initWithString:title
                                            attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(0.35)
    }];
}

- (IBAction)closeHelp:(id)sender {
    (void)sender;
    [self.window close];
}

#pragma mark - Help content

- (NSAttributedString *)helpContent {
    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];

    [self appendParagraph:
        @"This field guide explains what the three-dimensional detector represents, "
        @"how an event travels through it, and what the terminal telemetry means. "
        @"Everything is generated by this application; no external detector data or "
        @"3D assets are used."
                        color:DMDHelpColor(0xC7D6E2, 1.0)
                           to:content];

    [self appendSection:@"QUICK START" to:content];
    [self appendNumberedStep:1 body:
        @"Choose an incident particle in the sidebar: WIMP, background neutron, or cosmic-ray electron."
                             to:content];
    [self appendNumberedStep:2 body:
        @"Adjust liquid-xenon density and drift-field voltage. The value labels, derived drift speed, "
        @"HUD, and the next event update while you drag."
                             to:content];
    [self appendNumberedStep:3 body:
        @"Press FIRE PARTICLE / TRIGGER EVENT. The button latches into STOP FIRING and keeps launching "
        @"events; press it again to stop after the current event finishes."
                             to:content];
    [self appendNumberedStep:4 body:
        @"Watch the S1 flash, the upward electron drift, and the S2 flash. The terminal records the "
        @"coordinates, depth, timing, signal estimates, and ruling."
                             to:content];
    [self appendNumberedStep:5 body:
        @"Click a subsystem label to isolate it. Drag to orbit, scroll to zoom, and use CENTER 3D "
        @"(⌘0) to restore the camera."
                             to:content];

    [self appendSection:@"WHAT YOU ARE LOOKING AT" to:content];
    [self appendParagraph:
        @"The experiment is designed to search for dark matter in the form of weakly interacting "
        @"massive particles (WIMPs), hypothetical particles that would occasionally scatter off a "
        @"xenon nucleus. That recoil is rare and tiny, so the detector must reject much more common "
        @"neutron and electron recoils. The underground site, water shield, and signal analysis are "
        @"all part of that background-reduction strategy."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];
    [self appendParagraph:
        @"The scene is a stylized, interactive model of a dual-phase liquid-xenon time projection "
        @"chamber (TPC), inspired by the LZ and XENONnT experiments. A cylindrical active volume of "
        @"liquid xenon sits inside a titanium cryostat and a large water shield. Top and bottom "
        @"photomultiplier-tube (PMT) arrays watch for light, while an electric field drifts ionization "
        @"electrons upward toward a liquid-gas interface."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];

    [self appendBulletWithLead:@"Water shield and Gd veto"
                          body:@"Dense water and gadolinium-loaded material absorb neutrons and suppress "
                               @"external backgrounds. The underground site reduces cosmic-ray exposure."
                          to:content];
    [self appendBulletWithLead:@"Cryostat"
                          body:@"Titanium vessel that contains and insulates the liquid xenon; flanges and "
                               @"conduits carry services and instrumentation."
                          to:content];
    [self appendBulletWithLead:@"LXe TPC and field cage"
                          body:@"1.5 m of active liquid xenon in the model, with a shaped electric field "
                               @"that transports ionization electrons to the top interface."
                          to:content];
    [self appendBulletWithLead:@"Light sensors"
                          body:@"The model reports 494 top and 494 bottom PMTs, rendered as a dense "
                               @"procedural sensor field. These planes convert prompt scintillation and "
                               @"delayed electroluminescence into photoelectrons (PE)."
                          to:content];
    [self appendBulletWithLead:@"DAQ"
                          body:@"Readout and event reconstruction. The terminal is the simplified "
                               @"reconstruction display: it reports timing, position, signals, and a ruling."
                          to:content];
    [self appendBulletWithLead:@"Site and depth"
                          body:@"The base and telemetry represent an underground laboratory with roughly "
                               @"1.5 km of rock overburden; the rock itself is not modeled as geometry."
                          to:content];

    [self appendSection:@"WHAT THE SIMULATION MODELS" to:content];
    [self appendSubheading:@"The event loop" to:content];
    [self appendNumberedStep:1 body:
        @"Interaction — the selected particle deposits energy at a random point inside the active "
        @"fiducial volume."
                             to:content];
    [self appendNumberedStep:2 body:
        @"S1 — excited xenon atoms release prompt ultraviolet scintillation. The scene renders this "
        @"as a compact white-blue flash near the interaction point."
                             to:content];
    [self appendNumberedStep:3 body:
        @"Drift — the electric field pushes ionization electrons upward. The yellow tracer and particle "
        @"trail make the path visible. Higher field means faster drift; higher density means more "
        @"scattering and slower drift."
                             to:content];
    [self appendNumberedStep:4 body:
        @"S2 — at the liquid-gas interface, electrons are extracted into the gas and produce "
        @"electroluminescence. The top PMT plane sees a larger, delayed orange-white flash."
                             to:content];
    [self appendNumberedStep:5 body:
        @"Ruling — S1, S2, and their ratio are compared with a simplified nuclear-recoil selection. "
        @"The terminal labels the event as a candidate or a vetoed background."
                             to:content];

    [self appendSection:@"HOW THE SIGNALS ARE INTERPRETED" to:content];
    [self appendParagraph:
        @"S1 is the prompt-light signal. S2 is the delayed ionization signal. S2/S1 is the primary "
        @"separation observable: nuclear recoils tend to produce relatively little charge for a given "
        @"amount of light, while electron recoils produce much more."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];
    [self appendBulletWithLead:@"WIMP"
                          body:@"A nuclear recoil inside the fiducial volume that passes the generous "
                               @"WIMP signal window becomes a confirmed candidate. This is the alert path "
                               @"the simulator is designed to demonstrate."
                          to:content];
    [self appendBulletWithLead:@"Background neutron"
                          body:@"Also a nuclear recoil, but labeled as a vetoed background in this "
                               @"single-scatter demonstration. A real analysis would use additional "
                               @"multiplicity, shielding, and coincidence information."
                          to:content];
    [self appendBulletWithLead:@"Cosmic-ray electron"
                          body:@"An electronic recoil with a high S2/S1 ratio, rejected by the "
                               @"nuclear-recoil discrimination band."
                          to:content];
    [self appendNote:
        @"The confidence percentages and photoelectron counts are illustrative. The candidate/veto "
        @"decision is deterministic for the selected particle type and fiducial check in this "
        @"educational model."
                   to:content];

    [self appendSection:@"THE SIMPLIFIED PHYSICS" to:content];
    [self appendParagraph:
        @"The drift model is intentionally compact. It captures the two effects the controls expose: "
        @"a stronger field accelerates electrons, while a denser liquid increases scattering and slows "
        @"them."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];
    [self appendFormula:[NSString stringWithFormat:
        @"v_drift = %.2f mm/µs × (E / %.2f kV/cm) × (%.2f g/cm³ / ρ)",
        DMDReferenceDriftVelocityMMPerMicrosecond,
        DMDReferenceFieldKVPerCm,
        DMDReferenceDensityGPerCm3]
                     to:content];
    [self appendFormula:[NSString stringWithFormat:
        @"Δt = depth / v_drift   •   active height = %.0f mm   •   %.0f mm per scene unit",
        DMDTPCHeightMM,
        DMDMillimetersPerSceneUnit]
                     to:content];
    [self appendParagraph:
        [NSString stringWithFormat:
            @"The result is clamped to %.2f–%.2f mm/µs so the scene remains stable at extreme slider "
            @"settings. At the reference configuration, a full-depth %.0f mm event takes about 1000 µs.",
            DMDMinDriftVelocityMMPerMicrosecond,
            DMDMaxDriftVelocityMMPerMicrosecond,
            DMDTPCHeightMM]
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];
    [self appendParagraph:
        @"The visible drift is time-lapsed and clamped to 0.35–3.0 seconds for legibility. Roughly one "
        @"second on screen represents 1000 µs of simulated time; the terminal always reports the exact "
        @"model value in microseconds."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];

    [self appendSection:@"BACKGROUND REJECTION" to:content];
    [self appendParagraph:
        @"Background suppression is layered rather than a single cut. The underground rock overburden "
        @"suppresses cosmic-ray muons; the water shield and Gd-loaded veto absorb neutrons and external "
        @"gamma rays; the fiducial volume rejects events near boundaries; and S1/S2 discrimination "
        @"separates nuclear and electronic recoils. The cutaway makes those nested systems inspectable."
                        color:DMDHelpColor(0xAFC4D5, 1.0)
                           to:content];

    [self appendSection:@"WHAT THIS IS NOT" to:content];
    [self appendParagraph:
        @"This is an educational visual model, not a scientific analysis. Geometry, material response, "
        @"PMT behavior, event yields, and classification are deliberately simplified. Do not use the "
        @"output to infer real detector sensitivity, a limit on dark matter, or a discovery."
                        color:DMDHelpColor(0xC7D6E2, 1.0)
                           to:content];
    [self appendNote:
        @"Use the incident-particle menu and sliders to explore how a WIMP candidate, a neutron veto, "
        @"and an electron-recoil veto differ in the event loop and terminal."
                   to:content];

    return content;
}

- (void)appendSection:(NSString *)title
                   to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.paragraphSpacingBefore = content.length > 0 ? 15.0 : 0.0;
    paragraph.paragraphSpacing = 4.0;
    NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:
        [title stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: DMDHelpMonoFont(10.5, NSFontWeightSemibold),
            NSForegroundColorAttributeName: DMDHelpColor(0x5EE7FF, 1.0),
            NSKernAttributeName: @(1.2),
            NSParagraphStyleAttributeName: paragraph
        }];
    [content appendAttributedString:chunk];
}

- (void)appendSubheading:(NSString *)title
                      to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.paragraphSpacingBefore = 8.0;
    paragraph.paragraphSpacing = 3.0;
    NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:
        [title stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: DMDHelpColor(0xFFC46B, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }];
    [content appendAttributedString:chunk];
}

- (void)appendParagraph:(NSString *)text
                  color:(NSColor *)color
                     to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 3.0;
    paragraph.paragraphSpacing = 9.0;
    NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:
        [text stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: color,
            NSParagraphStyleAttributeName: paragraph
        }];
    [content appendAttributedString:chunk];
}

- (void)appendNumberedStep:(NSInteger)number
                      body:(NSString *)body
                        to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    paragraph.paragraphSpacing = 5.0;
    paragraph.headIndent = 18.0;

    NSMutableAttributedString *chunk = [[NSMutableAttributedString alloc] init];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:
        [NSString stringWithFormat:@"%ld.  ", (long)number]
        attributes:@{
            NSFontAttributeName: DMDHelpMonoFont(11.0, NSFontWeightSemibold),
            NSForegroundColorAttributeName: DMDHelpColor(0x5EE7FF, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:
        [body stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: DMDHelpColor(0xAFC4D5, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [content appendAttributedString:chunk];
}

- (void)appendBulletWithLead:(NSString *)lead
                        body:(NSString *)body
                          to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    paragraph.paragraphSpacing = 5.0;
    paragraph.headIndent = 14.0;

    NSMutableAttributedString *chunk = [[NSMutableAttributedString alloc] init];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:@"•  "
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: DMDHelpColor(0x5EE7FF, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:
        [lead stringByAppendingString:@"  "]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: DMDHelpColor(0xE5F2FA, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:
        [body stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: DMDHelpColor(0xAFC4D5, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [content appendAttributedString:chunk];
}

- (void)appendFormula:(NSString *)formula
                   to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.0;
    paragraph.paragraphSpacing = 8.0;
    paragraph.firstLineHeadIndent = 12.0;
    paragraph.headIndent = 12.0;
    NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:
        [formula stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: DMDHelpMonoFont(11.0, NSFontWeightRegular),
            NSForegroundColorAttributeName: DMDHelpColor(0x8FE9F7, 1.0),
            NSBackgroundColorAttributeName: DMDHelpColor(0x0A1B27, 0.92),
            NSParagraphStyleAttributeName: paragraph
        }];
    [content appendAttributedString:chunk];
}

- (void)appendNote:(NSString *)note
                to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    paragraph.paragraphSpacing = 10.0;
    paragraph.firstLineHeadIndent = 12.0;
    paragraph.headIndent = 12.0;

    NSMutableAttributedString *chunk = [[NSMutableAttributedString alloc] init];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:@"MODEL NOTE  "
        attributes:@{
            NSFontAttributeName: DMDHelpMonoFont(9.0, NSFontWeightSemibold),
            NSForegroundColorAttributeName: DMDHelpColor(0xFFC46B, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [chunk appendAttributedString:[[NSAttributedString alloc] initWithString:
        [note stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: DMDHelpColor(0x8DA7BA, 1.0),
            NSParagraphStyleAttributeName: paragraph
        }]];
    [content appendAttributedString:chunk];
}

@end
