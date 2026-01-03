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

#ifndef Metal_ShadowMap_HeaderFile
#define Metal_ShadowMap_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_CLight.hxx>
#include <NCollection_Vec3.hxx>
#include <NCollection_Vec4.hxx>
#include <NCollection_Mat4.hxx>

typedef NCollection_Vec3<float> Graphic3d_Vec3;
typedef NCollection_Vec4<float> Graphic3d_Vec4;

class Metal_Context;

//! Shadow map resource for shadow mapping rendering.
//! Creates and manages a depth texture for storing shadow information.
class Metal_ShadowMap : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_ShadowMap, Metal_Resource)

public:

  //! Default shadow map resolution.
  static const int DefaultShadowMapSize = 1024;

  //! Create shadow map resource.
  //! @param theContext Metal context
  //! @param theSize shadow map resolution (width = height)
  Standard_EXPORT Metal_ShadowMap(Metal_Context* theContext,
                                   int theSize = DefaultShadowMapSize);

  //! Destructor.
  Standard_EXPORT ~Metal_ShadowMap();

  //! Release GPU resources.
  Standard_EXPORT virtual void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory usage in bytes.
  Standard_EXPORT virtual size_t EstimatedDataSize() const override;

  //! Return true if shadow map is valid.
  bool IsValid() const { return myIsValid; }

  //! Return shadow map resolution.
  int Size() const { return mySize; }

  //! Return shadow map bias (to reduce shadow acne).
  float Bias() const { return myBias; }

  //! Set shadow map bias.
  void SetBias(float theBias) { myBias = theBias; }

  //! Return light source associated with this shadow map.
  const occ::handle<Graphic3d_CLight>& LightSource() const { return myLightSource; }

  //! Set light source for this shadow map.
  void SetLightSource(const occ::handle<Graphic3d_CLight>& theLight) { myLightSource = theLight; }

  //! Return light-space view-projection matrix.
  const NCollection_Mat4<float>& LightSpaceMatrix() const { return myLightSpaceMatrix; }

  //! Compute light-space matrix from light source and scene bounds.
  //! @param theLight light source
  //! @param theSceneMin scene bounding box minimum
  //! @param theSceneMax scene bounding box maximum
  Standard_EXPORT void ComputeLightSpaceMatrix(
    const occ::handle<Graphic3d_CLight>& theLight,
    const Graphic3d_Vec3& theSceneMin,
    const Graphic3d_Vec3& theSceneMax);

#ifdef __OBJC__
  //! Return depth texture.
  id<MTLTexture> DepthTexture() const { return myDepthTexture; }

  //! Return render pass descriptor for shadow map rendering.
  MTLRenderPassDescriptor* RenderPassDescriptor() const { return myRenderPassDesc; }
#endif

private:

  //! Initialize shadow map resources.
  bool init();

private:

  Metal_Context*                myContext;          //!< Metal context
  int                           mySize;             //!< Shadow map resolution
  float                         myBias;             //!< Shadow bias
  bool                          myIsValid;          //!< Validity flag
  occ::handle<Graphic3d_CLight> myLightSource;      //!< Associated light source
  NCollection_Mat4<float>       myLightSpaceMatrix; //!< Light-space VP matrix

#ifdef __OBJC__
  id<MTLTexture>              myDepthTexture;     //!< Depth texture
  MTLRenderPassDescriptor*    myRenderPassDesc;   //!< Render pass descriptor
#else
  void*                       myDepthTexture;
  void*                       myRenderPassDesc;
#endif
};

#endif // Metal_ShadowMap_HeaderFile
