#import <Cocoa/Cocoa.h>
#import <SceneKit/SceneKit.h>

@class DMDDetectorPart;

NS_ASSUME_NONNULL_BEGIN

/**
 * Everything the view controller needs to attach and animate an event. The
 * builder owns the static detector graph; transient flashes are added to
 * eventRoot and removed after each simulation. parts holds the annotated
 * subsystems displayed by the component inspector.
 */
@interface DMDDetectorSceneContext : NSObject

@property (nonatomic, strong, readonly) SCNScene *scene;
@property (nonatomic, strong, readonly) SCNNode *detectorRoot;
@property (nonatomic, strong, readonly) SCNNode *eventRoot;
@property (nonatomic, strong, readonly) SCNNode *cameraNode;
@property (nonatomic, readonly) SCNVector3 cameraHomePosition;
@property (nonatomic, readonly) SCNVector3 cameraHomeTarget;
@property (nonatomic, readonly) CGFloat cameraHomeFieldOfView;
@property (nonatomic, strong, readonly) NSArray<SCNNode *> *topPMTNodes;
@property (nonatomic, strong, readonly) NSArray<SCNNode *> *bottomPMTNodes;
@property (nonatomic, copy, readonly) NSArray<DMDDetectorPart *> *parts;
@property (nonatomic, strong, readonly) NSImage *particleGlowImage;
@property (nonatomic, strong, readonly) NSColor *backgroundColor;
@property (nonatomic, readonly) CGFloat tpcTopY;
@property (nonatomic, readonly) CGFloat tpcBottomY;
@property (nonatomic, readonly) CGFloat tpcRadius;

@end

@interface DetectorSceneBuilder : NSObject

- (DMDDetectorSceneContext *)buildScene;

@end

NS_ASSUME_NONNULL_END
