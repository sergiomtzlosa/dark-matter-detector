#import <Cocoa/Cocoa.h>
#import <SceneKit/SceneKit.h>

@class DMDDetectorPart;

NS_ASSUME_NONNULL_BEGIN

/**
 * Screen-space annotation layer for the 3D detector. Labels stay in fixed
 * technical-diagram slots at the left and right edges while leader lines track
 * their component anchors as the camera orbits. Only the label chips accept
 * mouse events; every other point falls through to the SCNView.
 */
@interface DMDComponentOverlayView : NSView

@property (nonatomic, weak, nullable) SCNView *sceneView;
@property (nonatomic, weak, nullable) SCNNode *detectorRoot;
@property (nonatomic, copy) NSArray<DMDDetectorPart *> *parts;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^partSelectedHandler)(NSInteger index);

- (void)refreshProjection;

@end

NS_ASSUME_NONNULL_END
