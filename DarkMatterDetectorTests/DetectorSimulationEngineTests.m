#import <XCTest/XCTest.h>

#import "DetectorSimulationEngine.h"
#import "DMDPhysicsConstants.h"

@interface DetectorSimulationEngineTests : XCTestCase

@property (nonatomic, strong) DetectorSimulationEngine *engine;

@end

@implementation DetectorSimulationEngineTests

- (void)setUp {
    [super setUp];
    self.engine = [[DetectorSimulationEngine alloc] init];
}

- (void)tearDown {
    self.engine = nil;
    [super tearDown];
}

- (void)testReferenceDriftVelocity {
    XCTAssertEqualWithAccuracy([self.engine calculateDriftVelocity],
                               DMDReferenceDriftVelocityMMPerMicrosecond,
                               1.0e-9);
}

- (void)testDriftVelocityIncreasesWithField {
    self.engine.driftFieldVoltage = 0.1;
    double lowFieldVelocity = [self.engine calculateDriftVelocity];
    self.engine.driftFieldVoltage = 1.5;
    double highFieldVelocity = [self.engine calculateDriftVelocity];
    XCTAssertGreaterThan(highFieldVelocity, lowFieldVelocity);
}

- (void)testDriftVelocityDecreasesWithDensity {
    self.engine.xenonDensity = 2.5;
    double lowDensityVelocity = [self.engine calculateDriftVelocity];
    self.engine.xenonDensity = 4.0;
    double highDensityVelocity = [self.engine calculateDriftVelocity];
    XCTAssertLessThan(highDensityVelocity, lowDensityVelocity);
}

- (void)testDriftTimeUsesDepthOverVelocity {
    self.engine.xenonDensity = 3.0;
    self.engine.driftFieldVoltage = 0.4;
    double velocity = [self.engine calculateDriftVelocity];
    double driftTime = [self.engine calculateDriftTimeForDepth:1000.0];
    XCTAssertEqualWithAccuracy(driftTime, 1000.0 / velocity, 1.0e-9);
}

- (void)testFullHeightDriftTimeAtReferenceConditions {
    double driftTime = [self.engine calculateDriftTimeForDepth:DMDTPCHeightMM];
    XCTAssertEqualWithAccuracy(driftTime, 1000.0, 1.0e-6);
    XCTAssertEqualWithAccuracy([self.engine calculateDriftTimeForDepth:0.0], 0.0, 1.0e-12);
}

- (void)testInputClamping {
    self.engine.xenonDensity = 0.0;
    XCTAssertEqualWithAccuracy(self.engine.xenonDensity, DMDDensityMinGPerCm3, 1.0e-12);

    self.engine.xenonDensity = 100.0;
    XCTAssertEqualWithAccuracy(self.engine.xenonDensity, DMDDensityMaxGPerCm3, 1.0e-12);

    self.engine.driftFieldVoltage = -4.0;
    XCTAssertEqualWithAccuracy(self.engine.driftFieldVoltage, DMDDriftFieldMinKVPerCm, 1.0e-12);

    self.engine.driftFieldVoltage = 50.0;
    XCTAssertEqualWithAccuracy(self.engine.driftFieldVoltage, DMDDriftFieldMaxKVPerCm, 1.0e-12);
}

- (void)testWIMPCandidateClassification {
    BOOL candidate = [self.engine isDarkMatterCandidateForParticleType:DMDParticleTypeWIMP
                                                                   s1:40.0
                                                                   s2:600.0
                                                           inFiducial:YES];
    XCTAssertTrue(candidate);

    BOOL outsideFiducial = [self.engine isDarkMatterCandidateForParticleType:DMDParticleTypeWIMP
                                                                         s1:40.0
                                                                         s2:600.0
                                                                 inFiducial:NO];
    XCTAssertFalse(outsideFiducial);
}

- (void)testBackgroundParticlesAreVetoed {
    BOOL neutron = [self.engine isDarkMatterCandidateForParticleType:DMDParticleTypeBackgroundNeutron
                                                                  s1:40.0
                                                                  s2:600.0
                                                          inFiducial:YES];
    BOOL electron = [self.engine isDarkMatterCandidateForParticleType:DMDParticleTypeCosmicRayElectron
                                                                   s1:40.0
                                                                   s2:600.0
                                                           inFiducial:YES];
    XCTAssertFalse(neutron);
    XCTAssertFalse(electron);
}

- (void)testElectronSignalRatioExceedsWIMPWindow {
    self.engine.particleType = DMDParticleTypeCosmicRayElectron;
    DMDEventResult *electronResult = [self.engine simulateEventAtXMillimeters:0.0
                                                               yMillimeters:0.0
                                                               zMillimeters:0.0
                                                          depthMillimeters:500.0];
    XCTAssertGreaterThan(electronResult.s2s1Ratio, DMDWIMPClassificationMaxS2S1Ratio);
    XCTAssertFalse(electronResult.isCandidate);
}

- (void)testEventResultIsFiniteAndBound {
    self.engine.particleType = DMDParticleTypeWIMP;
    DMDEventResult *result = [self.engine simulateEventAtXMillimeters:120.0
                                                        yMillimeters:220.0
                                                        zMillimeters:-80.0
                                                   depthMillimeters:930.0];
    XCTAssertTrue(isfinite(result.driftTimeMicroseconds));
    XCTAssertTrue(isfinite(result.driftVelocity));
    XCTAssertTrue(isfinite(result.s1PE));
    XCTAssertTrue(isfinite(result.s2PE));
    XCTAssertTrue(result.driftTimeMicroseconds >= 0.0);
    XCTAssertTrue(result.s1PE >= 0.0);
    XCTAssertTrue(result.s2PE >= 0.0);
    XCTAssertTrue(result.isInFiducial);
    XCTAssertTrue(result.isCandidate);
}

@end
