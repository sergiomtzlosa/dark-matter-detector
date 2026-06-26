#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// One SceneKit unit represents 250 mm. The active LXe volume is 6 units
// (1500 mm) tall and its liquid-gas interface is the mandatory y = +3.0 plane.
FOUNDATION_EXPORT const double DMDMillimetersPerSceneUnit;
FOUNDATION_EXPORT const double DMDTPCTopYScene;
FOUNDATION_EXPORT const double DMDTPCBottomYScene;
FOUNDATION_EXPORT const double DMDTPCHeightMM;
FOUNDATION_EXPORT const double DMDTPCRadiusScene;
FOUNDATION_EXPORT const double DMDTPCRadiusMM;

// Liquid xenon is commonly operated around 0.2 kV/cm and 2.9 g/cm3.
// The educational drift model is anchored to these reference conditions.
FOUNDATION_EXPORT const double DMDReferenceFieldKVPerCm;
FOUNDATION_EXPORT const double DMDReferenceDensityGPerCm3;
FOUNDATION_EXPORT const double DMDReferenceDriftVelocityMMPerMicrosecond;
FOUNDATION_EXPORT const double DMDMinDriftVelocityMMPerMicrosecond;
FOUNDATION_EXPORT const double DMDMaxDriftVelocityMMPerMicrosecond;

FOUNDATION_EXPORT const double DMDDensityMinGPerCm3;
FOUNDATION_EXPORT const double DMDDensityMaxGPerCm3;
FOUNDATION_EXPORT const double DMDDriftFieldMinKVPerCm;
FOUNDATION_EXPORT const double DMDDriftFieldMaxKVPerCm;
FOUNDATION_EXPORT const double DMDWIMPClassificationMaxS2S1Ratio;
FOUNDATION_EXPORT const double DMDWIMPMassMinGeV;
FOUNDATION_EXPORT const double DMDWIMPMassMaxGeV;

static inline double DMDClampedDouble(double value, double minimum, double maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

NS_ASSUME_NONNULL_END
