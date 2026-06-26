#import "DMDDetectorPart.h"

@implementation DMDDetectorPart

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
                         shortName:(NSString *)shortName
                     specification:(NSString *)specification
                            detail:(NSString *)detail
                       accentColor:(NSColor *)accentColor
                            anchor:(SCNVector3)anchor
                         labelSide:(DMDDetectorPartLabelSide)labelSide
                       contentNode:(SCNNode *)contentNode
                             index:(NSInteger)index {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _displayName = [displayName copy];
        _shortName = [shortName copy];
        _specification = [specification copy];
        _detail = [detail copy];
        _accentColor = accentColor;
        _anchor = anchor;
        _labelSide = labelSide;
        _contentNode = contentNode;
        _index = index;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<DMDDetectorPart %@: %@>", self.identifier, self.displayName];
}

@end
