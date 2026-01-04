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

#include <Metal_TessellationController.hxx>
#include <Metal_Context.hxx>
#include <Metal_ShaderManager.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_TessellationController, Standard_Transient)

// =======================================================================
// function : Metal_TessellationController
// purpose  : Constructor
// =======================================================================
Metal_TessellationController::Metal_TessellationController(Metal_Context* theCtx)
: myContext(theCtx),
  myTessLevel(8.0f),
  myAdaptiveFactor(0.0f),
  myMaxTessFactor(64),
  myTessFactorCapacity(0),
  myIsValid(false),
  myTessFactorPipeline(nil),
  myTessRenderPipeline(nil),
  myDepthStencilState(nil),
  myTessFactorBuffer(nil),
  myTessUniformBuffer(nil)
{
  myIsValid = initPipelines();
}

// =======================================================================
// function : ~Metal_TessellationController
// purpose  : Destructor
// =======================================================================
Metal_TessellationController::~Metal_TessellationController()
{
  Release();
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_TessellationController::Release()
{
  myTessFactorPipeline = nil;
  myTessRenderPipeline = nil;
  myDepthStencilState = nil;
  myTessFactorBuffer = nil;
  myTessUniformBuffer = nil;
  myTessFactorCapacity = 0;
  myIsValid = false;
}

// =======================================================================
// function : initPipelines
// purpose  : Initialize tessellation pipelines
// =======================================================================
bool Metal_TessellationController::initPipelines()
{
  if (myContext == nullptr || myContext->Device() == nil)
  {
    return false;
  }

  @autoreleasepool
  {
    id<MTLDevice> aDevice = myContext->Device();
    id<MTLLibrary> aLibrary = myContext->ShaderManager()->ShaderLibrary();

    if (aLibrary == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: Shader library not available";
      return false;
    }

    NSError* anError = nil;

    // Create compute pipeline for tessellation factor calculation
    id<MTLFunction> aComputeFunc = [aLibrary newFunctionWithName:@"compute_tess_factors"];
    if (aComputeFunc == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: compute_tess_factors not found";
      return false;
    }

    myTessFactorPipeline = [aDevice newComputePipelineStateWithFunction:aComputeFunc error:&anError];
    if (myTessFactorPipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: Compute pipeline failed: "
                                         << [[anError localizedDescription] UTF8String];
      return false;
    }

    // Create vertex descriptor for tessellation control points
    // TessControlPoint: position(float3) + normal(float3) + texCoord(float2) = 32 bytes
    MTLVertexDescriptor* aVertexDesc = [[MTLVertexDescriptor alloc] init];
    aVertexDesc.attributes[0].format = MTLVertexFormatFloat3;  // position
    aVertexDesc.attributes[0].offset = 0;
    aVertexDesc.attributes[0].bufferIndex = 0;
    aVertexDesc.attributes[1].format = MTLVertexFormatFloat3;  // normal
    aVertexDesc.attributes[1].offset = 12;
    aVertexDesc.attributes[1].bufferIndex = 0;
    aVertexDesc.attributes[2].format = MTLVertexFormatFloat2;  // texCoord
    aVertexDesc.attributes[2].offset = 24;
    aVertexDesc.attributes[2].bufferIndex = 0;
    aVertexDesc.layouts[0].stride = 32;
    aVertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;

    // Get post-tessellation vertex function
    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"vertex_post_tess"];
    if (aVertexFunc == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: vertex_post_tess not found";
      return false;
    }

    // Get tessellation fragment function
    id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"fragment_tess_phong"];
    if (aFragmentFunc == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: fragment_tess_phong not found";
      return false;
    }

    // Create tessellation render pipeline
    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.vertexDescriptor = aVertexDesc;
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.fragmentFunction = aFragmentFunc;
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    // Tessellation configuration
    aPipelineDesc.maxTessellationFactor = myMaxTessFactor;
    aPipelineDesc.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionPerPatch;
    aPipelineDesc.tessellationOutputWindingOrder = MTLWindingCounterClockwise;
    aPipelineDesc.tessellationPartitionMode = MTLTessellationPartitionModeFractionalEven;

    // Enable alpha blending
    aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
    aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    myTessRenderPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc error:&anError];
    if (myTessRenderPipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_TessellationController: Render pipeline failed: "
                                         << [[anError localizedDescription] UTF8String];
      return false;
    }

    // Create depth stencil state
    MTLDepthStencilDescriptor* aDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
    aDepthDesc.depthCompareFunction = MTLCompareFunctionLess;
    aDepthDesc.depthWriteEnabled = YES;
    myDepthStencilState = [aDevice newDepthStencilStateWithDescriptor:aDepthDesc];

    // Create tessellation uniform buffer
    myTessUniformBuffer = [aDevice newBufferWithLength:sizeof(Metal_TessParams)
                                               options:MTLResourceStorageModeShared];

    myContext->Messenger()->SendInfo() << "Metal_TessellationController: Initialized successfully";
    return true;
  }
}

// =======================================================================
// function : ensureTessFactorBuffer
// purpose  : Ensure buffer capacity
// =======================================================================
bool Metal_TessellationController::ensureTessFactorBuffer(int thePatchCount)
{
  if (thePatchCount <= myTessFactorCapacity)
  {
    return true;
  }

  // Allocate with headroom
  int aNewCapacity = thePatchCount + (thePatchCount / 4);

  // MTLQuadTessellationFactorsHalf: 4 edge factors (half) + 2 inside factors (half) = 12 bytes
  size_t aBufferSize = aNewCapacity * sizeof(MTLQuadTessellationFactorsHalf);

  myTessFactorBuffer = [myContext->Device() newBufferWithLength:aBufferSize
                                                        options:MTLResourceStorageModeShared];
  if (myTessFactorBuffer == nil)
  {
    myContext->Messenger()->SendFail() << "Metal_TessellationController: Failed to allocate tess factor buffer";
    return false;
  }

  myTessFactorCapacity = aNewCapacity;
  return true;
}

// =======================================================================
// function : ComputeTessFactors
// purpose  : Compute tessellation factors
// =======================================================================
bool Metal_TessellationController::ComputeTessFactors(
  id<MTLCommandBuffer> theCmdBuf,
  id<MTLBuffer> theControlPoints,
  int thePatchCount,
  const Metal_TessParams& theParams)
{
  if (!myIsValid || theCmdBuf == nil || theControlPoints == nil || thePatchCount <= 0)
  {
    return false;
  }

  // Ensure buffer capacity
  if (!ensureTessFactorBuffer(thePatchCount))
  {
    return false;
  }

  // Update uniform buffer
  memcpy([myTessUniformBuffer contents], &theParams, sizeof(Metal_TessParams));

  @autoreleasepool
  {
    id<MTLComputeCommandEncoder> aComputeEncoder = [theCmdBuf computeCommandEncoder];
    [aComputeEncoder setComputePipelineState:myTessFactorPipeline];

    // Buffer bindings match compute_tess_factors signature
    [aComputeEncoder setBuffer:theControlPoints offset:0 atIndex:0];     // control points
    [aComputeEncoder setBuffer:myTessFactorBuffer offset:0 atIndex:1];   // output factors
    [aComputeEncoder setBuffer:myTessUniformBuffer offset:0 atIndex:2];  // uniforms

    // Dispatch one thread per patch
    MTLSize aThreadgroupSize = MTLSizeMake(64, 1, 1);
    MTLSize aThreadgroups = MTLSizeMake((thePatchCount + 63) / 64, 1, 1);
    [aComputeEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];

    [aComputeEncoder endEncoding];
  }

  return true;
}

// =======================================================================
// function : BeginTessellationPass
// purpose  : Set up tessellation pipeline for rendering
// =======================================================================
void Metal_TessellationController::BeginTessellationPass(
  id<MTLRenderCommandEncoder> theEncoder,
  id<MTLBuffer> theControlPoints,
  const Metal_TessParams& theParams)
{
  if (!myIsValid || theEncoder == nil)
  {
    return;
  }

  // Update uniform buffer
  memcpy([myTessUniformBuffer contents], &theParams, sizeof(Metal_TessParams));

  [theEncoder setRenderPipelineState:myTessRenderPipeline];
  [theEncoder setDepthStencilState:myDepthStencilState];

  // Set tessellation factor buffer
  [theEncoder setTessellationFactorBuffer:myTessFactorBuffer offset:0 instanceStride:0];

  // Set control points (buffer 0)
  [theEncoder setVertexBuffer:theControlPoints offset:0 atIndex:0];

  // Set uniforms (buffer 1, matching vertex_post_tess signature)
  [theEncoder setVertexBuffer:myTessUniformBuffer offset:0 atIndex:1];
}

// =======================================================================
// function : DrawPatches
// purpose  : Draw tessellated patches
// =======================================================================
void Metal_TessellationController::DrawPatches(
  id<MTLRenderCommandEncoder> theEncoder,
  int thePatchCount)
{
  if (!myIsValid || theEncoder == nil || thePatchCount <= 0)
  {
    return;
  }

  // Draw quad patches (4 control points per patch)
  [theEncoder drawPatches:4
              patchStart:0
              patchCount:thePatchCount
        patchIndexBuffer:nil
  patchIndexBufferOffset:0
           instanceCount:1
            baseInstance:0];
}
