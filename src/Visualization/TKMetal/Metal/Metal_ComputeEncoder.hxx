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

#ifndef Metal_ComputeEncoder_HeaderFile
#define Metal_ComputeEncoder_HeaderFile

#include <Metal_ComputePipeline.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;
class Metal_Buffer;
class Metal_Texture;

//! Metal compute command encoder wrapper.
//! Provides convenient methods for dispatching compute shaders.
class Metal_ComputeEncoder
{
public:

  //! Create an empty encoder (must be initialized before use).
  Standard_EXPORT Metal_ComputeEncoder();

  //! Destructor - ends encoding if active.
  Standard_EXPORT ~Metal_ComputeEncoder();

  //! Begin compute encoding on a command buffer.
  //! @param theCommandBuffer Metal command buffer
  //! @return true on success
#ifdef __OBJC__
  Standard_EXPORT bool Begin(id<MTLCommandBuffer> theCommandBuffer);
#endif

  //! End compute encoding.
  Standard_EXPORT void End();

  //! Return true if encoder is active.
  bool IsActive() const { return myIsActive; }

  //! Set compute pipeline for dispatch.
  //! @param thePipeline compute pipeline to use
  Standard_EXPORT void SetPipeline(const occ::handle<Metal_ComputePipeline>& thePipeline);

  //! Set a buffer at the specified index.
  //! @param theBuffer Metal buffer
  //! @param theOffset offset in bytes
  //! @param theIndex buffer binding index
#ifdef __OBJC__
  Standard_EXPORT void SetBuffer(id<MTLBuffer> theBuffer, int theOffset, int theIndex);
#endif

  //! Set a buffer from Metal_Buffer at the specified index.
  //! @param theBuffer buffer wrapper
  //! @param theIndex buffer binding index
  Standard_EXPORT void SetBuffer(const occ::handle<Metal_Buffer>& theBuffer, int theIndex);

  //! Set bytes directly (for small uniform data).
  //! @param theBytes pointer to data
  //! @param theLength size in bytes
  //! @param theIndex buffer binding index
  Standard_EXPORT void SetBytes(const void* theBytes, int theLength, int theIndex);

  //! Set a texture at the specified index.
  //! @param theTexture Metal texture
  //! @param theIndex texture binding index
#ifdef __OBJC__
  Standard_EXPORT void SetTexture(id<MTLTexture> theTexture, int theIndex);
#endif

  //! Set a texture from Metal_Texture at the specified index.
  //! @param theTexture texture wrapper
  //! @param theIndex texture binding index
  Standard_EXPORT void SetTexture(const occ::handle<Metal_Texture>& theTexture, int theIndex);

  //! Set a sampler state at the specified index.
#ifdef __OBJC__
  Standard_EXPORT void SetSamplerState(id<MTLSamplerState> theSampler, int theIndex);
#endif

  //! Dispatch compute work with explicit threadgroup configuration.
  //! @param theThreadgroupsPerGrid number of threadgroups in each dimension
  //! @param theThreadsPerThreadgroup number of threads per threadgroup
#ifdef __OBJC__
  Standard_EXPORT void DispatchThreadgroups(MTLSize theThreadgroupsPerGrid,
                                            MTLSize theThreadsPerThreadgroup);
#endif

  //! Dispatch compute work for a 1D array.
  //! @param theCount total number of elements
  //! @param theThreadsPerGroup threads per threadgroup (default: auto)
  Standard_EXPORT void Dispatch1D(int theCount, int theThreadsPerGroup = 0);

  //! Dispatch compute work for a 2D grid (e.g., image processing).
  //! @param theWidth grid width
  //! @param theHeight grid height
  Standard_EXPORT void Dispatch2D(int theWidth, int theHeight);

  //! Dispatch compute work for a 3D grid.
  //! @param theWidth grid width
  //! @param theHeight grid height
  //! @param theDepth grid depth
  Standard_EXPORT void Dispatch3D(int theWidth, int theHeight, int theDepth);

  //! Insert a memory barrier to ensure all writes are complete
  //! before subsequent reads.
  //! @param theScope memory barrier scope
#ifdef __OBJC__
  Standard_EXPORT void MemoryBarrier(MTLBarrierScope theScope);
#endif

  //! Insert a barrier for buffer writes.
  Standard_EXPORT void MemoryBarrierBuffers();

  //! Insert a barrier for texture writes.
  Standard_EXPORT void MemoryBarrierTextures();

private:

#ifdef __OBJC__
  id<MTLComputeCommandEncoder> myEncoder;
#else
  void* myEncoder;
#endif

  occ::handle<Metal_ComputePipeline> myCurrentPipeline;
  bool myIsActive;
};

#endif // Metal_ComputeEncoder_HeaderFile
