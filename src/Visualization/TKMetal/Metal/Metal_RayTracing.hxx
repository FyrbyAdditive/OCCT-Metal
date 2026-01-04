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

#ifndef Metal_RayTracing_HeaderFile
#define Metal_RayTracing_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <NCollection_Vec3.hxx>
#include <NCollection_Vec4.hxx>
#include <NCollection_Mat4.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#endif

class Metal_Context;

//! Ray tracing material structure (matches OpenGl_RaytraceMaterial layout).
//! Padded to 16-byte alignment for Metal buffer access.
struct Metal_RaytraceMaterial
{
  NCollection_Vec4<float> Ambient;      //!< RGB + padding
  NCollection_Vec4<float> Diffuse;      //!< RGB + texture ID
  NCollection_Vec4<float> Specular;     //!< RGB + shininess
  NCollection_Vec4<float> Emission;     //!< RGB + padding
  NCollection_Vec4<float> Reflection;   //!< Reflection coefficient
  NCollection_Vec4<float> Refraction;   //!< Refraction coefficient
  NCollection_Vec4<float> Transparency; //!< Alpha, transparency, IOR, 1/IOR
};

//! Ray tracing light source structure.
struct Metal_RaytraceLight
{
  NCollection_Vec4<float> Emission;  //!< Light color/intensity
  NCollection_Vec4<float> Position;  //!< XYZ position, W = type (0=directional, 1=point)
};

//! Triangle structure for ray tracing geometry.
struct Metal_RaytraceTriangle
{
  uint32_t Indices[3];   //!< Vertex indices
  uint32_t MaterialId;   //!< Material index
};

//! Metal ray tracing acceleration structure and pipeline manager.
//! Uses Metal Performance Shaders (MPS) for hardware-accelerated ray tracing
//! on Apple GPUs with ray tracing support.
class Metal_RayTracing : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_RayTracing, Standard_Transient)

public:

  //! Create empty ray tracing manager.
  Standard_EXPORT Metal_RayTracing();

  //! Destructor.
  Standard_EXPORT ~Metal_RayTracing();

  //! Check if ray tracing is supported on this device.
  Standard_EXPORT static bool IsSupported(Metal_Context* theCtx);

  //! Initialize ray tracing resources.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return true if ray tracing is initialized.
  bool IsValid() const { return myIsValid; }

  //! Build acceleration structure from triangle geometry.
  //! @param theCtx Metal context
  //! @param theVertices vertex positions (3 floats per vertex)
  //! @param theVertexCount number of vertices
  //! @param theIndices triangle indices (3 per triangle)
  //! @param theTriangleCount number of triangles
  //! @return true on success
  Standard_EXPORT bool BuildAccelerationStructure(
    Metal_Context* theCtx,
    const float* theVertices,
    int theVertexCount,
    const uint32_t* theIndices,
    int theTriangleCount);

  //! Set materials for ray tracing.
  //! @param theCtx Metal context
  //! @param theMaterials array of materials
  //! @param theMaterialCount number of materials
  Standard_EXPORT void SetMaterials(Metal_Context* theCtx,
                                    const Metal_RaytraceMaterial* theMaterials,
                                    int theMaterialCount);

  //! Set per-triangle material indices.
  //! @param theCtx Metal context
  //! @param theMaterialIndices array of material indices (one per triangle)
  //! @param theTriangleCount number of triangles
  Standard_EXPORT void SetMaterialIndices(Metal_Context* theCtx,
                                          const int32_t* theMaterialIndices,
                                          int theTriangleCount);

  //! Set lights for ray tracing.
  //! @param theCtx Metal context
  //! @param theLights array of lights
  //! @param theLightCount number of lights
  Standard_EXPORT void SetLights(Metal_Context* theCtx,
                                 const Metal_RaytraceLight* theLights,
                                 int theLightCount);

  //! Set per-vertex texture coordinates (Phase 7).
  //! @param theCtx Metal context
  //! @param theTexCoords array of UV coordinates (2 floats per vertex)
  //! @param theVertexCount number of vertices
  Standard_EXPORT void SetTexCoords(Metal_Context* theCtx,
                                    const float* theTexCoords,
                                    int theVertexCount);

  //! Set diffuse texture array for ray tracing (Phase 8).
  //! @param theCtx Metal context
  //! @param theTextures array of textures
  //! @param theTextureCount number of textures
#ifdef __OBJC__
  Standard_EXPORT void SetDiffuseTextures(Metal_Context* theCtx,
                                          NSArray<id<MTLTexture>>* theTextures);
#endif

  //! Set normal map texture array for ray tracing (Phase 8).
  //! @param theCtx Metal context
  //! @param theTextures array of normal map textures
#ifdef __OBJC__
  Standard_EXPORT void SetNormalTextures(Metal_Context* theCtx,
                                         NSArray<id<MTLTexture>>* theTextures);
#endif

  //! Set texturing enabled (Phase 8).
  void SetTexturingEnabled(bool theEnabled) { myTexturingEnabled = theEnabled; }

  //! Return true if texturing is enabled.
  bool IsTexturingEnabled() const { return myTexturingEnabled; }

  //! Perform ray tracing to an output texture.
  //! @param theCtx Metal context
  //! @param theCommandBuffer command buffer
  //! @param theOutputTexture target texture for ray traced image
  //! @param theCameraOrigin camera position
  //! @param theCameraLookAt camera target
  //! @param theCameraUp camera up vector
  //! @param theFov field of view in radians
#ifdef __OBJC__
  Standard_EXPORT void Trace(Metal_Context* theCtx,
                             id<MTLCommandBuffer> theCommandBuffer,
                             id<MTLTexture> theOutputTexture,
                             const NCollection_Vec3<float>& theCameraOrigin,
                             const NCollection_Vec3<float>& theCameraLookAt,
                             const NCollection_Vec3<float>& theCameraUp,
                             float theFov);
#endif

  //! Set maximum ray bounces.
  void SetMaxBounces(int theBounces) { myMaxBounces = theBounces; }

  //! Return maximum ray bounces.
  int MaxBounces() const { return myMaxBounces; }

  //! Set shadows enabled.
  void SetShadowsEnabled(bool theEnabled) { myShadowsEnabled = theEnabled; }

  //! Return true if shadows are enabled.
  bool IsShadowsEnabled() const { return myShadowsEnabled; }

  //! Set reflections enabled.
  void SetReflectionsEnabled(bool theEnabled) { myReflectionsEnabled = theEnabled; }

  //! Return true if reflections are enabled.
  bool IsReflectionsEnabled() const { return myReflectionsEnabled; }

  //! Set refractions enabled (Phase 6).
  void SetRefractionsEnabled(bool theEnabled) { myRefractionsEnabled = theEnabled; }

  //! Return true if refractions are enabled.
  bool IsRefractionsEnabled() const { return myRefractionsEnabled; }

  //! Set path tracing enabled (Phase 9).
  void SetPathTracingEnabled(bool theEnabled) { myPathTracingEnabled = theEnabled; }

  //! Return true if path tracing is enabled.
  bool IsPathTracingEnabled() const { return myPathTracingEnabled; }

  //! Reset accumulation buffer for path tracing (Phase 9).
  //! Call this when camera or scene changes.
  void ResetAccumulation() { myFrameIndex = 0; }

  //! Return current frame index for path tracing accumulation.
  uint32_t FrameIndex() const { return myFrameIndex; }

  //! Set BSDF sampling enabled for physically-based materials (Phase 10).
  //! When enabled, uses Cook-Torrance GGX microfacet BRDF.
  void SetBSDFSamplingEnabled(bool theEnabled) { myBSDFSamplingEnabled = theEnabled; }

  //! Return true if BSDF sampling is enabled.
  bool IsBSDFSamplingEnabled() const { return myBSDFSamplingEnabled; }

  //! Set adaptive sampling enabled (Phase 11).
  //! When enabled, pixels converge independently based on variance.
  void SetAdaptiveSamplingEnabled(bool theEnabled) { myAdaptiveSamplingEnabled = theEnabled; }

  //! Return true if adaptive sampling is enabled.
  bool IsAdaptiveSamplingEnabled() const { return myAdaptiveSamplingEnabled; }

  //! Set variance threshold for adaptive sampling (Phase 11).
  //! Lower values = higher quality, more samples. Default: 0.01
  void SetVarianceThreshold(float theThreshold) { myVarianceThreshold = theThreshold; }

  //! Return variance threshold for adaptive sampling.
  float VarianceThreshold() const { return myVarianceThreshold; }

  //! Set minimum samples before checking variance (Phase 11). Default: 16
  void SetMinSamples(uint32_t theMinSamples) { myMinSamples = theMinSamples; }

  //! Return minimum samples for adaptive sampling.
  uint32_t MinSamples() const { return myMinSamples; }

  //! Set maximum samples per pixel (Phase 11). Default: 1024
  void SetMaxSamples(uint32_t theMaxSamples) { myMaxSamples = theMaxSamples; }

  //! Return maximum samples for adaptive sampling.
  uint32_t MaxSamples() const { return myMaxSamples; }

  //! Set environment map texture for IBL (Phase 12).
  //! @param theCtx Metal context
  //! @param theEnvMap equirectangular HDR environment map texture
#ifdef __OBJC__
  Standard_EXPORT void SetEnvironmentMap(Metal_Context* theCtx,
                                         id<MTLTexture> theEnvMap);
#endif

  //! Set environment map enabled (Phase 12).
  void SetEnvironmentMapEnabled(bool theEnabled) { myEnvMapEnabled = theEnabled; }

  //! Return true if environment map is enabled.
  bool IsEnvironmentMapEnabled() const { return myEnvMapEnabled; }

  //! Set environment map intensity multiplier (Phase 12). Default: 1.0
  void SetEnvironmentMapIntensity(float theIntensity) { myEnvMapIntensity = theIntensity; }

  //! Return environment map intensity.
  float EnvironmentMapIntensity() const { return myEnvMapIntensity; }

  //! Set environment map rotation in radians (Phase 12). Default: 0.0
  void SetEnvironmentMapRotation(float theRotation) { myEnvMapRotation = theRotation; }

  //! Return environment map rotation.
  float EnvironmentMapRotation() const { return myEnvMapRotation; }

  //! Set depth of field enabled (Phase 13).
  void SetDepthOfFieldEnabled(bool theEnabled) { myDOFEnabled = theEnabled; }

  //! Return true if depth of field is enabled.
  bool IsDepthOfFieldEnabled() const { return myDOFEnabled; }

  //! Set aperture radius for DOF (Phase 13). 0 = pinhole (no DOF). Default: 0.0
  void SetAperture(float theAperture) { myAperture = theAperture; }

  //! Return aperture radius.
  float Aperture() const { return myAperture; }

  //! Set focal distance for DOF (Phase 13). Default: 5.0
  void SetFocalDistance(float theDistance) { myFocalDistance = theDistance; }

  //! Return focal distance.
  float FocalDistance() const { return myFocalDistance; }

  //! Tone mapping mode enumeration (Phase 14).
  enum ToneMappingMode {
    ToneMapping_None = 0,       //!< No tone mapping (clamp to [0,1])
    ToneMapping_Reinhard = 1,   //!< Reinhard extended
    ToneMapping_ACES = 2,       //!< ACES Filmic
    ToneMapping_Uncharted2 = 3  //!< Uncharted 2 filmic
  };

  //! Set tone mapping enabled (Phase 14).
  void SetToneMappingEnabled(bool theEnabled) { myToneMappingEnabled = theEnabled; }

  //! Return true if tone mapping is enabled.
  bool IsToneMappingEnabled() const { return myToneMappingEnabled; }

  //! Set tone mapping mode (Phase 14). Default: ToneMapping_ACES
  void SetToneMappingMode(ToneMappingMode theMode) { myToneMappingMode = theMode; }

  //! Return tone mapping mode.
  ToneMappingMode GetToneMappingMode() const { return myToneMappingMode; }

  //! Set exposure value (Phase 14). Default: 0.0 (no adjustment)
  void SetExposure(float theExposure) { myExposure = theExposure; }

  //! Return exposure value.
  float Exposure() const { return myExposure; }

  //! Set gamma value (Phase 14). Default: 2.2
  void SetGamma(float theGamma) { myGamma = theGamma; }

  //! Return gamma value.
  float Gamma() const { return myGamma; }

  //! Set white point for tone mapping (Phase 14). Default: 4.0
  void SetWhitePoint(float theWhitePoint) { myWhitePoint = theWhitePoint; }

  //! Return white point.
  float WhitePoint() const { return myWhitePoint; }

  //! Set bloom enabled (Phase 14).
  void SetBloomEnabled(bool theEnabled) { myBloomEnabled = theEnabled; }

  //! Return true if bloom is enabled.
  bool IsBloomEnabled() const { return myBloomEnabled; }

  //! Set bloom threshold (Phase 14). Default: 1.0
  void SetBloomThreshold(float theThreshold) { myBloomThreshold = theThreshold; }

  //! Return bloom threshold.
  float BloomThreshold() const { return myBloomThreshold; }

  //! Set bloom intensity (Phase 14). Default: 0.3
  void SetBloomIntensity(float theIntensity) { myBloomIntensity = theIntensity; }

  //! Return bloom intensity.
  float BloomIntensity() const { return myBloomIntensity; }

private:

#ifdef __OBJC__
  // Acceleration structure (MPS ray tracing)
  MPSTriangleAccelerationStructure* myAccelerationStructure;
  MPSRayIntersector* myRayIntersector;

  // Compute pipeline for ray generation and shading
  id<MTLComputePipelineState> myRayGenPipeline;
  id<MTLComputePipelineState> myShadePipeline;
  id<MTLComputePipelineState> myShadeNoShadowPipeline;
  id<MTLComputePipelineState> myShadowRayGenPipeline;
  id<MTLComputePipelineState> myReflectionRayGenPipeline;  //!< Phase 5: Reflection ray generation
  id<MTLComputePipelineState> myBounceColorPipeline;       //!< Phase 5: Compute bounce colors
  id<MTLComputePipelineState> myShadeWithReflectionsPipeline; //!< Phase 5: Shade with reflections
  id<MTLComputePipelineState> myRefractionRayGenPipeline;  //!< Phase 6: Refraction ray generation
  id<MTLComputePipelineState> myRefractionColorPipeline;   //!< Phase 6: Compute refraction colors
  id<MTLComputePipelineState> myShadeWithAllPipeline;      //!< Phase 6: Full shading with reflections + refractions
  id<MTLComputePipelineState> myShadeWithTexturesPipeline; //!< Phase 8: Full shading with textures
  id<MTLComputePipelineState> myPathTraceRayGenPipeline;   //!< Phase 9: Path tracing ray generation with jitter
  id<MTLComputePipelineState> myPathTracePipeline;         //!< Phase 9: Path tracing kernel
  id<MTLComputePipelineState> myPathTraceBSDFPipeline;     //!< Phase 10: Path tracing with GGX BSDF
  id<MTLComputePipelineState> myAccumulatePipeline;        //!< Phase 9: Accumulation kernel
  id<MTLComputePipelineState> myAdaptiveRayGenPipeline;    //!< Phase 11: Adaptive ray generation
  id<MTLComputePipelineState> myAdaptivePathTracePipeline; //!< Phase 11: Adaptive path tracing
  id<MTLComputePipelineState> myResetAdaptiveStatsPipeline; //!< Phase 11: Reset adaptive stats
  id<MTLComputePipelineState> myEnvMapPathTracePipeline;   //!< Phase 12: Path tracing with environment map
  id<MTLComputePipelineState> myDOFRayGenPipeline;         //!< Phase 13: DOF ray generation
  id<MTLComputePipelineState> myDOFPathTracePipeline;      //!< Phase 13: DOF path tracing
  id<MTLComputePipelineState> myToneMappingPipeline;       //!< Phase 14: Tone mapping
  id<MTLComputePipelineState> myExtractBrightPipeline;     //!< Phase 14: Bloom brightness extraction
  id<MTLComputePipelineState> myBlurHorizontalPipeline;    //!< Phase 14: Bloom horizontal blur
  id<MTLComputePipelineState> myBlurVerticalPipeline;      //!< Phase 14: Bloom vertical blur
  id<MTLComputePipelineState> myApplyBloomPipeline;        //!< Phase 14: Apply bloom

  // Buffers
  id<MTLBuffer> myVertexBuffer;
  id<MTLBuffer> myIndexBuffer;
  id<MTLBuffer> myMaterialBuffer;
  id<MTLBuffer> myMaterialIndexBuffer;  //!< Per-triangle material indices
  id<MTLBuffer> myLightBuffer;
  id<MTLBuffer> myRayBuffer;
  id<MTLBuffer> myIntersectionBuffer;
  id<MTLBuffer> myShadowRayBuffer;           //!< Shadow rays
  id<MTLBuffer> myShadowIntersectionBuffer;  //!< Shadow ray intersections
  id<MTLBuffer> myReflectionRayBuffer;       //!< Phase 5: Reflection rays
  id<MTLBuffer> myReflectionIntersectionBuffer; //!< Phase 5: Reflection intersections
  id<MTLBuffer> myBounceColorBuffer;         //!< Phase 5: Accumulated bounce colors
  id<MTLBuffer> myTexCoordBuffer;            //!< Phase 7: Per-vertex texture coordinates
  id<MTLBuffer> myRefractionRayBuffer;       //!< Phase 6: Refraction rays (first bounce)
  id<MTLBuffer> myRefractionRayBuffer2;      //!< Phase 6: Refraction rays (second bounce)
  id<MTLBuffer> myRefractionIntersectionBuffer; //!< Phase 6: Refraction intersections (first)
  id<MTLBuffer> myRefractionIntersectionBuffer2; //!< Phase 6: Refraction intersections (second)
  id<MTLBuffer> myRefractionColorBuffer;     //!< Phase 6: Refraction colors

  // Phase 8: Textures
  id<MTLTexture> myDiffuseTextureArray;      //!< Phase 8: Diffuse texture array
  id<MTLTexture> myNormalTextureArray;       //!< Phase 8: Normal map texture array
  id<MTLSamplerState> myTextureSampler;      //!< Phase 8: Texture sampler

  // Phase 9: Path tracing buffers
  id<MTLTexture> myAccumulationBuffer;       //!< Phase 9: Accumulated radiance (RGBA32Float)
  id<MTLBuffer> myRandomSeedBuffer;          //!< Phase 9: Per-pixel RNG state

  // Phase 11: Adaptive sampling buffers
  id<MTLBuffer> myPixelStatsBuffer;          //!< Phase 11: Per-pixel variance statistics

  // Phase 12: Environment map
  id<MTLTexture> myEnvironmentMap;           //!< Phase 12: HDR environment map (equirectangular)
  id<MTLSamplerState> myEnvMapSampler;       //!< Phase 12: Environment map sampler

  // Phase 14: Tone mapping and bloom
  id<MTLTexture> myHDRBuffer;                //!< Phase 14: HDR render buffer
  id<MTLTexture> myBrightBuffer;             //!< Phase 14: Extracted bright pixels
  id<MTLTexture> myBloomTempBuffer;          //!< Phase 14: Bloom blur temp buffer

  // Shader library
  id<MTLLibrary> myShaderLibrary;
#else
  void* myAccelerationStructure;
  void* myRayIntersector;
  void* myRayGenPipeline;
  void* myShadePipeline;
  void* myShadeNoShadowPipeline;
  void* myShadowRayGenPipeline;
  void* myReflectionRayGenPipeline;
  void* myBounceColorPipeline;
  void* myShadeWithReflectionsPipeline;
  void* myRefractionRayGenPipeline;
  void* myRefractionColorPipeline;
  void* myShadeWithAllPipeline;
  void* myShadeWithTexturesPipeline;
  void* myPathTraceRayGenPipeline;
  void* myPathTracePipeline;
  void* myPathTraceBSDFPipeline;
  void* myAccumulatePipeline;
  void* myAdaptiveRayGenPipeline;
  void* myAdaptivePathTracePipeline;
  void* myResetAdaptiveStatsPipeline;
  void* myEnvMapPathTracePipeline;
  void* myDOFRayGenPipeline;
  void* myDOFPathTracePipeline;
  void* myToneMappingPipeline;
  void* myExtractBrightPipeline;
  void* myBlurHorizontalPipeline;
  void* myBlurVerticalPipeline;
  void* myApplyBloomPipeline;
  void* myVertexBuffer;
  void* myIndexBuffer;
  void* myMaterialBuffer;
  void* myMaterialIndexBuffer;
  void* myLightBuffer;
  void* myRayBuffer;
  void* myIntersectionBuffer;
  void* myShadowRayBuffer;
  void* myShadowIntersectionBuffer;
  void* myReflectionRayBuffer;
  void* myReflectionIntersectionBuffer;
  void* myBounceColorBuffer;
  void* myTexCoordBuffer;
  void* myRefractionRayBuffer;
  void* myRefractionRayBuffer2;
  void* myRefractionIntersectionBuffer;
  void* myRefractionIntersectionBuffer2;
  void* myRefractionColorBuffer;
  void* myDiffuseTextureArray;
  void* myNormalTextureArray;
  void* myTextureSampler;
  void* myAccumulationBuffer;
  void* myRandomSeedBuffer;
  void* myPixelStatsBuffer;
  void* myEnvironmentMap;
  void* myEnvMapSampler;
  void* myHDRBuffer;
  void* myBrightBuffer;
  void* myBloomTempBuffer;
  void* myShaderLibrary;
#endif

  int  myVertexCount;
  int  myTriangleCount;
  int  myMaterialCount;
  int  myLightCount;
  int  myMaxBounces;
  bool myShadowsEnabled;
  bool myReflectionsEnabled;
  bool myRefractionsEnabled;
  bool myTexturingEnabled;
  bool myPathTracingEnabled;
  bool myBSDFSamplingEnabled;      //!< Phase 10: Use Cook-Torrance GGX BSDF
  bool myAdaptiveSamplingEnabled;  //!< Phase 11: Use adaptive sampling
  bool myEnvMapEnabled;            //!< Phase 12: Use environment map for lighting
  bool myIsValid;
  uint32_t myFrameIndex;           //!< Phase 9: Current frame for accumulation
  float myVarianceThreshold;       //!< Phase 11: Variance threshold for convergence
  uint32_t myMinSamples;           //!< Phase 11: Minimum samples before checking variance
  uint32_t myMaxSamples;           //!< Phase 11: Maximum samples per pixel
  float myEnvMapIntensity;         //!< Phase 12: Environment map intensity multiplier
  float myEnvMapRotation;          //!< Phase 12: Environment map rotation in radians
  bool myDOFEnabled;               //!< Phase 13: Enable depth of field
  float myAperture;                //!< Phase 13: Aperture radius (0 = pinhole)
  float myFocalDistance;           //!< Phase 13: Focal distance
  bool myToneMappingEnabled;       //!< Phase 14: Enable tone mapping
  ToneMappingMode myToneMappingMode; //!< Phase 14: Tone mapping operator
  float myExposure;                //!< Phase 14: Exposure adjustment (EV)
  float myGamma;                   //!< Phase 14: Gamma correction value
  float myWhitePoint;              //!< Phase 14: White point for Reinhard/Uncharted2
  bool myBloomEnabled;             //!< Phase 14: Enable bloom post-process
  float myBloomThreshold;          //!< Phase 14: Bloom brightness threshold
  float myBloomIntensity;          //!< Phase 14: Bloom strength
};

DEFINE_STANDARD_HANDLE(Metal_RayTracing, Standard_Transient)

#endif // Metal_RayTracing_HeaderFile
