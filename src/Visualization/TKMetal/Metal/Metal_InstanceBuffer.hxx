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

#ifndef Metal_InstanceBuffer_HeaderFile
#define Metal_InstanceBuffer_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <Standard_Type.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;

//! Structure for per-instance data.
//! This is the default layout for instance attributes.
//! Custom layouts can be used by providing raw data directly.
struct Metal_InstanceData
{
  float Transform[16];  //!< 4x4 transformation matrix (column-major)
  float Color[4];       //!< RGBA color multiplier
};

//! Metal buffer for storing per-instance data for hardware instancing.
//! Supports transforms, colors, and custom per-instance attributes.
class Metal_InstanceBuffer : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_InstanceBuffer, Standard_Transient)

public:

  //! Create an empty instance buffer.
  Standard_EXPORT Metal_InstanceBuffer();

  //! Destructor.
  Standard_EXPORT ~Metal_InstanceBuffer();

  //! Initialize the buffer with instance data.
  //! @param theCtx Metal context
  //! @param theInstanceCount number of instances
  //! @param theData instance data (array of Metal_InstanceData or raw data)
  //! @param theStride stride in bytes for each instance (0 = use sizeof(Metal_InstanceData))
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            int theInstanceCount,
                            const void* theData,
                            int theStride = 0);

  //! Initialize with Metal_InstanceData structures.
  //! @param theCtx Metal context
  //! @param theInstanceCount number of instances
  //! @param theData array of Metal_InstanceData structures
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            int theInstanceCount,
                            const Metal_InstanceData* theData);

  //! Update instance data in the buffer.
  //! @param theCtx Metal context
  //! @param theOffset offset in instances from start
  //! @param theCount number of instances to update
  //! @param theData new instance data
  //! @return true on success
  Standard_EXPORT bool Update(Metal_Context* theCtx,
                              int theOffset,
                              int theCount,
                              const void* theData);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return true if buffer is valid.
  bool IsValid() const { return myIsValid; }

  //! Return number of instances.
  int InstanceCount() const { return myInstanceCount; }

  //! Return stride in bytes per instance.
  int Stride() const { return myStride; }

#ifdef __OBJC__
  //! Return the Metal buffer.
  id<MTLBuffer> Buffer() const { return myBuffer; }
#endif

private:

#ifdef __OBJC__
  id<MTLBuffer> myBuffer;
#else
  void* myBuffer;
#endif

  int  myInstanceCount;  //!< number of instances
  int  myStride;         //!< bytes per instance
  bool myIsValid;        //!< validity flag
};

DEFINE_STANDARD_HANDLE(Metal_InstanceBuffer, Standard_Transient)

#endif // Metal_InstanceBuffer_HeaderFile
