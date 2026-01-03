// Copyright (c) 2024 OPEN CASCADE SAS
//
// This file is part of Open CASCADE Technology software library.
//
// This library is free software; you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License version 2.1 as published
// by the Free Software Foundation, with special exception defined in the file
// OCCT_LGPL_EXCEPTION.txt. Consult the file LICENSE_LGPL_21.txt included in OCCT
// distribution for complete text of the license and disclaimer of any warranty.
//
// Alternatively, this file may be used under the terms of Open CASCADE
// commercial license or contractual agreement.

#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#include <Metal_RayTracing.hxx>
#include <Metal_Context.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_RayTracing, Standard_Transient)

// Ray tracing shaders using Metal Performance Shaders
static const char* RAYTRACING_SHADER_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

// Match the C++ structures
struct RaytraceMaterial {
  float4 ambient;
  float4 diffuse;      // RGB + textureId
  float4 specular;     // RGB + shininess
  float4 emission;
  float4 reflection;
  float4 refraction;
  float4 transparency; // alpha, transparency, IOR, 1/IOR
};

struct RaytraceLight {
  float4 emission;     // RGB + intensity
  float4 position;     // XYZ + type (0=directional, 1=point)
};

struct CameraParams {
  float3 origin;
  float3 lookAt;
  float3 up;
  float  fov;
  float2 resolution;
  int    maxBounces;
  int    shadowsEnabled;
  int    reflectionsEnabled;
  int    lightCount;
};

// Ray structure for MPS
struct Ray {
  packed_float3 origin;
  float minDistance;
  packed_float3 direction;
  float maxDistance;
};

// Intersection result from MPS
struct Intersection {
  float distance;
  int primitiveIndex;
  float2 coordinates;
};

// Generate primary rays from camera
kernel void rayGen(
  device Ray* rays [[buffer(0)]],
  constant CameraParams& camera [[buffer(1)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;

  // Compute ray direction
  float3 forward = normalize(camera.lookAt - camera.origin);
  float3 right = normalize(cross(forward, camera.up));
  float3 up = cross(right, forward);

  float aspectRatio = camera.resolution.x / camera.resolution.y;
  float halfHeight = tan(camera.fov * 0.5);
  float halfWidth = aspectRatio * halfHeight;

  float u = (float(gid.x) + 0.5) / camera.resolution.x * 2.0 - 1.0;
  float v = (float(gid.y) + 0.5) / camera.resolution.y * 2.0 - 1.0;

  float3 direction = normalize(forward + u * halfWidth * right - v * halfHeight * up);

  rays[rayIndex].origin = camera.origin;
  rays[rayIndex].minDistance = 0.001;
  rays[rayIndex].direction = direction;
  rays[rayIndex].maxDistance = INFINITY;
}

// Generate shadow rays from hit points toward a specific light
kernel void shadowRayGenForLight(
  device Ray* shadowRays [[buffer(0)]],
  device const Intersection* primaryIntersections [[buffer(1)]],
  device const Ray* primaryRays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  constant float3* vertices [[buffer(4)]],
  constant uint* indices [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int& lightIndex [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = primaryIntersections[rayIndex];

  // Default: invalid shadow ray (no hit on primary)
  shadowRays[rayIndex].origin = float3(0.0);
  shadowRays[rayIndex].minDistance = -1.0;  // Mark as invalid
  shadowRays[rayIndex].direction = float3(0.0, 1.0, 0.0);
  shadowRays[rayIndex].maxDistance = 0.0;

  if (isect.distance < 0.0) {
    return;  // No primary hit, no shadow ray needed
  }

  RaytraceLight light = lights[lightIndex];

  // Compute hit point
  float3 hitPoint = float3(primaryRays[rayIndex].origin) +
                    isect.distance * float3(primaryRays[rayIndex].direction);

  // Compute light direction and distance
  float3 lightDir;
  float maxDist;

  if (light.position.w < 0.5) {
    // Directional light - ray goes to infinity
    lightDir = normalize(-light.position.xyz);
    maxDist = 1e38;
  } else {
    // Point light - ray goes to light position
    float3 toLight = light.position.xyz - hitPoint;
    float dist = length(toLight);
    lightDir = toLight / dist;
    maxDist = dist - 0.001;  // Stop just before light
  }

  // Offset origin slightly to avoid self-intersection
  float3 shadowOrigin = hitPoint + lightDir * 0.01;

  shadowRays[rayIndex].origin = shadowOrigin;
  shadowRays[rayIndex].minDistance = 0.001;
  shadowRays[rayIndex].direction = lightDir;
  shadowRays[rayIndex].maxDistance = maxDist;
}

// Shade intersections with per-light shadow support
kernel void shade(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  constant float3* vertices [[buffer(3)]],
  constant uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  device const Intersection* shadowIntersections [[buffer(8)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];
  uint pixelCount = uint(camera.resolution.x) * uint(camera.resolution.y);

  float4 color;

  if (isect.distance < 0.0) {
    // No hit - background gradient
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    // Hit - compute shading
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    // Compute normal
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    // Hit point
    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    // Material lookup using per-triangle material index buffer
    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    // Flip normal if backface
    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Start with emission (self-illumination)
    float3 totalLight = mat.emission.rgb;

    // Add ambient contribution
    totalLight += mat.ambient.rgb * 0.15;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        // Directional light
        lightDir = normalize(-light.position.xyz);
      } else {
        // Point light
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      // Per-light shadow test: shadow intersections packed as [light0 pixels][light1 pixels]...
      float shadowFactor = 1.0;
      if (camera.shadowsEnabled > 0) {
        uint shadowIdx = i * pixelCount + rayIndex;
        Intersection shadowIsect = shadowIntersections[shadowIdx];
        if (shadowIsect.distance > 0.0) {
          shadowFactor = 0.0;
        }
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += shadowFactor * diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      // Specular (Blinn-Phong) - also affected by shadow
      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += shadowFactor * mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    // Apply transparency (alpha from transparency.x, opacity = 1 - transparency.y)
    float alpha = mat.transparency.x;
    float opacity = 1.0 - mat.transparency.y;

    // Clamp final color
    color = float4(clamp(totalLight, 0.0, 1.0), alpha * opacity);
  }

  output.write(color, gid);
}

// Shade without shadows (fallback)
kernel void shadeNoShadow(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  constant float3* vertices [[buffer(3)]],
  constant uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    float3 totalLight = mat.emission.rgb;
    totalLight += mat.ambient.rgb * 0.2;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.1 * dist * dist);
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    float alpha = mat.transparency.x;
    float opacity = 1.0 - mat.transparency.y;
    color = float4(clamp(totalLight, 0.0, 1.0), alpha * opacity);
  }

  output.write(color, gid);
}
)";

// =======================================================================
// function : Metal_RayTracing
// purpose  : Constructor
// =======================================================================
Metal_RayTracing::Metal_RayTracing()
: myAccelerationStructure(nil),
  myRayIntersector(nil),
  myRayGenPipeline(nil),
  myShadePipeline(nil),
  myShadeNoShadowPipeline(nil),
  myShadowRayGenPipeline(nil),
  myVertexBuffer(nil),
  myIndexBuffer(nil),
  myMaterialBuffer(nil),
  myMaterialIndexBuffer(nil),
  myLightBuffer(nil),
  myRayBuffer(nil),
  myIntersectionBuffer(nil),
  myShadowRayBuffer(nil),
  myShadowIntersectionBuffer(nil),
  myShaderLibrary(nil),
  myVertexCount(0),
  myTriangleCount(0),
  myMaterialCount(0),
  myLightCount(0),
  myMaxBounces(3),
  myShadowsEnabled(true),
  myReflectionsEnabled(true),
  myIsValid(false)
{
}

// =======================================================================
// function : ~Metal_RayTracing
// purpose  : Destructor
// =======================================================================
Metal_RayTracing::~Metal_RayTracing()
{
  Release(nullptr);
}

// =======================================================================
// function : IsSupported
// purpose  : Check if ray tracing is supported
// =======================================================================
bool Metal_RayTracing::IsSupported(Metal_Context* theCtx)
{
  if (theCtx == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Check for MPS ray tracing support (requires macOS 10.14+ / iOS 12+)
  // and Metal GPU Family Apple 4 or later
  if (@available(macOS 10.14, iOS 12, *))
  {
    // MPS ray tracing is available
    return true;
  }

  return false;
}

// =======================================================================
// function : Init
// purpose  : Initialize ray tracing resources
// =======================================================================
bool Metal_RayTracing::Init(Metal_Context* theCtx)
{
  Release(theCtx);

  if (!IsSupported(theCtx))
  {
    Message::SendWarning() << "Metal_RayTracing: ray tracing not supported on this device";
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  // Compile shaders
  NSError* anError = nil;
  MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
  anOptions.fastMathEnabled = YES;

  myShaderLibrary = [aDevice newLibraryWithSource:@(RAYTRACING_SHADER_SOURCE)
                                          options:anOptions
                                            error:&anError];
  if (myShaderLibrary == nil)
  {
    Message::SendFail() << "Metal_RayTracing: shader compilation failed - "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Create ray generation pipeline
  id<MTLFunction> aRayGenFunc = [myShaderLibrary newFunctionWithName:@"rayGen"];
  if (aRayGenFunc != nil)
  {
    myRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aRayGenFunc error:&anError];
    if (myRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: rayGen pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shading pipeline (with shadow support)
  id<MTLFunction> aShadeFunc = [myShaderLibrary newFunctionWithName:@"shade"];
  if (aShadeFunc != nil)
  {
    myShadePipeline = [aDevice newComputePipelineStateWithFunction:aShadeFunc error:&anError];
    if (myShadePipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shade pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shading pipeline without shadow (fallback)
  id<MTLFunction> aShadeNoShadowFunc = [myShaderLibrary newFunctionWithName:@"shadeNoShadow"];
  if (aShadeNoShadowFunc != nil)
  {
    myShadeNoShadowPipeline = [aDevice newComputePipelineStateWithFunction:aShadeNoShadowFunc error:&anError];
    if (myShadeNoShadowPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadeNoShadow pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shadow ray generation pipeline (per-light)
  id<MTLFunction> aShadowRayGenFunc = [myShaderLibrary newFunctionWithName:@"shadowRayGenForLight"];
  if (aShadowRayGenFunc != nil)
  {
    myShadowRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aShadowRayGenFunc error:&anError];
    if (myShadowRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadowRayGenForLight pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create ray intersector
  myRayIntersector = [[MPSRayIntersector alloc] initWithDevice:aDevice];
  myRayIntersector.rayDataType = MPSRayDataTypeOriginMinDistanceDirectionMaxDistance;
  myRayIntersector.rayStride = sizeof(float) * 8;  // origin(3) + min(1) + dir(3) + max(1)
  myRayIntersector.intersectionDataType = MPSIntersectionDataTypeDistancePrimitiveIndexCoordinates;

  myIsValid = true;
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_RayTracing::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  myAccelerationStructure = nil;
  myRayIntersector = nil;
  myRayGenPipeline = nil;
  myShadePipeline = nil;
  myShadeNoShadowPipeline = nil;
  myShadowRayGenPipeline = nil;
  myVertexBuffer = nil;
  myIndexBuffer = nil;
  myMaterialBuffer = nil;
  myMaterialIndexBuffer = nil;
  myLightBuffer = nil;
  myRayBuffer = nil;
  myIntersectionBuffer = nil;
  myShadowRayBuffer = nil;
  myShadowIntersectionBuffer = nil;
  myShaderLibrary = nil;

  myVertexCount = 0;
  myTriangleCount = 0;
  myMaterialCount = 0;
  myLightCount = 0;
  myIsValid = false;
}

// =======================================================================
// function : BuildAccelerationStructure
// purpose  : Build BVH from triangle geometry
// =======================================================================
bool Metal_RayTracing::BuildAccelerationStructure(
  Metal_Context* theCtx,
  const float* theVertices,
  int theVertexCount,
  const uint32_t* theIndices,
  int theTriangleCount)
{
  if (!myIsValid || theCtx == nullptr || theVertices == nullptr || theIndices == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  // Create vertex buffer
  size_t aVertexSize = static_cast<size_t>(theVertexCount) * 3 * sizeof(float);
  myVertexBuffer = [aDevice newBufferWithBytes:theVertices
                                        length:aVertexSize
                                       options:MTLResourceStorageModeShared];

  // Create index buffer
  size_t anIndexSize = static_cast<size_t>(theTriangleCount) * 3 * sizeof(uint32_t);
  myIndexBuffer = [aDevice newBufferWithBytes:theIndices
                                       length:anIndexSize
                                      options:MTLResourceStorageModeShared];

  myVertexCount = theVertexCount;
  myTriangleCount = theTriangleCount;

  // Build acceleration structure
  myAccelerationStructure = [[MPSTriangleAccelerationStructure alloc] initWithDevice:aDevice];
  myAccelerationStructure.vertexBuffer = myVertexBuffer;
  myAccelerationStructure.vertexStride = sizeof(float) * 3;
  myAccelerationStructure.indexBuffer = myIndexBuffer;
  myAccelerationStructure.indexType = MPSDataTypeUInt32;
  myAccelerationStructure.triangleCount = static_cast<NSUInteger>(theTriangleCount);

  // Rebuild the acceleration structure
  [myAccelerationStructure rebuild];

  return true;
}

// =======================================================================
// function : SetMaterials
// purpose  : Set materials for ray tracing
// =======================================================================
void Metal_RayTracing::SetMaterials(Metal_Context* theCtx,
                                    const Metal_RaytraceMaterial* theMaterials,
                                    int theMaterialCount)
{
  if (!myIsValid || theCtx == nullptr || theMaterials == nullptr || theMaterialCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theMaterialCount) * sizeof(Metal_RaytraceMaterial);
  myMaterialBuffer = [aDevice newBufferWithBytes:theMaterials
                                          length:aSize
                                         options:MTLResourceStorageModeShared];
  myMaterialCount = theMaterialCount;
}

// =======================================================================
// function : SetMaterialIndices
// purpose  : Set per-triangle material indices
// =======================================================================
void Metal_RayTracing::SetMaterialIndices(Metal_Context* theCtx,
                                          const int32_t* theMaterialIndices,
                                          int theTriangleCount)
{
  if (!myIsValid || theCtx == nullptr || theMaterialIndices == nullptr || theTriangleCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theTriangleCount) * sizeof(int32_t);
  myMaterialIndexBuffer = [aDevice newBufferWithBytes:theMaterialIndices
                                               length:aSize
                                              options:MTLResourceStorageModeShared];
}

// =======================================================================
// function : SetLights
// purpose  : Set lights for ray tracing
// =======================================================================
void Metal_RayTracing::SetLights(Metal_Context* theCtx,
                                 const Metal_RaytraceLight* theLights,
                                 int theLightCount)
{
  if (!myIsValid || theCtx == nullptr || theLights == nullptr || theLightCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theLightCount) * sizeof(Metal_RaytraceLight);
  myLightBuffer = [aDevice newBufferWithBytes:theLights
                                       length:aSize
                                      options:MTLResourceStorageModeShared];
  myLightCount = theLightCount;
}

// =======================================================================
// function : Trace
// purpose  : Perform ray tracing
// =======================================================================
void Metal_RayTracing::Trace(Metal_Context* theCtx,
                             id<MTLCommandBuffer> theCommandBuffer,
                             id<MTLTexture> theOutputTexture,
                             const NCollection_Vec3<float>& theCameraOrigin,
                             const NCollection_Vec3<float>& theCameraLookAt,
                             const NCollection_Vec3<float>& theCameraUp,
                             float theFov)
{
  if (!myIsValid || theCommandBuffer == nil || theOutputTexture == nil)
  {
    return;
  }

  if (myAccelerationStructure == nil || myTriangleCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  NSUInteger aWidth = [theOutputTexture width];
  NSUInteger aHeight = [theOutputTexture height];
  NSUInteger aRayCount = aWidth * aHeight;

  // Ensure ray and intersection buffers are large enough
  size_t aRayBufferSize = aRayCount * sizeof(float) * 8;
  size_t aIntersectionBufferSize = aRayCount * sizeof(float) * 4;  // distance + primitiveIndex + uv

  if (myRayBuffer == nil || [myRayBuffer length] < aRayBufferSize)
  {
    myRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                       options:MTLResourceStorageModePrivate];
  }

  if (myIntersectionBuffer == nil || [myIntersectionBuffer length] < aIntersectionBufferSize)
  {
    myIntersectionBuffer = [aDevice newBufferWithLength:aIntersectionBufferSize
                                                options:MTLResourceStorageModePrivate];
  }

  // Shadow ray buffers (only if shadows enabled and we have lights)
  // Shadow intersections are packed: [light0 all pixels][light1 all pixels]...
  bool aUseShadows = myShadowsEnabled && myLightCount > 0 && myShadowRayGenPipeline != nil;
  if (aUseShadows)
  {
    if (myShadowRayBuffer == nil || [myShadowRayBuffer length] < aRayBufferSize)
    {
      myShadowRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                               options:MTLResourceStorageModePrivate];
    }

    // Need space for shadow intersections for ALL lights
    size_t aShadowIntersectionSize = aIntersectionBufferSize * static_cast<size_t>(myLightCount);
    if (myShadowIntersectionBuffer == nil || [myShadowIntersectionBuffer length] < aShadowIntersectionSize)
    {
      myShadowIntersectionBuffer = [aDevice newBufferWithLength:aShadowIntersectionSize
                                                        options:MTLResourceStorageModePrivate];
    }
  }

  // Camera parameters
  struct CameraParams {
    simd_float3 origin;
    simd_float3 lookAt;
    simd_float3 up;
    float fov;
    simd_float2 resolution;
    int maxBounces;
    int shadowsEnabled;
    int reflectionsEnabled;
    int lightCount;
  } aCameraParams;

  aCameraParams.origin = simd_make_float3(theCameraOrigin.x(), theCameraOrigin.y(), theCameraOrigin.z());
  aCameraParams.lookAt = simd_make_float3(theCameraLookAt.x(), theCameraLookAt.y(), theCameraLookAt.z());
  aCameraParams.up = simd_make_float3(theCameraUp.x(), theCameraUp.y(), theCameraUp.z());
  aCameraParams.fov = theFov;
  aCameraParams.resolution = simd_make_float2(static_cast<float>(aWidth), static_cast<float>(aHeight));
  aCameraParams.maxBounces = myMaxBounces;
  aCameraParams.shadowsEnabled = aUseShadows ? 1 : 0;
  aCameraParams.reflectionsEnabled = myReflectionsEnabled ? 1 : 0;
  aCameraParams.lightCount = myLightCount;

  // Step 1: Generate rays
  {
    id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
    [anEncoder setComputePipelineState:myRayGenPipeline];
    [anEncoder setBuffer:myRayBuffer offset:0 atIndex:0];
    [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:1];

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);
    [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
    [anEncoder endEncoding];
  }

  // Step 2: Intersect primary rays with geometry
  [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                     intersectionType:MPSIntersectionTypeNearest
                                            rayBuffer:myRayBuffer
                                      rayBufferOffset:0
                                   intersectionBuffer:myIntersectionBuffer
                             intersectionBufferOffset:0
                                             rayCount:aRayCount
                                accelerationStructure:myAccelerationStructure];

  // Step 3: Generate and intersect shadow rays for each light
  if (aUseShadows)
  {
    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);

    for (int aLightIdx = 0; aLightIdx < myLightCount; ++aLightIdx)
    {
      // 3a: Generate shadow rays from hit points toward this light
      {
        id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
        [anEncoder setComputePipelineState:myShadowRayGenPipeline];
        [anEncoder setBuffer:myShadowRayBuffer offset:0 atIndex:0];
        [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:1];
        [anEncoder setBuffer:myRayBuffer offset:0 atIndex:2];
        [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
        [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
        [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
        [anEncoder setBuffer:myLightBuffer offset:0 atIndex:6];
        [anEncoder setBytes:&aLightIdx length:sizeof(aLightIdx) atIndex:7];
        [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
        [anEncoder endEncoding];
      }

      // 3b: Intersect shadow rays, store at offset for this light
      size_t aShadowOffset = static_cast<size_t>(aLightIdx) * aIntersectionBufferSize;
      [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                         intersectionType:MPSIntersectionTypeAny
                                                rayBuffer:myShadowRayBuffer
                                          rayBufferOffset:0
                                       intersectionBuffer:myShadowIntersectionBuffer
                                 intersectionBufferOffset:aShadowOffset
                                                 rayCount:aRayCount
                                    accelerationStructure:myAccelerationStructure];
    }
  }

  // Step 4: Shade intersections
  {
    id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];

    if (aUseShadows)
    {
      // Use shade kernel with shadow support
      [anEncoder setComputePipelineState:myShadePipeline];
    }
    else
    {
      // Use shade kernel without shadow support
      [anEncoder setComputePipelineState:myShadeNoShadowPipeline];
    }

    [anEncoder setTexture:theOutputTexture atIndex:0];
    [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:0];
    [anEncoder setBuffer:myRayBuffer offset:0 atIndex:1];
    [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:2];
    [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:3];
    [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:4];

    if (myMaterialBuffer != nil)
    {
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:5];
    }

    if (myLightBuffer != nil)
    {
      [anEncoder setBuffer:myLightBuffer offset:0 atIndex:6];
    }

    // Material index buffer (per-triangle material lookup)
    if (myMaterialIndexBuffer != nil)
    {
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:7];
    }
    else
    {
      // Fallback: all triangles use material 0
      static int32_t aZeroIndex = 0;
      [anEncoder setBytes:&aZeroIndex length:sizeof(aZeroIndex) atIndex:7];
    }

    // Shadow intersection buffer (only used if shadows enabled)
    if (aUseShadows)
    {
      [anEncoder setBuffer:myShadowIntersectionBuffer offset:0 atIndex:8];
    }

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);
    [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
    [anEncoder endEncoding];
  }
}
