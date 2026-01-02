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

#ifndef Metal_UniformBuffer_HeaderFile
#define Metal_UniformBuffer_HeaderFile

#include <Metal_Resource.hxx>
#include <Metal_Caps.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
#endif

class Metal_Context;

//! Uniform Buffer Object for shader uniform data with triple-buffering support.
//! Each frame uses a separate portion of the buffer to avoid GPU/CPU synchronization issues.
//! The buffer is organized as N copies of uniform data, where N = maxFramesInFlight.
class Metal_UniformBuffer : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_UniformBuffer, Metal_Resource)

public:

  //! Create uninitialized uniform buffer.
  Standard_EXPORT Metal_UniformBuffer();

  //! Destructor.
  Standard_EXPORT ~Metal_UniformBuffer() override;

  //! @return true if current object was initialized
  bool IsValid() const { return myBuffer != nullptr; }

  //! Return size of single uniform block in bytes.
  size_t BlockSize() const { return myBlockSize; }

  //! Return aligned block size (accounts for Metal alignment requirements).
  size_t AlignedBlockSize() const { return myAlignedBlockSize; }

  //! Return total buffer size in bytes.
  size_t TotalSize() const { return myTotalSize; }

  //! Return number of frames in flight (copies of data).
  int FramesInFlight() const { return myFramesInFlight; }

  //! Return estimated GPU memory usage.
  size_t EstimatedDataSize() const override { return myTotalSize; }

  //! Create uniform buffer for given block size.
  //! Creates enough space for maxFramesInFlight copies of the data.
  //! @param theCtx Metal context
  //! @param theBlockSize size of single uniform block in bytes
  //! @return true on success
  Standard_EXPORT bool Create(Metal_Context* theCtx, size_t theBlockSize);

  //! Update uniform data for current frame.
  //! @param theCtx Metal context (used to get current frame index)
  //! @param theData pointer to uniform data
  //! @param theSize size of data (must be <= BlockSize())
  //! @return true on success
  Standard_EXPORT bool Update(Metal_Context* theCtx,
                              const void* theData,
                              size_t theSize);

  //! Update uniform data for current frame with full block.
  //! @param theCtx Metal context
  //! @param theData pointer to uniform block (must be at least BlockSize() bytes)
  //! @return true on success
  bool Update(Metal_Context* theCtx, const void* theData)
  {
    return Update(theCtx, theData, myBlockSize);
  }

  //! Get offset for current frame's uniform block.
  //! @param theCtx Metal context
  //! @return offset in bytes from buffer start
  Standard_EXPORT size_t CurrentOffset(Metal_Context* theCtx) const;

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal buffer object.
  id<MTLBuffer> Buffer() const { return myBuffer; }
#endif

protected:

#ifdef __OBJC__
  id<MTLBuffer> myBuffer;        //!< Metal buffer object
#else
  void*         myBuffer;        //!< Metal buffer object (opaque)
#endif
  size_t myBlockSize;            //!< size of single uniform block
  size_t myAlignedBlockSize;     //!< aligned block size (256-byte aligned for Metal)
  size_t myTotalSize;            //!< total buffer size
  int    myFramesInFlight;       //!< number of frame copies
};

#endif // Metal_UniformBuffer_HeaderFile
