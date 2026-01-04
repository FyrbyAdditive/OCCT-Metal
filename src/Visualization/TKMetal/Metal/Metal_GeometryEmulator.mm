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

#include <Metal_GeometryEmulator.hxx>
#include <Metal_Context.hxx>
#include <Metal_ShaderManager.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_GeometryEmulator, Standard_Transient)

// =======================================================================
// function : Metal_GeometryEmulator
// purpose  : Constructor
// =======================================================================
Metal_GeometryEmulator::Metal_GeometryEmulator(Metal_Context* theCtx)
: myContext(theCtx),
  myProcessedVertexCount(0),
  myProcessedBufferCapacity(0),
  myIsValid(false),
  myComputePipeline(nil),
  myOverlayPipeline(nil),
  myOnlyPipeline(nil),
  myHiddenPipeline(nil),
  myDepthStencilState(nil),
  myProcessedVertexBuffer(nil),
  myViewportBuffer(nil)
{
  myIsValid = initPipelines();
}

// =======================================================================
// function : ~Metal_GeometryEmulator
// purpose  : Destructor
// =======================================================================
Metal_GeometryEmulator::~Metal_GeometryEmulator()
{
  Release();
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_GeometryEmulator::Release()
{
  myComputePipeline = nil;
  myOverlayPipeline = nil;
  myOnlyPipeline = nil;
  myHiddenPipeline = nil;
  myDepthStencilState = nil;
  myProcessedVertexBuffer = nil;
  myViewportBuffer = nil;
  myProcessedVertexCount = 0;
  myProcessedBufferCapacity = 0;
  myIsValid = false;
}

// =======================================================================
// function : initPipelines
// purpose  : Initialize compute and render pipelines
// =======================================================================
bool Metal_GeometryEmulator::initPipelines()
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
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Shader library not available";
      return false;
    }

    NSError* anError = nil;

    // Create compute pipeline for edge distance calculation
    id<MTLFunction> aComputeFunc = [aLibrary newFunctionWithName:@"compute_edge_distances"];
    if (aComputeFunc == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: compute_edge_distances function not found";
      return false;
    }

    myComputePipeline = [aDevice newComputePipelineStateWithFunction:aComputeFunc error:&anError];
    if (myComputePipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Compute pipeline creation failed: "
                                         << [[anError localizedDescription] UTF8String];
      return false;
    }

    // Create vertex descriptor for processed vertices (from compute output)
    // EdgeVertexOut: position(float4) + normal(float3) + edgeDistance(float3) + viewPosition(float3) + color(float4)
    // Total: 4+3+3+3+4 = 17 floats = 68 bytes
    MTLVertexDescriptor* aVertexDesc = [[MTLVertexDescriptor alloc] init];
    aVertexDesc.attributes[0].format = MTLVertexFormatFloat4;  // position
    aVertexDesc.attributes[0].offset = 0;
    aVertexDesc.attributes[0].bufferIndex = 0;
    aVertexDesc.attributes[1].format = MTLVertexFormatFloat3;  // normal
    aVertexDesc.attributes[1].offset = 16;
    aVertexDesc.attributes[1].bufferIndex = 0;
    aVertexDesc.attributes[2].format = MTLVertexFormatFloat3;  // edgeDistance
    aVertexDesc.attributes[2].offset = 28;
    aVertexDesc.attributes[2].bufferIndex = 0;
    aVertexDesc.attributes[3].format = MTLVertexFormatFloat3;  // viewPosition
    aVertexDesc.attributes[3].offset = 40;
    aVertexDesc.attributes[3].bufferIndex = 0;
    aVertexDesc.attributes[4].format = MTLVertexFormatFloat4;  // color
    aVertexDesc.attributes[4].offset = 52;
    aVertexDesc.attributes[4].bufferIndex = 0;
    aVertexDesc.layouts[0].stride = 68;
    aVertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    // Get vertex function
    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"vertex_wireframe"];
    if (aVertexFunc == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: vertex_wireframe function not found";
      return false;
    }

    // Base pipeline descriptor
    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.vertexDescriptor = aVertexDesc;
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    // Enable alpha blending for all wireframe modes
    aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
    aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    // Overlay pipeline
    id<MTLFunction> aOverlayFrag = [aLibrary newFunctionWithName:@"fragment_wireframe_overlay"];
    if (aOverlayFrag == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: fragment_wireframe_overlay not found";
      return false;
    }
    aPipelineDesc.fragmentFunction = aOverlayFrag;
    myOverlayPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc error:&anError];
    if (myOverlayPipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Overlay pipeline failed: "
                                         << [[anError localizedDescription] UTF8String];
      return false;
    }

    // Wireframe-only pipeline
    id<MTLFunction> aOnlyFrag = [aLibrary newFunctionWithName:@"fragment_wireframe_only"];
    if (aOnlyFrag == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: fragment_wireframe_only not found";
      return false;
    }
    aPipelineDesc.fragmentFunction = aOnlyFrag;
    myOnlyPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc error:&anError];
    if (myOnlyPipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Wireframe-only pipeline failed";
      return false;
    }

    // Hidden-line pipeline
    id<MTLFunction> aHiddenFrag = [aLibrary newFunctionWithName:@"fragment_wireframe_hidden"];
    if (aHiddenFrag == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: fragment_wireframe_hidden not found";
      return false;
    }
    aPipelineDesc.fragmentFunction = aHiddenFrag;
    myHiddenPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc error:&anError];
    if (myHiddenPipeline == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Hidden-line pipeline failed";
      return false;
    }

    // Create depth stencil state
    MTLDepthStencilDescriptor* aDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
    aDepthDesc.depthCompareFunction = MTLCompareFunctionLess;
    aDepthDesc.depthWriteEnabled = YES;
    myDepthStencilState = [aDevice newDepthStencilStateWithDescriptor:aDepthDesc];

    // Create viewport uniform buffer
    myViewportBuffer = [aDevice newBufferWithLength:sizeof(float) * 2
                                            options:MTLResourceStorageModeShared];

    myContext->Messenger()->SendInfo() << "Metal_GeometryEmulator: Initialized successfully";
    return true;
  }
}

// =======================================================================
// function : ensureProcessedBuffer
// purpose  : Ensure buffer capacity
// =======================================================================
bool Metal_GeometryEmulator::ensureProcessedBuffer(int theVertexCount)
{
  if (theVertexCount <= myProcessedBufferCapacity)
  {
    return true;
  }

  // Allocate with some headroom
  int aNewCapacity = theVertexCount + (theVertexCount / 4);

  // EdgeVertexOut struct size: 68 bytes
  size_t aBufferSize = aNewCapacity * 68;

  myProcessedVertexBuffer = [myContext->Device() newBufferWithLength:aBufferSize
                                                             options:MTLResourceStorageModeShared];
  if (myProcessedVertexBuffer == nil)
  {
    myContext->Messenger()->SendFail() << "Metal_GeometryEmulator: Failed to allocate processed vertex buffer";
    return false;
  }

  myProcessedBufferCapacity = aNewCapacity;
  return true;
}

// =======================================================================
// function : Process
// purpose  : Compute edge distances for mesh
// =======================================================================
bool Metal_GeometryEmulator::Process(
  id<MTLCommandBuffer> theCmdBuf,
  id<MTLBuffer> theVertices,
  id<MTLBuffer> theIndices,
  int theTriangleCount,
  id<MTLBuffer> theUniforms,
  float theViewportWidth,
  float theViewportHeight)
{
  if (!myIsValid || theCmdBuf == nil || theVertices == nil || theIndices == nil)
  {
    return false;
  }

  // Update processed vertex count
  myProcessedVertexCount = theTriangleCount * 3;

  // Ensure buffer is large enough
  if (!ensureProcessedBuffer(myProcessedVertexCount))
  {
    return false;
  }

  // Update viewport buffer
  float* aViewport = (float*)[myViewportBuffer contents];
  aViewport[0] = theViewportWidth;
  aViewport[1] = theViewportHeight;

  // Also update wireframe params
  myWireParams.Viewport[0] = theViewportWidth;
  myWireParams.Viewport[1] = theViewportHeight;

  @autoreleasepool
  {
    // Dispatch compute shader
    id<MTLComputeCommandEncoder> aComputeEncoder = [theCmdBuf computeCommandEncoder];
    [aComputeEncoder setComputePipelineState:myComputePipeline];

    // Buffer bindings match compute_edge_distances signature
    [aComputeEncoder setBuffer:theVertices offset:0 atIndex:0];       // vertices
    [aComputeEncoder setBuffer:theIndices offset:0 atIndex:1];        // indices
    [aComputeEncoder setBuffer:myProcessedVertexBuffer offset:0 atIndex:2]; // output
    [aComputeEncoder setBuffer:theUniforms offset:0 atIndex:3];       // uniforms
    [aComputeEncoder setBuffer:myViewportBuffer offset:0 atIndex:4];  // viewport

    // Dispatch one thread per triangle
    MTLSize aThreadgroupSize = MTLSizeMake(64, 1, 1);
    MTLSize aThreadgroups = MTLSizeMake((theTriangleCount + 63) / 64, 1, 1);
    [aComputeEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];

    [aComputeEncoder endEncoding];
  }

  return true;
}

// =======================================================================
// function : WireframePipeline
// purpose  : Get pipeline for specified mode
// =======================================================================
id<MTLRenderPipelineState> Metal_GeometryEmulator::WireframePipeline(Metal_WireframeMode theMode) const
{
  switch (theMode)
  {
    case Metal_WireframeMode_Overlay: return myOverlayPipeline;
    case Metal_WireframeMode_Only:    return myOnlyPipeline;
    case Metal_WireframeMode_Hidden:  return myHiddenPipeline;
    default:                          return myOverlayPipeline;
  }
}
