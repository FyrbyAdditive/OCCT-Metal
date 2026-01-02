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

#include <Metal_Buffer.hxx>
#include <Metal_Context.hxx>
#include <Standard_Assert.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Buffer, Metal_Resource)

// =======================================================================
// function : Metal_Buffer
// purpose  : Constructor
// =======================================================================
Metal_Buffer::Metal_Buffer()
: myBuffer(nil),
  mySize(0),
  myComponentsNb(4),
  myElemsNb(0),
  myDataTypeSize(sizeof(float)),
  myStorageMode(Metal_StorageMode_Shared)
{
  //
}

// =======================================================================
// function : ~Metal_Buffer
// purpose  : Destructor
// =======================================================================
Metal_Buffer::~Metal_Buffer()
{
  // Buffer should be released explicitly before destruction
  Standard_ASSERT_RAISE(myBuffer == nil,
    "Metal_Buffer destroyed without explicit Release()");
}

// =======================================================================
// function : Create
// purpose  : Create buffer with specified size
// =======================================================================
bool Metal_Buffer::Create(Metal_Context* theCtx,
                          size_t theSize,
                          const void* theData,
                          Metal_StorageMode theMode)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid() || theSize == 0)
  {
    return false;
  }

  myStorageMode = theMode;
  mySize = theSize;

  // Map storage mode to Metal resource options
  MTLResourceOptions aOptions = MTLResourceStorageModeShared;
  switch (theMode)
  {
    case Metal_StorageMode_Shared:
      aOptions = MTLResourceStorageModeShared;
      break;
    case Metal_StorageMode_Managed:
#if TARGET_OS_OSX
      aOptions = MTLResourceStorageModeManaged;
#else
      // Managed storage not available on iOS, use shared
      aOptions = MTLResourceStorageModeShared;
      myStorageMode = Metal_StorageMode_Shared;
#endif
      break;
    case Metal_StorageMode_Private:
      aOptions = MTLResourceStorageModePrivate;
      break;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (theData != nullptr && theMode != Metal_StorageMode_Private)
  {
    // Create buffer with initial data
    myBuffer = [aDevice newBufferWithBytes:theData
                                    length:theSize
                                   options:aOptions];
  }
  else
  {
    // Create empty buffer
    myBuffer = [aDevice newBufferWithLength:theSize
                                    options:aOptions];

    // For private storage with initial data, need to use blit encoder
    if (theData != nullptr && theMode == Metal_StorageMode_Private)
    {
      // Create staging buffer
      id<MTLBuffer> aStagingBuffer = [aDevice newBufferWithBytes:theData
                                                          length:theSize
                                                         options:MTLResourceStorageModeShared];

      // Copy using blit encoder
      id<MTLCommandBuffer> aCmdBuffer = theCtx->CurrentCommandBuffer();
      id<MTLBlitCommandEncoder> aBlitEncoder = [aCmdBuffer blitCommandEncoder];
      [aBlitEncoder copyFromBuffer:aStagingBuffer
                      sourceOffset:0
                          toBuffer:myBuffer
                 destinationOffset:0
                              size:theSize];
      [aBlitEncoder endEncoding];
    }
  }

  return myBuffer != nil;
}

// =======================================================================
// function : initData
// purpose  : Initialize buffer from raw data
// =======================================================================
bool Metal_Buffer::initData(Metal_Context* theCtx,
                            unsigned int theComponentsNb,
                            int theElemsNb,
                            size_t theDataTypeSize,
                            const void* theData)
{
  if (theComponentsNb < 1 || theComponentsNb > 4 || theElemsNb <= 0)
  {
    return false;
  }

  myComponentsNb = theComponentsNb;
  myElemsNb = theElemsNb;
  myDataTypeSize = theDataTypeSize;

  size_t aSize = size_t(theElemsNb) * size_t(theComponentsNb) * theDataTypeSize;
  return Create(theCtx, aSize, theData, Metal_StorageMode_Shared);
}

// =======================================================================
// function : Init (float)
// purpose  : Initialize buffer with float data
// =======================================================================
bool Metal_Buffer::Init(Metal_Context* theCtx,
                        unsigned int theComponentsNb,
                        int theElemsNb,
                        const float* theData)
{
  return initData(theCtx, theComponentsNb, theElemsNb, sizeof(float), theData);
}

// =======================================================================
// function : Init (unsigned int)
// purpose  : Initialize buffer with unsigned int data
// =======================================================================
bool Metal_Buffer::Init(Metal_Context* theCtx,
                        unsigned int theComponentsNb,
                        int theElemsNb,
                        const unsigned int* theData)
{
  return initData(theCtx, theComponentsNb, theElemsNb, sizeof(unsigned int), theData);
}

// =======================================================================
// function : Init (unsigned short)
// purpose  : Initialize buffer with unsigned short data
// =======================================================================
bool Metal_Buffer::Init(Metal_Context* theCtx,
                        unsigned int theComponentsNb,
                        int theElemsNb,
                        const unsigned short* theData)
{
  return initData(theCtx, theComponentsNb, theElemsNb, sizeof(unsigned short), theData);
}

// =======================================================================
// function : Init (uint8_t)
// purpose  : Initialize buffer with byte data
// =======================================================================
bool Metal_Buffer::Init(Metal_Context* theCtx,
                        unsigned int theComponentsNb,
                        int theElemsNb,
                        const uint8_t* theData)
{
  return initData(theCtx, theComponentsNb, theElemsNb, sizeof(uint8_t), theData);
}

// =======================================================================
// function : SubData
// purpose  : Update portion of buffer data
// =======================================================================
bool Metal_Buffer::SubData(Metal_Context* theCtx,
                           int theElemFrom,
                           int theElemsNb,
                           const void* theData)
{
  if (myBuffer == nil || theCtx == nullptr || theData == nullptr)
  {
    return false;
  }

  if (theElemFrom < 0 || theElemsNb <= 0 || theElemFrom + theElemsNb > myElemsNb)
  {
    return false;
  }

  size_t anOffset = size_t(theElemFrom) * size_t(myComponentsNb) * myDataTypeSize;
  size_t aSize = size_t(theElemsNb) * size_t(myComponentsNb) * myDataTypeSize;

  if (myStorageMode == Metal_StorageMode_Private)
  {
    // For private storage, need to use staging buffer and blit
    id<MTLDevice> aDevice = theCtx->Device();
    id<MTLBuffer> aStagingBuffer = [aDevice newBufferWithBytes:theData
                                                        length:aSize
                                                       options:MTLResourceStorageModeShared];

    id<MTLCommandBuffer> aCmdBuffer = theCtx->CurrentCommandBuffer();
    id<MTLBlitCommandEncoder> aBlitEncoder = [aCmdBuffer blitCommandEncoder];
    [aBlitEncoder copyFromBuffer:aStagingBuffer
                    sourceOffset:0
                        toBuffer:myBuffer
               destinationOffset:anOffset
                            size:aSize];
    [aBlitEncoder endEncoding];
  }
  else
  {
    // For shared/managed storage, can copy directly
    void* aContents = [myBuffer contents];
    memcpy(static_cast<uint8_t*>(aContents) + anOffset, theData, aSize);

#if TARGET_OS_OSX
    if (myStorageMode == Metal_StorageMode_Managed)
    {
      // Notify GPU of the modified range
      [myBuffer didModifyRange:NSMakeRange(anOffset, aSize)];
    }
#endif
  }

  return true;
}

// =======================================================================
// function : GetData
// purpose  : Read buffer contents back to CPU
// =======================================================================
bool Metal_Buffer::GetData(Metal_Context* theCtx,
                           void* theData,
                           size_t theSize,
                           size_t theOffset) const
{
  (void)theCtx;

  if (myBuffer == nil || theData == nullptr)
  {
    return false;
  }

  if (theOffset + theSize > mySize)
  {
    return false;
  }

  if (myStorageMode == Metal_StorageMode_Private)
  {
    // Cannot read directly from private storage
    // Would need to use blit encoder to staging buffer
    return false;
  }

  const void* aContents = [myBuffer contents];
  memcpy(theData, static_cast<const uint8_t*>(aContents) + theOffset, theSize);
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Buffer::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (myBuffer != nil)
  {
    myBuffer = nil;
  }

  mySize = 0;
  myElemsNb = 0;
}
