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

#include <Metal_ComputeEncoder.hxx>
#include <Metal_Context.hxx>
#include <Metal_Buffer.hxx>
#include <Metal_Texture.hxx>

// =======================================================================
// function : Metal_ComputeEncoder
// purpose  : Constructor
// =======================================================================
Metal_ComputeEncoder::Metal_ComputeEncoder()
: myEncoder(nil),
  myIsActive(false)
{
}

// =======================================================================
// function : ~Metal_ComputeEncoder
// purpose  : Destructor
// =======================================================================
Metal_ComputeEncoder::~Metal_ComputeEncoder()
{
  End();
}

// =======================================================================
// function : Begin
// purpose  : Begin compute encoding
// =======================================================================
bool Metal_ComputeEncoder::Begin(id<MTLCommandBuffer> theCommandBuffer)
{
  End(); // End any previous encoding

  if (theCommandBuffer == nil)
  {
    return false;
  }

  myEncoder = [theCommandBuffer computeCommandEncoder];
  if (myEncoder == nil)
  {
    return false;
  }

  myIsActive = true;
  return true;
}

// =======================================================================
// function : End
// purpose  : End compute encoding
// =======================================================================
void Metal_ComputeEncoder::End()
{
  if (myEncoder != nil)
  {
    [myEncoder endEncoding];
    myEncoder = nil;
  }

  myCurrentPipeline.Nullify();
  myIsActive = false;
}

// =======================================================================
// function : SetPipeline
// purpose  : Set compute pipeline
// =======================================================================
void Metal_ComputeEncoder::SetPipeline(const occ::handle<Metal_ComputePipeline>& thePipeline)
{
  if (!myIsActive || myEncoder == nil || thePipeline.IsNull() || !thePipeline->IsValid())
  {
    return;
  }

  myCurrentPipeline = thePipeline;
  [myEncoder setComputePipelineState:thePipeline->PipelineState()];
}

// =======================================================================
// function : SetBuffer (raw)
// purpose  : Set buffer at index
// =======================================================================
void Metal_ComputeEncoder::SetBuffer(id<MTLBuffer> theBuffer, int theOffset, int theIndex)
{
  if (!myIsActive || myEncoder == nil)
  {
    return;
  }

  [myEncoder setBuffer:theBuffer
                offset:static_cast<NSUInteger>(theOffset)
               atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : SetBuffer (wrapper)
// purpose  : Set buffer from Metal_Buffer
// =======================================================================
void Metal_ComputeEncoder::SetBuffer(const occ::handle<Metal_Buffer>& theBuffer, int theIndex)
{
  if (!myIsActive || myEncoder == nil || theBuffer.IsNull() || !theBuffer->IsValid())
  {
    return;
  }

  [myEncoder setBuffer:theBuffer->Buffer()
                offset:0
               atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : SetBytes
// purpose  : Set bytes directly
// =======================================================================
void Metal_ComputeEncoder::SetBytes(const void* theBytes, int theLength, int theIndex)
{
  if (!myIsActive || myEncoder == nil || theBytes == nullptr || theLength <= 0)
  {
    return;
  }

  [myEncoder setBytes:theBytes
               length:static_cast<NSUInteger>(theLength)
              atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : SetTexture (raw)
// purpose  : Set texture at index
// =======================================================================
void Metal_ComputeEncoder::SetTexture(id<MTLTexture> theTexture, int theIndex)
{
  if (!myIsActive || myEncoder == nil)
  {
    return;
  }

  [myEncoder setTexture:theTexture
                atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : SetTexture (wrapper)
// purpose  : Set texture from Metal_Texture
// =======================================================================
void Metal_ComputeEncoder::SetTexture(const occ::handle<Metal_Texture>& theTexture, int theIndex)
{
  if (!myIsActive || myEncoder == nil || theTexture.IsNull())
  {
    return;
  }

  [myEncoder setTexture:theTexture->Texture()
                atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : SetSamplerState
// purpose  : Set sampler state at index
// =======================================================================
void Metal_ComputeEncoder::SetSamplerState(id<MTLSamplerState> theSampler, int theIndex)
{
  if (!myIsActive || myEncoder == nil)
  {
    return;
  }

  [myEncoder setSamplerState:theSampler
                     atIndex:static_cast<NSUInteger>(theIndex)];
}

// =======================================================================
// function : DispatchThreadgroups
// purpose  : Dispatch with explicit configuration
// =======================================================================
void Metal_ComputeEncoder::DispatchThreadgroups(MTLSize theThreadgroupsPerGrid,
                                                MTLSize theThreadsPerThreadgroup)
{
  if (!myIsActive || myEncoder == nil || myCurrentPipeline.IsNull())
  {
    return;
  }

  [myEncoder dispatchThreadgroups:theThreadgroupsPerGrid
            threadsPerThreadgroup:theThreadsPerThreadgroup];
}

// =======================================================================
// function : Dispatch1D
// purpose  : Dispatch for 1D array
// =======================================================================
void Metal_ComputeEncoder::Dispatch1D(int theCount, int theThreadsPerGroup)
{
  if (!myIsActive || myEncoder == nil || myCurrentPipeline.IsNull() || theCount <= 0)
  {
    return;
  }

  // Use optimal threads per group if not specified
  int threadsPerGroup = theThreadsPerGroup;
  if (threadsPerGroup <= 0)
  {
    threadsPerGroup = myCurrentPipeline->ThreadExecutionWidth();
  }

  // Calculate number of threadgroups
  int groupCount = (theCount + threadsPerGroup - 1) / threadsPerGroup;

  MTLSize threadgroupsPerGrid = MTLSizeMake(static_cast<NSUInteger>(groupCount), 1, 1);
  MTLSize threadsPerThreadgroup = MTLSizeMake(static_cast<NSUInteger>(threadsPerGroup), 1, 1);

  [myEncoder dispatchThreadgroups:threadgroupsPerGrid
            threadsPerThreadgroup:threadsPerThreadgroup];
}

// =======================================================================
// function : Dispatch2D
// purpose  : Dispatch for 2D grid
// =======================================================================
void Metal_ComputeEncoder::Dispatch2D(int theWidth, int theHeight)
{
  if (!myIsActive || myEncoder == nil || myCurrentPipeline.IsNull())
  {
    return;
  }

  if (theWidth <= 0 || theHeight <= 0)
  {
    return;
  }

  MTLSize threadgroupSize = myCurrentPipeline->OptimalThreadgroupSize2D(theWidth, theHeight);
  MTLSize threadgroupCount = myCurrentPipeline->ThreadgroupCount2D(theWidth, theHeight, threadgroupSize);

  [myEncoder dispatchThreadgroups:threadgroupCount
            threadsPerThreadgroup:threadgroupSize];
}

// =======================================================================
// function : Dispatch3D
// purpose  : Dispatch for 3D grid
// =======================================================================
void Metal_ComputeEncoder::Dispatch3D(int theWidth, int theHeight, int theDepth)
{
  if (!myIsActive || myEncoder == nil || myCurrentPipeline.IsNull())
  {
    return;
  }

  if (theWidth <= 0 || theHeight <= 0 || theDepth <= 0)
  {
    return;
  }

  // Calculate optimal 3D threadgroup size
  int maxThreads = myCurrentPipeline->MaxThreadsPerThreadgroup();
  int w = myCurrentPipeline->ThreadExecutionWidth();
  int h = 8;  // Common value for 3D work
  int d = maxThreads / (w * h);

  if (d < 1) d = 1;
  if (w > theWidth) w = theWidth;
  if (h > theHeight) h = theHeight;
  if (d > theDepth) d = theDepth;

  MTLSize threadgroupSize = MTLSizeMake(static_cast<NSUInteger>(w),
                                        static_cast<NSUInteger>(h),
                                        static_cast<NSUInteger>(d));

  NSUInteger gx = (static_cast<NSUInteger>(theWidth) + threadgroupSize.width - 1) / threadgroupSize.width;
  NSUInteger gy = (static_cast<NSUInteger>(theHeight) + threadgroupSize.height - 1) / threadgroupSize.height;
  NSUInteger gz = (static_cast<NSUInteger>(theDepth) + threadgroupSize.depth - 1) / threadgroupSize.depth;

  MTLSize threadgroupCount = MTLSizeMake(gx, gy, gz);

  [myEncoder dispatchThreadgroups:threadgroupCount
            threadsPerThreadgroup:threadgroupSize];
}

// =======================================================================
// function : MemoryBarrier
// purpose  : Insert memory barrier with scope
// =======================================================================
void Metal_ComputeEncoder::MemoryBarrier(MTLBarrierScope theScope)
{
  if (!myIsActive || myEncoder == nil)
  {
    return;
  }

  [myEncoder memoryBarrierWithScope:theScope];
}

// =======================================================================
// function : MemoryBarrierBuffers
// purpose  : Insert barrier for buffer writes
// =======================================================================
void Metal_ComputeEncoder::MemoryBarrierBuffers()
{
  MemoryBarrier(MTLBarrierScopeBuffers);
}

// =======================================================================
// function : MemoryBarrierTextures
// purpose  : Insert barrier for texture writes
// =======================================================================
void Metal_ComputeEncoder::MemoryBarrierTextures()
{
  MemoryBarrier(MTLBarrierScopeTextures);
}
