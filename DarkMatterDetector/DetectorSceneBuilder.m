#import "DetectorSceneBuilder.h"

#import "DMDDetectorPart.h"
#import "DMDPhysicsConstants.h"

static NSColor *DMDHexColor(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:(CGFloat)((rgb >> 16) & 0xFF) / 255.0
                                green:(CGFloat)((rgb >> 8) & 0xFF) / 255.0
                                 blue:(CGFloat)(rgb & 0xFF) / 255.0
                                alpha:alpha];
}

static CGFloat DMDDegrees(CGFloat degrees) {
    return degrees * (CGFloat)M_PI / 180.0;
}

static const SCNVector3 kDMDCameraHomePosition = {10.4f, 10.0f, 21.0f};
static const SCNVector3 kDMDCameraHomeTarget = {0.0f, -0.35f, 0.0f};
static const CGFloat kDMDCameraHomeFieldOfView = 39.0;

@interface DMDDetectorSceneContext ()

@property (nonatomic, strong, readwrite) SCNScene *scene;
@property (nonatomic, strong, readwrite) SCNNode *detectorRoot;
@property (nonatomic, strong, readwrite) SCNNode *eventRoot;
@property (nonatomic, strong, readwrite) SCNNode *cameraNode;
@property (nonatomic, readwrite) SCNVector3 cameraHomePosition;
@property (nonatomic, readwrite) SCNVector3 cameraHomeTarget;
@property (nonatomic, readwrite) CGFloat cameraHomeFieldOfView;
@property (nonatomic, strong, readwrite) NSArray<SCNNode *> *topPMTNodes;
@property (nonatomic, strong, readwrite) NSArray<SCNNode *> *bottomPMTNodes;
@property (nonatomic, copy, readwrite) NSArray<DMDDetectorPart *> *parts;
@property (nonatomic, strong, readwrite) NSImage *particleGlowImage;
@property (nonatomic, strong, readwrite) NSColor *backgroundColor;
@property (nonatomic, readwrite) CGFloat tpcTopY;
@property (nonatomic, readwrite) CGFloat tpcBottomY;
@property (nonatomic, readwrite) CGFloat tpcRadius;

@end

@implementation DMDDetectorSceneContext
@end

@interface DetectorSceneBuilder ()

@property (nonatomic, strong) NSColor *titaniumColor;
@property (nonatomic, strong) NSColor *goldColor;
@property (nonatomic, strong) NSImage *pmtArrayImage;

@end

@implementation DetectorSceneBuilder

- (instancetype)init {
    self = [super init];
    if (self) {
        _titaniumColor = DMDHexColor(0xC3CEDB, 1.0);
        _goldColor = DMDHexColor(0xE8B95E, 1.0);
    }
    return self;
}

- (DMDDetectorSceneContext *)buildScene {
    NSImage *backgroundImage = [self makeBackgroundImage];
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = backgroundImage;

    SCNNode *detectorRoot = [SCNNode node];
    detectorRoot.name = @"detectorRoot";
    [scene.rootNode addChildNode:detectorRoot];

    // The model is a cutaway: the source references are engineering cutaways,
    // and removing a 120-degree front wedge is what makes the nested systems
    // readable without sacrificing the density of the real detector.
    SCNNode *baseGroup = [self groupNodeNamed:@"siteBaseGroup" parent:detectorRoot];
    SCNNode *waterGroup = [self groupNodeNamed:@"waterShieldGroup" parent:detectorRoot];
    SCNNode *cryostatGroup = [self groupNodeNamed:@"cryostatGroup" parent:detectorRoot];
    SCNNode *vetoGroup = [self groupNodeNamed:@"vetoGroup" parent:detectorRoot];
    SCNNode *tpcGroup = [self groupNodeNamed:@"liquidXenonGroup" parent:detectorRoot];
    SCNNode *fieldGroup = [self groupNodeNamed:@"fieldCageGroup" parent:detectorRoot];
    SCNNode *arraysGroup = [self groupNodeNamed:@"lightSensorGroup" parent:detectorRoot];
    SCNNode *topArrayGroup = [self groupNodeNamed:@"topPMTArrayGroup" parent:arraysGroup];
    SCNNode *bottomArrayGroup = [self groupNodeNamed:@"bottomPMTArrayGroup" parent:arraysGroup];
    SCNNode *daqGroup = [self groupNodeNamed:@"daqGroup" parent:detectorRoot];

    [self addSiteBaseToRoot:baseGroup];
    [self addWaterShieldToRoot:waterGroup];
    [self addCryostatToRoot:cryostatGroup];
    [self addVetoToRoot:vetoGroup];
    [self addLiquidXenonTPCToRoot:tpcGroup];
    [self addFieldCageToRoot:fieldGroup];

    NSArray<SCNNode *> *topPMTs = [self addPMTArrayAtY:3.07
                                                  top:YES
                                                group:topArrayGroup];
    NSArray<SCNNode *> *bottomPMTs = [self addPMTArrayAtY:-3.07
                                                     top:NO
                                                   group:bottomArrayGroup];
    [self addDAQToRoot:daqGroup];

    // Transient flashes live outside the subsystem groups, so isolating a
    // component never dims an event or leaves stale event nodes behind.
    SCNNode *eventRoot = [SCNNode node];
    eventRoot.name = @"eventRoot";
    [detectorRoot addChildNode:eventRoot];

    SCNNode *cameraNode = [self addCameraToRoot:scene.rootNode];
    [self addLightingToRoot:scene.rootNode];

    NSArray<DMDDetectorPart *> *parts =
        [self makeDetectorPartsWithBase:baseGroup
                             waterGroup:waterGroup
                          cryostatGroup:cryostatGroup
                              vetoGroup:vetoGroup
                               tpcGroup:tpcGroup
                             fieldGroup:fieldGroup
                             arraysGroup:arraysGroup
                                daqGroup:daqGroup];

    DMDDetectorSceneContext *context = [[DMDDetectorSceneContext alloc] init];
    context.scene = scene;
    context.detectorRoot = detectorRoot;
    context.eventRoot = eventRoot;
    context.cameraNode = cameraNode;
    context.cameraHomePosition = kDMDCameraHomePosition;
    context.cameraHomeTarget = kDMDCameraHomeTarget;
    context.cameraHomeFieldOfView = kDMDCameraHomeFieldOfView;
    context.topPMTNodes = topPMTs;
    context.bottomPMTNodes = bottomPMTs;
    context.parts = parts;
    context.particleGlowImage = [self makeParticleGlowImage];
    context.backgroundColor = DMDHexColor(0x03070D, 1.0);
    context.tpcTopY = DMDTPCTopYScene;
    context.tpcBottomY = DMDTPCBottomYScene;
    context.tpcRadius = DMDTPCRadiusScene;
    return context;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Small node helpers

- (SCNNode *)groupNodeNamed:(NSString *)name parent:(SCNNode *)parent {
    SCNNode *node = [SCNNode node];
    node.name = name;
    [parent addChildNode:node];
    return node;
}

- (SCNNode *)nodeWithGeometry:(SCNGeometry *)geometry
                     material:(SCNMaterial *)material
                     position:(SCNVector3)position {
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    node.position = position;
    node.castsShadow = NO;
    if (material) {
        geometry.materials = @[material];
    }
    return node;
}

- (SCNNode *)cylinderWithRadius:(CGFloat)radius
                         height:(CGFloat)height
                       material:(SCNMaterial *)material
                       position:(SCNVector3)position {
    SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:radius height:height];
    geometry.radialSegmentCount = 64;
    return [self nodeWithGeometry:geometry material:material position:position];
}

- (SCNNode *)torusWithRingRadius:(CGFloat)ringRadius
                      pipeRadius:(CGFloat)pipeRadius
                        material:(SCNMaterial *)material
                        position:(SCNVector3)position {
    SCNTorus *geometry = [SCNTorus torusWithRingRadius:ringRadius pipeRadius:pipeRadius];
    geometry.ringSegmentCount = 128;
    geometry.pipeSegmentCount = 14;
    return [self nodeWithGeometry:geometry material:material position:position];
}

- (SCNNode *)boxWithWidth:(CGFloat)width
                   height:(CGFloat)height
                   length:(CGFloat)length
                 chamfer:(CGFloat)chamfer
                 material:(SCNMaterial *)material
                 position:(SCNVector3)position {
    SCNBox *geometry = [SCNBox boxWithWidth:width
                                    height:height
                                    length:length
                             chamferRadius:chamfer];
    return [self nodeWithGeometry:geometry material:material position:position];
}

- (SCNNode *)cylinderFromPoint:(SCNVector3)start
                       toPoint:(SCNVector3)end
                        radius:(CGFloat)radius
                      material:(SCNMaterial *)material {
    SCNVector3 delta = SCNVector3Make(end.x - start.x, end.y - start.y, end.z - start.z);
    CGFloat length = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z);
    if (length < 0.0001) {
        return [SCNNode node];
    }

    SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:radius height:length];
    geometry.radialSegmentCount = 12;
    geometry.materials = @[material];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    node.position = SCNVector3Make((start.x + end.x) * 0.5,
                                   (start.y + end.y) * 0.5,
                                   (start.z + end.z) * 0.5);
    node.castsShadow = NO;

    // The cylinder's local axis is +Y. Rotate that axis onto the requested
    // segment direction with an axis-angle quaternion.
    SCNVector3 axis = SCNVector3Make(delta.z, 0.0, -delta.x);
    CGFloat axisLength = sqrt(axis.x * axis.x + axis.z * axis.z);
    if (axisLength < 0.00001) {
        node.rotation = SCNVector4Make(1.0, 0.0, 0.0, delta.y >= 0.0 ? 0.0 : (CGFloat)M_PI);
    } else {
        CGFloat angle = acos(DMDClampedDouble(delta.y / length, -1.0, 1.0));
        node.rotation = SCNVector4Make(axis.x / axisLength,
                                       0.0,
                                       axis.z / axisLength,
                                       angle);
    }
    return node;
}

#pragma mark - Materials

- (SCNMaterial *)materialWithColor:(NSColor *)color
                         metalness:(CGFloat)metalness
                         roughness:(CGFloat)roughness
                           opacity:(CGFloat)opacity
                          emission:(nullable NSColor *)emission
                        writeDepth:(BOOL)writeDepth
                       doubleSided:(BOOL)doubleSided {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelPhysicallyBased;
    material.diffuse.contents = color;
    material.metalness.contents = @(metalness);
    material.roughness.contents = @(roughness);
    material.transparency = opacity;
    material.locksAmbientWithDiffuse = YES;
    material.doubleSided = doubleSided;
    material.blendMode = SCNBlendModeAlpha;
    material.writesToDepthBuffer = writeDepth;
    material.transparencyMode = SCNTransparencyModeAOne;
    material.emission.contents = emission ?: [NSColor blackColor];
    material.emission.intensity = emission ? 1.0 : 0.0;
    return material;
}

- (SCNMaterial *)glassMaterialWithColor:(NSColor *)color
                                 opacity:(CGFloat)opacity
                                emission:(nullable NSColor *)emission
                                  fresnel:(CGFloat)fresnel {
    SCNMaterial *material = [self materialWithColor:color
                                          metalness:0.0
                                          roughness:0.08
                                            opacity:opacity
                                           emission:emission
                                         writeDepth:NO
                                        doubleSided:YES];
    material.fresnelExponent = fresnel;
    return material;
}

- (SCNMaterial *)cutawayTintMaterialWithColor:(NSColor *)color
                                      opacity:(CGFloat)opacity
                                     emission:(nullable NSColor *)emission {
    // Large nested shells are intentionally flat-shaded. Physically based
    // highlights on multiple concentric transparent cylinders stack into a
    // white veil under scene lighting; a controlled flat tint preserves the
    // read-through that makes a cutaway useful.
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = color;
    material.transparency = opacity;
    material.transparencyMode = SCNTransparencyModeAOne;
    material.blendMode = SCNBlendModeAlpha;
    material.writesToDepthBuffer = NO;
    material.doubleSided = YES;
    material.emission.contents = emission ?: [NSColor blackColor];
    material.emission.intensity = emission ? 1.0 : 0.0;
    return material;
}

- (SCNMaterial *)metalMaterialWithColor:(NSColor *)color roughness:(CGFloat)roughness {
    return [self materialWithColor:color
                         metalness:0.9
                         roughness:roughness
                           opacity:1.0
                          emission:nil
                        writeDepth:YES
                       doubleSided:NO];
}

- (SCNMaterial *)glowMaterialWithColor:(NSColor *)color opacity:(CGFloat)opacity {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = color;
    material.emission.contents = color;
    material.emission.intensity = 1.5;
    material.transparency = opacity;
    material.blendMode = SCNBlendModeAdd;
    material.writesToDepthBuffer = NO;
    material.doubleSided = YES;
    return material;
}

#pragma mark - Geometry helpers

- (SCNGeometry *)partialCylinderGeometryWithRadius:(CGFloat)radius
                                            height:(CGFloat)height
                                        startAngle:(CGFloat)startAngle
                                          endAngle:(CGFloat)endAngle
                                          segments:(NSInteger)segments {
    NSInteger vertexCount = (segments + 1) * 2;
    NSMutableData *positions = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 3 * sizeof(float)];
    NSMutableData *normals = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 3 * sizeof(float)];
    NSMutableData *texcoords = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 2 * sizeof(float)];
    NSMutableData *indices = [NSMutableData dataWithCapacity:(NSUInteger)segments * 6 * sizeof(uint32_t)];
    CGFloat halfHeight = height * 0.5;

    for (NSInteger index = 0; index <= segments; index++) {
        CGFloat fraction = (CGFloat)index / (CGFloat)segments;
        CGFloat angle = startAngle + (endAngle - startAngle) * fraction;
        float nx = (float)cos(angle);
        float nz = (float)sin(angle);
        float px = (float)(radius * cos(angle));
        float pz = (float)(radius * sin(angle));
        float topY = (float)halfHeight;
        float bottomY = (float)-halfHeight;
        float topVertex[3] = {px, topY, pz};
        float bottomVertex[3] = {px, bottomY, pz};
        float normal[3] = {nx, 0.0f, nz};
        float topUV[2] = {(float)fraction, 1.0f};
        float bottomUV[2] = {(float)fraction, 0.0f};

        [positions appendBytes:topVertex length:sizeof(topVertex)];
        [positions appendBytes:bottomVertex length:sizeof(bottomVertex)];
        [normals appendBytes:normal length:sizeof(normal)];
        [normals appendBytes:normal length:sizeof(normal)];
        [texcoords appendBytes:topUV length:sizeof(topUV)];
        [texcoords appendBytes:bottomUV length:sizeof(bottomUV)];
    }

    for (NSInteger index = 0; index < segments; index++) {
        uint32_t top = (uint32_t)(index * 2);
        uint32_t bottom = top + 1;
        uint32_t nextTop = top + 2;
        uint32_t nextBottom = top + 3;
        uint32_t triangleA[3] = {top, nextTop, bottom};
        uint32_t triangleB[3] = {bottom, nextTop, nextBottom};
        [indices appendBytes:triangleA length:sizeof(triangleA)];
        [indices appendBytes:triangleB length:sizeof(triangleB)];
    }

    SCNGeometrySource *positionSource =
        [SCNGeometrySource geometrySourceWithData:positions
                                        semantic:SCNGeometrySourceSemanticVertex
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:3
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:3 * sizeof(float)];
    SCNGeometrySource *normalSource =
        [SCNGeometrySource geometrySourceWithData:normals
                                        semantic:SCNGeometrySourceSemanticNormal
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:3
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:3 * sizeof(float)];
    SCNGeometrySource *textureSource =
        [SCNGeometrySource geometrySourceWithData:texcoords
                                        semantic:SCNGeometrySourceSemanticTexcoord
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:2
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:2 * sizeof(float)];
    SCNGeometryElement *element =
        [SCNGeometryElement geometryElementWithData:indices
                                      primitiveType:SCNGeometryPrimitiveTypeTriangles
                                     primitiveCount:segments * 2
                                      bytesPerIndex:sizeof(uint32_t)];
    return [SCNGeometry geometryWithSources:@[positionSource, normalSource, textureSource]
                                   elements:@[element]];
}

- (SCNGeometry *)partialTorusGeometryWithRingRadius:(CGFloat)ringRadius
                                         pipeRadius:(CGFloat)pipeRadius
                                         startAngle:(CGFloat)startAngle
                                           endAngle:(CGFloat)endAngle
                                      majorSegments:(NSInteger)majorSegments
                                      minorSegments:(NSInteger)minorSegments {
    NSInteger majorCount = majorSegments + 1;
    NSInteger minorCount = minorSegments + 1;
    NSInteger vertexCount = majorCount * minorCount;
    NSMutableData *positions = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 3 * sizeof(float)];
    NSMutableData *normals = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 3 * sizeof(float)];
    NSMutableData *texcoords = [NSMutableData dataWithCapacity:(NSUInteger)vertexCount * 2 * sizeof(float)];
    NSMutableData *indices = [NSMutableData dataWithCapacity:(NSUInteger)majorSegments * (NSUInteger)minorSegments * 6 * sizeof(uint32_t)];

    for (NSInteger major = 0; major <= majorSegments; major++) {
        CGFloat majorFraction = (CGFloat)major / (CGFloat)majorSegments;
        CGFloat theta = startAngle + (endAngle - startAngle) * majorFraction;
        CGFloat cosTheta = cos(theta);
        CGFloat sinTheta = sin(theta);
        for (NSInteger minor = 0; minor <= minorSegments; minor++) {
            CGFloat minorFraction = (CGFloat)minor / (CGFloat)minorSegments;
            CGFloat phi = minorFraction * 2.0 * (CGFloat)M_PI;
            CGFloat cosPhi = cos(phi);
            CGFloat sinPhi = sin(phi);
            float nx = (float)(cosPhi * cosTheta);
            float ny = (float)sinPhi;
            float nz = (float)(cosPhi * sinTheta);
            float px = (float)((ringRadius + pipeRadius * cosPhi) * cosTheta);
            float py = (float)(pipeRadius * sinPhi);
            float pz = (float)((ringRadius + pipeRadius * cosPhi) * sinTheta);
            float position[3] = {px, py, pz};
            float normal[3] = {nx, ny, nz};
            float uv[2] = {(float)majorFraction, (float)minorFraction};
            [positions appendBytes:position length:sizeof(position)];
            [normals appendBytes:normal length:sizeof(normal)];
            [texcoords appendBytes:uv length:sizeof(uv)];
        }
    }

    for (NSInteger major = 0; major < majorSegments; major++) {
        for (NSInteger minor = 0; minor < minorSegments; minor++) {
            uint32_t a = (uint32_t)(major * minorCount + minor);
            uint32_t b = a + 1;
            uint32_t c = (uint32_t)((major + 1) * minorCount + minor);
            uint32_t d = c + 1;
            uint32_t triangleA[3] = {a, c, b};
            uint32_t triangleB[3] = {b, c, d};
            [indices appendBytes:triangleA length:sizeof(triangleA)];
            [indices appendBytes:triangleB length:sizeof(triangleB)];
        }
    }

    SCNGeometrySource *positionSource =
        [SCNGeometrySource geometrySourceWithData:positions
                                        semantic:SCNGeometrySourceSemanticVertex
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:3
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:3 * sizeof(float)];
    SCNGeometrySource *normalSource =
        [SCNGeometrySource geometrySourceWithData:normals
                                        semantic:SCNGeometrySourceSemanticNormal
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:3
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:3 * sizeof(float)];
    SCNGeometrySource *textureSource =
        [SCNGeometrySource geometrySourceWithData:texcoords
                                        semantic:SCNGeometrySourceSemanticTexcoord
                                     vectorCount:vertexCount
                                 floatComponents:YES
                             componentsPerVector:2
                               bytesPerComponent:sizeof(float)
                                      dataOffset:0
                                        dataStride:2 * sizeof(float)];
    SCNGeometryElement *element =
        [SCNGeometryElement geometryElementWithData:indices
                                      primitiveType:SCNGeometryPrimitiveTypeTriangles
                                     primitiveCount:majorSegments * minorSegments * 2
                                      bytesPerIndex:sizeof(uint32_t)];
    return [SCNGeometry geometryWithSources:@[positionSource, normalSource, textureSource]
                                   elements:@[element]];
}

- (SCNNode *)partialTorusWithRingRadius:(CGFloat)ringRadius
                             pipeRadius:(CGFloat)pipeRadius
                             startAngle:(CGFloat)startAngle
                               endAngle:(CGFloat)endAngle
                               material:(SCNMaterial *)material
                               position:(SCNVector3)position {
    SCNGeometry *geometry = [self partialTorusGeometryWithRingRadius:ringRadius
                                                          pipeRadius:pipeRadius
                                                          startAngle:startAngle
                                                            endAngle:endAngle
                                                       majorSegments:112
                                                       minorSegments:12];
    SCNNode *node = [self nodeWithGeometry:geometry material:material position:position];
    node.name = @"cutawayTorus";
    return node;
}

- (void)addPartialCylinderWithRadius:(CGFloat)radius
                              height:(CGFloat)height
                          startAngle:(CGFloat)startAngle
                            endAngle:(CGFloat)endAngle
                            material:(SCNMaterial *)material
                          renderOrder:(NSInteger)renderOrder
                           toParent:(SCNNode *)parent {
    SCNGeometry *geometry = [self partialCylinderGeometryWithRadius:radius
                                                             height:height
                                                         startAngle:startAngle
                                                           endAngle:endAngle
                                                           segments:112];
    geometry.materials = @[material];
    SCNNode *shell = [SCNNode nodeWithGeometry:geometry];
    shell.name = @"cutawayShell";
    shell.castsShadow = NO;
    shell.renderingOrder = renderOrder;
    [parent addChildNode:shell];
}

#pragma mark - Programmatic textures

- (NSImage *)makeBackgroundImage {
    const CGFloat size = 1024.0;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSRect bounds = NSMakeRect(0.0, 0.0, size, size);
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:DMDHexColor(0x0B1D2D, 1.0)
                                                         endingColor:DMDHexColor(0x010308, 1.0)];
    [gradient drawInRect:bounds relativeCenterPosition:NSMakePoint(-0.05, 0.10)];

    // A faint blue pool of light behind the vessel adds separation from the
    // nearly black corners without introducing a visible gradient edge.
    NSBezierPath *glowPath = [NSBezierPath bezierPathWithOvalInRect:
        NSMakeRect(size * 0.12, size * 0.10, size * 0.76, size * 0.74)];
    NSGradient *glow = [[NSGradient alloc] initWithStartingColor:DMDHexColor(0x16354A, 0.42)
                                                     endingColor:DMDHexColor(0x06101A, 0.0)];
    [glow drawInBezierPath:glowPath relativeCenterPosition:NSZeroPoint];

    NSBezierPath *vignette = [NSBezierPath bezierPathWithRect:bounds];
    NSGradient *darken = [[NSGradient alloc] initWithStartingColor:DMDHexColor(0x000000, 0.0)
                                                       endingColor:DMDHexColor(0x000000, 0.62)];
    [darken drawInBezierPath:vignette relativeCenterPosition:NSZeroPoint];
    [image unlockFocus];
    return image;
}

- (NSImage *)makePMTArrayImage {
    if (self.pmtArrayImage) {
        return self.pmtArrayImage;
    }

    const CGFloat size = 1024.0;
    const CGFloat center = size * 0.5;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;

    NSRect fullRect = NSMakeRect(0.0, 0.0, size, size);
    [DMDHexColor(0x050B12, 1.0) setFill];
    NSRectFill(fullRect);

    NSBezierPath *clip = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(fullRect, 10.0, 10.0)];
    [NSGraphicsContext saveGraphicsState];
    [clip addClip];

    NSGradient *backing = [[NSGradient alloc] initWithStartingColor:DMDHexColor(0x1A3145, 1.0)
                                                        endingColor:DMDHexColor(0x03080D, 1.0)];
    [backing drawInBezierPath:clip relativeCenterPosition:NSZeroPoint];

    // Hexagonal close packing, trimmed to exactly the LZ PMT count. The
    // texture carries the fine sensor detail while the geometry stays cheap
    // enough for smooth camera orbit and event animation.
    const CGFloat spacing = 43.0;
    const CGFloat pmtRadius = 18.2;
    const CGFloat arrayRadius = 490.0;
    const CGFloat rowSpacing = spacing * 0.8660254038;
    NSInteger rowLimit = (NSInteger)ceil(arrayRadius / rowSpacing) + 1;
    NSInteger columnLimit = (NSInteger)ceil(arrayRadius / spacing) + 1;
    NSMutableArray<NSValue *> *centers = [NSMutableArray array];

    for (NSInteger row = -rowLimit; row <= rowLimit; row++) {
        CGFloat y = (CGFloat)row * rowSpacing;
        CGFloat xOffset = (row & 1) ? spacing * 0.5 : 0.0;
        for (NSInteger column = -columnLimit; column <= columnLimit; column++) {
            CGFloat x = (CGFloat)column * spacing + xOffset;
            if (x * x + y * y <= arrayRadius * arrayRadius) {
                [centers addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            }
        }
    }

    [centers sortUsingComparator:^NSComparisonResult(NSValue *lhs, NSValue *rhs) {
        NSPoint a = lhs.pointValue;
        NSPoint b = rhs.pointValue;
        CGFloat da = a.x * a.x + a.y * a.y;
        CGFloat db = b.x * b.x + b.y * b.y;
        if (da < db) {
            return NSOrderedAscending;
        }
        if (da > db) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    NSUInteger sensorCount = MIN((NSUInteger)494, centers.count);

    uint32_t faceStarts[] = {0xE8FBFF, 0xD9F4FF, 0xE6FFF5, 0xDCEFFF};
    uint32_t faceEnds[] = {0x1A5DB4, 0x1B72C8, 0x0E7B86, 0x254FB2};

    for (NSUInteger index = 0; index < sensorCount; index++) {
        NSPoint point = centers[index].pointValue;
        CGFloat cx = center + point.x;
        CGFloat cy = center + point.y;
        NSUInteger palette = index % 4;

        // Gold housing, dark seal, and glass window, each as a radial gradient.
        NSBezierPath *housing = [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(cx - pmtRadius, cy - pmtRadius, pmtRadius * 2.0, pmtRadius * 2.0)];
        NSGradient *gold = [[NSGradient alloc] initWithStartingColor:DMDHexColor(0xF2D18A, 1.0)
                                                         endingColor:DMDHexColor(0x76501B, 1.0)];
        [gold drawInBezierPath:housing relativeCenterPosition:NSMakePoint(-0.2, 0.24)];

        CGFloat sealRadius = pmtRadius - 2.0;
        NSBezierPath *seal = [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(cx - sealRadius, cy - sealRadius, sealRadius * 2.0, sealRadius * 2.0)];
        [DMDHexColor(0x07121C, 1.0) setFill];
        [seal fill];

        CGFloat glassRadius = pmtRadius - 4.0;
        NSBezierPath *glass = [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(cx - glassRadius, cy - glassRadius, glassRadius * 2.0, glassRadius * 2.0)];
        NSGradient *face = [[NSGradient alloc] initWithStartingColor:DMDHexColor(faceStarts[palette], 1.0)
                                                        endingColor:DMDHexColor(faceEnds[palette], 1.0)];
        [face drawInBezierPath:glass relativeCenterPosition:NSMakePoint(-0.22, 0.26)];

        // A small specular highlight reads as a curved photocathode window.
        NSBezierPath *glint = [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(cx - 6.4, cy + 2.6, 4.6, 3.3)];
        [DMDHexColor(0xFFFFFF, 0.55) setFill];
        [glint fill];
    }

    // Radial support spokes and a machined outer retaining ring.
    NSColor *spokeColor = DMDHexColor(0x91A6B4, 0.28);
    [spokeColor setStroke];
    for (NSInteger index = 0; index < 12; index++) {
        CGFloat angle = DMDDegrees((CGFloat)index * 30.0);
        NSBezierPath *spoke = [NSBezierPath bezierPath];
        [spoke moveToPoint:NSMakePoint(center + cos(angle) * 150.0, center + sin(angle) * 150.0)];
        [spoke lineToPoint:NSMakePoint(center + cos(angle) * 495.0, center + sin(angle) * 495.0)];
        spoke.lineWidth = 2.0;
        [spoke stroke];
    }
    [NSGraphicsContext restoreGraphicsState];

    [DMDHexColor(0x7C8B98, 1.0) setStroke];
    NSBezierPath *outerRing = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(fullRect, 12.0, 12.0)];
    outerRing.lineWidth = 9.0;
    [outerRing stroke];
    [DMDHexColor(0xD8B36B, 1.0) setStroke];
    NSBezierPath *goldRing = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(fullRect, 18.0, 18.0)];
    goldRing.lineWidth = 3.0;
    [goldRing stroke];

    // Bolt heads around the array flange.
    for (NSInteger index = 0; index < 24; index++) {
        CGFloat angle = DMDDegrees((CGFloat)index * 15.0 + 7.5);
        CGFloat bx = center + cos(angle) * 505.0;
        CGFloat by = center + sin(angle) * 505.0;
        NSBezierPath *bolt = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(bx - 4.2, by - 4.2, 8.4, 8.4)];
        [DMDHexColor(0x253440, 1.0) setFill];
        [bolt fill];
        [DMDHexColor(0xD8B36B, 1.0) setStroke];
        bolt.lineWidth = 1.2;
        [bolt stroke];
    }

    [image unlockFocus];
    self.pmtArrayImage = image;
    [self dumpDebugImage:image named:@"pmt-array"];
    return image;
}

- (void)dumpDebugImage:(NSImage *)image named:(NSString *)name {
    NSString *directory = NSProcessInfo.processInfo.environment[@"DMD_TEXTURE_DUMP_PATH"];
    if (directory.length == 0) {
        return;
    }
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString *path = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.png", name]];
    [png writeToFile:path atomically:YES];
}

- (NSImage *)makeParticleGlowImage {
    const CGFloat size = 64.0;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1.0, 1.0, size - 2.0, size - 2.0)];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]
                                                         endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [gradient drawInBezierPath:path relativeCenterPosition:NSZeroPoint];
    [image unlockFocus];
    return image;
}

#pragma mark - Site and shielding

- (void)addSiteBaseToRoot:(SCNNode *)root {
    SCNMaterial *cavernMaterial = [self materialWithColor:DMDHexColor(0x171C21, 1.0)
                                                metalness:0.05
                                                roughness:0.96
                                                  opacity:1.0
                                                 emission:nil
                                               writeDepth:YES
                                              doubleSided:NO];
    SCNNode *cavernFloor = [self cylinderWithRadius:8.35
                                              height:0.18
                                            material:cavernMaterial
                                            position:SCNVector3Make(0.0, -5.14, 0.0)];
    cavernFloor.name = @"cavernFloor";
    [root addChildNode:cavernFloor];

    SCNMaterial *platformMaterial = [self materialWithColor:DMDHexColor(0x182531, 1.0)
                                                  metalness:0.72
                                                  roughness:0.38
                                                    opacity:1.0
                                                   emission:nil
                                                 writeDepth:YES
                                                doubleSided:NO];
    SCNNode *platform = [self cylinderWithRadius:6.75
                                           height:0.24
                                         material:platformMaterial
                                         position:SCNVector3Make(0.0, -4.94, 0.0)];
    platform.name = @"supportPlatform";
    [root addChildNode:platform];

    SCNMaterial *ringMaterial = [self materialWithColor:DMDHexColor(0x33576B, 1.0)
                                              metalness:0.84
                                              roughness:0.25
                                                opacity:1.0
                                               emission:DMDHexColor(0x072531, 1.0)
                                             writeDepth:YES
                                            doubleSided:NO];
    [root addChildNode:[self torusWithRingRadius:5.42
                                      pipeRadius:0.045
                                        material:ringMaterial
                                        position:SCNVector3Make(0.0, -4.78, 0.0)]];
    [root addChildNode:[self torusWithRingRadius:6.28
                                      pipeRadius:0.035
                                        material:ringMaterial
                                        position:SCNVector3Make(0.0, -4.79, 0.0)]];

    SCNMaterial *cavernRingMaterial = [self materialWithColor:DMDHexColor(0x2B3A44, 1.0)
                                                    metalness:0.25
                                                    roughness:0.82
                                                      opacity:1.0
                                                     emission:nil
                                                   writeDepth:YES
                                                  doubleSided:NO];
    [root addChildNode:[self torusWithRingRadius:7.55
                                      pipeRadius:0.06
                                        material:cavernRingMaterial
                                        position:SCNVector3Make(0.0, -5.03, 0.0)]];

    SCNBox *footGeometry = [SCNBox boxWithWidth:0.94
                                         height:0.30
                                         length:0.42
                                  chamferRadius:0.035];
    SCNMaterial *footMaterial = [self materialWithColor:DMDHexColor(0x0D1722, 1.0)
                                              metalness:0.6
                                              roughness:0.5
                                                opacity:1.0
                                               emission:nil
                                             writeDepth:YES
                                            doubleSided:NO];
    footGeometry.materials = @[footMaterial];
    for (NSInteger index = 0; index < 8; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 8.0 + DMDDegrees(22.5);
        SCNNode *foot = [SCNNode nodeWithGeometry:footGeometry];
        foot.position = SCNVector3Make(cos(angle) * 5.95,
                                       -4.76,
                                       sin(angle) * 5.95);
        foot.eulerAngles = SCNVector3Make(0.0, -angle, 0.0);
        [root addChildNode:foot];
    }

    // Small service hatch in the platform at the back of the cutaway.
    SCNMaterial *hatchMaterial = [self metalMaterialWithColor:DMDHexColor(0x415260, 1.0) roughness:0.3];
    SCNNode *hatch = [self cylinderWithRadius:0.75
                                        height:0.06
                                      material:hatchMaterial
                                      position:SCNVector3Make(-4.6, -4.80, -3.1)];
    [root addChildNode:hatch];
}

- (void)addWaterShieldToRoot:(SCNNode *)root {
    // Front wedge cut from -34 to +88 degrees, matching the reference
    // cutaways while keeping the camera's default 26-degree azimuth open.
    const CGFloat cutStart = DMDDegrees(88.0);
    const CGFloat cutEnd = DMDDegrees(326.0);

    SCNMaterial *outerWater = [self cutawayTintMaterialWithColor:DMDHexColor(0x176F85, 1.0)
                                                         opacity:0.22
                                                        emission:DMDHexColor(0x061F29, 1.0)];
    [self addPartialCylinderWithRadius:5.38
                                height:8.8
                            startAngle:cutStart
                              endAngle:cutEnd
                              material:outerWater
                            renderOrder:60
                             toParent:root];

    SCNMaterial *innerWater = [self cutawayTintMaterialWithColor:DMDHexColor(0x3FAEC2, 1.0)
                                                         opacity:0.05
                                                        emission:DMDHexColor(0x041F28, 1.0)];
    [self addPartialCylinderWithRadius:5.28
                                height:8.66
                            startAngle:cutStart + DMDDegrees(1.2)
                              endAngle:cutEnd - DMDDegrees(1.2)
                              material:innerWater
                            renderOrder:59
                             toParent:root];

    SCNMaterial *rimMaterial = [self materialWithColor:DMDHexColor(0x8FDDE8, 1.0)
                                             metalness:0.68
                                             roughness:0.22
                                               opacity:1.0
                                              emission:DMDHexColor(0x08333F, 1.0)
                                            writeDepth:YES
                                           doubleSided:NO];
    SCNNode *topRim = [self partialTorusWithRingRadius:5.38
                                            pipeRadius:0.065
                                            startAngle:cutStart
                                              endAngle:cutEnd
                                              material:rimMaterial
                                              position:SCNVector3Make(0.0, 4.40, 0.0)];
    topRim.renderingOrder = 63;
    [root addChildNode:topRim];
    [root addChildNode:[self torusWithRingRadius:5.38
                                      pipeRadius:0.065
                                        material:rimMaterial
                                        position:SCNVector3Make(0.0, -4.40, 0.0)]];

    // Hoop stiffeners break up the large glass wall and echo the segmented
    // water-tank schematic in the supplied reference images.
    for (NSNumber *yValue in @[@(-2.6), @(0.0), @(2.6)]) {
        SCNNode *hoop = [self partialTorusWithRingRadius:5.385
                                             pipeRadius:0.018
                                             startAngle:cutStart
                                               endAngle:cutEnd
                                               material:rimMaterial
                                               position:SCNVector3Make(0.0, yValue.doubleValue, 0.0)];
        hoop.renderingOrder = 61;
        [root addChildNode:hoop];
    }

    SCNMaterial *cutEdgeMaterial = [self materialWithColor:DMDHexColor(0x8EF4FF, 1.0)
                                                 metalness:0.45
                                                 roughness:0.2
                                                   opacity:0.9
                                                  emission:DMDHexColor(0x1687A3, 1.0)
                                                writeDepth:YES
                                               doubleSided:NO];
    for (NSNumber *angleValue in @[@(88.0), @(326.0)]) {
        CGFloat angle = DMDDegrees(angleValue.doubleValue);
        SCNNode *edge = [self cylinderWithRadius:0.042
                                           height:8.8
                                         material:cutEdgeMaterial
                                         position:SCNVector3Make(cos(angle) * 5.39,
                                                                 0.0,
                                                                 sin(angle) * 5.39)];
        edge.renderingOrder = 62;
        [root addChildNode:edge];
    }

    // Back-wall stiffeners echo the segmented tank wall in the LZ schematic.
    SCNMaterial *stripeMaterial = [self materialWithColor:DMDHexColor(0x3E9DAB, 1.0)
                                                metalness:0.58
                                                roughness:0.3
                                                  opacity:0.72
                                                 emission:DMDHexColor(0x08333F, 1.0)
                                               writeDepth:NO
                                              doubleSided:NO];
    SCNCylinder *stripeGeometry = [SCNCylinder cylinderWithRadius:0.014 height:8.52];
    stripeGeometry.radialSegmentCount = 8;
    stripeGeometry.materials = @[stripeMaterial];
    for (NSInteger index = 0; index < 9; index++) {
        CGFloat angle = DMDDegrees(102.0 + (CGFloat)index * 25.2);
        SCNNode *stripe = [SCNNode nodeWithGeometry:stripeGeometry];
        stripe.position = SCNVector3Make(cos(angle) * 5.39, 0.0, sin(angle) * 5.39);
        stripe.renderingOrder = 61;
        [root addChildNode:stripe];
    }

    // Interior ladder from the clean-room reference photo.
    SCNMaterial *ladderMaterial = [self materialWithColor:DMDHexColor(0xA9BBBF, 1.0)
                                                metalness:0.7
                                                roughness:0.32
                                                  opacity:0.95
                                                 emission:nil
                                               writeDepth:YES
                                              doubleSided:NO];
    CGFloat ladderAngle = DMDDegrees(152.0);
    CGFloat ladderRadius = 5.08;
    SCNVector3 ladderCenter = SCNVector3Make(cos(ladderAngle) * ladderRadius,
                                             0.0,
                                             sin(ladderAngle) * ladderRadius);
    SCNVector3 tangent = SCNVector3Make(-sin(ladderAngle), 0.0, cos(ladderAngle));
    for (NSNumber *side in @[@(-0.17), @(0.17)]) {
        CGFloat offset = side.doubleValue;
        SCNVector3 start = SCNVector3Make(ladderCenter.x + tangent.x * offset,
                                          -3.8,
                                          ladderCenter.z + tangent.z * offset);
        SCNVector3 end = SCNVector3Make(start.x, 4.1, start.z);
        [root addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.022 material:ladderMaterial]];
    }
    for (NSInteger index = 0; index < 16; index++) {
        CGFloat y = -3.6 + (CGFloat)index * 0.48;
        SCNVector3 start = SCNVector3Make(ladderCenter.x - tangent.x * 0.17,
                                          y,
                                          ladderCenter.z - tangent.z * 0.17);
        SCNVector3 end = SCNVector3Make(ladderCenter.x + tangent.x * 0.17,
                                        y,
                                        ladderCenter.z + tangent.z * 0.17);
        [root addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.014 material:ladderMaterial]];
    }

    // Roof beams and central water-tank service port.
    SCNMaterial *beamMaterial = [self materialWithColor:DMDHexColor(0x577688, 1.0)
                                              metalness:0.8
                                              roughness:0.34
                                                opacity:0.9
                                               emission:nil
                                             writeDepth:YES
                                            doubleSided:NO];
    for (NSNumber *angleValue in @[@(112.0), @(148.0), @(212.0), @(248.0)]) {
        CGFloat angle = DMDDegrees(angleValue.doubleValue);
        [root addChildNode:[self cylinderFromPoint:SCNVector3Make(0.0, 4.39, 0.0)
                                           toPoint:SCNVector3Make(cos(angle) * 5.34, 4.39, sin(angle) * 5.34)
                                            radius:0.035
                                          material:beamMaterial]];
    }
    SCNMaterial *portMaterial = [self metalMaterialWithColor:DMDHexColor(0x9AAAB5, 1.0) roughness:0.24];
    [root addChildNode:[self cylinderWithRadius:1.0
                                          height:0.20
                                        material:portMaterial
                                        position:SCNVector3Make(0.0, 4.49, 0.0)]];
    [root addChildNode:[self cylinderWithRadius:0.54
                                          height:0.48
                                        material:portMaterial
                                        position:SCNVector3Make(0.0, 4.78, 0.0)]];
    [root addChildNode:[self torusWithRingRadius:0.54
                                      pipeRadius:0.055
                                        material:rimMaterial
                                        position:SCNVector3Make(0.0, 5.03, 0.0)]];
}

#pragma mark - Cryostat, veto, TPC, field cage

- (void)addCryostatToRoot:(SCNNode *)root {
    const CGFloat cutStart = DMDDegrees(92.0);
    const CGFloat cutEnd = DMDDegrees(322.0);

    SCNMaterial *outerShell = [self cutawayTintMaterialWithColor:DMDHexColor(0x728796, 1.0)
                                                         opacity:0.28
                                                        emission:nil];
    [self addPartialCylinderWithRadius:3.76
                                height:7.22
                            startAngle:cutStart
                              endAngle:cutEnd
                              material:outerShell
                            renderOrder:40
                             toParent:root];

    SCNMaterial *innerShell = [self cutawayTintMaterialWithColor:DMDHexColor(0x26343E, 1.0)
                                                         opacity:0.07
                                                        emission:nil];
    [self addPartialCylinderWithRadius:3.64
                                height:7.06
                            startAngle:cutStart + DMDDegrees(1.5)
                              endAngle:cutEnd - DMDDegrees(1.5)
                              material:innerShell
                            renderOrder:39
                             toParent:root];

    SCNMaterial *titanium = [self metalMaterialWithColor:self.titaniumColor roughness:0.2];
    SCNMaterial *cutEdge = [self materialWithColor:DMDHexColor(0xC8D6E1, 1.0)
                                        metalness:0.9
                                        roughness:0.2
                                          opacity:1.0
                                         emission:nil
                                       writeDepth:YES
                                      doubleSided:NO];
    for (NSNumber *angleValue in @[@(92.0), @(322.0)]) {
        CGFloat angle = DMDDegrees(angleValue.doubleValue);
        SCNNode *edge = [self cylinderWithRadius:0.045
                                           height:7.23
                                         material:cutEdge
                                         position:SCNVector3Make(cos(angle) * 3.77,
                                                                 0.0,
                                                                 sin(angle) * 3.77)];
        edge.renderingOrder = 42;
        [root addChildNode:edge];
    }
    SCNNode *topFlange = [self partialTorusWithRingRadius:3.77
                                               pipeRadius:0.105
                                               startAngle:cutStart
                                                 endAngle:cutEnd
                                                 material:titanium
                                                 position:SCNVector3Make(0.0, 3.59, 0.0)];
    topFlange.renderingOrder = 41;
    [root addChildNode:topFlange];
    [root addChildNode:[self torusWithRingRadius:3.77
                                      pipeRadius:0.105
                                        material:titanium
                                        position:SCNVector3Make(0.0, -3.59, 0.0)]];

    SCNMaterial *bandMaterial = [self materialWithColor:DMDHexColor(0x8397A5, 1.0)
                                             metalness:0.82
                                             roughness:0.27
                                               opacity:0.92
                                              emission:DMDHexColor(0x111D25, 1.0)
                                            writeDepth:YES
                                           doubleSided:NO];
    for (NSNumber *yValue in @[@(-1.8), @(0.0), @(1.8)]) {
        SCNNode *band = [self partialTorusWithRingRadius:3.78
                                             pipeRadius:0.028
                                             startAngle:cutStart
                                               endAngle:cutEnd
                                               material:bandMaterial
                                               position:SCNVector3Make(0.0, yValue.doubleValue, 0.0)];
        band.renderingOrder = 41;
        [root addChildNode:band];
    }

    // Flange bolts only on the visible cutaway arc.
    SCNCylinder *boltGeometry = [SCNCylinder cylinderWithRadius:0.038 height:0.11];
    boltGeometry.radialSegmentCount = 10;
    boltGeometry.materials = @[titanium];
    for (NSInteger index = 0; index < 18; index++) {
        CGFloat angle = cutStart + DMDDegrees(2.5) + (cutEnd - cutStart - DMDDegrees(5.0)) *
                        (CGFloat)index / 17.0;
        for (NSNumber *yValue in @[@(3.70), @(-3.70)]) {
            SCNNode *bolt = [SCNNode nodeWithGeometry:boltGeometry];
            bolt.position = SCNVector3Make(cos(angle) * 3.56,
                                           yValue.doubleValue,
                                           sin(angle) * 3.56);
            [root addChildNode:bolt];
        }
    }

    SCNMaterial *seamMaterial = [self materialWithColor:DMDHexColor(0x526574, 1.0)
                                              metalness:0.78
                                              roughness:0.3
                                                opacity:0.82
                                               emission:nil
                                             writeDepth:YES
                                            doubleSided:NO];
    SCNCylinder *seamGeometry = [SCNCylinder cylinderWithRadius:0.017 height:6.9];
    seamGeometry.radialSegmentCount = 8;
    seamGeometry.materials = @[seamMaterial];
    for (NSInteger index = 0; index < 9; index++) {
        CGFloat angle = DMDDegrees(102.0 + (CGFloat)index * 26.0);
        SCNNode *seam = [SCNNode nodeWithGeometry:seamGeometry];
        seam.position = SCNVector3Make(cos(angle) * 3.77, 0.0, sin(angle) * 3.77);
        [root addChildNode:seam];
    }

    SCNMaterial *conduitMaterial = [self materialWithColor:DMDHexColor(0x2C3B46, 1.0)
                                                metalness:0.86
                                                roughness:0.28
                                                  opacity:1.0
                                                 emission:nil
                                               writeDepth:YES
                                              doubleSided:NO];
    for (NSNumber *angleValue in @[@(128.0), @(178.0), @(232.0)]) {
        CGFloat angle = DMDDegrees(angleValue.doubleValue);
        SCNNode *conduit = [self cylinderWithRadius:0.055
                                              height:6.55
                                            material:conduitMaterial
                                            position:SCNVector3Make(cos(angle) * 3.9,
                                                                    0.0,
                                                                    sin(angle) * 3.9)];
        conduit.renderingOrder = 38;
        [root addChildNode:conduit];
    }

    SCNMaterial *neckMaterial = [self metalMaterialWithColor:DMDHexColor(0x8C9EAC, 1.0) roughness:0.24];
    [root addChildNode:[self cylinderWithRadius:0.56
                                          height:0.44
                                        material:neckMaterial
                                        position:SCNVector3Make(0.0, 3.86, 0.0)]];
    [root addChildNode:[self torusWithRingRadius:0.56
                                      pipeRadius:0.055
                                        material:titanium
                                        position:SCNVector3Make(0.0, 4.06, 0.0)]];

    // Top spider beams leave the PMT array visible from the default camera.
    SCNMaterial *spokeMaterial = [self metalMaterialWithColor:DMDHexColor(0x9EAEB9, 1.0) roughness:0.3];
    for (NSNumber *angleValue in @[@(125.0), @(165.0), @(215.0), @(255.0)]) {
        CGFloat angle = DMDDegrees(angleValue.doubleValue);
        [root addChildNode:[self cylinderFromPoint:SCNVector3Make(cos(angle) * 0.58, 3.63, sin(angle) * 0.58)
                                           toPoint:SCNVector3Make(cos(angle) * 3.64, 3.63, sin(angle) * 3.64)
                                            radius:0.032
                                          material:spokeMaterial]];
    }

    SCNMaterial *baseMaterial = [self materialWithColor:DMDHexColor(0x6F7E8B, 1.0)
                                              metalness:0.84
                                              roughness:0.34
                                                opacity:0.92
                                               emission:nil
                                             writeDepth:YES
                                            doubleSided:NO];
    [root addChildNode:[self cylinderWithRadius:3.62
                                          height:0.18
                                        material:baseMaterial
                                        position:SCNVector3Make(0.0, -3.66, 0.0)]];

    // Pylons and cross-bracing under the vessel.
    SCNCylinder *pylonGeometry = [SCNCylinder cylinderWithRadius:0.11 height:0.88];
    pylonGeometry.radialSegmentCount = 14;
    pylonGeometry.materials = @[seamMaterial];
    for (NSInteger index = 0; index < 6; index++) {
        CGFloat angle = DMDDegrees(30.0 + (CGFloat)index * 60.0);
        SCNVector3 top = SCNVector3Make(cos(angle) * 2.55, -4.05, sin(angle) * 2.55);
        SCNVector3 bottom = SCNVector3Make(cos(angle) * 2.35, -4.58, sin(angle) * 2.35);
        [root addChildNode:[self cylinderFromPoint:top toPoint:bottom radius:0.105 material:seamMaterial]];
    }

    SCNMaterial *calibrationMaterial = [self materialWithColor:DMDHexColor(0x8FA2B0, 1.0)
                                                    metalness:0.78
                                                    roughness:0.26
                                                      opacity:0.9
                                                     emission:nil
                                                   writeDepth:YES
                                                  doubleSided:NO];
    for (NSNumber *offset in @[@(-0.6), @(0.0), @(0.6)]) {
        SCNNode *tube = [self cylinderWithRadius:0.032
                                          height:1.0
                                        material:calibrationMaterial
                                        position:SCNVector3Make(offset.doubleValue,
                                                                4.25,
                                                                -0.95)];
        [root addChildNode:tube];
        [root addChildNode:[self torusWithRingRadius:0.055
                                          pipeRadius:0.018
                                            material:calibrationMaterial
                                            position:SCNVector3Make(offset.doubleValue,
                                                                    4.76,
                                                                    -0.95)]];
    }
}

- (void)addVetoToRoot:(SCNNode *)root {
    const CGFloat cutStart = DMDDegrees(96.0);
    const CGFloat cutEnd = DMDDegrees(318.0);

    SCNMaterial *skinMaterial = [self cutawayTintMaterialWithColor:DMDHexColor(0x145A6D, 1.0)
                                                          opacity:0.055
                                                         emission:DMDHexColor(0x062834, 1.0)];
    [self addPartialCylinderWithRadius:3.32
                                height:6.42
                            startAngle:cutStart
                              endAngle:cutEnd
                              material:skinMaterial
                            renderOrder:26
                             toParent:root];

    SCNMaterial *panelMaterial = [self materialWithColor:DMDHexColor(0x27B977, 1.0)
                                               metalness:0.0
                                               roughness:0.42
                                                 opacity:0.26
                                                emission:DMDHexColor(0x0C6037, 1.0)
                                              writeDepth:NO
                                             doubleSided:YES];
    panelMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    SCNMaterial *frameMaterial = [self materialWithColor:DMDHexColor(0x4E7E63, 1.0)
                                               metalness:0.55
                                               roughness:0.38
                                                 opacity:0.8
                                                emission:nil
                                              writeDepth:YES
                                             doubleSided:NO];

    for (NSInteger index = 0; index < 9; index++) {
        CGFloat angle = DMDDegrees(108.0 + (CGFloat)index * 24.0);
        // Box local X is radial and local Z is tangential.
        SCNNode *frame = [self boxWithWidth:0.13
                                     height:4.98
                                     length:1.16
                                   chamfer:0.018
                                   material:frameMaterial
                                   position:SCNVector3Make(cos(angle) * 3.98,
                                                           0.0,
                                                           sin(angle) * 3.98)];
        frame.eulerAngles = SCNVector3Make(0.0, -angle, 0.0);
        [root addChildNode:frame];

        SCNNode *panel = [self boxWithWidth:0.07
                                     height:4.82
                                     length:1.03
                                   chamfer:0.02
                                   material:panelMaterial
                                   position:SCNVector3Make(cos(angle) * 4.04,
                                                           0.0,
                                                           sin(angle) * 4.04)];
        panel.eulerAngles = SCNVector3Make(0.0, -angle, 0.0);
        panel.renderingOrder = 27;
        [root addChildNode:panel];
    }

    // Outer-detector PMTs face inward, toward the center of the water tank.
    SCNMaterial *gold = [self materialWithColor:self.goldColor
                                     metalness:1.0
                                     roughness:0.2
                                       opacity:1.0
                                      emission:DMDHexColor(0x5D3E12, 1.0)
                                    writeDepth:YES
                                   doubleSided:NO];
    NSArray<NSColor *> *faceColors = @[
        DMDHexColor(0x8FEAFF, 1.0),
        DMDHexColor(0x42A8FF, 1.0),
        DMDHexColor(0x76FFD7, 1.0)
    ];
    NSMutableArray<SCNGeometry *> *outerPMTGeometries = [NSMutableArray array];
    for (NSColor *faceColor in faceColors) {
        SCNMaterial *face = [self materialWithColor:faceColor
                                          metalness:0.1
                                          roughness:0.25
                                            opacity:1.0
                                           emission:faceColor
                                         writeDepth:YES
                                        doubleSided:NO];
        SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:0.128 height:0.24];
        geometry.radialSegmentCount = 18;
        geometry.materials = @[gold, face, gold];
        [outerPMTGeometries addObject:geometry];
    }

    NSArray<NSNumber *> *bands = @[@(-2.16), @(0.0), @(2.16)];
    for (NSNumber *yValue in bands) {
        for (NSInteger index = 0; index < 18; index++) {
            CGFloat angle = DMDDegrees(100.0 + (CGFloat)index * 12.9);
            SCNNode *pivot = [SCNNode node];
            pivot.position = SCNVector3Make(cos(angle) * 4.42,
                                            yValue.doubleValue,
                                            sin(angle) * 4.42);
            pivot.eulerAngles = SCNVector3Make(0.0, -angle, 0.0);
            NSUInteger colorIndex = (NSUInteger)(index % 3);
            SCNNode *body = [SCNNode nodeWithGeometry:outerPMTGeometries[colorIndex]];
            // Point the cylinder's +Y face inward (-X in the pivot frame).
            body.eulerAngles = SCNVector3Make(0.0, 0.0, (CGFloat)M_PI_2);
            body.castsShadow = NO;
            [pivot addChildNode:body];
            [root addChildNode:pivot];
        }
    }

    SCNMaterial *supportMaterial = [self materialWithColor:DMDHexColor(0x66737D, 1.0)
                                                metalness:0.72
                                                roughness:0.36
                                                  opacity:0.85
                                                 emission:nil
                                               writeDepth:YES
                                              doubleSided:NO];
    for (NSInteger index = 0; index < 8; index++) {
        CGFloat angle = DMDDegrees(102.0 + (CGFloat)index * 26.0);
        SCNNode *rail = [self cylinderWithRadius:0.018
                                           height:5.5
                                         material:supportMaterial
                                         position:SCNVector3Make(cos(angle) * 4.55,
                                                                 0.0,
                                                                 sin(angle) * 4.55)];
        [root addChildNode:rail];
    }
}

- (void)addLiquidXenonTPCToRoot:(SCNNode *)root {
    SCNMaterial *xenonMaterial = [self cutawayTintMaterialWithColor:DMDHexColor(0x2C88B6, 1.0)
                                                           opacity:0.18
                                                          emission:DMDHexColor(0x0A4A70, 1.0)];
    xenonMaterial.emission.intensity = 0.42;

    SCNNode *shell = [self cylinderWithRadius:DMDTPCRadiusScene
                                        height:6.0
                                      material:xenonMaterial
                                      position:SCNVector3Make(0.0, 0.0, 0.0)];
    shell.name = @"liquidXenonTPC";
    shell.renderingOrder = 20;
    [root addChildNode:shell];

    SCNMaterial *innerGlow = [self cutawayTintMaterialWithColor:DMDHexColor(0x2A89AA, 1.0)
                                                       opacity:0.028
                                                      emission:DMDHexColor(0x073D54, 1.0)];
    SCNNode *inner = [self cylinderWithRadius:2.57
                                        height:5.84
                                      material:innerGlow
                                      position:SCNVector3Make(0.0, 0.0, 0.0)];
    inner.renderingOrder = 19;
    [root addChildNode:inner];

    SCNMaterial *boundaryGlow = [self glowMaterialWithColor:DMDHexColor(0x7BEBFF, 1.0) opacity:0.9];
    for (NSNumber *yValue in @[@(DMDTPCTopYScene), @(DMDTPCBottomYScene)]) {
        SCNNode *ring = [self torusWithRingRadius:DMDTPCRadiusScene
                                       pipeRadius:0.028
                                         material:boundaryGlow
                                         position:SCNVector3Make(0.0, yValue.doubleValue, 0.0)];
        ring.renderingOrder = 23;
        [root addChildNode:ring];
    }

    SCNMaterial *innerBoundary = [self glowMaterialWithColor:DMDHexColor(0x4EA9D0, 1.0) opacity:0.35];
    for (NSNumber *yValue in @[@(2.98), @(-2.98)]) {
        [root addChildNode:[self torusWithRingRadius:2.56
                                          pipeRadius:0.012
                                            material:innerBoundary
                                            position:SCNVector3Make(0.0, yValue.doubleValue, 0.0)]];
    }
}

- (void)addFieldCageToRoot:(SCNNode *)root {
    SCNMaterial *ringMaterial = [self glowMaterialWithColor:DMDHexColor(0x4FBDE4, 1.0) opacity:0.13];
    for (NSInteger index = 0; index < 21; index++) {
        CGFloat y = -2.90 + (CGFloat)index * (5.80 / 20.0);
        SCNNode *ring = [self torusWithRingRadius:2.635
                                       pipeRadius:0.005
                                         material:ringMaterial
                                         position:SCNVector3Make(0.0, y, 0.0)];
        ring.renderingOrder = 22;
        [root addChildNode:ring];
    }

    SCNMaterial *postMaterial = [self materialWithColor:DMDHexColor(0x4D7B8E, 1.0)
                                             metalness:0.58
                                             roughness:0.4
                                               opacity:0.7
                                              emission:DMDHexColor(0x0A2B39, 1.0)
                                            writeDepth:YES
                                           doubleSided:NO];
    for (NSInteger index = 0; index < 12; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 12.0;
        SCNNode *post = [self cylinderWithRadius:0.012
                                           height:5.94
                                         material:postMaterial
                                         position:SCNVector3Make(cos(angle) * 2.665,
                                                                 0.0,
                                                                 sin(angle) * 2.665)];
        post.renderingOrder = 21;
        [root addChildNode:post];
    }

}

#pragma mark - Light sensors

- (NSArray<SCNNode *> *)addPMTArrayAtY:(CGFloat)y
                                   top:(BOOL)isTop
                                 group:(SCNNode *)group {
    SCNMaterial *gold = [self materialWithColor:self.goldColor
                                     metalness:1.0
                                     roughness:0.19
                                       opacity:1.0
                                      emission:DMDHexColor(0x654413, 1.0)
                                    writeDepth:YES
                                   doubleSided:NO];

    SCNMaterial *arrayFace = [SCNMaterial material];
    arrayFace.lightingModelName = SCNLightingModelConstant;
    arrayFace.diffuse.contents = [self makePMTArrayImage];
    arrayFace.emission.contents = [self makePMTArrayImage];
    arrayFace.emission.intensity = 0.08;
    arrayFace.writesToDepthBuffer = YES;
    arrayFace.doubleSided = NO;

    SCNCylinder *arrayGeometry = [SCNCylinder cylinderWithRadius:2.56 height:0.09];
    arrayGeometry.radialSegmentCount = 112;
    // Cylinder material slots: side, top cap, bottom cap.
    arrayGeometry.materials = @[gold, arrayFace, arrayFace];
    SCNNode *array = [SCNNode nodeWithGeometry:arrayGeometry];
    array.name = isTop ? @"topPMTArray" : @"bottomPMTArray";
    array.position = SCNVector3Make(0.0, y, 0.0);
    array.castsShadow = NO;
    [group addChildNode:array];

    SCNMaterial *supportMetal = [self materialWithColor:DMDHexColor(0xB99759, 1.0)
                                             metalness:0.95
                                             roughness:0.24
                                               opacity:1.0
                                              emission:DMDHexColor(0x2A1B05, 1.0)
                                            writeDepth:YES
                                           doubleSided:NO];
    SCNNode *outerRing = [self torusWithRingRadius:2.575
                                        pipeRadius:0.055
                                          material:supportMetal
                                          position:SCNVector3Make(0.0, y + (isTop ? -0.01 : 0.01), 0.0)];
    outerRing.renderingOrder = 12;
    [group addChildNode:outerRing];
    SCNNode *innerRing = [self torusWithRingRadius:2.47
                                        pipeRadius:0.014
                                          material:supportMetal
                                          position:SCNVector3Make(0.0, y + (isTop ? -0.06 : 0.06), 0.0)];
    [group addChildNode:innerRing];

    SCNMaterial *steel = [self materialWithColor:DMDHexColor(0x7C8B96, 1.0)
                                       metalness:0.84
                                       roughness:0.32
                                         opacity:1.0
                                        emission:nil
                                      writeDepth:YES
                                     doubleSided:NO];
    for (NSInteger index = 0; index < 4; index++) {
        CGFloat angle = (CGFloat)index * (CGFloat)M_PI_2 + (CGFloat)M_PI_4;
        SCNVector3 start = SCNVector3Make(cos(angle) * 0.15,
                                          y + (isTop ? -0.055 : 0.055),
                                          sin(angle) * 0.15);
        SCNVector3 end = SCNVector3Make(cos(angle) * 2.54,
                                        start.y,
                                        sin(angle) * 2.54);
        [group addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.026 material:steel]];
    }

    // A few physical PMTs at the rim complement the fine texture and give the
    // array a convincing three-dimensional edge in oblique views.
    NSMutableArray<SCNNode *> *rimNodes = [NSMutableArray array];
    NSArray<NSColor *> *faceColors = @[
        DMDHexColor(0xB8F4FF, 1.0),
        DMDHexColor(0x62BEFF, 1.0),
        DMDHexColor(0x8BFFE1, 1.0)
    ];
    NSMutableArray<SCNGeometry *> *rimGeometries = [NSMutableArray array];
    for (NSColor *faceColor in faceColors) {
        SCNMaterial *face = [self materialWithColor:faceColor
                                          metalness:0.1
                                          roughness:0.22
                                            opacity:1.0
                                           emission:faceColor
                                         writeDepth:YES
                                        doubleSided:NO];
        SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:0.086 height:0.13];
        geometry.radialSegmentCount = 14;
        geometry.materials = @[gold, face, gold];
        [rimGeometries addObject:geometry];
    }
    for (NSInteger index = 0; index < 24; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 24.0;
        SCNNode *pmt = [SCNNode nodeWithGeometry:rimGeometries[(NSUInteger)(index % 3)]];
        pmt.position = SCNVector3Make(cos(angle) * 2.40,
                                      y + (isTop ? 0.055 : -0.055),
                                      sin(angle) * 2.40);
        if (isTop) {
            pmt.eulerAngles = SCNVector3Make((CGFloat)M_PI, 0.0, 0.0);
        }
        [group addChildNode:pmt];
        [rimNodes addObject:pmt];
    }

    return rimNodes;
}

#pragma mark - Data acquisition

- (void)addDAQToRoot:(SCNNode *)root {
    SCNMaterial *crateMaterial = [self materialWithColor:DMDHexColor(0x596B78, 1.0)
                                               metalness:0.75
                                               roughness:0.3
                                                 opacity:1.0
                                                emission:nil
                                              writeDepth:YES
                                             doubleSided:NO];
    SCNMaterial *ledMaterial = [self glowMaterialWithColor:DMDHexColor(0x66F1FF, 1.0) opacity:1.0];

    SCNBox *crateGeometry = [SCNBox boxWithWidth:0.54
                                          height:0.24
                                          length:0.32
                                   chamferRadius:0.025];
    crateGeometry.materials = @[crateMaterial];
    SCNSphere *ledGeometry = [SCNSphere sphereWithRadius:0.026];
    ledGeometry.segmentCount = 10;
    ledGeometry.materials = @[ledMaterial];

    for (NSInteger index = 0; index < 6; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 6.0 + DMDDegrees(30.0);
        SCNNode *crate = [SCNNode nodeWithGeometry:crateGeometry];
        crate.position = SCNVector3Make(cos(angle) * 3.05, 4.04, sin(angle) * 3.05);
        crate.eulerAngles = SCNVector3Make(0.0, -angle, 0.0);
        [root addChildNode:crate];

        SCNNode *led = [SCNNode nodeWithGeometry:ledGeometry];
        led.position = SCNVector3Make(cos(angle) * 3.05, 4.17, sin(angle) * 3.05);
        led.renderingOrder = 44;
        [root addChildNode:led];
    }

    SCNMaterial *cableMaterial = [self materialWithColor:DMDHexColor(0x26343E, 1.0)
                                               metalness:0.35
                                               roughness:0.62
                                                 opacity:0.95
                                                emission:nil
                                              writeDepth:YES
                                             doubleSided:NO];
    for (NSInteger index = 0; index < 16; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 16.0;
        SCNVector3 start = SCNVector3Make(cos(angle) * 3.35, 3.66, sin(angle) * 3.35);
        SCNVector3 end = SCNVector3Make(cos(angle) * 3.06, 3.98, sin(angle) * 3.06);
        [root addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.009 material:cableMaterial]];
    }

    SCNMaterial *trayMaterial = [self materialWithColor:DMDHexColor(0x3E515D, 1.0)
                                              metalness:0.8
                                              roughness:0.3
                                                opacity:0.9
                                               emission:nil
                                             writeDepth:YES
                                            doubleSided:NO];

    // Copper-coloured low-voltage bundles under the vessel, visible through the
    // cutaway and matching the cable bundles in the cryostat photograph.
    SCNMaterial *bottomCable = [self materialWithColor:DMDHexColor(0x9A5A2E, 1.0)
                                             metalness:0.12
                                             roughness:0.7
                                               opacity:1.0
                                              emission:nil
                                            writeDepth:YES
                                           doubleSided:NO];
    for (NSInteger index = 0; index < 10; index++) {
        CGFloat angle = (CGFloat)index * 2.0 * (CGFloat)M_PI / 10.0;
        SCNVector3 start = SCNVector3Make(cos(angle) * 2.75, -3.66, sin(angle) * 2.75);
        SCNVector3 end = SCNVector3Make(cos(angle) * 2.45, -4.34, sin(angle) * 2.45);
        [root addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.028 material:bottomCable]];
    }
    [root addChildNode:[self torusWithRingRadius:2.53
                                      pipeRadius:0.03
                                        material:trayMaterial
                                        position:SCNVector3Make(0.0, -4.28, 0.0)]];

    // Three long signal runs down the back of the water tank.
    for (NSInteger index = 0; index < 3; index++) {
        CGFloat angle = DMDDegrees(150.0 + (CGFloat)index * 45.0);
        SCNVector3 start = SCNVector3Make(cos(angle) * 4.8, 4.1, sin(angle) * 4.8);
        SCNVector3 end = SCNVector3Make(cos(angle) * 4.8, -4.35, sin(angle) * 4.8);
        [root addChildNode:[self cylinderFromPoint:start toPoint:end radius:0.024 material:cableMaterial]];
    }
}

#pragma mark - Part metadata

- (NSArray<DMDDetectorPart *> *)makeDetectorPartsWithBase:(SCNNode *)baseGroup
                                               waterGroup:(SCNNode *)waterGroup
                                            cryostatGroup:(SCNNode *)cryostatGroup
                                                vetoGroup:(SCNNode *)vetoGroup
                                                 tpcGroup:(SCNNode *)tpcGroup
                                               fieldGroup:(SCNNode *)fieldGroup
                                              arraysGroup:(SCNNode *)arraysGroup
                                                 daqGroup:(SCNNode *)daqGroup {
    DMDDetectorPart *water =
        [[DMDDetectorPart alloc] initWithIdentifier:@"water-shield"
                                       displayName:@"WATER SHIELD"
                                         shortName:@"WATER SHIELD"
                                     specification:@"60,000 gal ultrapure water"
                                            detail:@"Radiates outward from the cryostat, stopping external neutrons and gammas."
                                       accentColor:DMDHexColor(0x50DDF2, 1.0)
                                            anchor:SCNVector3Make(-4.88, 2.8, 1.7)
                                         labelSide:DMDDetectorPartLabelSideLeft
                                       contentNode:waterGroup
                                             index:0];

    DMDDetectorPart *cryostat =
        [[DMDDetectorPart alloc] initWithIdentifier:@"cryostat"
                                       displayName:@"TITANIUM CRYOSTAT"
                                         shortName:@"CRYOSTAT"
                                     specification:@"Double-walled inner vessel"
                                            detail:@"Holds the liquid xenon at -100 °C and supports the PMT arrays and field cage."
                                       accentColor:DMDHexColor(0xBED3E2, 1.0)
                                            anchor:SCNVector3Make(-3.55, 2.3, 1.2)
                                         labelSide:DMDDetectorPartLabelSideLeft
                                       contentNode:cryostatGroup
                                             index:1];

    DMDDetectorPart *veto =
        [[DMDDetectorPart alloc] initWithIdentifier:@"veto"
                                       displayName:@"Gd VETO PANELS"
                                         shortName:@"Gd VETO"
                                     specification:@"Gd-loaded scintillator + 120 outer PMTs"
                                            detail:@"Tags neutrons and gamma rays escaping the TPC, vetoing background events."
                                       accentColor:DMDHexColor(0x54E59C, 1.0)
                                            anchor:SCNVector3Make(-3.92, 1.22, 1.55)
                                         labelSide:DMDDetectorPartLabelSideLeft
                                       contentNode:vetoGroup
                                             index:2];

    DMDDetectorPart *site =
        [[DMDDetectorPart alloc] initWithIdentifier:@"site-depth"
                                       displayName:@"SITE & DEPTH"
                                         shortName:@"SITE & DEPTH"
                                     specification:@"Sanford Underground Research Facility"
                                            detail:@"About 1.5 km of rock overburden suppresses cosmic-ray muons by many orders of magnitude."
                                       accentColor:DMDHexColor(0xE2B86C, 1.0)
                                            anchor:SCNVector3Make(-3.4, -4.85, 2.5)
                                         labelSide:DMDDetectorPartLabelSideLeft
                                       contentNode:baseGroup
                                             index:3];

    DMDDetectorPart *tpc =
        [[DMDDetectorPart alloc] initWithIdentifier:@"lxen-tpc"
                                       displayName:@"LIQUID XENON TPC"
                                         shortName:@"LXe TARGET"
                                     specification:@"10 t active LXe · 1500 mm drift"
                                            detail:@"The ultrapure liquid-xenon target: a time projection chamber tuned to WIMP recoils."
                                       accentColor:DMDHexColor(0x69B8FF, 1.0)
                                            anchor:SCNVector3Make(1.75, -0.05, 2.0)
                                         labelSide:DMDDetectorPartLabelSideRight
                                       contentNode:tpcGroup
                                             index:4];

    DMDDetectorPart *sensors =
        [[DMDDetectorPart alloc] initWithIdentifier:@"light-sensors"
                                       displayName:@"LIGHT SENSORS"
                                         shortName:@"LIGHT SENSORS"
                                     specification:@"494 top + 494 bottom PMTs"
                                            detail:@"Photomultiplier arrays record the prompt S1 flash and the drifted S2 signal."
                                       accentColor:DMDHexColor(0xFFC768, 1.0)
                                            anchor:SCNVector3Make(0.9, 3.10, 1.3)
                                         labelSide:DMDDetectorPartLabelSideRight
                                       contentNode:arraysGroup
                                             index:5];

    DMDDetectorPart *field =
        [[DMDDetectorPart alloc] initWithIdentifier:@"electric-field"
                                       displayName:@"ELECTRIC FIELD"
                                         shortName:@"E-FIELD"
                                     specification:@"0.10–2.00 kV/cm drift field"
                                            detail:@"Cathode, gate, and extraction grids steer ionization electrons toward the gas gap."
                                       accentColor:DMDHexColor(0x57E3D0, 1.0)
                                            anchor:SCNVector3Make(2.64, 0.4, 0.8)
                                         labelSide:DMDDetectorPartLabelSideRight
                                       contentNode:fieldGroup
                                             index:6];

    DMDDetectorPart *daq =
        [[DMDDetectorPart alloc] initWithIdentifier:@"daq"
                                       displayName:@"DATA ACQUISITION"
                                         shortName:@"DAQ"
                                     specification:@"PMT cables + readout electronics"
                                            detail:@"Digitizes every sensor waveform and reconstructs event energy, position, and timing."
                                       accentColor:DMDHexColor(0xA0B6FF, 1.0)
                                            anchor:SCNVector3Make(2.55, 4.04, 1.45)
                                         labelSide:DMDDetectorPartLabelSideRight
                                       contentNode:daqGroup
                                             index:7];

    // Right-column labels are ordered by their vertical anchors so leader
    // lines stay short in the default camera view: DAQ and PMTs sit above the
    // TPC, while the field cage occupies the lower-right readout slot.
    return @[water, cryostat, veto, site, daq, sensors, field, tpc];
}

#pragma mark - Camera and lights

- (SCNNode *)addCameraToRoot:(SCNNode *)root {
    SCNNode *cameraNode = [SCNNode node];
    cameraNode.name = @"mainCamera";
    cameraNode.position = kDMDCameraHomePosition;
    [cameraNode lookAt:kDMDCameraHomeTarget];

    SCNCamera *camera = [SCNCamera camera];
    camera.fieldOfView = kDMDCameraHomeFieldOfView;
    camera.zNear = 0.1;
    camera.zFar = 150.0;
    camera.wantsHDR = YES;
    camera.bloomIntensity = 0.06;
    camera.bloomThreshold = 1.35;
    camera.bloomBlurRadius = 4.0;
    camera.wantsExposureAdaptation = NO;
    cameraNode.camera = camera;
    [root addChildNode:cameraNode];
    return cameraNode;
}

- (void)addLightingToRoot:(SCNNode *)root {
    SCNLight *ambientLight = [SCNLight light];
    ambientLight.type = SCNLightTypeAmbient;
    ambientLight.color = DMDHexColor(0x77A1BE, 1.0);
    ambientLight.intensity = 180.0;
    SCNNode *ambientNode = [SCNNode node];
    ambientNode.light = ambientLight;
    [root addChildNode:ambientNode];

    SCNLight *keyLight = [SCNLight light];
    keyLight.type = SCNLightTypeOmni;
    keyLight.color = DMDHexColor(0xFFF0DD, 1.0);
    keyLight.intensity = 620.0;
    SCNNode *keyNode = [SCNNode node];
    keyNode.light = keyLight;
    keyNode.position = SCNVector3Make(8.0, 12.0, 10.0);
    [root addChildNode:keyNode];

    SCNLight *fillLight = [SCNLight light];
    fillLight.type = SCNLightTypeOmni;
    fillLight.color = DMDHexColor(0x42D8FF, 1.0);
    fillLight.intensity = 330.0;
    SCNNode *fillNode = [SCNNode node];
    fillNode.light = fillLight;
    fillNode.position = SCNVector3Make(-9.0, 4.0, -4.0);
    [root addChildNode:fillNode];

    SCNLight *frontLight = [SCNLight light];
    frontLight.type = SCNLightTypeOmni;
    frontLight.color = DMDHexColor(0xBBDDFF, 1.0);
    frontLight.intensity = 260.0;
    SCNNode *frontNode = [SCNNode node];
    frontNode.light = frontLight;
    frontNode.position = SCNVector3Make(0.0, 2.0, 13.0);
    [root addChildNode:frontNode];

    SCNLight *rimLight = [SCNLight light];
    rimLight.type = SCNLightTypeOmni;
    rimLight.color = DMDHexColor(0x8CB6FF, 1.0);
    rimLight.intensity = 190.0;
    SCNNode *rimNode = [SCNNode node];
    rimNode.light = rimLight;
    rimNode.position = SCNVector3Make(-5.0, 7.0, -11.0);
    [root addChildNode:rimNode];

    SCNLight *coreLight = [SCNLight light];
    coreLight.type = SCNLightTypeOmni;
    coreLight.color = DMDHexColor(0x5AD7FF, 1.0);
    coreLight.intensity = 90.0;
    SCNNode *coreNode = [SCNNode node];
    coreNode.light = coreLight;
    coreNode.position = SCNVector3Make(0.0, 0.4, 0.0);
    [root addChildNode:coreNode];
}

@end
