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

// Import Apple frameworks first to avoid Handle name conflicts with Carbon
#import <TargetConditionals.h>
#import <Metal/Metal.h>
#import <dispatch/dispatch.h>

// Now include OCCT headers
#include <Metal_Context.hxx>
#include <Metal_ShaderManager.hxx>
#include <Message.hxx>
#include <Standard_Assert.hxx>

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
  myDefaultPipeline(nil),
  myLinePipeline(nil),
  myWireframePipeline(nil),
  myBlendingPipeline(nil),
  myGradientPipeline(nil),
  myTexturedBackgroundPipeline(nil),
  myDefaultDepthStencilState(nil),
  myTransparentDepthStencilState(nil),
  myFrameSemaphore(nil),
  myCaps(theCaps),
  myMsgContext(Message::DefaultMessenger()),
  mySharedResources(new Metal_ResourcesMap()),
  myUnusedResources(new Metal_ResourcesList()),
  myMaxTexDim(4096),
  myMaxBufferLength(256 * 1024 * 1024),
  myMaxColorAttachments(8),
  myMaxMsaaSamples(8),
  myHasArgumentBuffersTier2(false),
  myHasRayTracing(false),
  myIsInitialized(false),
  myCurrentFrameIndex(0),
  myDepthFunc(MTLCompareFunctionLess),
  myDepthMask(true),
  myBlendEnabled(false),
  myBlendSrcRGB(MTLBlendFactorOne),
  myBlendDstRGB(MTLBlendFactorZero),
  myBlendSrcAlpha(MTLBlendFactorOne),
  myBlendDstAlpha(MTLBlendFactorZero),
  myColorMask(true),
  myShaderManager(nullptr)
{
  myViewport[0] = 0;
  myViewport[1] = 0;
  myViewport[2] = 0;
  myViewport[3] = 0;
  myClearColor[0] = 0.0f;
  myClearColor[1] = 0.0f;
  myClearColor[2] = 0.0f;
  myClearColor[3] = 1.0f;
  myClearDepth = 1.0f;

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
  myDefaultPipeline = nil;
  myLinePipeline = nil;
  myWireframePipeline = nil;
  myBlendingPipeline = nil;
  myGradientPipeline = nil;
  myTexturedBackgroundPipeline = nil;
  myDefaultDepthStencilState = nil;
  myTransparentDepthStencilState = nil;
  myDefaultLibrary = nil;
  myCommandQueue = nil;
  myDevice = nil;

  // Delete shader manager
  delete myShaderManager;
  myShaderManager = nullptr;

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

    // Create shader manager for advanced shader support
    myShaderManager = new Metal_ShaderManager(this);

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
    // Add completion handler to signal semaphore when frame completes
    __block dispatch_semaphore_t blockSemaphore = myFrameSemaphore;
    [myCurrentCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> /* buffer */)
    {
      if (blockSemaphore != nil)
      {
        dispatch_semaphore_signal(blockSemaphore);
      }
    }];

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
    if (aResource != nullptr && !aResource->IsNull() && (*aResource)->GetRefCount() <= 2)
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
  if ((theFlags & Graphic3d_DiagnosticInfo_NativePlatform) != 0)
  {
    theDict.Add("Platform", "Apple Metal");
#if TARGET_OS_OSX
    theDict.Add("OS", "macOS");
#elif TARGET_OS_IOS
    theDict.Add("OS", "iOS");
#elif TARGET_OS_TV
    theDict.Add("OS", "tvOS");
#else
    theDict.Add("OS", "Unknown Apple OS");
#endif
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Device) != 0)
  {
    theDict.Add("GLvendor", "Apple");
    theDict.Add("GLdevice", myDeviceName);
    theDict.Add("Graphics API", "Metal");

    if (myDevice != nil)
    {
      // Device type
      if (myDevice.isLowPower)
      {
        theDict.Add("GPU Type", "Integrated (Low Power)");
      }
      else
      {
        theDict.Add("GPU Type", "Discrete");
      }

      // Headless (no display attached)
      if (myDevice.isHeadless)
      {
        theDict.Add("Headless", "Yes");
      }

      // Removable (eGPU)
      if (@available(macOS 10.15, iOS 13.0, *))
      {
        if (myDevice.isRemovable)
        {
          theDict.Add("Removable (eGPU)", "Yes");
        }
      }

      // Metal Feature Set / GPU Family
      if (@available(macOS 10.15, iOS 13.0, *))
      {
        // Check GPU families (Apple Silicon vs Intel/AMD)
        if ([myDevice supportsFamily:MTLGPUFamilyApple7])
        {
          theDict.Add("GPU Family", "Apple7 (M1 Pro/Max/Ultra or newer)");
        }
        else if ([myDevice supportsFamily:MTLGPUFamilyApple6])
        {
          theDict.Add("GPU Family", "Apple6 (A14/M1)");
        }
        else if ([myDevice supportsFamily:MTLGPUFamilyApple5])
        {
          theDict.Add("GPU Family", "Apple5 (A12/A13)");
        }
        else if ([myDevice supportsFamily:MTLGPUFamilyApple4])
        {
          theDict.Add("GPU Family", "Apple4 (A11)");
        }
        else if ([myDevice supportsFamily:MTLGPUFamilyMac2])
        {
          theDict.Add("GPU Family", "Mac2 (AMD/Intel discrete)");
        }
        else if ([myDevice supportsFamily:MTLGPUFamilyMac1])
        {
          theDict.Add("GPU Family", "Mac1 (Intel integrated)");
        }
        else
        {
          theDict.Add("GPU Family", "Common");
        }
      }

      // Recommended working set size
      if (@available(macOS 10.12, iOS 10.0, *))
      {
        NSUInteger workingSetSize = myDevice.recommendedMaxWorkingSetSize;
        theDict.Add("Recommended Working Set",
                    TCollection_AsciiString((int)(workingSetSize / (1024 * 1024))) + " MB");
      }

      // Registry ID (unique device identifier)
      theDict.Add("Registry ID", TCollection_AsciiString((Standard_Integer)myDevice.registryID));
    }
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Limits) != 0)
  {
    theDict.Add("Max Texture Size", TCollection_AsciiString(myMaxTexDim));
    theDict.Add("Max Cube Texture Size", TCollection_AsciiString(myMaxTexDim)); // Metal uses same limit
    theDict.Add("Max 3D Texture Size", TCollection_AsciiString(2048)); // Metal standard
    theDict.Add("Max Buffer Length", TCollection_AsciiString((int)(myMaxBufferLength / (1024 * 1024))) + " MB");
    theDict.Add("Max Color Attachments", TCollection_AsciiString(myMaxColorAttachments));
    theDict.Add("Max MSAA Samples", TCollection_AsciiString(myMaxMsaaSamples));
    theDict.Add("Max Threads Per Threadgroup", TCollection_AsciiString(1024)); // Metal standard
    theDict.Add("Max Threadgroup Memory", TCollection_AsciiString(32) + " KB"); // Metal standard

    if (myDevice != nil)
    {
      // Argument buffer tier
      if (@available(macOS 10.13, iOS 11.0, *))
      {
        MTLArgumentBuffersTier abTier = myDevice.argumentBuffersSupport;
        if (abTier == MTLArgumentBuffersTier2)
        {
          theDict.Add("Argument Buffers Tier", "2 (Full bindless)");
        }
        else
        {
          theDict.Add("Argument Buffers Tier", "1 (Basic)");
        }
      }

      // Read-write texture tier
      if (@available(macOS 10.13, iOS 11.0, *))
      {
        MTLReadWriteTextureTier rwTier = myDevice.readWriteTextureSupport;
        if (rwTier == MTLReadWriteTextureTier2)
        {
          theDict.Add("Read-Write Textures", "Tier 2 (All formats)");
        }
        else if (rwTier == MTLReadWriteTextureTier1)
        {
          theDict.Add("Read-Write Textures", "Tier 1 (Basic formats)");
        }
        else
        {
          theDict.Add("Read-Write Textures", "Not supported");
        }
      }
    }
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Extensions) != 0 && myDevice != nil)
  {
    // Metal feature support as "extensions"
    TCollection_AsciiString aFeatures;

    // Ray tracing support
    if (myHasRayTracing)
    {
      if (!aFeatures.IsEmpty()) aFeatures += ", ";
      aFeatures += "RayTracing";
    }

    // Argument buffers tier 2
    if (myHasArgumentBuffersTier2)
    {
      if (!aFeatures.IsEmpty()) aFeatures += ", ";
      aFeatures += "ArgumentBuffersTier2";
    }

    // Check various features
    if (@available(macOS 10.14, iOS 12.0, *))
    {
      if (myDevice.rasterOrderGroupsSupported)
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "RasterOrderGroups";
      }
    }

    if (@available(macOS 10.15, iOS 13.0, *))
    {
      if (myDevice.supportsPrimitiveMotionBlur)
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "PrimitiveMotionBlur";
      }

      if ([myDevice supportsShaderBarycentricCoordinates])
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "BarycentricCoordinates";
      }
    }

    if (@available(macOS 11.0, iOS 14.0, *))
    {
      if ([myDevice supportsFunctionPointers])
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "FunctionPointers";
      }
    }

    // 32-bit float filtering
    if (@available(macOS 10.14, iOS 12.0, *))
    {
      if (myDevice.supports32BitFloatFiltering)
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "Float32Filtering";
      }
    }

    // 32-bit MSAA
    if (@available(macOS 10.14, iOS 12.0, *))
    {
      if (myDevice.supports32BitMSAA)
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "MSAA32Bit";
      }
    }

    // Depth resolve (for MSAA depth)
    if (@available(macOS 10.14, iOS 12.0, *))
    {
      if (myDevice.supportsQueryTextureLOD)
      {
        if (!aFeatures.IsEmpty()) aFeatures += ", ";
        aFeatures += "QueryTextureLOD";
      }
    }

    if (!aFeatures.IsEmpty())
    {
      theDict.Add("Metal Features", aFeatures);
    }
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Memory) != 0 && myDevice != nil)
  {
    if (@available(macOS 10.13, iOS 11.0, *))
    {
      NSUInteger currentSize = myDevice.currentAllocatedSize;
      theDict.Add("GPU Memory Allocated",
                  TCollection_AsciiString((int)(currentSize / (1024 * 1024))) + " MB");
    }

    // Has unified memory (Apple Silicon)
    if (@available(macOS 10.15, iOS 13.0, *))
    {
      if (myDevice.hasUnifiedMemory)
      {
        theDict.Add("Unified Memory", "Yes (Apple Silicon)");
      }
      else
      {
        theDict.Add("Unified Memory", "No (Discrete GPU)");
      }
    }

    // Recommended working set
    if (@available(macOS 10.12, iOS 10.0, *))
    {
      NSUInteger workingSetSize = myDevice.recommendedMaxWorkingSetSize;
      theDict.Add("Max Working Set",
                  TCollection_AsciiString((int)(workingSetSize / (1024 * 1024))) + " MB");
    }
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_FrameBuffer) != 0)
  {
    // Note: actual framebuffer info would come from the view/window
    theDict.Add("Pixel Format", "BGRA8Unorm");
    theDict.Add("Depth Format", "Depth32Float");
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

// =======================================================================
// function : InitDefaultShaders
// purpose  : Initialize default shaders and pipeline
// =======================================================================
bool Metal_Context::InitDefaultShaders()
{
  if (myDevice == nil)
  {
    return false;
  }

  @autoreleasepool
  {
    // Basic shader source code embedded in the binary
    NSString* shaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
  float4x4 modelViewMatrix;
  float4x4 projectionMatrix;
  float4   color;
};

struct VertexOut {
  float4 position [[position]];
  float3 normal;
  float3 viewPosition;
};

vertex VertexOut vertex_basic(
  const device float3* positions [[buffer(0)]],
  constant Uniforms& uniforms    [[buffer(1)]],
  uint vid                       [[vertex_id]])
{
  VertexOut out;
  float4 worldPos = float4(positions[vid], 1.0);
  float4 viewPos = uniforms.modelViewMatrix * worldPos;
  out.position = uniforms.projectionMatrix * viewPos;
  out.viewPosition = viewPos.xyz;
  out.normal = float3(0.0, 0.0, 1.0);
  return out;
}

fragment float4 fragment_solid_color(
  VertexOut in                [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  return uniforms.color;
}

fragment float4 fragment_phong(
  VertexOut in                [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  float3 lightDir = normalize(float3(0.0, 0.0, 1.0));
  float3 N = normalize(in.normal);
  float NdotL = max(dot(N, lightDir), 0.0);
  float ambient = 0.3;
  float lighting = ambient + (1.0 - ambient) * NdotL;
  float4 color = uniforms.color;
  color.rgb *= lighting;
  return color;
}

// Gradient background structures
struct GradientUniforms {
  float4 colorFrom;
  float4 colorTo;
  int    fillMethod; // 0=none, 1=horizontal, 2=vertical, 3=diag1, 4=diag2, 5=corner1-4
  int    padding[3];
};

struct GradientVertexOut {
  float4 position [[position]];
  float2 texCoord;
};

// Full-screen quad vertex shader for gradient
vertex GradientVertexOut vertex_gradient(uint vid [[vertex_id]])
{
  // Generate full-screen triangle (3 vertices covering entire screen)
  GradientVertexOut out;
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2( 3.0, -1.0),
    float2(-1.0,  3.0)
  };
  out.position = float4(positions[vid], 0.0, 1.0);
  out.texCoord = positions[vid] * 0.5 + 0.5;
  return out;
}

// Gradient fragment shader
fragment float4 fragment_gradient(
  GradientVertexOut in [[stage_in]],
  constant GradientUniforms& uniforms [[buffer(0)]])
{
  float t = 0.0;

  switch (uniforms.fillMethod) {
    case 1: // Horizontal
      t = in.texCoord.x;
      break;
    case 2: // Vertical
      t = 1.0 - in.texCoord.y; // Flip Y so gradient goes top to bottom
      break;
    case 3: // Diagonal 1 (top-left to bottom-right)
      t = (in.texCoord.x + (1.0 - in.texCoord.y)) * 0.5;
      break;
    case 4: // Diagonal 2 (top-right to bottom-left)
      t = ((1.0 - in.texCoord.x) + (1.0 - in.texCoord.y)) * 0.5;
      break;
    case 5: // Corner 1
    case 6: // Corner 2
    case 7: // Corner 3
    case 8: // Corner 4
      // Radial-like from corner
      t = length(in.texCoord - float2(0.0, 1.0));
      t = saturate(t / 1.414); // Normalize by diagonal length
      break;
    default: // None or unknown - just use first color
      return uniforms.colorFrom;
  }

  return mix(uniforms.colorFrom, uniforms.colorTo, t);
}

// Textured background structures
struct TexturedBackgroundUniforms {
  float2 textureScale;
  float2 textureOffset;
  float2 viewportSize;
  int    fillMethod; // 0=stretch, 1=tile, 2=center
  int    padding;
};

// Full-screen quad vertex shader for textured background
vertex GradientVertexOut vertex_textured_background(uint vid [[vertex_id]])
{
  // Generate full-screen triangle (3 vertices covering entire screen)
  GradientVertexOut out;
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2( 3.0, -1.0),
    float2(-1.0,  3.0)
  };
  out.position = float4(positions[vid], 0.0, 1.0);
  out.texCoord = positions[vid] * 0.5 + 0.5;
  return out;
}

// Textured background fragment shader
fragment float4 fragment_textured_background(
  GradientVertexOut in [[stage_in]],
  constant TexturedBackgroundUniforms& uniforms [[buffer(0)]],
  texture2d<float> backgroundTexture [[texture(0)]],
  sampler textureSampler [[sampler(0)]])
{
  float2 uv = in.texCoord;

  // Apply fill method
  switch (uniforms.fillMethod) {
    case 0: // Stretch - UV goes from 0 to 1, default behavior
      uv = uv * uniforms.textureScale + uniforms.textureOffset;
      break;
    case 1: // Tile - repeat texture based on viewport/texture ratio
      uv = uv * uniforms.textureScale + uniforms.textureOffset;
      break;
    case 2: // Center - center texture at original size
      {
        // Center the texture
        float2 center = float2(0.5, 0.5);
        uv = (uv - center) * uniforms.textureScale + center + uniforms.textureOffset;
        // Clamp to check if we're outside the texture
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
          return float4(0.0, 0.0, 0.0, 1.0); // Background color for areas outside texture
        }
      }
      break;
  }

  // Flip Y coordinate for proper image orientation
  uv.y = 1.0 - uv.y;

  return backgroundTexture.sample(textureSampler, uv);
}
)";

    NSError* error = nil;

    // Compile shader library from source
    id<MTLLibrary> aLibrary = [myDevice newLibraryWithSource:shaderSource
                                                     options:nil
                                                       error:&error];
    if (aLibrary == nil)
    {
      if (error != nil)
      {
        myMsgContext->SendFail() << "Metal_Context: Shader compilation failed: "
                                 << [[error localizedDescription] UTF8String];
      }
      return false;
    }

    // Get shader functions
    id<MTLFunction> vertexFunc = [aLibrary newFunctionWithName:@"vertex_basic"];
    id<MTLFunction> fragmentFunc = [aLibrary newFunctionWithName:@"fragment_solid_color"];

    if (vertexFunc == nil || fragmentFunc == nil)
    {
      myMsgContext->SendFail() << "Metal_Context: Failed to find shader functions";
      return false;
    }

    // Create render pipeline descriptor
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    // Enable alpha blending
    pipelineDesc.colorAttachments[0].blendingEnabled = YES;
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    // Create pipeline state
    myDefaultPipeline = [myDevice newRenderPipelineStateWithDescriptor:pipelineDesc
                                                                 error:&error];
    if (myDefaultPipeline == nil)
    {
      if (error != nil)
      {
        myMsgContext->SendFail() << "Metal_Context: Pipeline creation failed: "
                                 << [[error localizedDescription] UTF8String];
      }
      return false;
    }

    // Create line pipeline (same shaders, but will use MTLPrimitiveTypeLine)
    // The pipeline itself is the same, but we create a separate one for clarity
    // and potential future line-specific shader modifications
    myLinePipeline = [myDevice newRenderPipelineStateWithDescriptor:pipelineDesc
                                                              error:&error];
    if (myLinePipeline == nil)
    {
      myMsgContext->SendWarning() << "Metal_Context: Line pipeline creation failed, using default";
      myLinePipeline = myDefaultPipeline;
    }

    // Create wireframe pipeline (for rendering triangles as lines)
    // Same as default pipeline - wireframe mode is controlled via encoder settings
    myWireframePipeline = [myDevice newRenderPipelineStateWithDescriptor:pipelineDesc
                                                                   error:&error];
    if (myWireframePipeline == nil)
    {
      myMsgContext->SendWarning() << "Metal_Context: Wireframe pipeline creation failed, using default";
      myWireframePipeline = myDefaultPipeline;
    }

    // Create blending pipeline for transparent objects
    // Uses standard alpha blending (already enabled in pipelineDesc)
    myBlendingPipeline = [myDevice newRenderPipelineStateWithDescriptor:pipelineDesc
                                                                  error:&error];
    if (myBlendingPipeline == nil)
    {
      myMsgContext->SendWarning() << "Metal_Context: Blending pipeline creation failed, using default";
      myBlendingPipeline = myDefaultPipeline;
    }

    // Create gradient background pipeline
    id<MTLFunction> gradientVertexFunc = [aLibrary newFunctionWithName:@"vertex_gradient"];
    id<MTLFunction> gradientFragmentFunc = [aLibrary newFunctionWithName:@"fragment_gradient"];

    if (gradientVertexFunc != nil && gradientFragmentFunc != nil)
    {
      MTLRenderPipelineDescriptor* gradientPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
      gradientPipelineDesc.vertexFunction = gradientVertexFunc;
      gradientPipelineDesc.fragmentFunction = gradientFragmentFunc;
      gradientPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
      // No depth attachment for gradient - it's a background
      gradientPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

      myGradientPipeline = [myDevice newRenderPipelineStateWithDescriptor:gradientPipelineDesc
                                                                    error:&error];
      if (myGradientPipeline == nil)
      {
        myMsgContext->SendWarning() << "Metal_Context: Gradient pipeline creation failed";
      }
    }
    else
    {
      myMsgContext->SendWarning() << "Metal_Context: Gradient shader functions not found";
    }

    // Create textured background pipeline
    id<MTLFunction> texturedBgVertexFunc = [aLibrary newFunctionWithName:@"vertex_textured_background"];
    id<MTLFunction> texturedBgFragmentFunc = [aLibrary newFunctionWithName:@"fragment_textured_background"];

    if (texturedBgVertexFunc != nil && texturedBgFragmentFunc != nil)
    {
      MTLRenderPipelineDescriptor* texturedBgPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
      texturedBgPipelineDesc.vertexFunction = texturedBgVertexFunc;
      texturedBgPipelineDesc.fragmentFunction = texturedBgFragmentFunc;
      texturedBgPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
      texturedBgPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

      myTexturedBackgroundPipeline = [myDevice newRenderPipelineStateWithDescriptor:texturedBgPipelineDesc
                                                                              error:&error];
      if (myTexturedBackgroundPipeline == nil)
      {
        myMsgContext->SendWarning() << "Metal_Context: Textured background pipeline creation failed";
      }
    }
    else
    {
      myMsgContext->SendWarning() << "Metal_Context: Textured background shader functions not found";
    }

    // Create depth-stencil state
    MTLDepthStencilDescriptor* depthDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;

    myDefaultDepthStencilState = [myDevice newDepthStencilStateWithDescriptor:depthDesc];
    if (myDefaultDepthStencilState == nil)
    {
      myMsgContext->SendFail() << "Metal_Context: Depth-stencil state creation failed";
      return false;
    }

    // Create depth-stencil state for transparent objects (depth test but no write)
    MTLDepthStencilDescriptor* transparentDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
    transparentDepthDesc.depthCompareFunction = MTLCompareFunctionLess;
    transparentDepthDesc.depthWriteEnabled = NO; // Key difference: don't write to depth buffer

    myTransparentDepthStencilState = [myDevice newDepthStencilStateWithDescriptor:transparentDepthDesc];
    if (myTransparentDepthStencilState == nil)
    {
      myMsgContext->SendWarning() << "Metal_Context: Transparent depth-stencil state creation failed, using default";
      myTransparentDepthStencilState = myDefaultDepthStencilState;
    }

    myMsgContext->SendInfo() << "Metal_Context: Default shaders initialized (with edge/wireframe/blending support)";
    return true;
  }
}

// =======================================================================
// function : SetDepthFunc
// purpose  : Set depth compare function
// =======================================================================
void Metal_Context::SetDepthFunc(int theFunc)
{
  myDepthFunc = theFunc;
  // Note: In Metal, depth function is set via depth-stencil state object,
  // which needs to be recreated when this changes. For dynamic changes,
  // we track the state and apply it when creating render encoders.
}

// =======================================================================
// function : SetDepthMask
// purpose  : Set depth write mask
// =======================================================================
void Metal_Context::SetDepthMask(bool theValue)
{
  myDepthMask = theValue;
  // Similar to SetDepthFunc, this is handled via depth-stencil state
}

// =======================================================================
// function : SetBlendEnabled
// purpose  : Enable or disable blending
// =======================================================================
void Metal_Context::SetBlendEnabled(bool theValue)
{
  myBlendEnabled = theValue;
}

// =======================================================================
// function : SetBlendFunc
// purpose  : Set blend function
// =======================================================================
void Metal_Context::SetBlendFunc(int theSrcFactor, int theDstFactor)
{
  myBlendSrcRGB = theSrcFactor;
  myBlendDstRGB = theDstFactor;
  myBlendSrcAlpha = theSrcFactor;
  myBlendDstAlpha = theDstFactor;
}

// =======================================================================
// function : SetBlendFuncSeparate
// purpose  : Set blend function with separate alpha
// =======================================================================
void Metal_Context::SetBlendFuncSeparate(int theSrcRGB, int theDstRGB, int theSrcAlpha, int theDstAlpha)
{
  myBlendSrcRGB = theSrcRGB;
  myBlendDstRGB = theDstRGB;
  myBlendSrcAlpha = theSrcAlpha;
  myBlendDstAlpha = theDstAlpha;
}

// =======================================================================
// function : SetColorMask
// purpose  : Enable or disable color writing
// =======================================================================
void Metal_Context::SetColorMask(bool theValue)
{
  myColorMask = theValue;
}

// =======================================================================
// function : ClearDepth
// purpose  : Set depth clear value (used when creating render pass descriptor)
// =======================================================================
void Metal_Context::ClearDepth()
{
  // In Metal, depth clearing is done via render pass descriptor loadAction.
  // This method tracks the clear depth value (default 1.0).
  // The value is used by Metal_FrameBuffer::CreateRenderPassDescriptor().
  myClearDepth = 1.0f;
}

// =======================================================================
// function : ClearColor
// purpose  : Set color clear value (used when creating render pass descriptor)
// =======================================================================
void Metal_Context::ClearColor(float theR, float theG, float theB, float theA)
{
  // In Metal, color clearing is done via render pass descriptor loadAction.
  // This method tracks the clear color values.
  // The values are used by Metal_FrameBuffer::CreateRenderPassDescriptor().
  myClearColor[0] = theR;
  myClearColor[1] = theG;
  myClearColor[2] = theB;
  myClearColor[3] = theA;
}

// =======================================================================
// function : BindProgram
// purpose  : Bind shader program
// =======================================================================
void Metal_Context::BindProgram(void* theProgram)
{
  // In Metal, shader programs are bound via pipeline state objects
  (void)theProgram;
}
