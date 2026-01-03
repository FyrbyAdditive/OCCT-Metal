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
  bool myIsValid;
};

DEFINE_STANDARD_HANDLE(Metal_RayTracing, Standard_Transient)

#endif // Metal_RayTracing_HeaderFile
