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

#ifndef Metal_IndexBuffer_HeaderFile
#define Metal_IndexBuffer_HeaderFile

#include <Metal_Buffer.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;

//! Index type for Metal index buffers.
enum Metal_IndexType
{
  Metal_IndexType_UInt16 = 0, //!< 16-bit unsigned integer indices
  Metal_IndexType_UInt32 = 1  //!< 32-bit unsigned integer indices
};

//! Index Buffer Object for storing index data.
//! Wraps MTLBuffer for indexed drawing operations.
class Metal_IndexBuffer : public Metal_Buffer
{
  DEFINE_STANDARD_RTTIEXT(Metal_IndexBuffer, Metal_Buffer)

public:

  //! Create uninitialized index buffer.
  Standard_EXPORT Metal_IndexBuffer();

  //! Destructor.
  Standard_EXPORT ~Metal_IndexBuffer() override;

  //! Return index type.
  Metal_IndexType IndexType() const { return myIndexType; }

  //! Return number of indices.
  int NbIndices() const { return myElemsNb; }

  //! Initialize index buffer with 16-bit unsigned integer indices.
  //! @param theCtx Metal context
  //! @param theNbIndices number of indices
  //! @param theData pointer to index data
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            int theNbIndices,
                            const unsigned short* theData);

  //! Initialize index buffer with 32-bit unsigned integer indices.
  //! @param theCtx Metal context
  //! @param theNbIndices number of indices
  //! @param theData pointer to index data
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            int theNbIndices,
                            const unsigned int* theData);

  //! Initialize index buffer with specified type.
  //! @param theCtx Metal context
  //! @param theType index type (UInt16 or UInt32)
  //! @param theNbIndices number of indices
  //! @param theData pointer to index data
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            Metal_IndexType theType,
                            int theNbIndices,
                            const void* theData);

#ifdef __OBJC__
  //! Return Metal index type enum.
  MTLIndexType MetalIndexType() const
  {
    return (myIndexType == Metal_IndexType_UInt16) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
  }
#endif

  //! Return size of single index in bytes.
  size_t IndexSize() const
  {
    return (myIndexType == Metal_IndexType_UInt16) ? sizeof(unsigned short) : sizeof(unsigned int);
  }

protected:

  Metal_IndexType myIndexType; //!< index data type
};

#endif // Metal_IndexBuffer_HeaderFile
