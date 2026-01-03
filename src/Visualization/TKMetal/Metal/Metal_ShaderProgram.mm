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

#include <Metal_ShaderProgram.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_ShaderProgram, Metal_Resource)

// =======================================================================
// function : Metal_ShaderProgram
// purpose  : Constructor
// =======================================================================
Metal_ShaderProgram::Metal_ShaderProgram(const occ::handle<Graphic3d_ShaderProgram>& theProxy,
                                         const TCollection_AsciiString& theId)
: myId(theId),
  myProxy(theProxy),
  myRenderPipeline(nil),
  myComputePipeline(nil),
  myDepthStencilState(nil),
  myNbLightsMax(8),
  myNbShadowMaps(0),
  myNbClipPlanesMax(8),
  myNbFragOutputs(1),
  myTextureSetBits(Graphic3d_TextureSetBits_NONE),
  myOitOutput(Graphic3d_RTM_BLEND_UNORDERED),
  myHasAlphaTest(false),
  myHasTessShader(false)
{
  for (int i = 0; i < Metal_UniformStateType_NB; ++i)
  {
    myCurrentState[i] = 0;
  }
}

// =======================================================================
// function : ~Metal_ShaderProgram
// purpose  : Destructor
// =======================================================================
Metal_ShaderProgram::~Metal_ShaderProgram()
{
  Release(nullptr);
}

// =======================================================================
// function : AttachVertexShader
// purpose  : Attach vertex shader
// =======================================================================
bool Metal_ShaderProgram::AttachVertexShader(const occ::handle<Metal_ShaderObject>& theShader)
{
  if (theShader.IsNull() || !theShader->IsValid())
  {
    return false;
  }

  if (theShader->Type() != Metal_ShaderType_Vertex)
  {
    return false;
  }

  myVertexShader = theShader;
  return true;
}

// =======================================================================
// function : AttachFragmentShader
// purpose  : Attach fragment shader
// =======================================================================
bool Metal_ShaderProgram::AttachFragmentShader(const occ::handle<Metal_ShaderObject>& theShader)
{
  if (theShader.IsNull() || !theShader->IsValid())
  {
    return false;
  }

  if (theShader->Type() != Metal_ShaderType_Fragment)
  {
    return false;
  }

  myFragmentShader = theShader;
  return true;
}

// =======================================================================
// function : AttachComputeShader
// purpose  : Attach compute shader
// =======================================================================
bool Metal_ShaderProgram::AttachComputeShader(const occ::handle<Metal_ShaderObject>& theShader)
{
  if (theShader.IsNull() || !theShader->IsValid())
  {
    return false;
  }

  if (theShader->Type() != Metal_ShaderType_Compute)
  {
    return false;
  }

  myComputeShader = theShader;
  return true;
}

// =======================================================================
// function : CreateRenderPipeline
// purpose  : Create render pipeline state
// =======================================================================
bool Metal_ShaderProgram::CreateRenderPipeline(Metal_Context* theCtx,
                                               int theColorFormat,
                                               int theDepthFormat,
                                               int theSampleCount)
{
  if (theCtx == nullptr || !theCtx->IsValid())
  {
    myLinkLog = "Invalid Metal context";
    return false;
  }

  if (myVertexShader.IsNull() || !myVertexShader->IsValid())
  {
    myLinkLog = "No valid vertex shader attached";
    return false;
  }

  if (myFragmentShader.IsNull() || !myFragmentShader->IsValid())
  {
    myLinkLog = "No valid fragment shader attached";
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    myLinkLog = "No Metal device";
    return false;
  }

  // Create pipeline descriptor
  MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
  aPipelineDesc.vertexFunction = myVertexShader->Function();
  aPipelineDesc.fragmentFunction = myFragmentShader->Function();
  aPipelineDesc.colorAttachments[0].pixelFormat = (MTLPixelFormat)theColorFormat;

  if (theDepthFormat != 0)
  {
    aPipelineDesc.depthAttachmentPixelFormat = (MTLPixelFormat)theDepthFormat;
  }

  if (theSampleCount > 1)
  {
    aPipelineDesc.rasterSampleCount = theSampleCount;
  }

  // Enable blending by default
  aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
  aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

  // Create pipeline state
  NSError* anError = nil;
  myRenderPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc error:&anError];

  if (anError != nil)
  {
    myLinkLog = [[anError localizedDescription] UTF8String];
    if (myRenderPipeline == nil)
    {
      return false;
    }
  }

  return true;
}

// =======================================================================
// function : CreateComputePipeline
// purpose  : Create compute pipeline state
// =======================================================================
bool Metal_ShaderProgram::CreateComputePipeline(Metal_Context* theCtx)
{
  if (theCtx == nullptr || !theCtx->IsValid())
  {
    myLinkLog = "Invalid Metal context";
    return false;
  }

  if (myComputeShader.IsNull() || !myComputeShader->IsValid())
  {
    myLinkLog = "No valid compute shader attached";
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    myLinkLog = "No Metal device";
    return false;
  }

  NSError* anError = nil;
  myComputePipeline = [aDevice newComputePipelineStateWithFunction:myComputeShader->Function()
                                                             error:&anError];

  if (anError != nil)
  {
    myLinkLog = [[anError localizedDescription] UTF8String];
    if (myComputePipeline == nil)
    {
      return false;
    }
  }

  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_ShaderProgram::Release(Metal_Context* /*theCtx*/)
{
  myRenderPipeline = nil;
  myComputePipeline = nil;
  myDepthStencilState = nil;

  myVertexShader.Nullify();
  myFragmentShader.Nullify();
  myComputeShader.Nullify();

  myLinkLog.Clear();
}
