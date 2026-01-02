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

#ifndef Metal_ShaderManager_HeaderFile
#define Metal_ShaderManager_HeaderFile

#include <Graphic3d_ShaderManager.hxx>
#include <Graphic3d_LightSet.hxx>
#include <Graphic3d_TypeOfShadingModel.hxx>
#include <Graphic3d_ShaderFlags.hxx>
#include <Graphic3d_SequenceOfHClipPlane.hxx>
#include <NCollection_DataMap.hxx>
#include <NCollection_Mat4.hxx>
#include <NCollection_Vec4.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLDevice;
@protocol MTLLibrary;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
@protocol MTLFunction;
#endif

class Metal_Context;
class Graphic3d_ClipPlane;

//! Maximum number of light sources supported in shaders.
static const int Metal_MaxLights = 8;

//! Maximum number of clipping planes supported in shaders.
static const int Metal_MaxClipPlanes = 8;

//! Packed light source parameters for shader uniform.
struct Metal_ShaderLightSource
{
  float Color[4];      //!< RGB color + intensity (in .w)
  float Position[4];   //!< XYZ position/direction + isHeadlight (in .w)
  float Direction[4];  //!< spot direction + range (in .w)
  float Parameters[4]; //!< spot cos(cutoff), spot exponent, type, enabled
};

//! Material properties for shader uniform.
struct Metal_ShaderMaterial
{
  float Ambient[4];     //!< ambient color
  float Diffuse[4];     //!< diffuse color
  float Specular[4];    //!< specular color
  float Emissive[4];    //!< emissive color
  float Shininess;      //!< specular exponent
  float Transparency;   //!< alpha value
  float Padding[2];     //!< alignment padding
};

//! Frame-level uniform data (projection, view matrices).
struct Metal_FrameUniforms
{
  float ProjectionMatrix[16];
  float ViewMatrix[16];
  float ProjectionMatrixInverse[16];
  float ViewMatrixInverse[16];
};

//! Object-level uniform data (model matrix, material).
struct Metal_ObjectUniforms
{
  float ModelMatrix[16];
  float ModelViewMatrix[16];
  float NormalMatrix[12];  //!< 3x4 for alignment (upper-left 3x3 of ModelView)
  float ObjectColor[4];
};

//! Lighting uniform data.
struct Metal_LightUniforms
{
  Metal_ShaderLightSource Lights[Metal_MaxLights];
  float AmbientColor[4];   //!< global ambient
  int   LightCount;        //!< number of active lights
  int   Padding[3];
};

//! Clipping plane uniform data.
struct Metal_ClipPlaneUniforms
{
  float Planes[Metal_MaxClipPlanes][4]; //!< plane equations (A, B, C, D)
  int   PlaneCount;                      //!< number of active clipping planes
  int   Padding[3];
};

//! Shader program configuration key.
struct Metal_ShaderProgramKey
{
  Graphic3d_TypeOfShadingModel ShadingModel;
  int                          ProgramBits;

  Metal_ShaderProgramKey(Graphic3d_TypeOfShadingModel theModel = Graphic3d_TypeOfShadingModel_Unlit,
                         int theBits = 0)
  : ShadingModel(theModel), ProgramBits(theBits) {}

  bool operator==(const Metal_ShaderProgramKey& theOther) const
  {
    return ShadingModel == theOther.ShadingModel && ProgramBits == theOther.ProgramBits;
  }

  size_t HashCode(size_t theUpperBound) const
  {
    return (static_cast<size_t>(ShadingModel) * 1000 + ProgramBits) % theUpperBound;
  }
};

//! Hash functor for Metal_ShaderProgramKey.
struct Metal_ShaderProgramKeyHasher
{
  size_t operator()(const Metal_ShaderProgramKey& theKey) const noexcept
  {
    return static_cast<size_t>(theKey.ShadingModel) * 1000 + theKey.ProgramBits;
  }

  bool operator()(const Metal_ShaderProgramKey& theKey1, const Metal_ShaderProgramKey& theKey2) const noexcept
  {
    return theKey1 == theKey2;
  }
};

//! Shader manager for Metal backend.
//! Manages shader program compilation and caching.
class Metal_ShaderManager : public Graphic3d_ShaderManager
{
  DEFINE_STANDARD_RTTIEXT(Metal_ShaderManager, Graphic3d_ShaderManager)

public:

  //! Create shader manager.
  Standard_EXPORT Metal_ShaderManager(Metal_Context* theCtx);

  //! Destructor.
  Standard_EXPORT ~Metal_ShaderManager() override;

  //! Release all resources.
  Standard_EXPORT void Release();

  //! Return Metal context.
  Metal_Context* Context() const { return myContext; }

public: //! @name Transform state

  //! Return current projection matrix.
  const NCollection_Mat4<float>& ProjectionMatrix() const { return myProjectionMatrix; }

  //! Set projection matrix.
  void SetProjectionMatrix(const NCollection_Mat4<float>& theMat)
  {
    myProjectionMatrix = theMat;
    myProjectionMatrixInverse = theMat.IsIdentity() ? theMat : theMat.IsIdentity() ? theMat : theMat;
    // Note: inverse calculation should be done properly
  }

  //! Return current view matrix.
  const NCollection_Mat4<float>& ViewMatrix() const { return myViewMatrix; }

  //! Set view matrix.
  void SetViewMatrix(const NCollection_Mat4<float>& theMat)
  {
    myViewMatrix = theMat;
  }

  //! Return current model matrix.
  const NCollection_Mat4<float>& ModelMatrix() const { return myModelMatrix; }

  //! Set model matrix.
  void SetModelMatrix(const NCollection_Mat4<float>& theMat)
  {
    myModelMatrix = theMat;
  }

public: //! @name Material state

  //! Set current material.
  Standard_EXPORT void SetMaterial(const Metal_ShaderMaterial& theMat);

  //! Return current material.
  const Metal_ShaderMaterial& Material() const { return myMaterial; }

  //! Set object color (overrides material diffuse).
  void SetObjectColor(float theR, float theG, float theB, float theA)
  {
    myObjectColor[0] = theR;
    myObjectColor[1] = theG;
    myObjectColor[2] = theB;
    myObjectColor[3] = theA;
  }

public: //! @name Lighting state

  //! Update light sources from Graphic3d light set.
  Standard_EXPORT void UpdateLightSources(const occ::handle<Graphic3d_LightSet>& theLights);

  //! Return number of active light sources.
  int LightCount() const { return myLightUniforms.LightCount; }

  //! Return lighting uniforms.
  const Metal_LightUniforms& LightUniforms() const { return myLightUniforms; }

public: //! @name Clipping planes

  //! Update clipping planes.
  Standard_EXPORT void UpdateClippingPlanes(const Graphic3d_SequenceOfHClipPlane& thePlanes);

  //! Return number of active clipping planes.
  int ClipPlaneCount() const { return myClipPlaneUniforms.PlaneCount; }

  //! Return clipping plane uniforms.
  const Metal_ClipPlaneUniforms& ClipPlaneUniforms() const { return myClipPlaneUniforms; }

public: //! @name Shader program access

  //! Get or create shader program for specified shading model and configuration.
  //! @param[in] theModel     shading model (Unlit, Phong, PBR, etc.)
  //! @param[in] theBits      additional shader flags
  //! @param[out] thePipeline returned pipeline state
  //! @param[out] theDepthStencil returned depth-stencil state
  //! @return true on success
  Standard_EXPORT bool GetProgram(Graphic3d_TypeOfShadingModel theModel,
                                   int theBits,
#ifdef __OBJC__
                                   id<MTLRenderPipelineState>& thePipeline,
                                   id<MTLDepthStencilState>& theDepthStencil
#else
                                   void*& thePipeline,
                                   void*& theDepthStencil
#endif
                                   );

  //! Choose appropriate shading model for faces.
  Graphic3d_TypeOfShadingModel ChooseFaceShadingModel(Graphic3d_TypeOfShadingModel theCustomModel,
                                                       bool theHasNodalNormals) const;

  //! Choose appropriate shading model for lines.
  Graphic3d_TypeOfShadingModel ChooseLineShadingModel(Graphic3d_TypeOfShadingModel theCustomModel,
                                                       bool theHasNodalNormals) const;

  //! Return default shading model.
  Graphic3d_TypeOfShadingModel ShadingModel() const { return myShadingModel; }

  //! Set default shading model.
  void SetShadingModel(Graphic3d_TypeOfShadingModel theModel) { myShadingModel = theModel; }

public: //! @name Uniform buffer preparation

  //! Prepare frame uniforms structure.
  Standard_EXPORT void PrepareFrameUniforms(Metal_FrameUniforms& theUniforms) const;

  //! Prepare object uniforms structure.
  Standard_EXPORT void PrepareObjectUniforms(Metal_ObjectUniforms& theUniforms) const;

protected:

  //! Create shader library with all shader functions.
  Standard_EXPORT bool createShaderLibrary();

  //! Create pipeline state for given configuration.
  Standard_EXPORT bool createPipeline(Graphic3d_TypeOfShadingModel theModel,
                                       int theBits,
#ifdef __OBJC__
                                       id<MTLRenderPipelineState>& thePipeline,
                                       id<MTLDepthStencilState>& theDepthStencil
#else
                                       void*& thePipeline,
                                       void*& theDepthStencil
#endif
                                       );

  //! Generate MSL shader source code.
  Standard_EXPORT TCollection_AsciiString generateShaderSource() const;

protected:

  Metal_Context* myContext; //!< Metal context

  // Transform matrices
  NCollection_Mat4<float> myProjectionMatrix;
  NCollection_Mat4<float> myProjectionMatrixInverse;
  NCollection_Mat4<float> myViewMatrix;
  NCollection_Mat4<float> myModelMatrix;

  // Material and color
  Metal_ShaderMaterial myMaterial;
  float myObjectColor[4];

  // Lighting
  Metal_LightUniforms myLightUniforms;

  // Clipping
  Metal_ClipPlaneUniforms myClipPlaneUniforms;

  // Shading model
  Graphic3d_TypeOfShadingModel myShadingModel;

#ifdef __OBJC__
  id<MTLLibrary> myShaderLibrary;  //!< compiled shader library

  //! Cache of pipeline states.
  NCollection_DataMap<Metal_ShaderProgramKey,
                      id<MTLRenderPipelineState>,
                      Metal_ShaderProgramKeyHasher> myPipelineCache;

  //! Cache of depth-stencil states.
  NCollection_DataMap<int, id<MTLDepthStencilState>> myDepthStencilCache;
#else
  void* myShaderLibrary;
#endif
};

#endif // Metal_ShaderManager_HeaderFile
