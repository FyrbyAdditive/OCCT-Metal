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

#include <Metal_PrimitiveArray.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>

// =======================================================================
// function : Metal_PrimitiveArray
// purpose  : Constructor
// =======================================================================
Metal_PrimitiveArray::Metal_PrimitiveArray(
  const Graphic3d_TypeOfPrimitiveArray theType,
  const occ::handle<Graphic3d_IndexBuffer>& theIndices,
  const occ::handle<Graphic3d_Buffer>& theAttribs,
  const occ::handle<Graphic3d_BoundBuffer>& theBounds)
: myType(theType),
  myAttribs(theAttribs),
  myIndices(theIndices),
  myBounds(theBounds),
  myNbVertices(0),
  myNbIndices(0),
  myIsInitialized(false)
{
  if (!myAttribs.IsNull())
  {
    myNbVertices = static_cast<int>(myAttribs->NbElements);
  }
  if (!myIndices.IsNull())
  {
    myNbIndices = static_cast<int>(myIndices->NbElements);
  }
}

// =======================================================================
// function : ~Metal_PrimitiveArray
// purpose  : Destructor
// =======================================================================
Metal_PrimitiveArray::~Metal_PrimitiveArray()
{
  Release(nullptr);
}

// =======================================================================
// function : Init
// purpose  : Initialize Metal resources
// =======================================================================
bool Metal_PrimitiveArray::Init(Metal_Context* theCtx)
{
  if (myIsInitialized || theCtx == nullptr)
  {
    return myIsInitialized;
  }

  if (myAttribs.IsNull() || myAttribs->NbElements == 0)
  {
    return false;
  }

  // Find and upload each attribute type
  for (int anAttribIdx = 0; anAttribIdx < myAttribs->NbAttributes; ++anAttribIdx)
  {
    const Graphic3d_Attribute& anAttrib = myAttribs->Attribute(anAttribIdx);
    const size_t anOffset = myAttribs->AttributeOffset(anAttribIdx);
    const uint8_t* aData = myAttribs->Data() + anOffset;

    switch (anAttrib.Id)
    {
      case Graphic3d_TOA_POS:
      {
        myPositionVbo = new Metal_VertexBuffer();
        if (!myPositionVbo->Init(theCtx, anAttrib.DataType,
                                 static_cast<int>(myAttribs->Stride),
                                 static_cast<int>(myAttribs->NbElements),
                                 aData))
        {
          return false;
        }
        break;
      }
      case Graphic3d_TOA_NORM:
      {
        myNormalVbo = new Metal_VertexBuffer();
        if (!myNormalVbo->Init(theCtx, anAttrib.DataType,
                               static_cast<int>(myAttribs->Stride),
                               static_cast<int>(myAttribs->NbElements),
                               aData))
        {
          return false;
        }
        break;
      }
      case Graphic3d_TOA_COLOR:
      {
        myColorVbo = new Metal_VertexBuffer();
        if (!myColorVbo->Init(theCtx, anAttrib.DataType,
                              static_cast<int>(myAttribs->Stride),
                              static_cast<int>(myAttribs->NbElements),
                              aData))
        {
          return false;
        }
        break;
      }
      case Graphic3d_TOA_UV:
      {
        myTexCoordVbo = new Metal_VertexBuffer();
        if (!myTexCoordVbo->Init(theCtx, anAttrib.DataType,
                                 static_cast<int>(myAttribs->Stride),
                                 static_cast<int>(myAttribs->NbElements),
                                 aData))
        {
          return false;
        }
        break;
      }
      default:
        break;
    }
  }

  // Upload index buffer if present
  if (!myIndices.IsNull() && myIndices->NbElements > 0)
  {
    myIndexBuffer = new Metal_IndexBuffer();
    Metal_IndexType anIndexType = myIndices->Stride == 2
                                ? Metal_IndexType_UInt16
                                : Metal_IndexType_UInt32;
    if (!myIndexBuffer->Init(theCtx, anIndexType,
                             static_cast<int>(myIndices->NbElements),
                             myIndices->Data()))
    {
      return false;
    }
  }

  myIsInitialized = true;
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_PrimitiveArray::Release(Metal_Context* theCtx)
{
  if (!myPositionVbo.IsNull())
  {
    myPositionVbo->Release(theCtx);
    myPositionVbo.Nullify();
  }
  if (!myNormalVbo.IsNull())
  {
    myNormalVbo->Release(theCtx);
    myNormalVbo.Nullify();
  }
  if (!myColorVbo.IsNull())
  {
    myColorVbo->Release(theCtx);
    myColorVbo.Nullify();
  }
  if (!myTexCoordVbo.IsNull())
  {
    myTexCoordVbo->Release(theCtx);
    myTexCoordVbo.Nullify();
  }
  if (!myIndexBuffer.IsNull())
  {
    myIndexBuffer->Release(theCtx);
    myIndexBuffer.Nullify();
  }

  myIsInitialized = false;
}

// =======================================================================
// function : Render
// purpose  : Render the primitive array
// =======================================================================
void Metal_PrimitiveArray::Render(Metal_Workspace* theWorkspace) const
{
  if (!myIsInitialized || theWorkspace == nullptr)
  {
    return;
  }

  id<MTLRenderCommandEncoder> anEncoder = theWorkspace->ActiveEncoder();
  if (anEncoder == nil)
  {
    return;
  }

  // Bind vertex buffers
  int aBufferIdx = 0;
  if (!myPositionVbo.IsNull() && myPositionVbo->IsValid())
  {
    [anEncoder setVertexBuffer:myPositionVbo->Buffer()
                        offset:0
                       atIndex:aBufferIdx++];
  }
  if (!myNormalVbo.IsNull() && myNormalVbo->IsValid())
  {
    [anEncoder setVertexBuffer:myNormalVbo->Buffer()
                        offset:0
                       atIndex:aBufferIdx++];
  }
  if (!myColorVbo.IsNull() && myColorVbo->IsValid())
  {
    [anEncoder setVertexBuffer:myColorVbo->Buffer()
                        offset:0
                       atIndex:aBufferIdx++];
  }
  if (!myTexCoordVbo.IsNull() && myTexCoordVbo->IsValid())
  {
    [anEncoder setVertexBuffer:myTexCoordVbo->Buffer()
                        offset:0
                       atIndex:aBufferIdx++];
  }

  // Draw
  MTLPrimitiveType aPrimType = MetalPrimitiveType();

  if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
  {
    // Indexed drawing
    MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
    [anEncoder drawIndexedPrimitives:aPrimType
                          indexCount:static_cast<NSUInteger>(myNbIndices)
                           indexType:anIndexType
                         indexBuffer:myIndexBuffer->Buffer()
                   indexBufferOffset:0];
  }
  else
  {
    // Non-indexed drawing
    [anEncoder drawPrimitives:aPrimType
                  vertexStart:0
                  vertexCount:static_cast<NSUInteger>(myNbVertices)];
  }
}

// =======================================================================
// function : MetalPrimitiveType
// purpose  : Return Metal primitive type
// =======================================================================
MTLPrimitiveType Metal_PrimitiveArray::MetalPrimitiveType() const
{
  switch (myType)
  {
    case Graphic3d_TOPA_POINTS:
      return MTLPrimitiveTypePoint;
    case Graphic3d_TOPA_SEGMENTS:
      return MTLPrimitiveTypeLine;
    case Graphic3d_TOPA_POLYLINES:
      return MTLPrimitiveTypeLineStrip;
    case Graphic3d_TOPA_TRIANGLES:
      return MTLPrimitiveTypeTriangle;
    case Graphic3d_TOPA_TRIANGLESTRIPS:
      return MTLPrimitiveTypeTriangleStrip;
    case Graphic3d_TOPA_TRIANGLEFANS:
      // Metal doesn't support triangle fans, need to convert to triangles
      // For now, fall back to triangles (will need conversion)
      return MTLPrimitiveTypeTriangle;
    case Graphic3d_TOPA_LINES_ADJACENCY:
    case Graphic3d_TOPA_LINE_STRIP_ADJACENCY:
    case Graphic3d_TOPA_TRIANGLES_ADJACENCY:
    case Graphic3d_TOPA_TRIANGLE_STRIP_ADJACENCY:
    case Graphic3d_TOPA_QUADRANGLES:
    case Graphic3d_TOPA_QUADRANGLESTRIPS:
    case Graphic3d_TOPA_POLYGONS:
    default:
      return MTLPrimitiveTypeTriangle;
    case Graphic3d_TOPA_UNDEFINED:
      return MTLPrimitiveTypeTriangle;
  }
}
