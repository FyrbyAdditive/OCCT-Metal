// Copyright (c) 2025 OPEN CASCADE SAS
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

#ifndef _Metal_PBREnvironment_HeaderFile
#define _Metal_PBREnvironment_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_CubeMap.hxx>
#include <NCollection_Vec3.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
@protocol MTLComputePipelineState;
@protocol MTLRenderPipelineState;
#endif

class Metal_Context;

//! PBR environment maps for Image Based Lighting (IBL) in Metal.
//! Contains specular (pre-filtered) and diffuse (irradiance) cubemaps
//! generated from an environment map for physically-based rendering.
class Metal_PBREnvironment : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_PBREnvironment, Metal_Resource)
public:
  //! Default size for IBL maps (2^9 = 512)
  static const unsigned int DefaultPow2Size = 9;

  //! Default number of specular mipmap levels
  static const unsigned int DefaultSpecMapLevels = 6;

  //! Creates and initializes new PBR environment.
  //! @param theCtx Metal context
  //! @param thePow2Size size of IBL maps as power of 2 (e.g., 9 = 512x512)
  //! @param theSpecMapLevelsNum number of mipmap levels for specular map
  //! @return handle to created PBR environment or NULL on failure
  Standard_EXPORT static occ::handle<Metal_PBREnvironment> Create(
    const occ::handle<Metal_Context>& theCtx,
    unsigned int thePow2Size = DefaultPow2Size,
    unsigned int theSpecMapLevelsNum = DefaultSpecMapLevels);

public:
  //! Destructor - releases Metal resources.
  Standard_EXPORT virtual ~Metal_PBREnvironment();

  //! Returns size of IBL maps as power of 2.
  unsigned int Pow2Size() const { return myPow2Size; }

  //! Returns actual size of IBL maps in pixels.
  unsigned int Size() const { return 1u << myPow2Size; }

  //! Returns number of specular map mipmap levels.
  unsigned int SpecMapLevelsNumber() const { return mySpecMapLevelsNumber; }

  //! Returns true if environment needs to be bound before rendering.
  bool IsNeededToBeBound() const { return myIsNeededToBeBound; }

  //! Generates specular and diffuse IBL maps from environment cubemap.
  //! @param theCtx Metal context
  //! @param theEnvMap source environment cubemap texture
  //! @param theZIsInverted whether Z axis is inverted
  //! @param theIsTopDown whether texture is top-down
  //! @param theDiffMapNbSamples samples for diffuse map Monte-Carlo integration
  //! @param theSpecMapNbSamples samples for specular map Monte-Carlo integration
  Standard_EXPORT void Bake(const occ::handle<Metal_Context>& theCtx,
#ifdef __OBJC__
                            id<MTLTexture> theEnvMap,
#else
                            void* theEnvMap,
#endif
                            bool theZIsInverted = false,
                            bool theIsTopDown = true,
                            size_t theDiffMapNbSamples = 1024,
                            size_t theSpecMapNbSamples = 256);

  //! Clears IBL maps to a uniform color.
  Standard_EXPORT void Clear(const occ::handle<Metal_Context>& theCtx,
                             const NCollection_Vec3<float>& theColor = NCollection_Vec3<float>(1.0f));

  //! Binds diffuse and specular IBL maps for rendering.
  Standard_EXPORT void Bind(const occ::handle<Metal_Context>& theCtx);

  //! Unbinds IBL maps.
  Standard_EXPORT void Unbind(const occ::handle<Metal_Context>& theCtx);

  //! Checks if sizes would be different from current.
  Standard_EXPORT bool SizesAreDifferent(unsigned int thePow2Size,
                                         unsigned int theSpecMapLevelsNumber) const;

  //! Returns estimated GPU memory usage.
  Standard_EXPORT virtual Standard_Size EstimatedDataSize() const Standard_OVERRIDE;

  //! Releases Metal resources.
  Standard_EXPORT virtual void Release() Standard_OVERRIDE;

#ifdef __OBJC__
  //! Returns the specular IBL cubemap texture.
  id<MTLTexture> SpecularMap() const { return mySpecularMap; }

  //! Returns the diffuse/irradiance IBL cubemap texture.
  id<MTLTexture> DiffuseMap() const { return myDiffuseMap; }

  //! Returns the spherical harmonics texture for diffuse IBL.
  id<MTLTexture> DiffuseSHTexture() const { return myDiffuseSHTexture; }
#endif

protected:
  //! Constructor - use Create() factory method.
  Standard_EXPORT Metal_PBREnvironment(const occ::handle<Metal_Context>& theCtx,
                                       unsigned int thePow2Size,
                                       unsigned int theSpecMapLevelsNum);

  //! Initializes textures for IBL maps.
  Standard_EXPORT bool initTextures(const occ::handle<Metal_Context>& theCtx);

  //! Creates compute pipelines for IBL baking.
  Standard_EXPORT bool initPipelines(const occ::handle<Metal_Context>& theCtx);

  //! Generates specular IBL map with GGX importance sampling.
  Standard_EXPORT bool bakeSpecularMap(const occ::handle<Metal_Context>& theCtx,
#ifdef __OBJC__
                                       id<MTLTexture> theEnvMap,
#else
                                       void* theEnvMap,
#endif
                                       bool theZIsInverted,
                                       bool theIsTopDown,
                                       size_t theNbSamples);

  //! Generates diffuse/irradiance IBL map.
  Standard_EXPORT bool bakeDiffuseMap(const occ::handle<Metal_Context>& theCtx,
#ifdef __OBJC__
                                      id<MTLTexture> theEnvMap,
#else
                                      void* theEnvMap,
#endif
                                      bool theZIsInverted,
                                      bool theIsTopDown,
                                      size_t theNbSamples);

private:
  unsigned int myPow2Size;            //!< Size as power of 2
  unsigned int mySpecMapLevelsNumber; //!< Number of specular mipmap levels
  bool myIsNeededToBeBound;           //!< Whether binding is needed
  bool myIsComplete;                  //!< Whether initialization succeeded

#ifdef __OBJC__
  id<MTLTexture> mySpecularMap;           //!< Pre-filtered specular environment cubemap
  id<MTLTexture> myDiffuseMap;            //!< Diffuse irradiance cubemap
  id<MTLTexture> myDiffuseSHTexture;      //!< Spherical harmonics coefficients texture
  id<MTLComputePipelineState> mySpecularBakePipeline;  //!< Compute pipeline for specular baking
  id<MTLComputePipelineState> myDiffuseBakePipeline;   //!< Compute pipeline for diffuse baking
#else
  void* mySpecularMap;
  void* myDiffuseMap;
  void* myDiffuseSHTexture;
  void* mySpecularBakePipeline;
  void* myDiffuseBakePipeline;
#endif
};

#endif // _Metal_PBREnvironment_HeaderFile
