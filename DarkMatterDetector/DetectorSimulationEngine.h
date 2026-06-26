#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DMDParticleType) {
    DMDParticleTypeWIMP = 0,
    DMDParticleTypeBackgroundNeutron,
    DMDParticleTypeCosmicRayElectron
};

/**
 * Immutable result of one simulated interaction. This object contains only
 * Foundation types so the physics layer remains independent of AppKit/SceneKit.
 */
@interface DMDEventResult : NSObject

@property (nonatomic, readonly) DMDParticleType particleType;
@property (nonatomic, copy, readonly) NSString *particleName;
@property (nonatomic, readonly) double xenonDensity;       // g/cm3
@property (nonatomic, readonly) double driftField;         // kV/cm
@property (nonatomic, readonly) double driftVelocity;      // mm/us
@property (nonatomic, readonly) double driftTimeMicroseconds;
@property (nonatomic, readonly) double depthMillimeters;
@property (nonatomic, readonly) double xMillimeters;
@property (nonatomic, readonly) double yMillimeters;
@property (nonatomic, readonly) double zMillimeters;
@property (nonatomic, readonly) double s1PE;
@property (nonatomic, readonly) double s2PE;
@property (nonatomic, readonly) double s2s1Ratio;
@property (nonatomic, readonly) double confidence;
@property (nonatomic, readonly, getter=isCandidate) BOOL candidate;
@property (nonatomic, readonly, getter=isInFiducial) BOOL inFiducial;
@property (nonatomic, copy, readonly) NSString *classification;
@property (nonatomic, copy, readonly) NSString *reason;

@end

@interface DetectorSimulationEngine : NSObject

@property (nonatomic) DMDParticleType particleType;
@property (nonatomic) double xenonDensity;        // clamped to 2.5 ... 4.0 g/cm3
@property (nonatomic) double driftFieldVoltage;   // clamped to 0.1 ... 2.0 kV/cm
@property (nonatomic) double wimpMassGeV;         // clamped to 5 ... 1000 GeV/c2

- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * Simplified LXe electron drift model:
 *   v_d = v_ref * (E / E_ref) * (rho_ref / rho)
 * Higher field accelerates electrons; higher density increases scattering.
 * Real liquid-xenon drift velocity saturates at high fields, so the model is
 * clamped to a stable range for visualization.
 */
- (double)calculateDriftVelocity;

/**
 * Time-of-flight for electrons travelling upward from a collision depth.
 * Depth is measured downward from the liquid-gas boundary at y = +3.0.
 */
- (double)calculateDriftTimeForDepth:(double)depthMM;

- (BOOL)isDarkMatterCandidateForParticleType:(DMDParticleType)type
                                          s1:(double)s1PE
                                          s2:(double)s2PE
                                  inFiducial:(BOOL)inFiducial;

/**
 * Generate S1/S2 estimates and the safety ruling for one event. The supplied
 * coordinates are physical millimetres relative to the TPC centre.
 */
- (DMDEventResult *)simulateEventAtXMillimeters:(double)xMillimeters
                                      yMillimeters:(double)yMillimeters
                                      zMillimeters:(double)zMillimeters
                                     depthMillimeters:(double)depthMillimeters;

- (NSString *)displayNameForParticleType:(DMDParticleType)type;

@end

NS_ASSUME_NONNULL_END
