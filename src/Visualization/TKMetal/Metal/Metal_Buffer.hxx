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

#ifndef Metal_Buffer_HeaderFile
#define Metal_Buffer_HeaderFile

#include <Metal_Resource.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
#endif

class Metal_Context;

//! Metal storage mode for buffer allocation.
enum Metal_StorageMode
{
  Metal_StorageMode_Shared = 0,  //!< CPU and GPU access, not cached on GPU (unified memory)
  Metal_StorageMode_Managed = 1, //!< CPU and GPU access with explicit synchronization
  Metal_StorageMode_Private = 2  //!< GPU only access, optimal performance
};

//! Buffer Object - is a general storage object for arbitrary data (see sub-classes).
//! Wraps MTLBuffer for Metal GPU memory management.
class Metal_Buffer : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_Buffer, Metal_Resource)

public:

  //! Create uninitialized buffer.
  Standard_EXPORT Metal_Buffer();

  //! Destroy object.
  Standard_EXPORT ~Metal_Buffer() override;

  //! @return true if current object was initialized
  bool IsValid() const { return myBuffer != nullptr; }

  //! @return the number of components per generic vertex attribute.
  unsigned int GetComponentsNb() const { return myComponentsNb; }

  //! @return number of elements specified within ::Init()
  int GetElemsNb() const { return myElemsNb; }

  //! Overrides the number of elements.
  void SetElemsNb(int theNbElems) { myElemsNb = theNbElems; }

  //! @return data type size in bytes
  size_t GetDataTypeSize() const { return myDataTypeSize; }

  //! @return buffer size in bytes
  size_t GetSize() const { return mySize; }

  //! @return storage mode
  Metal_StorageMode StorageMode() const { return myStorageMode; }

  //! Return estimated GPU memory usage.
  size_t EstimatedDataSize() const override { return mySize; }

  //! Creates buffer with specified size.
  //! @param theCtx Metal context
  //! @param theSize buffer size in bytes
  //! @param theData pointer to data to copy (or nullptr for empty buffer)
  //! @param theMode storage mode
  //! @return true on success
  Standard_EXPORT bool Create(Metal_Context* theCtx,
                              size_t theSize,
                              const void* theData = nullptr,
                              Metal_StorageMode theMode = Metal_StorageMode_Shared);

  //! Initialize buffer with float data.
  //! @param theCtx Metal context
  //! @param theComponentsNb number of components per element (1-4)
  //! @param theElemsNb number of elements
  //! @param theData pointer to float data
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            unsigned int theComponentsNb,
                            int theElemsNb,
                            const float* theData);

  //! Initialize buffer with unsigned int data.
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            unsigned int theComponentsNb,
                            int theElemsNb,
                            const unsigned int* theData);

  //! Initialize buffer with unsigned short data.
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            unsigned int theComponentsNb,
                            int theElemsNb,
                            const unsigned short* theData);

  //! Initialize buffer with byte data.
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            unsigned int theComponentsNb,
                            int theElemsNb,
                            const uint8_t* theData);

  //! Update portion of buffer data.
  //! @param theCtx Metal context
  //! @param theElemFrom starting element index
  //! @param theElemsNb number of elements to update
  //! @param theData pointer to data
  //! @return true on success
  Standard_EXPORT bool SubData(Metal_Context* theCtx,
                               int theElemFrom,
                               int theElemsNb,
                               const void* theData);

  //! Read buffer contents back to CPU memory.
  //! @param theCtx Metal context
  //! @param theData pointer to destination buffer
  //! @param theSize size to read in bytes
  //! @param theOffset offset in buffer
  //! @return true on success
  Standard_EXPORT bool GetData(Metal_Context* theCtx,
                               void* theData,
                               size_t theSize,
                               size_t theOffset = 0) const;

  //! Destroy object - will release GPU memory if any.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal buffer object.
  id<MTLBuffer> Buffer() const { return myBuffer; }
#endif

protected:

  //! Initialize internal data from raw pointer.
  Standard_EXPORT bool initData(Metal_Context* theCtx,
                                unsigned int theComponentsNb,
                                int theElemsNb,
                                size_t theDataTypeSize,
                                const void* theData);

protected:

#ifdef __OBJC__
  id<MTLBuffer> myBuffer;       //!< Metal buffer object
#else
  void*         myBuffer;       //!< Metal buffer object (opaque)
#endif
  size_t            mySize;         //!< buffer size in bytes
  unsigned int      myComponentsNb; //!< number of components per element
  int               myElemsNb;      //!< number of elements
  size_t            myDataTypeSize; //!< size of data type in bytes
  Metal_StorageMode myStorageMode;  //!< storage mode
};

#endif // Metal_Buffer_HeaderFile
