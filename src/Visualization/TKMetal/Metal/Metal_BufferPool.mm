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

#import <Metal/Metal.h>

#include <Metal_BufferPool.hxx>
#include <Metal_Context.hxx>

// =======================================================================
// function : Metal_BufferPool
// purpose  : Constructor
// =======================================================================
Metal_BufferPool::Metal_BufferPool()
: myDevice(nil),
  myNbCached(0),
  myCachedMemory(0),
  myNbAllocations(0),
  myNbCacheHits(0)
{
  //
}

// =======================================================================
// function : ~Metal_BufferPool
// purpose  : Destructor
// =======================================================================
Metal_BufferPool::~Metal_BufferPool()
{
  Release();
}

// =======================================================================
// function : Init
// purpose  : Initialize pool
// =======================================================================
void Metal_BufferPool::Init(Metal_Context* theCtx)
{
  if (theCtx != nullptr)
  {
    myDevice = theCtx->Device();
  }
}

// =======================================================================
// function : Release
// purpose  : Release all pooled buffers
// =======================================================================
void Metal_BufferPool::Release()
{
  // Clear all size class pools
  for (int i = 0; i < NbSizeClasses; ++i)
  {
    myPool[i].Clear();
  }

  // Clear in-use list
  myInUse.Clear();

  myDevice = nil;
  myNbCached = 0;
  myCachedMemory = 0;
}

// =======================================================================
// function : sizeClassIndex
// purpose  : Get size class for a given size
// =======================================================================
int Metal_BufferPool::sizeClassIndex(size_t theSize)
{
  if (theSize <= MinBufferSize)
  {
    return 0;
  }

  // Find smallest size class >= theSize
  size_t aClassSize = MinBufferSize;
  for (int i = 0; i < NbSizeClasses; ++i)
  {
    if (aClassSize >= theSize)
    {
      return i;
    }
    aClassSize *= 2;
  }

  return -1; // Size too large for pool
}

// =======================================================================
// function : sizeForClass
// purpose  : Get buffer size for size class
// =======================================================================
size_t Metal_BufferPool::sizeForClass(int theClass)
{
  if (theClass < 0 || theClass >= NbSizeClasses)
  {
    return 0;
  }
  return MinBufferSize << theClass;
}

// =======================================================================
// function : Acquire
// purpose  : Get a buffer from pool or allocate new
// =======================================================================
id<MTLBuffer> Metal_BufferPool::Acquire(size_t theSize)
{
  if (myDevice == nil || theSize == 0)
  {
    return nil;
  }

  // Bypass pool for very large buffers
  if (theSize > MaxPooledSize)
  {
    ++myNbAllocations;
    id<MTLBuffer> aBuffer = [myDevice newBufferWithLength:theSize
                                                  options:MTLResourceStorageModeShared];
    if (aBuffer != nil)
    {
      myInUse.Append(aBuffer);
    }
    return aBuffer;
  }

  // Find appropriate size class
  int aClass = sizeClassIndex(theSize);
  if (aClass < 0)
  {
    aClass = NbSizeClasses - 1;
  }

  // Try to get from pool
  if (!myPool[aClass].IsEmpty())
  {
    id<MTLBuffer> aBuffer = myPool[aClass].First();
    myPool[aClass].RemoveFirst();

    --myNbCached;
    myCachedMemory -= aBuffer.length;
    ++myNbCacheHits;

    myInUse.Append(aBuffer);
    return aBuffer;
  }

  // Allocate new buffer
  size_t aBufferSize = sizeForClass(aClass);
  if (aBufferSize < theSize)
  {
    aBufferSize = theSize;
  }

  ++myNbAllocations;
  id<MTLBuffer> aBuffer = [myDevice newBufferWithLength:aBufferSize
                                                options:MTLResourceStorageModeShared];
  if (aBuffer != nil)
  {
    myInUse.Append(aBuffer);
  }
  return aBuffer;
}

// =======================================================================
// function : Reclaim
// purpose  : Return buffer to pool
// =======================================================================
void Metal_BufferPool::Reclaim(id<MTLBuffer> theBuffer)
{
  if (theBuffer == nil)
  {
    return;
  }

  size_t aSize = theBuffer.length;

  // Don't pool very large buffers
  if (aSize > MaxPooledSize)
  {
    return;
  }

  int aClass = sizeClassIndex(aSize);
  if (aClass < 0 || aClass >= NbSizeClasses)
  {
    return;
  }

  // Don't exceed max buffers per class
  if (myPool[aClass].Size() >= MaxBuffersPerClass)
  {
    return; // Let buffer be released
  }

  // Add to pool
  myPool[aClass].Append(theBuffer);
  ++myNbCached;
  myCachedMemory += aSize;
}

// =======================================================================
// function : ReclaimAll
// purpose  : Return all in-use buffers to pool
// =======================================================================
void Metal_BufferPool::ReclaimAll()
{
  for (NCollection_List<id<MTLBuffer>>::Iterator anIter(myInUse);
       anIter.More(); anIter.Next())
  {
    Reclaim(anIter.Value());
  }
  myInUse.Clear();
}
