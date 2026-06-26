#import <Cocoa/Cocoa.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DMDDetectorPartLabelSide) {
    DMDDetectorPartLabelSideLeft = 0,
    DMDDetectorPartLabelSideRight
};

/**
 * A selectable, annotated detector subsystem. The content node groups every
 * static node that belongs to the part so the view controller can isolate it
 * without mutating shared geometries or materials.
 */
@interface DMDDetectorPart : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *shortName;
@property (nonatomic, copy, readonly) NSString *specification;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, strong, readonly) NSColor *accentColor;
@property (nonatomic, readonly) SCNVector3 anchor;
@property (nonatomic, readonly) DMDDetectorPartLabelSide labelSide;
@property (nonatomic, strong, readonly) SCNNode *contentNode;
@property (nonatomic, readonly) NSInteger index;

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
                         shortName:(NSString *)shortName
                     specification:(NSString *)specification
                            detail:(NSString *)detail
                       accentColor:(NSColor *)accentColor
                            anchor:(SCNVector3)anchor
                         labelSide:(DMDDetectorPartLabelSide)labelSide
                       contentNode:(SCNNode *)contentNode
                             index:(NSInteger)index NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
