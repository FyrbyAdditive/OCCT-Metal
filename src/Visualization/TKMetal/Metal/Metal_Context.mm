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

#include <Metal_Context.hxx>
#include <Message.hxx>
#include <Standard_Assert.hxx>

#import <Metal/Metal.h>
#import <dispatch/dispatch.h>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Context, Standard_Transient)

namespace
{
  //! Null handle for returning from GetResource.
  static const occ::handle<Metal_Resource> THE_NULL_RESOURCE;
}

// =======================================================================
// function : Metal_Context
// purpose  : Constructor
// =======================================================================
Metal_Context::Metal_Context(const occ::handle<Metal_Caps>& theCaps)
: myDevice(nil),
  myCommandQueue(nil),
  myDefaultLibrary(nil),
  myCurrentCmdBuffer(nil),
  myFrameSemaphore(nil),
  myCaps(theCaps),
  myMsgContext(Message::DefaultMessenger()),
  mySharedResources(new Metal_ResourcesMap()),
  myUnusedResources(new NCollection_List<occ::handle<Metal_Resource>>()),
  myMaxTexDim(4096),
  myMaxBufferLength(256 * 1024 * 1024),
  myMaxColorAttachments(8),
  myMaxMsaaSamples(8),
  myHasArgumentBuffersTier2(false),
  myHasRayTracing(false),
  myIsInitialized(false),
  myCurrentFrameIndex(0)
{
  if (myCaps.IsNull())
  {
    myCaps = new Metal_Caps();
  }
}

// =======================================================================
// function : ~Metal_Context
// purpose  : Destructor
// =======================================================================
Metal_Context::~Metal_Context()
{
  forcedRelease();
}

// =======================================================================
// function : forcedRelease
// purpose  : Release all resources
// =======================================================================
void Metal_Context::forcedRelease()
{
  // Release all shared resources
  if (!mySharedResources.IsNull())
  {
    for (Metal_ResourcesMap::Iterator anIter(*mySharedResources); anIter.More(); anIter.Next())
    {
      occ::handle<Metal_Resource>& aRes = anIter.ChangeValue();
      if (!aRes.IsNull())
      {
        aRes->Release(this);
        aRes.Nullify();
      }
    }
    mySharedResources->Clear();
  }

  // Release delayed resources
  ReleaseDelayed();

  // Release Metal objects
  if (myFrameSemaphore != nil)
  {
    // Wait for all frames to complete
    for (int i = 0; i < myCaps->maxFramesInFlight; ++i)
    {
      dispatch_semaphore_wait(myFrameSemaphore, DISPATCH_TIME_FOREVER);
    }
    // Signal back to restore semaphore state
    for (int i = 0; i < myCaps->maxFramesInFlight; ++i)
    {
      dispatch_semaphore_signal(myFrameSemaphore);
    }
    myFrameSemaphore = nil;
  }

  myCurrentCmdBuffer = nil;
  myDefaultLibrary = nil;
  myCommandQueue = nil;
  myDevice = nil;
  myIsInitialized = false;
}

// =======================================================================
// function : Share
// purpose  : Share resources with another context
// =======================================================================
void Metal_Context::Share(const occ::handle<Metal_Context>& theShareCtx)
{
  if (!theShareCtx.IsNull())
  {
    mySharedResources = theShareCtx->mySharedResources;
  }
}

// =======================================================================
// function : Init
// purpose  : Initialize Metal context
// =======================================================================
bool Metal_Context::Init(bool thePreferLowPower)
{
  if (myIsInitialized)
  {
    return true;
  }

  @autoreleasepool
  {
    // Get the Metal device
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    if (devices == nil || devices.count == 0)
    {
      myMsgContext->SendFail() << "Metal_Context: No Metal devices available";
      return false;
    }

    // Select device based on preference
    myDevice = nil;
    if (thePreferLowPower || myCaps->preferLowPowerGPU)
    {
      // Prefer integrated GPU
      for (id<MTLDevice> aDevice in devices)
      {
        if (aDevice.lowPower)
        {
          myDevice = aDevice;
          break;
        }
      }
    }

    // Fall back to default device if no low-power device found
    if (myDevice == nil)
    {
      myDevice = MTLCreateSystemDefaultDevice();
    }

    if (myDevice == nil)
    {
      myMsgContext->SendFail() << "Metal_Context: Failed to create Metal device";
      return false;
    }

    // Store device name
    myDeviceName = TCollection_AsciiString([myDevice.name UTF8String]);

    // Create command queue
    myCommandQueue = [myDevice newCommandQueue];
    if (myCommandQueue == nil)
    {
      myMsgContext->SendFail() << "Metal_Context: Failed to create command queue";
      myDevice = nil;
      return false;
    }

    // Try to load default shader library
    NSError* error = nil;
    myDefaultLibrary = [myDevice newDefaultLibrary];
    if (myDefaultLibrary == nil)
    {
      // Not a fatal error - shaders will be compiled from source
      myMsgContext->SendInfo() << "Metal_Context: No default shader library found";
    }

    // Create frame semaphore for triple-buffering
    myFrameSemaphore = dispatch_semaphore_create(myCaps->maxFramesInFlight);

    // Query device capabilities
    queryDeviceCaps();

    myIsInitialized = true;

    myMsgContext->SendInfo() << "Metal_Context: Initialized with device '" << myDeviceName << "'";

    return true;
  }
}

// =======================================================================
// function : queryDeviceCaps
// purpose  : Query device capabilities
// =======================================================================
void Metal_Context::queryDeviceCaps()
{
  if (myDevice == nil)
  {
    return;
  }

  // Query maximum texture size
  if (@available(macOS 10.15, iOS 13.0, *))
  {
    if ([myDevice supportsFamily:MTLGPUFamilyApple3])
    {
      myMaxTexDim = 16384;
    }
    else
    {
      myMaxTexDim = 8192;
    }
  }
  else
  {
    myMaxTexDim = 8192;
  }

  // Query maximum buffer length
  myMaxBufferLength = myDevice.maxBufferLength;

  // Query argument buffers support
  if (@available(macOS 10.15, iOS 13.0, *))
  {
    myHasArgumentBuffersTier2 = (myDevice.argumentBuffersSupport == MTLArgumentBuffersTier2);
  }
  else
  {
    myHasArgumentBuffersTier2 = false;
  }

  // Query ray tracing support
  if (@available(macOS 11.0, iOS 14.0, *))
  {
    myHasRayTracing = myDevice.supportsRaytracing;
  }
  else
  {
    myHasRayTracing = false;
  }

  // Max color attachments is typically 8 for Metal
  myMaxColorAttachments = 8;

  // Query MSAA support
  myMaxMsaaSamples = 1;
  for (int samples = 8; samples >= 2; samples /= 2)
  {
    if ([myDevice supportsTextureSampleCount:samples])
    {
      myMaxMsaaSamples = samples;
      break;
    }
  }
}

// =======================================================================
// function : CreateCommandBuffer
// purpose  : Create a new command buffer
// =======================================================================
id<MTLCommandBuffer> Metal_Context::CreateCommandBuffer()
{
  if (myCommandQueue == nil)
  {
    return nil;
  }

  if (myCaps->contextDebug)
  {
    // Create with error tracking enabled
    MTLCommandBufferDescriptor* desc = [[MTLCommandBufferDescriptor alloc] init];
    desc.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
    return [myCommandQueue commandBufferWithDescriptor:desc];
  }
  else
  {
    return [myCommandQueue commandBuffer];
  }
}

// =======================================================================
// function : CurrentCommandBuffer
// purpose  : Return current command buffer (creates one if needed)
// =======================================================================
id<MTLCommandBuffer> Metal_Context::CurrentCommandBuffer()
{
  if (myCurrentCmdBuffer == nil)
  {
    myCurrentCmdBuffer = CreateCommandBuffer();
  }
  return myCurrentCmdBuffer;
}

// =======================================================================
// function : CommitAndWait
// purpose  : Commit command buffer and wait for completion
// =======================================================================
void Metal_Context::CommitAndWait()
{
  if (myCurrentCmdBuffer != nil)
  {
    [myCurrentCmdBuffer commit];
    [myCurrentCmdBuffer waitUntilCompleted];

    if (myCaps->contextDebug && myCurrentCmdBuffer.error != nil)
    {
      NSString* errStr = myCurrentCmdBuffer.error.localizedDescription;
      myMsgContext->SendWarning() << "Metal_Context: Command buffer error: "
                                   << [errStr UTF8String];
    }

    myCurrentCmdBuffer = nil;
  }
}

// =======================================================================
// function : Commit
// purpose  : Commit command buffer (non-blocking)
// =======================================================================
void Metal_Context::Commit()
{
  if (myCurrentCmdBuffer != nil)
  {
    [myCurrentCmdBuffer commit];
    myCurrentCmdBuffer = nil;
  }
}

// =======================================================================
// function : IsFormatSupported
// purpose  : Check if pixel format is supported
// =======================================================================
bool Metal_Context::IsFormatSupported(int thePixelFormat) const
{
  if (myDevice == nil)
  {
    return false;
  }

  // All standard formats are supported on modern Metal devices
  // Add specific format checks as needed
  return true;
}

// =======================================================================
// function : GetResource
// purpose  : Access shared resource by key
// =======================================================================
const occ::handle<Metal_Resource>& Metal_Context::GetResource(const TCollection_AsciiString& theKey) const
{
  if (!mySharedResources.IsNull())
  {
    const occ::handle<Metal_Resource>* aResource = mySharedResources->Seek(theKey);
    if (aResource != nullptr)
    {
      return *aResource;
    }
  }
  return THE_NULL_RESOURCE;
}

// =======================================================================
// function : ShareResource
// purpose  : Register shared resource
// =======================================================================
bool Metal_Context::ShareResource(const TCollection_AsciiString& theKey,
                                  const occ::handle<Metal_Resource>& theResource)
{
  if (theKey.IsEmpty() || theResource.IsNull())
  {
    return false;
  }

  return mySharedResources->Bind(theKey, theResource);
}

// =======================================================================
// function : ReleaseResource
// purpose  : Release shared resource
// =======================================================================
void Metal_Context::ReleaseResource(const TCollection_AsciiString& theKey,
                                    bool theToDelay)
{
  if (!mySharedResources.IsNull())
  {
    occ::handle<Metal_Resource>* aResource = mySharedResources->ChangeSeek(theKey);
    if (aResource != nullptr && aResource->GetRefCount() <= 2)
    {
      if (theToDelay)
      {
        myUnusedResources->Prepend(*aResource);
      }
      else
      {
        (*aResource)->Release(this);
      }
      mySharedResources->UnBind(theKey);
    }
  }
}

// =======================================================================
// function : ReleaseDelayed
// purpose  : Release delayed resources
// =======================================================================
void Metal_Context::ReleaseDelayed()
{
  if (!myUnusedResources.IsNull())
  {
    for (NCollection_List<occ::handle<Metal_Resource>>::Iterator anIter(*myUnusedResources);
         anIter.More(); anIter.Next())
    {
      occ::handle<Metal_Resource>& aRes = anIter.ChangeValue();
      if (!aRes.IsNull())
      {
        aRes->Release(this);
        aRes.Nullify();
      }
    }
    myUnusedResources->Clear();
  }
}

// =======================================================================
// function : AdvanceFrame
// purpose  : Advance to next frame
// =======================================================================
void Metal_Context::AdvanceFrame()
{
  myCurrentFrameIndex = (myCurrentFrameIndex + 1) % myCaps->maxFramesInFlight;
}

// =======================================================================
// function : WaitForFrame
// purpose  : Wait for frame to become available
// =======================================================================
void Metal_Context::WaitForFrame()
{
  if (myFrameSemaphore != nil)
  {
    dispatch_semaphore_wait(myFrameSemaphore, DISPATCH_TIME_FOREVER);
  }
}

// =======================================================================
// function : DiagnosticInformation
// purpose  : Fill diagnostic info dictionary
// =======================================================================
void Metal_Context::DiagnosticInformation(
  NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict,
  Graphic3d_DiagnosticInfo theFlags) const
{
  if ((theFlags & Graphic3d_DiagnosticInfo_Device) != 0)
  {
    theDict.Add("Renderer", myDeviceName);
    theDict.Add("Graphics API", "Metal");
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Limits) != 0)
  {
    theDict.Add("Max Texture Size", TCollection_AsciiString(myMaxTexDim));
    theDict.Add("Max Buffer Length", TCollection_AsciiString((int)(myMaxBufferLength / (1024 * 1024))) + " MB");
    theDict.Add("Max Color Attachments", TCollection_AsciiString(myMaxColorAttachments));
    theDict.Add("Max MSAA Samples", TCollection_AsciiString(myMaxMsaaSamples));
    theDict.Add("Argument Buffers Tier 2", myHasArgumentBuffersTier2 ? "Yes" : "No");
    theDict.Add("Ray Tracing", myHasRayTracing ? "Yes" : "No");
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Memory) != 0 && myDevice != nil)
  {
    if (@available(macOS 10.13, iOS 11.0, *))
    {
      NSUInteger currentSize = myDevice.currentAllocatedSize;
      theDict.Add("GPU Memory Allocated",
                  TCollection_AsciiString((int)(currentSize / (1024 * 1024))) + " MB");
    }
  }
}

// =======================================================================
// function : MemoryInfo
// purpose  : Return memory info string
// =======================================================================
TCollection_AsciiString Metal_Context::MemoryInfo() const
{
  TCollection_AsciiString aResult;
  if (myDevice != nil)
  {
    if (@available(macOS 10.13, iOS 11.0, *))
    {
      NSUInteger currentSize = myDevice.currentAllocatedSize;
      aResult = TCollection_AsciiString("GPU Memory: ")
              + TCollection_AsciiString((int)(currentSize / (1024 * 1024))) + " MB";
    }
  }
  return aResult;
}
