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

#ifndef Metal_CappingAlgo_HeaderFile
#define Metal_CappingAlgo_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_ClipPlane.hxx>
#include <NCollection_DataMap.hxx>
#include <Standard_Handle.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
@protocol MTLBuffer;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
#endif

class Metal_Context;

//! Capping plane resource - manages geometry and state for rendering a capping surface.
//! The capping plane is an infinite plane that fills the cross-section
//! when geometry is clipped.
class Metal_CappingPlaneResource : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_CappingPlaneResource, Metal_Resource)

public:

  //! Constructor.
  Standard_EXPORT Metal_CappingPlaneResource(const Handle(Graphic3d_ClipPlane)& thePlane);

  //! Destructor.
  Standard_EXPORT ~Metal_CappingPlaneResource() override;

  //! Return associated clip plane.
  const Handle(Graphic3d_ClipPlane)& Plane() const { return myPlane; }

  //! Update transformation based on current plane equation.
  //! @param theCtx Metal context
  Standard_EXPORT void Update(Metal_Context* theCtx);

  //! Return true if the resource is valid.
  bool IsValid() const { return myVertexBuffer != nullptr; }

  //! Release resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory size.
  size_t EstimatedDataSize() const override { return myEstimatedSize; }

#ifdef __OBJC__
  //! Return vertex buffer for plane geometry.
  id<MTLBuffer> VertexBuffer() const { return myVertexBuffer; }

  //! Return number of vertices.
  int VertexCount() const { return myVertexCount; }

  //! Return orientation matrix (4x4).
  const float* OrientationMatrix() const { return myOrientation; }
#endif

protected:

  //! Build plane geometry.
  Standard_EXPORT void buildGeometry(Metal_Context* theCtx);

  //! Update orientation matrix from plane equation.
  Standard_EXPORT void updateOrientation();

protected:

  Handle(Graphic3d_ClipPlane) myPlane;      //!< associated clip plane

#ifdef __OBJC__
  id<MTLBuffer> myVertexBuffer;             //!< vertex buffer
#else
  void*         myVertexBuffer;
#endif

  float         myOrientation[16];          //!< orientation matrix
  int           myVertexCount;              //!< number of vertices
  size_t        myEstimatedSize;            //!< estimated GPU memory
};

//! Algorithm for rendering capping planes using stencil buffer.
//! Uses a two-pass approach:
//! 1. Generate stencil mask by inverting stencil bits for each face
//! 2. Render infinite capping plane where stencil indicates "inside"
class Metal_CappingAlgo : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_CappingAlgo, Standard_Transient)

public:

  //! Constructor.
  Standard_EXPORT Metal_CappingAlgo();

  //! Destructor.
  Standard_EXPORT ~Metal_CappingAlgo();

  //! Initialize capping algorithm resources.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Return true if capping is initialized and ready.
  bool IsReady() const { return myIsInitialized; }

  //! Release resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Get or create capping plane resource for given clip plane.
  //! @param theCtx   Metal context
  //! @param thePlane clip plane
  //! @return capping plane resource
  Standard_EXPORT Handle(Metal_CappingPlaneResource) GetPlaneResource(
    Metal_Context* theCtx,
    const Handle(Graphic3d_ClipPlane)& thePlane);

#ifdef __OBJC__
  //! Return stencil-generate pipeline (for mask generation pass).
  id<MTLRenderPipelineState> StencilGenPipeline() const { return myStencilGenPipeline; }

  //! Return stencil-render pipeline (for capping surface render).
  id<MTLRenderPipelineState> StencilRenderPipeline() const { return myStencilRenderPipeline; }

  //! Return depth-stencil state for stencil generation (invert on all).
  id<MTLDepthStencilState> StencilGenDepthState() const { return myStencilGenDepthState; }

  //! Return depth-stencil state for capping render (test equal to 1).
  id<MTLDepthStencilState> StencilRenderDepthState() const { return myStencilRenderDepthState; }
#endif

protected:

  //! Create pipeline states.
  Standard_EXPORT bool createPipelines(Metal_Context* theCtx);

  //! Create depth-stencil states.
  Standard_EXPORT bool createDepthStencilStates(Metal_Context* theCtx);

protected:

#ifdef __OBJC__
  id<MTLRenderPipelineState> myStencilGenPipeline;     //!< pipeline for stencil mask generation
  id<MTLRenderPipelineState> myStencilRenderPipeline;  //!< pipeline for capping plane render
  id<MTLDepthStencilState>   myStencilGenDepthState;   //!< depth-stencil for mask generation
  id<MTLDepthStencilState>   myStencilRenderDepthState; //!< depth-stencil for capping render
#else
  void*                      myStencilGenPipeline;
  void*                      myStencilRenderPipeline;
  void*                      myStencilGenDepthState;
  void*                      myStencilRenderDepthState;
#endif

  NCollection_DataMap<Standard_Address, Handle(Metal_CappingPlaneResource)> myPlaneResources;
  bool myIsInitialized;
};

#endif // Metal_CappingAlgo_HeaderFile
