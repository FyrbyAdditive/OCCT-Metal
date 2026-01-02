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

#ifndef Metal_VertexBuffer_HeaderFile
#define Metal_VertexBuffer_HeaderFile

#include <Metal_Buffer.hxx>
#include <Graphic3d_Buffer.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;

//! Vertex attribute format for Metal vertex descriptors.
enum Metal_VertexFormat
{
  Metal_VertexFormat_Invalid = 0,
  Metal_VertexFormat_Float,
  Metal_VertexFormat_Float2,
  Metal_VertexFormat_Float3,
  Metal_VertexFormat_Float4,
  Metal_VertexFormat_Half2,
  Metal_VertexFormat_Half4,
  Metal_VertexFormat_Int,
  Metal_VertexFormat_Int2,
  Metal_VertexFormat_Int3,
  Metal_VertexFormat_Int4,
  Metal_VertexFormat_UChar4,
  Metal_VertexFormat_UChar4Normalized
};

//! Vertex Buffer Object for storing vertex attribute data.
//! This class wraps MTLBuffer specifically for vertex attributes
//! and provides methods to configure MTLVertexDescriptor.
class Metal_VertexBuffer : public Metal_Buffer
{
  DEFINE_STANDARD_RTTIEXT(Metal_VertexBuffer, Metal_Buffer)

public:

  //! Create uninitialized vertex buffer.
  Standard_EXPORT Metal_VertexBuffer();

  //! Destructor.
  Standard_EXPORT ~Metal_VertexBuffer() override;

  //! Return vertex format suitable for this buffer.
  Metal_VertexFormat VertexFormat() const { return myVertexFormat; }

  //! Return stride between vertices in bytes.
  size_t Stride() const { return myStride; }

  //! Initialize vertex buffer with position data (3 floats per vertex).
  //! @param theCtx Metal context
  //! @param theNbVertices number of vertices
  //! @param theData pointer to position data (x,y,z per vertex)
  //! @return true on success
  Standard_EXPORT bool InitPositions(Metal_Context* theCtx,
                                     int theNbVertices,
                                     const float* theData);

  //! Initialize vertex buffer with normal data (3 floats per vertex).
  Standard_EXPORT bool InitNormals(Metal_Context* theCtx,
                                   int theNbVertices,
                                   const float* theData);

  //! Initialize vertex buffer with texture coordinate data (2 floats per vertex).
  Standard_EXPORT bool InitTexCoords(Metal_Context* theCtx,
                                     int theNbVertices,
                                     const float* theData);

  //! Initialize vertex buffer with color data (4 bytes per vertex, RGBA).
  Standard_EXPORT bool InitColors(Metal_Context* theCtx,
                                  int theNbVertices,
                                  const uint8_t* theData);

  //! Initialize vertex buffer with color data (4 floats per vertex, RGBA).
  Standard_EXPORT bool InitColorsFloat(Metal_Context* theCtx,
                                       int theNbVertices,
                                       const float* theData);

  //! Initialize from Graphic3d data type.
  //! @param theCtx Metal context
  //! @param theType data type from Graphic3d
  //! @param theStride stride between elements (0 = tightly packed)
  //! @param theNbElems number of elements
  //! @param theData pointer to data
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            Graphic3d_TypeOfData theType,
                            int theStride,
                            int theNbElems,
                            const void* theData);

#ifdef __OBJC__
  //! Return Metal vertex format enum value.
  MTLVertexFormat MetalVertexFormat() const;
#endif

  //! Convert Graphic3d_TypeOfData to Metal_VertexFormat.
  Standard_EXPORT static Metal_VertexFormat ToVertexFormat(Graphic3d_TypeOfData theType);

  //! Return size in bytes for given vertex format.
  Standard_EXPORT static size_t VertexFormatSize(Metal_VertexFormat theFormat);

protected:

  Metal_VertexFormat myVertexFormat; //!< vertex attribute format
  size_t             myStride;       //!< stride between vertices
};

#endif // Metal_VertexBuffer_HeaderFile
