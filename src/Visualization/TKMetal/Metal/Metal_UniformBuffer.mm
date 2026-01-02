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

#include <Metal_UniformBuffer.hxx>
#include <Metal_Context.hxx>
#include <Standard_Assert.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_UniformBuffer, Metal_Resource)

// Metal requires 256-byte alignment for buffer offsets when binding
static const size_t METAL_BUFFER_OFFSET_ALIGNMENT = 256;

// =======================================================================
// function : Metal_UniformBuffer
// purpose  : Constructor
// =======================================================================
Metal_UniformBuffer::Metal_UniformBuffer()
: myBuffer(nil),
  myBlockSize(0),
  myAlignedBlockSize(0),
  myTotalSize(0),
  myFramesInFlight(Metal_MaxFramesInFlight)
{
  //
}

// =======================================================================
// function : ~Metal_UniformBuffer
// purpose  : Destructor
// =======================================================================
Metal_UniformBuffer::~Metal_UniformBuffer()
{
  Standard_ASSERT_RAISE(myBuffer == nil,
    "Metal_UniformBuffer destroyed without explicit Release()");
}

// =======================================================================
// function : Create
// purpose  : Create uniform buffer
// =======================================================================
bool Metal_UniformBuffer::Create(Metal_Context* theCtx, size_t theBlockSize)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid() || theBlockSize == 0)
  {
    return false;
  }

  myBlockSize = theBlockSize;
  myFramesInFlight = theCtx->Caps()->maxFramesInFlight;

  // Align block size to Metal's 256-byte requirement
  myAlignedBlockSize = ((myBlockSize + METAL_BUFFER_OFFSET_ALIGNMENT - 1)
                        / METAL_BUFFER_OFFSET_ALIGNMENT)
                       * METAL_BUFFER_OFFSET_ALIGNMENT;

  // Total size for all frame copies
  myTotalSize = myAlignedBlockSize * size_t(myFramesInFlight);

  // Create buffer with shared storage mode for CPU updates
  id<MTLDevice> aDevice = theCtx->Device();
  myBuffer = [aDevice newBufferWithLength:myTotalSize
                                  options:MTLResourceStorageModeShared];

  return myBuffer != nil;
}

// =======================================================================
// function : Update
// purpose  : Update uniform data for current frame
// =======================================================================
bool Metal_UniformBuffer::Update(Metal_Context* theCtx,
                                 const void* theData,
                                 size_t theSize)
{
  if (myBuffer == nil || theCtx == nullptr || theData == nullptr)
  {
    return false;
  }

  if (theSize > myBlockSize)
  {
    return false;
  }

  // Get offset for current frame
  size_t anOffset = CurrentOffset(theCtx);

  // Copy data to buffer
  void* aContents = [myBuffer contents];
  memcpy(static_cast<uint8_t*>(aContents) + anOffset, theData, theSize);

  return true;
}

// =======================================================================
// function : CurrentOffset
// purpose  : Get offset for current frame's uniform block
// =======================================================================
size_t Metal_UniformBuffer::CurrentOffset(Metal_Context* theCtx) const
{
  if (theCtx == nullptr)
  {
    return 0;
  }

  int aFrameIndex = theCtx->CurrentFrameIndex();
  return size_t(aFrameIndex) * myAlignedBlockSize;
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_UniformBuffer::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (myBuffer != nil)
  {
    myBuffer = nil;
  }

  myBlockSize = 0;
  myAlignedBlockSize = 0;
  myTotalSize = 0;
}
