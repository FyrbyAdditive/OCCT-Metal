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

#include <Metal_InstanceBuffer.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_InstanceBuffer, Standard_Transient)

// =======================================================================
// function : Metal_InstanceBuffer
// purpose  : Constructor
// =======================================================================
Metal_InstanceBuffer::Metal_InstanceBuffer()
: myBuffer(nil),
  myInstanceCount(0),
  myStride(0),
  myIsValid(false)
{
}

// =======================================================================
// function : ~Metal_InstanceBuffer
// purpose  : Destructor
// =======================================================================
Metal_InstanceBuffer::~Metal_InstanceBuffer()
{
  Release(nullptr);
}

// =======================================================================
// function : Init
// purpose  : Initialize with raw data and custom stride
// =======================================================================
bool Metal_InstanceBuffer::Init(Metal_Context* theCtx,
                                int theInstanceCount,
                                const void* theData,
                                int theStride)
{
  Release(theCtx);

  if (theCtx == nullptr || theInstanceCount <= 0 || theData == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Use default stride if not specified
  myStride = (theStride > 0) ? theStride : static_cast<int>(sizeof(Metal_InstanceData));
  myInstanceCount = theInstanceCount;

  size_t aBufferSize = static_cast<size_t>(myInstanceCount) * static_cast<size_t>(myStride);

  // Create buffer with shared storage for CPU/GPU access
  myBuffer = [aDevice newBufferWithBytes:theData
                                  length:aBufferSize
                                 options:MTLResourceStorageModeShared];

  if (myBuffer == nil)
  {
    return false;
  }

  myIsValid = true;
  return true;
}

// =======================================================================
// function : Init
// purpose  : Initialize with Metal_InstanceData structures
// =======================================================================
bool Metal_InstanceBuffer::Init(Metal_Context* theCtx,
                                int theInstanceCount,
                                const Metal_InstanceData* theData)
{
  return Init(theCtx, theInstanceCount, theData, sizeof(Metal_InstanceData));
}

// =======================================================================
// function : Update
// purpose  : Update instance data in the buffer
// =======================================================================
bool Metal_InstanceBuffer::Update(Metal_Context* theCtx,
                                  int theOffset,
                                  int theCount,
                                  const void* theData)
{
  (void)theCtx; // Currently unused as we use shared storage

  if (!myIsValid || myBuffer == nil || theData == nullptr)
  {
    return false;
  }

  if (theOffset < 0 || theCount <= 0 || (theOffset + theCount) > myInstanceCount)
  {
    return false;
  }

  size_t anOffsetBytes = static_cast<size_t>(theOffset) * static_cast<size_t>(myStride);
  size_t aCopySize = static_cast<size_t>(theCount) * static_cast<size_t>(myStride);

  // Copy data to buffer
  uint8_t* aContents = static_cast<uint8_t*>([myBuffer contents]);
  memcpy(aContents + anOffsetBytes, theData, aCopySize);

  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_InstanceBuffer::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (myBuffer != nil)
  {
    myBuffer = nil;
  }

  myInstanceCount = 0;
  myStride = 0;
  myIsValid = false;
}
