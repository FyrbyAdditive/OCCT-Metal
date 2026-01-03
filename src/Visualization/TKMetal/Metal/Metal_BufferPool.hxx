// Copyright (c) 2025 OPEN CASCADE SAS
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

#ifndef Metal_BufferPool_HeaderFile
#define Metal_BufferPool_HeaderFile

#include <Standard.hxx>
#include <NCollection_Vector.hxx>
#include <NCollection_List.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
@protocol MTLDevice;
#endif

class Metal_Context;

//! Pool of reusable Metal buffers to reduce allocation overhead.
//! Manages transient buffers (uniforms, staging, etc.) that are
//! allocated frequently and have short lifetimes.
//!
//! Usage pattern:
//! 1. Acquire() a buffer of needed size at frame start
//! 2. Use the buffer for rendering
//! 3. ReclaimAll() at frame end to return buffers to pool
//!
//! Buffers are organized by size class (powers of 2) for efficient reuse.
class Metal_BufferPool
{
public:

  //! Size classes: 256, 512, 1K, 2K, 4K, 8K, 16K, 32K, 64K, 128K, 256K, 512K, 1M
  static const int NbSizeClasses = 13;

  //! Minimum buffer size (256 bytes, for small uniforms)
  static const size_t MinBufferSize = 256;

  //! Maximum pooled buffer size (1MB, larger allocations bypass pool)
  static const size_t MaxPooledSize = 1024 * 1024;

  //! Maximum buffers to keep per size class
  static const int MaxBuffersPerClass = 16;

public:

  //! Constructor.
  Standard_EXPORT Metal_BufferPool();

  //! Destructor - releases all pooled buffers.
  Standard_EXPORT ~Metal_BufferPool();

  //! Initialize pool with Metal device.
  Standard_EXPORT void Init(Metal_Context* theCtx);

  //! Release all pooled buffers.
  Standard_EXPORT void Release();

  //! Acquire a buffer of at least the specified size.
  //! Returns a buffer from the pool if available, or allocates a new one.
  //! The returned buffer is removed from the pool until Reclaim() is called.
  //! @param theSize minimum required size in bytes
  //! @return buffer handle (may be nil if allocation fails)
#ifdef __OBJC__
  Standard_EXPORT id<MTLBuffer> Acquire(size_t theSize);
#endif

  //! Return a buffer to the pool for future reuse.
  //! @param theBuffer buffer to return
#ifdef __OBJC__
  Standard_EXPORT void Reclaim(id<MTLBuffer> theBuffer);
#endif

  //! Return all in-use buffers to the pool.
  //! Call this at the end of each frame.
  Standard_EXPORT void ReclaimAll();

  //! Return the number of cached buffers.
  int NbCachedBuffers() const { return myNbCached; }

  //! Return the total size of cached buffers in bytes.
  size_t CachedMemory() const { return myCachedMemory; }

  //! Return the number of allocations since pool creation.
  int NbAllocations() const { return myNbAllocations; }

  //! Return the number of cache hits (reused buffers).
  int NbCacheHits() const { return myNbCacheHits; }

  //! Return cache hit ratio (0.0 - 1.0).
  float CacheHitRatio() const
  {
    int total = myNbAllocations + myNbCacheHits;
    return total > 0 ? float(myNbCacheHits) / float(total) : 0.0f;
  }

  //! Reset statistics counters.
  void ResetStatistics()
  {
    myNbAllocations = 0;
    myNbCacheHits = 0;
  }

protected:

  //! Get size class index for a given size.
  static int sizeClassIndex(size_t theSize);

  //! Get buffer size for a size class.
  static size_t sizeForClass(int theClass);

protected:

#ifdef __OBJC__
  id<MTLDevice> myDevice;  //!< Metal device for allocations

  //! Pooled buffers organized by size class
  NCollection_List<id<MTLBuffer>> myPool[NbSizeClasses];

  //! Buffers currently in use (to be reclaimed)
  NCollection_List<id<MTLBuffer>> myInUse;
#else
  void* myDevice;
  void* myPool[NbSizeClasses];
  void* myInUse;
#endif

  int    myNbCached;      //!< number of cached buffers
  size_t myCachedMemory;  //!< total cached memory in bytes
  int    myNbAllocations; //!< number of new allocations
  int    myNbCacheHits;   //!< number of cache hits
};

#endif // Metal_BufferPool_HeaderFile
