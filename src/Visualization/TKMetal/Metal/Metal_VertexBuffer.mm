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

#include <Metal_VertexBuffer.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_VertexBuffer, Metal_Buffer)

// =======================================================================
// function : Metal_VertexBuffer
// purpose  : Constructor
// =======================================================================
Metal_VertexBuffer::Metal_VertexBuffer()
: Metal_Buffer(),
  myVertexFormat(Metal_VertexFormat_Invalid),
  myStride(0)
{
  //
}

// =======================================================================
// function : ~Metal_VertexBuffer
// purpose  : Destructor
// =======================================================================
Metal_VertexBuffer::~Metal_VertexBuffer()
{
  //
}

// =======================================================================
// function : VertexFormatSize
// purpose  : Return size in bytes for vertex format
// =======================================================================
size_t Metal_VertexBuffer::VertexFormatSize(Metal_VertexFormat theFormat)
{
  switch (theFormat)
  {
    case Metal_VertexFormat_Invalid:         return 0;
    case Metal_VertexFormat_Float:           return 4;
    case Metal_VertexFormat_Float2:          return 8;
    case Metal_VertexFormat_Float3:          return 12;
    case Metal_VertexFormat_Float4:          return 16;
    case Metal_VertexFormat_Half2:           return 4;
    case Metal_VertexFormat_Half4:           return 8;
    case Metal_VertexFormat_Int:             return 4;
    case Metal_VertexFormat_Int2:            return 8;
    case Metal_VertexFormat_Int3:            return 12;
    case Metal_VertexFormat_Int4:            return 16;
    case Metal_VertexFormat_UChar4:          return 4;
    case Metal_VertexFormat_UChar4Normalized: return 4;
  }
  return 0;
}

// =======================================================================
// function : ToVertexFormat
// purpose  : Convert Graphic3d type to Metal format
// =======================================================================
Metal_VertexFormat Metal_VertexBuffer::ToVertexFormat(Graphic3d_TypeOfData theType)
{
  switch (theType)
  {
    case Graphic3d_TOD_FLOAT:   return Metal_VertexFormat_Float;
    case Graphic3d_TOD_VEC2:    return Metal_VertexFormat_Float2;
    case Graphic3d_TOD_VEC3:    return Metal_VertexFormat_Float3;
    case Graphic3d_TOD_VEC4:    return Metal_VertexFormat_Float4;
    case Graphic3d_TOD_VEC4UB:  return Metal_VertexFormat_UChar4Normalized;
    default:                    return Metal_VertexFormat_Invalid;
  }
}

// =======================================================================
// function : MetalVertexFormat
// purpose  : Return Metal vertex format enum
// =======================================================================
MTLVertexFormat Metal_VertexBuffer::MetalVertexFormat() const
{
  switch (myVertexFormat)
  {
    case Metal_VertexFormat_Invalid:          return MTLVertexFormatInvalid;
    case Metal_VertexFormat_Float:            return MTLVertexFormatFloat;
    case Metal_VertexFormat_Float2:           return MTLVertexFormatFloat2;
    case Metal_VertexFormat_Float3:           return MTLVertexFormatFloat3;
    case Metal_VertexFormat_Float4:           return MTLVertexFormatFloat4;
    case Metal_VertexFormat_Half2:            return MTLVertexFormatHalf2;
    case Metal_VertexFormat_Half4:            return MTLVertexFormatHalf4;
    case Metal_VertexFormat_Int:              return MTLVertexFormatInt;
    case Metal_VertexFormat_Int2:             return MTLVertexFormatInt2;
    case Metal_VertexFormat_Int3:             return MTLVertexFormatInt3;
    case Metal_VertexFormat_Int4:             return MTLVertexFormatInt4;
    case Metal_VertexFormat_UChar4:           return MTLVertexFormatUChar4;
    case Metal_VertexFormat_UChar4Normalized: return MTLVertexFormatUChar4Normalized;
  }
  return MTLVertexFormatInvalid;
}

// =======================================================================
// function : InitPositions
// purpose  : Initialize with position data
// =======================================================================
bool Metal_VertexBuffer::InitPositions(Metal_Context* theCtx,
                                       int theNbVertices,
                                       const float* theData)
{
  myVertexFormat = Metal_VertexFormat_Float3;
  myStride = 3 * sizeof(float);
  return Metal_Buffer::Init(theCtx, 3, theNbVertices, theData);
}

// =======================================================================
// function : InitNormals
// purpose  : Initialize with normal data
// =======================================================================
bool Metal_VertexBuffer::InitNormals(Metal_Context* theCtx,
                                     int theNbVertices,
                                     const float* theData)
{
  myVertexFormat = Metal_VertexFormat_Float3;
  myStride = 3 * sizeof(float);
  return Metal_Buffer::Init(theCtx, 3, theNbVertices, theData);
}

// =======================================================================
// function : InitTexCoords
// purpose  : Initialize with texture coordinate data
// =======================================================================
bool Metal_VertexBuffer::InitTexCoords(Metal_Context* theCtx,
                                       int theNbVertices,
                                       const float* theData)
{
  myVertexFormat = Metal_VertexFormat_Float2;
  myStride = 2 * sizeof(float);
  return Metal_Buffer::Init(theCtx, 2, theNbVertices, theData);
}

// =======================================================================
// function : InitColors
// purpose  : Initialize with RGBA byte color data
// =======================================================================
bool Metal_VertexBuffer::InitColors(Metal_Context* theCtx,
                                    int theNbVertices,
                                    const uint8_t* theData)
{
  myVertexFormat = Metal_VertexFormat_UChar4Normalized;
  myStride = 4 * sizeof(uint8_t);
  return Metal_Buffer::Init(theCtx, 4, theNbVertices, theData);
}

// =======================================================================
// function : InitColorsFloat
// purpose  : Initialize with RGBA float color data
// =======================================================================
bool Metal_VertexBuffer::InitColorsFloat(Metal_Context* theCtx,
                                         int theNbVertices,
                                         const float* theData)
{
  myVertexFormat = Metal_VertexFormat_Float4;
  myStride = 4 * sizeof(float);
  return Metal_Buffer::Init(theCtx, 4, theNbVertices, theData);
}

// =======================================================================
// function : Init
// purpose  : Initialize from Graphic3d data type
// =======================================================================
bool Metal_VertexBuffer::Init(Metal_Context* theCtx,
                              Graphic3d_TypeOfData theType,
                              int theStride,
                              int theNbElems,
                              const void* theData)
{
  myVertexFormat = ToVertexFormat(theType);
  if (myVertexFormat == Metal_VertexFormat_Invalid)
  {
    return false;
  }

  size_t aFormatSize = VertexFormatSize(myVertexFormat);
  myStride = (theStride > 0) ? size_t(theStride) : aFormatSize;

  // Determine components and type size
  unsigned int aComponentsNb = 1;
  size_t aTypeSize = sizeof(float);
  switch (theType)
  {
    case Graphic3d_TOD_FLOAT:
      aComponentsNb = 1;
      aTypeSize = sizeof(float);
      break;
    case Graphic3d_TOD_VEC2:
      aComponentsNb = 2;
      aTypeSize = sizeof(float);
      break;
    case Graphic3d_TOD_VEC3:
      aComponentsNb = 3;
      aTypeSize = sizeof(float);
      break;
    case Graphic3d_TOD_VEC4:
      aComponentsNb = 4;
      aTypeSize = sizeof(float);
      break;
    case Graphic3d_TOD_VEC4UB:
      aComponentsNb = 4;
      aTypeSize = sizeof(uint8_t);
      break;
    default:
      return false;
  }

  return Metal_Buffer::initData(theCtx, aComponentsNb, theNbElems, aTypeSize, theData);
}
