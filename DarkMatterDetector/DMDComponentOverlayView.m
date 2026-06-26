#import "DMDComponentOverlayView.h"

#import "DMDDetectorPart.h"

static NSColor *DMDOverlayColor(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:(CGFloat)((rgb >> 16) & 0xFF) / 255.0
                                green:(CGFloat)((rgb >> 8) & 0xFF) / 255.0
                                 blue:(CGFloat)(rgb & 0xFF) / 255.0
                                alpha:alpha];
}

static CGFloat DMDClampedOverlayCoordinate(CGFloat value, CGFloat minimum, CGFloat maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

@interface DMDComponentOverlayView ()

@property (nonatomic, strong) NSMutableArray<NSButton *> *chips;

@end

@implementation DMDComponentOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _chips = [NSMutableArray array];
        _selectedIndex = -1;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.accessibilityIdentifier = @"componentOverlay";
    }
    return self;
}

- (void)setParts:(NSArray<DMDDetectorPart *> *)parts {
    _parts = [parts copy];
    [self rebuildChips];
    [self setNeedsLayout:YES];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self updateChipStyles];
    [self setNeedsDisplay:YES];
}

- (void)setSceneView:(SCNView *)sceneView {
    _sceneView = sceneView;
    [self setNeedsDisplay:YES];
}

- (void)setDetectorRoot:(SCNNode *)detectorRoot {
    _detectorRoot = detectorRoot;
    [self setNeedsDisplay:YES];
}

#pragma mark - Label construction

- (void)rebuildChips {
    for (NSButton *chip in self.chips) {
        [chip removeFromSuperview];
    }
    [self.chips removeAllObjects];

    for (NSUInteger index = 0; index < self.parts.count; index++) {
        DMDDetectorPart *part = self.parts[index];
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        button.bordered = NO;
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.buttonType = NSButtonTypeMomentaryChange;
        button.focusRingType = NSFocusRingTypeNone;
        button.alignment = NSTextAlignmentLeft;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 6.0;
        button.layer.borderWidth = 0.8;
        button.layer.masksToBounds = YES;
        button.tag = (NSInteger)index;
        button.target = self;
        button.action = @selector(chipPressed:);
        button.toolTip = [NSString stringWithFormat:@"%@ — %@", part.displayName, part.detail];
        button.accessibilityIdentifier = [NSString stringWithFormat:@"part-%@", part.identifier];
        button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:button];
        [self.chips addObject:button];
    }

    [self updateChipStyles];
    [self setNeedsLayout:YES];
}

- (NSAttributedString *)titleForPart:(DMDDetectorPart *)part selected:(BOOL)selected {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentLeft;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;

    NSColor *textColor = selected ? DMDOverlayColor(0xF2FAFF, 1.0) : DMDOverlayColor(0x9DB5C7, 1.0);
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"●  %@", part.shortName]
            attributes:@{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.5 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: textColor,
                NSKernAttributeName: @(0.55),
                NSParagraphStyleAttributeName: paragraph
            }];
    [title addAttribute:NSForegroundColorAttributeName
                  value:part.accentColor
                  range:NSMakeRange(0, 1)];
    return title;
}

- (void)updateChipStyles {
    for (NSUInteger index = 0; index < self.chips.count && index < self.parts.count; index++) {
        DMDDetectorPart *part = self.parts[index];
        NSButton *chip = self.chips[index];
        BOOL selected = (NSInteger)index == self.selectedIndex;
        chip.attributedTitle = [self titleForPart:part selected:selected];
        chip.layer.backgroundColor = selected
            ? [part.accentColor colorWithAlphaComponent:0.19].CGColor
            : DMDOverlayColor(0x08131F, 0.84).CGColor;
        chip.layer.borderColor = selected
            ? [part.accentColor colorWithAlphaComponent:0.92].CGColor
            : DMDOverlayColor(0x294352, 0.78).CGColor;
        chip.layer.borderWidth = selected ? 1.35 : 0.75;
    }
}

- (void)chipPressed:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.parts.count) {
        return;
    }
    if (self.partSelectedHandler) {
        self.partSelectedHandler(index);
    }
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    [self layoutChips];
    [self setNeedsDisplay:YES];
}

- (void)layoutChips {
    NSUInteger count = MIN(self.chips.count, self.parts.count);
    if (count == 0 || self.bounds.size.width < 2.0 || self.bounds.size.height < 2.0) {
        return;
    }

    CGFloat width = MIN(184.0, MAX(128.0, (self.bounds.size.width - 28.0) * 0.22));
    CGFloat height = 28.0;
    CGFloat topInset = 150.0;
    CGFloat bottomInset = 96.0;
    CGFloat minGap = 10.0;
    CGFloat maxCenter = self.bounds.size.height - topInset - height * 0.5;
    CGFloat minCenter = bottomInset + height * 0.5;

    NSMutableArray<NSDictionary *> *leftEntries = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *rightEntries = [NSMutableArray array];
    NSInteger leftFallbackSlot = 0;
    NSInteger rightFallbackSlot = 0;

    for (NSUInteger index = 0; index < count; index++) {
        DMDDetectorPart *part = self.parts[index];
        BOOL isLeft = part.labelSide == DMDDetectorPartLabelSideLeft;
        CGFloat desiredCenter = NAN;

        if (self.sceneView) {
            SCNVector3 world = part.anchor;
            if (self.detectorRoot) {
                world = [self.detectorRoot convertPosition:part.anchor toNode:nil];
            }
            SCNVector3 projected = [self.sceneView projectPoint:world];
            if (isfinite(projected.x) && isfinite(projected.y)
                && projected.z >= 0.0 && projected.z <= 1.0) {
                desiredCenter = projected.y;
            }
        }

        if (!isfinite(desiredCenter)) {
            NSInteger slot = isLeft ? leftFallbackSlot : rightFallbackSlot;
            desiredCenter = maxCenter - (CGFloat)slot * (height + 18.0);
        }
        if (isLeft) {
            leftFallbackSlot++;
        } else {
            rightFallbackSlot++;
        }

        NSMutableArray<NSDictionary *> *entries = isLeft ? leftEntries : rightEntries;
        [entries addObject:@{
            @"index": @(index),
            @"center": @(desiredCenter)
        }];
    }

    [self layoutChipEntries:leftEntries
                     isLeft:YES
                      width:width
                     height:height
                  maxCenter:maxCenter
                  minCenter:minCenter
                     minGap:minGap];
    [self layoutChipEntries:rightEntries
                     isLeft:NO
                      width:width
                     height:height
                  maxCenter:maxCenter
                  minCenter:minCenter
                     minGap:minGap];
}

- (void)layoutChipEntries:(NSArray<NSDictionary *> *)entries
                   isLeft:(BOOL)isLeft
                    width:(CGFloat)width
                   height:(CGFloat)height
                maxCenter:(CGFloat)maxCenter
                minCenter:(CGFloat)minCenter
                   minGap:(CGFloat)minGap {
    if (entries.count == 0) {
        return;
    }

    NSArray<NSDictionary *> *sorted = [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left,
                                                                                              NSDictionary *right) {
        return [right[@"center"] compare:left[@"center"]];
    }];

    NSMutableArray<NSNumber *> *centers = [NSMutableArray arrayWithCapacity:sorted.count];
    CGFloat nextMaxCenter = maxCenter;
    for (NSDictionary *entry in sorted) {
        CGFloat center = MIN([entry[@"center"] doubleValue], nextMaxCenter);
        [centers addObject:@(center)];
        nextMaxCenter = center - height - minGap;
    }

    CGFloat lowestCenter = centers.lastObject.doubleValue;
    CGFloat shift = MAX(0.0, minCenter - lowestCenter);
    if (shift > 0.0) {
        CGFloat highestCenter = centers.firstObject.doubleValue + shift;
        if (highestCenter > maxCenter) {
            shift -= (highestCenter - maxCenter);
        }
    }

    CGFloat x = isLeft
        ? 14.0
        : self.bounds.size.width - 14.0 - width;
    [sorted enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger position, BOOL *stop) {
        (void)stop;
        NSInteger index = [entry[@"index"] integerValue];
        CGFloat center = [centers[position] doubleValue] + shift;
        self.chips[(NSUInteger)index].frame = NSMakeRect(x, center - height * 0.5, width, height);
    }];
}

#pragma mark - Projection and drawing

- (void)refreshProjection {
    // Follow the camera so callout labels stay near their components when the
    // user orbits or zooms instead of sitting at stale fixed slots.
    [self layoutChips];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (!self.sceneView || self.parts.count == 0) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];

    for (NSUInteger index = 0; index < self.parts.count && index < self.chips.count; index++) {
        DMDDetectorPart *part = self.parts[index];
        NSButton *chip = self.chips[index];
        BOOL selected = (NSInteger)index == self.selectedIndex;
        NSRect chipFrame = chip.frame;

        SCNVector3 world = part.anchor;
        if (self.detectorRoot) {
            world = [self.detectorRoot convertPosition:part.anchor toNode:nil];
        }
        SCNVector3 projected = [self.sceneView projectPoint:world];
        if (!isfinite(projected.x) || !isfinite(projected.y) || projected.z < 0.0 || projected.z > 1.0) {
            continue;
        }

        NSPoint anchor = NSMakePoint(projected.x, projected.y);
        anchor.x = DMDClampedOverlayCoordinate(anchor.x, 5.0, self.bounds.size.width - 5.0);
        anchor.y = DMDClampedOverlayCoordinate(anchor.y, 5.0, self.bounds.size.height - 5.0);

        NSPoint labelEdge = part.labelSide == DMDDetectorPartLabelSideLeft
            ? NSMakePoint(NSMaxX(chipFrame) + 3.0, NSMidY(chipFrame))
            : NSMakePoint(NSMinX(chipFrame) - 3.0, NSMidY(chipFrame));

        // A short horizontal shoulder keeps the leader lines visually attached
        // to the labels instead of emerging from the text itself.
        NSPoint shoulder = part.labelSide == DMDDetectorPartLabelSideLeft
            ? NSMakePoint(labelEdge.x + 9.0, labelEdge.y)
            : NSMakePoint(labelEdge.x - 9.0, labelEdge.y);

        NSBezierPath *leader = [NSBezierPath bezierPath];
        [leader moveToPoint:labelEdge];
        [leader lineToPoint:shoulder];
        [leader lineToPoint:anchor];

        // A dark under-stroke keeps thin leader lines legible over the bright
        // transparent shells as well as the nearly black background.
        [[NSColor colorWithWhite:0.0 alpha:0.72] setStroke];
        leader.lineWidth = selected ? 3.4 : 2.4;
        [leader stroke];

        NSColor *lineColor = [part.accentColor colorWithAlphaComponent:selected ? 0.98 : 0.58];
        [lineColor setStroke];
        leader.lineWidth = selected ? 1.45 : 0.9;
        [leader stroke];

        CGFloat dotRadius = selected ? 4.6 : 3.1;
        NSRect dotRect = NSMakeRect(anchor.x - dotRadius,
                                    anchor.y - dotRadius,
                                    dotRadius * 2.0,
                                    dotRadius * 2.0);
        NSBezierPath *dotBed = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dotRect, -1.8, -1.8)];
        [[NSColor colorWithWhite:0.0 alpha:0.82] setFill];
        [dotBed fill];

        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:dotRect];
        [[part.accentColor colorWithAlphaComponent:selected ? 1.0 : 0.82] setFill];
        [dot fill];

        NSBezierPath *dotCore = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dotRect, 1.4, 1.4)];
        [[NSColor colorWithWhite:1.0 alpha:selected ? 0.9 : 0.5] setFill];
        [dotCore fill];

        if (selected) {
            NSBezierPath *halo = [NSBezierPath bezierPathWithOvalInRect:
                NSInsetRect(dotRect, -4.8, -4.8)];
            [[part.accentColor colorWithAlphaComponent:0.5] setStroke];
            halo.lineWidth = 1.2;
            [halo stroke];
        }
    }

    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Passthrough behavior

- (nullable NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (hit == nil || hit == self) {
        return nil;
    }
    return hit;
}

@end
