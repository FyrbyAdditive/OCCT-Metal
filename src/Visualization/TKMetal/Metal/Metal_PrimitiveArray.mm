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

#include <set>
#include <vector>
#include <algorithm>

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
  myNbEdgeIndices(0),
  myNbFanTriIndices(0),
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

    // Generate unique edge indices for triangle primitives
    if (myType == Graphic3d_TOPA_TRIANGLES)
    {
      buildEdgeIndices(theCtx);
    }

    // Convert triangle fans to triangle list (Metal doesn't support fans)
    if (myType == Graphic3d_TOPA_TRIANGLEFANS)
    {
      convertTriangleFan(theCtx);
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
  if (!myEdgeIndexBuffer.IsNull())
  {
    myEdgeIndexBuffer->Release(theCtx);
    myEdgeIndexBuffer.Nullify();
  }
  if (!myConvertedFanBuffer.IsNull())
  {
    myConvertedFanBuffer->Release(theCtx);
    myConvertedFanBuffer.Nullify();
  }
  myNbEdgeIndices = 0;
  myNbFanTriIndices = 0;

  myIsInitialized = false;
}

// =======================================================================
// function : buildEdgeIndices
// purpose  : Build edge index buffer from triangle indices
// =======================================================================
void Metal_PrimitiveArray::buildEdgeIndices(Metal_Context* theCtx)
{
  if (myIndices.IsNull() || myIndices->NbElements < 3)
  {
    return;
  }

  const int aNbTriangles = static_cast<int>(myIndices->NbElements) / 3;
  if (aNbTriangles == 0)
  {
    return;
  }

  // Edge represented as pair of vertex indices (always smaller index first)
  struct Edge
  {
    uint32_t v0, v1;
    Edge(uint32_t a, uint32_t b) : v0(std::min(a, b)), v1(std::max(a, b)) {}
    bool operator<(const Edge& other) const
    {
      return v0 < other.v0 || (v0 == other.v0 && v1 < other.v1);
    }
  };

  std::set<Edge> aUniqueEdges;

  // Extract edges from triangles
  const bool is16bit = (myIndices->Stride == 2);
  for (int iTri = 0; iTri < aNbTriangles; ++iTri)
  {
    uint32_t idx0, idx1, idx2;
    if (is16bit)
    {
      const uint16_t* aPtr = reinterpret_cast<const uint16_t*>(myIndices->Data()) + iTri * 3;
      idx0 = aPtr[0];
      idx1 = aPtr[1];
      idx2 = aPtr[2];
    }
    else
    {
      const uint32_t* aPtr = reinterpret_cast<const uint32_t*>(myIndices->Data()) + iTri * 3;
      idx0 = aPtr[0];
      idx1 = aPtr[1];
      idx2 = aPtr[2];
    }

    // Add 3 edges per triangle (duplicates will be filtered by set)
    aUniqueEdges.insert(Edge(idx0, idx1));
    aUniqueEdges.insert(Edge(idx1, idx2));
    aUniqueEdges.insert(Edge(idx2, idx0));
  }

  if (aUniqueEdges.empty())
  {
    return;
  }

  // Build edge index buffer (2 indices per edge for line primitive)
  myNbEdgeIndices = static_cast<int>(aUniqueEdges.size()) * 2;

  // Use 32-bit indices for the edge buffer (simpler, and edge count is typically much smaller)
  std::vector<uint32_t> anEdgeIndices;
  anEdgeIndices.reserve(myNbEdgeIndices);
  for (const Edge& anEdge : aUniqueEdges)
  {
    anEdgeIndices.push_back(anEdge.v0);
    anEdgeIndices.push_back(anEdge.v1);
  }

  // Create Metal index buffer for edges
  myEdgeIndexBuffer = new Metal_IndexBuffer();
  if (!myEdgeIndexBuffer->Init(theCtx, Metal_IndexType_UInt32,
                               myNbEdgeIndices,
                               anEdgeIndices.data()))
  {
    myEdgeIndexBuffer.Nullify();
    myNbEdgeIndices = 0;
  }
}

// =======================================================================
// function : convertTriangleFan
// purpose  : Convert triangle fan indices to triangle list indices
// =======================================================================
void Metal_PrimitiveArray::convertTriangleFan(Metal_Context* theCtx)
{
  // Triangle fan: first vertex is the center, subsequent vertices form triangles
  // Fan with N vertices = N-2 triangles = (N-2)*3 indices
  //
  // For indexed fan: indices[0] is center, then indices[1,2,3,...] are fan vertices
  // Triangle 0: indices[0], indices[1], indices[2]
  // Triangle 1: indices[0], indices[2], indices[3]
  // etc.
  //
  // For non-indexed fan: vertex 0 is center
  // Triangle 0: 0, 1, 2
  // Triangle 1: 0, 2, 3
  // etc.

  if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid() && myNbIndices >= 3)
  {
    // Indexed triangle fan
    const int aNbTriangles = myNbIndices - 2;
    if (aNbTriangles <= 0)
    {
      return;
    }

    myNbFanTriIndices = aNbTriangles * 3;
    std::vector<uint32_t> aTriIndices;
    aTriIndices.reserve(myNbFanTriIndices);

    const bool is16bit = (myIndices->Stride == 2);

    // Get center vertex index
    uint32_t centerIdx;
    if (is16bit)
    {
      centerIdx = reinterpret_cast<const uint16_t*>(myIndices->Data())[0];
    }
    else
    {
      centerIdx = reinterpret_cast<const uint32_t*>(myIndices->Data())[0];
    }

    // Build triangles from fan
    for (int iTri = 0; iTri < aNbTriangles; ++iTri)
    {
      uint32_t idx1, idx2;
      if (is16bit)
      {
        const uint16_t* aPtr = reinterpret_cast<const uint16_t*>(myIndices->Data());
        idx1 = aPtr[iTri + 1];
        idx2 = aPtr[iTri + 2];
      }
      else
      {
        const uint32_t* aPtr = reinterpret_cast<const uint32_t*>(myIndices->Data());
        idx1 = aPtr[iTri + 1];
        idx2 = aPtr[iTri + 2];
      }

      aTriIndices.push_back(centerIdx);
      aTriIndices.push_back(idx1);
      aTriIndices.push_back(idx2);
    }

    // Create converted index buffer
    myConvertedFanBuffer = new Metal_IndexBuffer();
    if (!myConvertedFanBuffer->Init(theCtx, Metal_IndexType_UInt32,
                                    myNbFanTriIndices,
                                    aTriIndices.data()))
    {
      myConvertedFanBuffer.Nullify();
      myNbFanTriIndices = 0;
    }
  }
  else if (myNbVertices >= 3)
  {
    // Non-indexed triangle fan
    const int aNbTriangles = myNbVertices - 2;
    if (aNbTriangles <= 0)
    {
      return;
    }

    myNbFanTriIndices = aNbTriangles * 3;
    std::vector<uint32_t> aTriIndices;
    aTriIndices.reserve(myNbFanTriIndices);

    // Vertex 0 is center
    for (int iTri = 0; iTri < aNbTriangles; ++iTri)
    {
      aTriIndices.push_back(0);                     // center
      aTriIndices.push_back(uint32_t(iTri + 1));    // vertex i+1
      aTriIndices.push_back(uint32_t(iTri + 2));    // vertex i+2
    }

    // Create converted index buffer
    myConvertedFanBuffer = new Metal_IndexBuffer();
    if (!myConvertedFanBuffer->Init(theCtx, Metal_IndexType_UInt32,
                                    myNbFanTriIndices,
                                    aTriIndices.data()))
    {
      myConvertedFanBuffer.Nullify();
      myNbFanTriIndices = 0;
    }
  }
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

  // For triangle fans, use the converted triangle list buffer if available
  if (myType == Graphic3d_TOPA_TRIANGLEFANS &&
      !myConvertedFanBuffer.IsNull() && myConvertedFanBuffer->IsValid())
  {
    [anEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:static_cast<NSUInteger>(myNbFanTriIndices)
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:myConvertedFanBuffer->Buffer()
                   indexBufferOffset:0];
  }
  else if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
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
// function : RenderInstanced
// purpose  : Render the primitive array with hardware instancing
// =======================================================================
void Metal_PrimitiveArray::RenderInstanced(Metal_Workspace* theWorkspace,
                                           const occ::handle<Metal_InstanceBuffer>& theInstanceBuffer,
                                           int theInstanceBufferIndex) const
{
  if (!myIsInitialized || theWorkspace == nullptr)
  {
    return;
  }

  if (theInstanceBuffer.IsNull() || !theInstanceBuffer->IsValid())
  {
    // Fall back to single instance if no instance buffer
    Render(theWorkspace);
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

  // Bind instance buffer at specified index
  [anEncoder setVertexBuffer:theInstanceBuffer->Buffer()
                      offset:0
                     atIndex:theInstanceBufferIndex];

  // Draw with instancing
  MTLPrimitiveType aPrimType = MetalPrimitiveType();
  NSUInteger anInstanceCount = static_cast<NSUInteger>(theInstanceBuffer->InstanceCount());

  if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
  {
    // Indexed instanced drawing
    MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
    [anEncoder drawIndexedPrimitives:aPrimType
                          indexCount:static_cast<NSUInteger>(myNbIndices)
                           indexType:anIndexType
                         indexBuffer:myIndexBuffer->Buffer()
                   indexBufferOffset:0
                       instanceCount:anInstanceCount];
  }
  else
  {
    // Non-indexed instanced drawing
    [anEncoder drawPrimitives:aPrimType
                  vertexStart:0
                  vertexCount:static_cast<NSUInteger>(myNbVertices)
                instanceCount:anInstanceCount];
  }
}

// =======================================================================
// function : RenderEdges
// purpose  : Render edges of the primitive array
// =======================================================================
void Metal_PrimitiveArray::RenderEdges(Metal_Workspace* theWorkspace) const
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

  // Bind vertex buffers (same as regular render)
  int aBufferIdx = 0;
  if (!myPositionVbo.IsNull() && myPositionVbo->IsValid())
  {
    [anEncoder setVertexBuffer:myPositionVbo->Buffer()
                        offset:0
                       atIndex:aBufferIdx++];
  }

  // For edge rendering, we handle different primitive types differently
  switch (myType)
  {
    case Graphic3d_TOPA_TRIANGLES:
    {
      // For triangles, render edges as lines
      // Prefer using pre-built unique edge buffer if available
      if (!myEdgeIndexBuffer.IsNull() && myEdgeIndexBuffer->IsValid() && myNbEdgeIndices > 0)
      {
        // Use unique edge buffer - each edge drawn once as a line segment
        [anEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
                              indexCount:static_cast<NSUInteger>(myNbEdgeIndices)
                               indexType:MTLIndexTypeUInt32
                             indexBuffer:myEdgeIndexBuffer->Buffer()
                       indexBufferOffset:0];
      }
      else if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
      {
        // Fallback: use triangle fill mode lines (draws shared edges twice)
        MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
        [anEncoder setTriangleFillMode:MTLTriangleFillModeLines];

        [anEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:static_cast<NSUInteger>(myNbIndices)
                               indexType:anIndexType
                             indexBuffer:myIndexBuffer->Buffer()
                       indexBufferOffset:0];

        [anEncoder setTriangleFillMode:MTLTriangleFillModeFill];
      }
      else
      {
        // Non-indexed triangles fallback
        [anEncoder setTriangleFillMode:MTLTriangleFillModeLines];

        [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:static_cast<NSUInteger>(myNbVertices)];

        [anEncoder setTriangleFillMode:MTLTriangleFillModeFill];
      }
      break;
    }
    case Graphic3d_TOPA_TRIANGLESTRIPS:
    case Graphic3d_TOPA_TRIANGLEFANS:
    {
      // Use wireframe mode for triangle strips/fans
      [anEncoder setTriangleFillMode:MTLTriangleFillModeLines];

      if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
      {
        MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
        [anEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
                              indexCount:static_cast<NSUInteger>(myNbIndices)
                               indexType:anIndexType
                             indexBuffer:myIndexBuffer->Buffer()
                       indexBufferOffset:0];
      }
      else
      {
        [anEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                      vertexStart:0
                      vertexCount:static_cast<NSUInteger>(myNbVertices)];
      }

      [anEncoder setTriangleFillMode:MTLTriangleFillModeFill];
      break;
    }
    case Graphic3d_TOPA_SEGMENTS:
    case Graphic3d_TOPA_POLYLINES:
    {
      // Lines are already edges, just render them normally
      MTLPrimitiveType aPrimType = (myType == Graphic3d_TOPA_SEGMENTS)
                                 ? MTLPrimitiveTypeLine
                                 : MTLPrimitiveTypeLineStrip;

      if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
      {
        MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
        [anEncoder drawIndexedPrimitives:aPrimType
                              indexCount:static_cast<NSUInteger>(myNbIndices)
                               indexType:anIndexType
                             indexBuffer:myIndexBuffer->Buffer()
                       indexBufferOffset:0];
      }
      else
      {
        [anEncoder drawPrimitives:aPrimType
                      vertexStart:0
                      vertexCount:static_cast<NSUInteger>(myNbVertices)];
      }
      break;
    }
    default:
      // For other types, use wireframe mode
      [anEncoder setTriangleFillMode:MTLTriangleFillModeLines];
      if (!myIndexBuffer.IsNull() && myIndexBuffer->IsValid())
      {
        MTLIndexType anIndexType = myIndexBuffer->MetalIndexType();
        [anEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:static_cast<NSUInteger>(myNbIndices)
                               indexType:anIndexType
                             indexBuffer:myIndexBuffer->Buffer()
                       indexBufferOffset:0];
      }
      else
      {
        [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:static_cast<NSUInteger>(myNbVertices)];
      }
      [anEncoder setTriangleFillMode:MTLTriangleFillModeFill];
      break;
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
