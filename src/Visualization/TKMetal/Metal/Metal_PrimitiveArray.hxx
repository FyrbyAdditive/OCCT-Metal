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

#ifndef Metal_PrimitiveArray_HeaderFile
#define Metal_PrimitiveArray_HeaderFile

#include <Graphic3d_TypeOfPrimitiveArray.hxx>
#include <Graphic3d_Buffer.hxx>
#include <Graphic3d_IndexBuffer.hxx>
#include <Graphic3d_BoundBuffer.hxx>
#include <Metal_VertexBuffer.hxx>
#include <Metal_IndexBuffer.hxx>
#include <Metal_InstanceBuffer.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;
class Metal_Workspace;

//! Metal primitive array for rendering geometry.
class Metal_PrimitiveArray
{
public:

  //! Create primitive array.
  Standard_EXPORT Metal_PrimitiveArray(const Graphic3d_TypeOfPrimitiveArray theType,
                                       const occ::handle<Graphic3d_IndexBuffer>& theIndices,
                                       const occ::handle<Graphic3d_Buffer>& theAttribs,
                                       const occ::handle<Graphic3d_BoundBuffer>& theBounds);

  //! Destructor.
  Standard_EXPORT ~Metal_PrimitiveArray();

  //! Initialize Metal resources.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Render the primitive array.
  Standard_EXPORT void Render(Metal_Workspace* theWorkspace) const;

  //! Render the primitive array with hardware instancing.
  //! @param theWorkspace workspace for rendering
  //! @param theInstanceBuffer buffer containing per-instance data
  //! @param theInstanceBufferIndex Metal buffer index for instance data
  Standard_EXPORT void RenderInstanced(Metal_Workspace* theWorkspace,
                                       const occ::handle<Metal_InstanceBuffer>& theInstanceBuffer,
                                       int theInstanceBufferIndex = 10) const;

  //! Render edges of the primitive array (for triangle primitives, renders as lines).
  Standard_EXPORT void RenderEdges(Metal_Workspace* theWorkspace) const;

  //! Return true if resources are initialized.
  bool IsInitialized() const { return myIsInitialized; }

  //! Return primitive type.
  Graphic3d_TypeOfPrimitiveArray Type() const { return myType; }

  //! Return number of vertices.
  int NbVertices() const { return myNbVertices; }

  //! Return number of indices (0 if not indexed).
  int NbIndices() const { return myNbIndices; }

#ifdef __OBJC__
  //! Return Metal primitive type.
  MTLPrimitiveType MetalPrimitiveType() const;
#endif

protected:

  //! Build edge index buffer from triangle indices for wireframe rendering.
  //! Extracts unique edges from triangle mesh.
  void buildEdgeIndices(Metal_Context* theCtx);

  //! Convert triangle fan indices to triangle list indices.
  //! Metal doesn't support triangle fans, so we expand them.
  void convertTriangleFan(Metal_Context* theCtx);

protected:

  Graphic3d_TypeOfPrimitiveArray       myType;           //!< primitive type
  occ::handle<Graphic3d_Buffer>        myAttribs;        //!< CPU attribute data
  occ::handle<Graphic3d_IndexBuffer>   myIndices;        //!< CPU index data
  occ::handle<Graphic3d_BoundBuffer>   myBounds;         //!< CPU bounds data

  occ::handle<Metal_VertexBuffer>      myPositionVbo;    //!< position buffer
  occ::handle<Metal_VertexBuffer>      myNormalVbo;      //!< normal buffer
  occ::handle<Metal_VertexBuffer>      myColorVbo;       //!< color buffer
  occ::handle<Metal_VertexBuffer>      myTexCoordVbo;    //!< texture coordinate buffer
  occ::handle<Metal_IndexBuffer>       myIndexBuffer;         //!< index buffer
  occ::handle<Metal_IndexBuffer>       myEdgeIndexBuffer;     //!< edge index buffer for unique edges
  occ::handle<Metal_IndexBuffer>       myConvertedFanBuffer;  //!< converted triangle fan -> triangles

  int  myNbVertices;       //!< number of vertices
  int  myNbIndices;        //!< number of indices
  int  myNbEdgeIndices;    //!< number of edge indices (unique edges * 2)
  int  myNbFanTriIndices;  //!< number of converted triangle fan indices
  bool myIsInitialized;    //!< initialization flag
};

#endif // Metal_PrimitiveArray_HeaderFile
