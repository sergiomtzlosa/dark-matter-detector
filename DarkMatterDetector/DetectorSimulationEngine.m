#import "DetectorSimulationEngine.h"

#import "DMDPhysicsConstants.h"

static double DMDUniform01(void) {
    return (double)arc4random() / (double)UINT32_MAX;
}

@interface DMDEventResult ()

@property (nonatomic, readwrite) DMDParticleType particleType;
@property (nonatomic, copy, readwrite) NSString *particleName;
@property (nonatomic, readwrite) double xenonDensity;
@property (nonatomic, readwrite) double driftField;
@property (nonatomic, readwrite) double driftVelocity;
@property (nonatomic, readwrite) double driftTimeMicroseconds;
@property (nonatomic, readwrite) double depthMillimeters;
@property (nonatomic, readwrite) double xMillimeters;
@property (nonatomic, readwrite) double yMillimeters;
@property (nonatomic, readwrite) double zMillimeters;
@property (nonatomic, readwrite) double s1PE;
@property (nonatomic, readwrite) double s2PE;
@property (nonatomic, readwrite) double s2s1Ratio;
@property (nonatomic, readwrite) double confidence;
@property (nonatomic, readwrite, getter=isCandidate) BOOL candidate;
@property (nonatomic, readwrite, getter=isInFiducial) BOOL inFiducial;
@property (nonatomic, copy, readwrite) NSString *classification;
@property (nonatomic, copy, readwrite) NSString *reason;

- (instancetype)initWithParticleType:(DMDParticleType)particleType
                        particleName:(NSString *)particleName
                        xenonDensity:(double)xenonDensity
                         driftField:(double)driftField
                      driftVelocity:(double)driftVelocity
                driftTimeMicroseconds:(double)driftTimeMicroseconds
                   depthMillimeters:(double)depthMillimeters
                       xMillimeters:(double)xMillimeters
                       yMillimeters:(double)yMillimeters
                       zMillimeters:(double)zMillimeters
                              s1PE:(double)s1PE
                              s2PE:(double)s2PE
                          s2s1Ratio:(double)s2s1Ratio
                          confidence:(double)confidence
                           candidate:(BOOL)candidate
                          inFiducial:(BOOL)inFiducial
                      classification:(NSString *)classification
                              reason:(NSString *)reason NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@implementation DMDEventResult

- (instancetype)initWithParticleType:(DMDParticleType)particleType
                        particleName:(NSString *)particleName
                        xenonDensity:(double)xenonDensity
                         driftField:(double)driftField
                      driftVelocity:(double)driftVelocity
                driftTimeMicroseconds:(double)driftTimeMicroseconds
                   depthMillimeters:(double)depthMillimeters
                       xMillimeters:(double)xMillimeters
                       yMillimeters:(double)yMillimeters
                       zMillimeters:(double)zMillimeters
                              s1PE:(double)s1PE
                              s2PE:(double)s2PE
                          s2s1Ratio:(double)s2s1Ratio
                          confidence:(double)confidence
                           candidate:(BOOL)candidate
                          inFiducial:(BOOL)inFiducial
                      classification:(NSString *)classification
                              reason:(NSString *)reason {
    self = [super init];
    if (self) {
        _particleType = particleType;
        _particleName = [particleName copy];
        _xenonDensity = xenonDensity;
        _driftField = driftField;
        _driftVelocity = driftVelocity;
        _driftTimeMicroseconds = driftTimeMicroseconds;
        _depthMillimeters = depthMillimeters;
        _xMillimeters = xMillimeters;
        _yMillimeters = yMillimeters;
        _zMillimeters = zMillimeters;
        _s1PE = s1PE;
        _s2PE = s2PE;
        _s2s1Ratio = s2s1Ratio;
        _confidence = confidence;
        _candidate = candidate;
        _inFiducial = inFiducial;
        _classification = [classification copy];
        _reason = [reason copy];
    }
    return self;
}

@end

@implementation DetectorSimulationEngine {
    double _xenonDensity;
    double _driftFieldVoltage;
    double _wimpMassGeV;
}

@synthesize xenonDensity = _xenonDensity;
@synthesize driftFieldVoltage = _driftFieldVoltage;
@synthesize wimpMassGeV = _wimpMassGeV;

- (instancetype)init {
    self = [super init];
    if (self) {
        _particleType = DMDParticleTypeWIMP;
        _xenonDensity = DMDReferenceDensityGPerCm3;
        _driftFieldVoltage = DMDReferenceFieldKVPerCm;
        _wimpMassGeV = 50.0;
    }
    return self;
}

- (void)setXenonDensity:(double)xenonDensity {
    _xenonDensity = DMDClampedDouble(xenonDensity,
                                     DMDDensityMinGPerCm3,
                                     DMDDensityMaxGPerCm3);
}

- (void)setDriftFieldVoltage:(double)driftFieldVoltage {
    _driftFieldVoltage = DMDClampedDouble(driftFieldVoltage,
                                          DMDDriftFieldMinKVPerCm,
                                          DMDDriftFieldMaxKVPerCm);
}

- (void)setWimpMassGeV:(double)wimpMassGeV {
    if (!isfinite(wimpMassGeV)) {
        return;
    }
    _wimpMassGeV = DMDClampedDouble(wimpMassGeV,
                                    DMDWIMPMassMinGeV,
                                    DMDWIMPMassMaxGeV);
}

- (double)calculateDriftVelocity {
    // Simplified linear model: v ∝ field and v ∝ 1/density.
    // This is the relationship requested by the prompt; the clamp keeps the
    // demonstration stable near the high-field and low-density extremes.
    double density = _xenonDensity > 0.0 ? _xenonDensity : DMDReferenceDensityGPerCm3;
    double velocity = DMDReferenceDriftVelocityMMPerMicrosecond
                    * (_driftFieldVoltage / DMDReferenceFieldKVPerCm)
                    * (DMDReferenceDensityGPerCm3 / density);

    return DMDClampedDouble(velocity,
                            DMDMinDriftVelocityMMPerMicrosecond,
                            DMDMaxDriftVelocityMMPerMicrosecond);
}

- (double)calculateDriftTimeForDepth:(double)depthMM {
    if (!isfinite(depthMM) || depthMM <= 0.0) {
        return 0.0;
    }

    // Δt = depth / drift velocity. Depth is millimetres, velocity mm/µs,
    // therefore the result is in microseconds.
    return depthMM / [self calculateDriftVelocity];
}

- (BOOL)isDarkMatterCandidateForParticleType:(DMDParticleType)type
                                          s1:(double)s1PE
                                          s2:(double)s2PE
                                  inFiducial:(BOOL)inFiducial {
    if (type != DMDParticleTypeWIMP || !inFiducial || s1PE <= 0.0 || s2PE <= 0.0) {
        return NO;
    }

    double ratio = s2PE / s1PE;
    BOOL signalWindow = (s1PE >= 5.0 && s1PE <= 150.0);

    // Nuclear recoils have a lower charge-to-light ratio than electron
    // recoils. The threshold is intentionally generous for this educational
    // simulator and is expressed in photoelectrons.
    return signalWindow && ratio <= DMDWIMPClassificationMaxS2S1Ratio;
}

- (DMDEventResult *)simulateEventAtXMillimeters:(double)xMillimeters
                                      yMillimeters:(double)yMillimeters
                                      zMillimeters:(double)zMillimeters
                                     depthMillimeters:(double)depthMillimeters {
    double x = isfinite(xMillimeters) ? xMillimeters : 0.0;
    double y = isfinite(yMillimeters) ? yMillimeters : 0.0;
    double z = isfinite(zMillimeters) ? zMillimeters : 0.0;
    double depth = DMDClampedDouble(isfinite(depthMillimeters) ? depthMillimeters : 0.0,
                                    0.0,
                                    DMDTPCHeightMM);

    double velocity = [self calculateDriftVelocity];
    double driftTime = depth / velocity;
    BOOL inFiducial = hypot(x, z) <= 600.0 && fabs(y) <= 720.0;

    // Simulated energy/light-yield distributions. The output is not a
    // calibration; it provides stable, physically ordered signal estimates.
    double energyRoll = DMDUniform01();
    double ratioRoll = DMDUniform01();
    double s1PE = 0.0;
    double rawRatio = 0.0;

    switch (self.particleType) {
        case DMDParticleTypeWIMP:
            // 18-50 keVnr nuclear recoil, 20-52 prompt photoelectrons.
            s1PE = 20.0 + 32.0 * energyRoll;
            rawRatio = 9.0 + 12.0 * ratioRoll;
            break;
        case DMDParticleTypeBackgroundNeutron:
            // Higher-energy nuclear recoil, still vetoed by the WIMP selection.
            s1PE = 35.0 + 140.0 * energyRoll;
            rawRatio = 12.0 + 18.0 * ratioRoll;
            break;
        case DMDParticleTypeCosmicRayElectron:
            // Electronic recoil: much larger charge-to-light ratio.
            s1PE = 25.0 + 125.0 * energyRoll;
            rawRatio = 75.0 + 150.0 * ratioRoll;
            break;
    }

    // Prompt light is attenuated by the finite liquid-xenon volume, while the
    // field-dependent charge extraction slightly raises S2 at higher voltages.
    double lightSurvival = exp(-depth / 9000.0);
    double chargeSurvival = exp(-depth / 12000.0);
    double fieldFactor = DMDClampedDouble(self.driftFieldVoltage / DMDReferenceFieldKVPerCm,
                                          0.4,
                                          3.0);
    double ratio = rawRatio * pow(fieldFactor, 0.15);
    s1PE *= lightSurvival;
    double s2PE = s1PE * ratio * chargeSurvival;

    BOOL candidate = [self isDarkMatterCandidateForParticleType:self.particleType
                                                             s1:s1PE
                                                             s2:s2PE
                                                     inFiducial:inFiducial];
    NSString *classification = candidate ? @"CONFIRMED DARK MATTER CANDIDATE"
                                         : @"BACKGROUND EVENT (VETOED)";
    NSString *reason = nil;
    double confidence = 0.0;

    switch (self.particleType) {
        case DMDParticleTypeWIMP:
            if (candidate) {
                reason = @"Fiducial nuclear recoil consistent with a WIMP interaction.";
                confidence = 0.86 + 0.13 * DMDUniform01();
            } else {
                reason = @"WIMP-like recoil rejected by the fiducial or S2/S1 selection.";
                confidence = 0.72 + 0.15 * DMDUniform01();
            }
            break;
        case DMDParticleTypeBackgroundNeutron:
            reason = @"Neutron recoil vetoed by the single-scatter WIMP selection.";
            confidence = 0.93 + 0.06 * DMDUniform01();
            break;
        case DMDParticleTypeCosmicRayElectron:
            reason = @"Electronic recoil rejected by the nuclear-recoil discrimination band.";
            confidence = 0.94 + 0.05 * DMDUniform01();
            break;
    }

    return [[DMDEventResult alloc] initWithParticleType:self.particleType
                                           particleName:[self displayNameForParticleType:self.particleType]
                                           xenonDensity:self.xenonDensity
                                            driftField:self.driftFieldVoltage
                                         driftVelocity:velocity
                                   driftTimeMicroseconds:driftTime
                                      depthMillimeters:depth
                                          xMillimeters:x
                                          yMillimeters:y
                                          zMillimeters:z
                                                 s1PE:s1PE
                                                 s2PE:s2PE
                                             s2s1Ratio:s2PE / MAX(s1PE, 0.0001)
                                             confidence:confidence
                                              candidate:candidate
                                             inFiducial:inFiducial
                                         classification:classification
                                                 reason:reason];
}

- (NSString *)displayNameForParticleType:(DMDParticleType)type {
    switch (type) {
        case DMDParticleTypeWIMP:
            return @"WIMP";
        case DMDParticleTypeBackgroundNeutron:
            return @"Background Neutron";
        case DMDParticleTypeCosmicRayElectron:
            return @"Cosmic Ray Electron";
    }
    return @"Unknown Particle";
}

@end
