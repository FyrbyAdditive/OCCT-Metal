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

#include <Metal_ComputePipeline.hxx>
#include <Metal_Context.hxx>
#include <Message.hxx>
#include <Message_Messenger.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_ComputePipeline, Standard_Transient)

// =======================================================================
// function : Metal_ComputePipeline
// purpose  : Constructor
// =======================================================================
Metal_ComputePipeline::Metal_ComputePipeline()
: myPipelineState(nil),
  myThreadExecutionWidth(32),
  myMaxThreadsPerThreadgroup(1024),
  myIsValid(false)
{
}

// =======================================================================
// function : ~Metal_ComputePipeline
// purpose  : Destructor
// =======================================================================
Metal_ComputePipeline::~Metal_ComputePipeline()
{
  Release(nullptr);
}

// =======================================================================
// function : Init
// purpose  : Initialize from library and function name
// =======================================================================
bool Metal_ComputePipeline::Init(Metal_Context* theCtx,
                                 id<MTLLibrary> theLibrary,
                                 NSString* theFunctionName)
{
  Release(theCtx);

  if (theCtx == nullptr || theLibrary == nil || theFunctionName == nil)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Get the compute function from the library
  id<MTLFunction> aFunction = [theLibrary newFunctionWithName:theFunctionName];
  if (aFunction == nil)
  {
    Message::SendFail() << "Metal_ComputePipeline: compute function '"
                        << [theFunctionName UTF8String] << "' not found in library";
    return false;
  }

  // Create the compute pipeline state
  NSError* anError = nil;
  myPipelineState = [aDevice newComputePipelineStateWithFunction:aFunction
                                                           error:&anError];

  if (myPipelineState == nil)
  {
    Message::SendFail() << "Metal_ComputePipeline: failed to create pipeline - "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Query execution properties
  myThreadExecutionWidth = static_cast<int>([myPipelineState threadExecutionWidth]);
  myMaxThreadsPerThreadgroup = static_cast<int>([myPipelineState maxTotalThreadsPerThreadgroup]);

  myIsValid = true;
  return true;
}

// =======================================================================
// function : InitFromSource
// purpose  : Initialize from source code
// =======================================================================
bool Metal_ComputePipeline::InitFromSource(Metal_Context* theCtx,
                                           const TCollection_AsciiString& theSource,
                                           const TCollection_AsciiString& theFunctionName)
{
  Release(theCtx);

  if (theCtx == nullptr || theSource.IsEmpty() || theFunctionName.IsEmpty())
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Compile the shader source
  NSString* aSource = [NSString stringWithUTF8String:theSource.ToCString()];
  NSError* anError = nil;

  MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
  anOptions.fastMathEnabled = YES;

  id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:aSource
                                                  options:anOptions
                                                    error:&anError];

  if (aLibrary == nil)
  {
    Message::SendFail() << "Metal_ComputePipeline: shader compilation failed - "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  NSString* aFunctionName = [NSString stringWithUTF8String:theFunctionName.ToCString()];
  return Init(theCtx, aLibrary, aFunctionName);
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_ComputePipeline::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (myPipelineState != nil)
  {
    myPipelineState = nil;
  }

  myThreadExecutionWidth = 32;
  myMaxThreadsPerThreadgroup = 1024;
  myIsValid = false;
}

// =======================================================================
// function : OptimalThreadgroupSize2D
// purpose  : Calculate optimal threadgroup size for 2D dispatch
// =======================================================================
MTLSize Metal_ComputePipeline::OptimalThreadgroupSize2D(int theWidth, int theHeight) const
{
  // Use thread execution width as one dimension
  int w = myThreadExecutionWidth;
  int h = myMaxThreadsPerThreadgroup / w;

  // Clamp to reasonable values
  if (w > theWidth)  w = theWidth;
  if (h > theHeight) h = theHeight;
  if (w < 1) w = 1;
  if (h < 1) h = 1;

  return MTLSizeMake(static_cast<NSUInteger>(w),
                     static_cast<NSUInteger>(h),
                     1);
}

// =======================================================================
// function : ThreadgroupCount2D
// purpose  : Calculate threadgroup count for 2D dispatch
// =======================================================================
MTLSize Metal_ComputePipeline::ThreadgroupCount2D(int theWidth, int theHeight,
                                                  MTLSize theThreadgroupSize) const
{
  // Calculate number of threadgroups needed to cover the image
  NSUInteger w = (static_cast<NSUInteger>(theWidth) + theThreadgroupSize.width - 1) / theThreadgroupSize.width;
  NSUInteger h = (static_cast<NSUInteger>(theHeight) + theThreadgroupSize.height - 1) / theThreadgroupSize.height;

  return MTLSizeMake(w, h, 1);
}
