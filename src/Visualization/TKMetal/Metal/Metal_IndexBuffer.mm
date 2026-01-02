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

#include <Metal_IndexBuffer.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_IndexBuffer, Metal_Buffer)

// =======================================================================
// function : Metal_IndexBuffer
// purpose  : Constructor
// =======================================================================
Metal_IndexBuffer::Metal_IndexBuffer()
: Metal_Buffer(),
  myIndexType(Metal_IndexType_UInt16)
{
  //
}

// =======================================================================
// function : ~Metal_IndexBuffer
// purpose  : Destructor
// =======================================================================
Metal_IndexBuffer::~Metal_IndexBuffer()
{
  //
}

// =======================================================================
// function : Init (unsigned short)
// purpose  : Initialize with 16-bit indices
// =======================================================================
bool Metal_IndexBuffer::Init(Metal_Context* theCtx,
                             int theNbIndices,
                             const unsigned short* theData)
{
  myIndexType = Metal_IndexType_UInt16;
  myComponentsNb = 1;
  myDataTypeSize = sizeof(unsigned short);
  return Metal_Buffer::initData(theCtx, 1, theNbIndices, sizeof(unsigned short), theData);
}

// =======================================================================
// function : Init (unsigned int)
// purpose  : Initialize with 32-bit indices
// =======================================================================
bool Metal_IndexBuffer::Init(Metal_Context* theCtx,
                             int theNbIndices,
                             const unsigned int* theData)
{
  myIndexType = Metal_IndexType_UInt32;
  myComponentsNb = 1;
  myDataTypeSize = sizeof(unsigned int);
  return Metal_Buffer::initData(theCtx, 1, theNbIndices, sizeof(unsigned int), theData);
}
