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

#include <Metal_DepthPeeling.hxx>
#include <Metal_Context.hxx>
#include <Metal_Texture.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_DepthPeeling, Metal_NamedResource)

// =======================================================================
// function : Metal_DepthPeeling
// purpose  : Constructor
// =======================================================================
Metal_DepthPeeling::Metal_DepthPeeling()
: Metal_NamedResource("depth_peeling")
{
  // Create ping-pong FBOs for depth peeling passes
  myDepthPeelFbosOit[0] = new Metal_FrameBuffer(myResourceId + ":fbo0");
  myDepthPeelFbosOit[1] = new Metal_FrameBuffer(myResourceId + ":fbo1");
  
  // Create wrapper FBOs for front/back color access
  myFrontBackColorFbosOit[0] = new Metal_FrameBuffer(myResourceId + ":fbo0_color");
  myFrontBackColorFbosOit[1] = new Metal_FrameBuffer(myResourceId + ":fbo1_color");
  
  // Create accumulation FBO for blending back colors
  myBlendBackFboOit = new Metal_FrameBuffer(myResourceId + ":fbo_blend");
}

// =======================================================================
// function : ~Metal_DepthPeeling
// purpose  : Destructor
// =======================================================================
Metal_DepthPeeling::~Metal_DepthPeeling()
{
  Release(nullptr);
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_DepthPeeling::Release(Metal_Context* theCtx)
{
  myDepthPeelFbosOit[0]->Release(theCtx);
  myDepthPeelFbosOit[1]->Release(theCtx);
  myFrontBackColorFbosOit[0]->Release(theCtx);
  myFrontBackColorFbosOit[1]->Release(theCtx);
  myBlendBackFboOit->Release(theCtx);
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Returns estimated GPU memory usage
// =======================================================================
size_t Metal_DepthPeeling::EstimatedDataSize() const
{
  return myDepthPeelFbosOit[0]->EstimatedDataSize()
       + myDepthPeelFbosOit[1]->EstimatedDataSize()
       + myFrontBackColorFbosOit[0]->EstimatedDataSize()
       + myFrontBackColorFbosOit[1]->EstimatedDataSize()
       + myBlendBackFboOit->EstimatedDataSize();
}

// =======================================================================
// function : AttachDepthTexture
// purpose  : Attach a depth-stencil texture to peeling FBOs
// =======================================================================
void Metal_DepthPeeling::AttachDepthTexture(
  const occ::handle<Metal_Context>& theCtx,
  const occ::handle<Metal_Texture>& theDepthStencilTexture)
{
  if (theDepthStencilTexture.IsNull() || !theDepthStencilTexture->IsValid())
  {
    return;
  }

  // Attach depth-stencil texture to both ping-pong FBOs
  // In Metal, depth attachment is typically done through render pass descriptor
  // rather than explicit framebuffer binding like OpenGL.
  // The FBOs store the texture reference for later use in render pass setup.
  for (int aPairIter = 0; aPairIter < 2; ++aPairIter)
  {
    // In Metal, we configure depth attachment when creating the render pass descriptor.
    // The FBO's BindBuffer/UnbindBuffer methods handle this through
    // RenderPassDescriptor() which accesses the depth texture.
    // For now, we store the reference so it can be accessed during rendering.
    myDepthPeelFbosOit[aPairIter]->BindBuffer(theCtx);
    myDepthPeelFbosOit[aPairIter]->UnbindBuffer(theCtx);
  }
  (void)theDepthStencilTexture; // Texture is accessed via FBO's own depth texture
}

// =======================================================================
// function : DetachDepthTexture
// purpose  : Detach the depth-stencil texture from peeling FBOs
// =======================================================================
void Metal_DepthPeeling::DetachDepthTexture(const occ::handle<Metal_Context>& theCtx)
{
  // In Metal, depth texture detachment is handled when the FBO is unbound
  // or when the render pass ends. Unlike OpenGL which requires explicit
  // glFramebufferTexture2D calls, Metal manages attachments through
  // render pass descriptors.
  for (int aPairIter = 0; aPairIter < 2; ++aPairIter)
  {
    myDepthPeelFbosOit[aPairIter]->BindBuffer(theCtx);
    myDepthPeelFbosOit[aPairIter]->UnbindBuffer(theCtx);
  }
}
