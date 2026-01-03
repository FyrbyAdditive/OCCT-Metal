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

#ifndef Metal_ComputePipeline_HeaderFile
#define Metal_ComputePipeline_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;

//! Metal compute pipeline wrapper.
//! Encapsulates compute shader compilation and dispatch.
class Metal_ComputePipeline : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_ComputePipeline, Standard_Transient)

public:

  //! Create empty compute pipeline.
  Standard_EXPORT Metal_ComputePipeline();

  //! Destructor.
  Standard_EXPORT ~Metal_ComputePipeline();

  //! Initialize compute pipeline from Metal shader library and function name.
  //! @param theCtx Metal context
  //! @param theLibrary shader library containing the compute function
  //! @param theFunctionName name of the compute kernel function
  //! @return true on success
#ifdef __OBJC__
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            id<MTLLibrary> theLibrary,
                            NSString* theFunctionName);
#endif

  //! Initialize compute pipeline from source code.
  //! @param theCtx Metal context
  //! @param theSource Metal Shading Language source code
  //! @param theFunctionName name of the compute kernel function
  //! @return true on success
  Standard_EXPORT bool InitFromSource(Metal_Context* theCtx,
                                      const TCollection_AsciiString& theSource,
                                      const TCollection_AsciiString& theFunctionName);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return true if pipeline is valid.
  bool IsValid() const { return myIsValid; }

  //! Return thread execution width (threads per threadgroup, X dimension).
  int ThreadExecutionWidth() const { return myThreadExecutionWidth; }

  //! Return max threads per threadgroup.
  int MaxThreadsPerThreadgroup() const { return myMaxThreadsPerThreadgroup; }

#ifdef __OBJC__
  //! Return the compute pipeline state.
  id<MTLComputePipelineState> PipelineState() const { return myPipelineState; }

  //! Return optimal threadgroup size for a 2D grid.
  //! @param theWidth image width
  //! @param theHeight image height
  //! @return MTLSize with optimal threadgroup dimensions
  MTLSize OptimalThreadgroupSize2D(int theWidth, int theHeight) const;

  //! Return optimal threadgroup count for a 2D grid.
  //! @param theWidth image width
  //! @param theHeight image height
  //! @param theThreadgroupSize threadgroup size
  //! @return MTLSize with threadgroup count
  MTLSize ThreadgroupCount2D(int theWidth, int theHeight, MTLSize theThreadgroupSize) const;
#endif

private:

#ifdef __OBJC__
  id<MTLComputePipelineState> myPipelineState;
#else
  void* myPipelineState;
#endif

  int  myThreadExecutionWidth;      //!< optimal threads per threadgroup
  int  myMaxThreadsPerThreadgroup;  //!< max total threads per threadgroup
  bool myIsValid;                   //!< validity flag
};

DEFINE_STANDARD_HANDLE(Metal_ComputePipeline, Standard_Transient)

#endif // Metal_ComputePipeline_HeaderFile
