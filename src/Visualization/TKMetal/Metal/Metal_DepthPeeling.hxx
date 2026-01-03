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

#ifndef Metal_DepthPeeling_HeaderFile
#define Metal_DepthPeeling_HeaderFile

#include <Metal_FrameBuffer.hxx>
#include <Metal_Resource.hxx>

class Metal_Context;
class Metal_Texture;

//! Class provides FBOs for dual depth peeling OIT algorithm.
//! Manages ping-pong framebuffers for multi-pass depth peeling rendering.
//!
//! Dual depth peeling captures both front and back layers per pass:
//! - myDepthPeelFbosOit[2]: depth + front color + back color (ping-pong)
//! - myFrontBackColorFbosOit[2]: front color + back color wrapper
//! - myBlendBackFboOit: accumulated back color
class Metal_DepthPeeling : public Metal_NamedResource
{
  DEFINE_STANDARD_RTTIEXT(Metal_DepthPeeling, Metal_NamedResource)

public:

  //! Constructor.
  Standard_EXPORT Metal_DepthPeeling();

  //! Destructor.
  Standard_EXPORT ~Metal_DepthPeeling() override;

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Returns estimated GPU memory usage for holding data without considering
  //! overheads and allocation alignment rules.
  Standard_EXPORT size_t EstimatedDataSize() const override;

  //! Attach a depth-stencil texture to the depth peeling FBOs.
  //! This allows sharing the scene's depth buffer with the peeling passes.
  //! @param theCtx Metal context
  //! @param theDepthStencilTexture the depth-stencil texture to attach
  Standard_EXPORT void AttachDepthTexture(
    const occ::handle<Metal_Context>& theCtx,
    const occ::handle<Metal_Texture>& theDepthStencilTexture);

  //! Detach the depth-stencil texture from the depth peeling FBOs.
  //! @param theCtx Metal context
  Standard_EXPORT void DetachDepthTexture(const occ::handle<Metal_Context>& theCtx);

  //! Returns additional buffers for ping-pong depth peeling.
  //! Each FBO contains: depth texture + front color + back color.
  const occ::handle<Metal_FrameBuffer>* DepthPeelFbosOit() const { return myDepthPeelFbosOit; }

  //! Returns additional buffers for ping-pong color access.
  //! Wrapper FBOs providing access to front and back color textures.
  const occ::handle<Metal_FrameBuffer>* FrontBackColorFbosOit() const { return myFrontBackColorFbosOit; }

  //! Returns additional FBO for depth peeling back color accumulation.
  const occ::handle<Metal_FrameBuffer>& BlendBackFboOit() const { return myBlendBackFboOit; }

private:

  occ::handle<Metal_FrameBuffer> myDepthPeelFbosOit[2];      //!< depth + front color + back color (ping-pong)
  occ::handle<Metal_FrameBuffer> myFrontBackColorFbosOit[2]; //!< front color + back color wrapper
  occ::handle<Metal_FrameBuffer> myBlendBackFboOit;          //!< accumulated back color
};

#endif // Metal_DepthPeeling_HeaderFile
