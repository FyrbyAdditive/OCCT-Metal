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

#include <Metal_FrameBuffer.hxx>
#include <Metal_Context.hxx>
#include <Metal_Texture.hxx>
#include <Image_PixMap.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_FrameBuffer, Metal_Resource)

namespace
{
  //! Convert Metal_PixelFormat to MTLPixelFormat.
  MTLPixelFormat toMTLPixelFormat(Metal_PixelFormat theFormat)
  {
    switch (theFormat)
    {
      case Metal_PixelFormat_RGBA8:   return MTLPixelFormatRGBA8Unorm;
      case Metal_PixelFormat_BGRA8:   return MTLPixelFormatBGRA8Unorm;
      case Metal_PixelFormat_RGBA16F: return MTLPixelFormatRGBA16Float;
      case Metal_PixelFormat_RGBA32F: return MTLPixelFormatRGBA32Float;
      case Metal_PixelFormat_Depth32F: return MTLPixelFormatDepth32Float;
      case Metal_PixelFormat_Depth24Stencil8:
        // Note: Depth24Unorm_Stencil8 is not available on all devices
        // Fall back to Depth32Float_Stencil8 which is universally available
        return MTLPixelFormatDepth32Float_Stencil8;
      case Metal_PixelFormat_Unknown:
      default:
        return MTLPixelFormatInvalid;
    }
  }

  //! Get bytes per pixel for format.
  int bytesPerPixel(Metal_PixelFormat theFormat)
  {
    switch (theFormat)
    {
      case Metal_PixelFormat_RGBA8:
      case Metal_PixelFormat_BGRA8:
        return 4;
      case Metal_PixelFormat_RGBA16F:
        return 8;
      case Metal_PixelFormat_RGBA32F:
        return 16;
      case Metal_PixelFormat_Depth32F:
        return 4;
      case Metal_PixelFormat_Depth24Stencil8:
        return 8; // Depth32Float_Stencil8
      default:
        return 0;
    }
  }
}

// =======================================================================
// function : Metal_FrameBuffer
// purpose  : Constructor
// =======================================================================
Metal_FrameBuffer::Metal_FrameBuffer(const TCollection_AsciiString& theResourceId)
: Metal_Resource(),
  myResourceId(theResourceId),
  mySizeX(0),
  mySizeY(0),
  myVPSizeX(0),
  myVPSizeY(0),
  myNbSamples(0),
  myIsValid(false),
  myDepthFormat(Metal_PixelFormat_Unknown)
{
  //
}

// =======================================================================
// function : ~Metal_FrameBuffer
// purpose  : Destructor
// =======================================================================
Metal_FrameBuffer::~Metal_FrameBuffer()
{
  Release(nullptr);
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_FrameBuffer::Release(Metal_Context* /*theCtx*/)
{
  myColorTextures.Clear();
  myColorTexturesMSAA.Clear();
  myDepthStencilTexture.Nullify();
  myDepthStencilTextureMSAA.Nullify();
  myColorFormats.Clear();
  myDepthFormat = Metal_PixelFormat_Unknown;
  mySizeX = 0;
  mySizeY = 0;
  myVPSizeX = 0;
  myVPSizeY = 0;
  myNbSamples = 0;
  myIsValid = false;
}

// =======================================================================
// function : Init
// purpose  : Initialize framebuffer with single color attachment
// =======================================================================
bool Metal_FrameBuffer::Init(Metal_Context* theCtx,
                              const NCollection_Vec2<int>& theSize,
                              Metal_PixelFormat theColorFormat,
                              Metal_PixelFormat theDepthFormat,
                              int theNbSamples)
{
  NCollection_Vector<Metal_PixelFormat> aColorFormats;
  if (theColorFormat != Metal_PixelFormat_Unknown)
  {
    aColorFormats.Append(theColorFormat);
  }
  return Init(theCtx, theSize, aColorFormats, theDepthFormat, theNbSamples);
}

// =======================================================================
// function : Init
// purpose  : Initialize framebuffer with multiple color attachments
// =======================================================================
bool Metal_FrameBuffer::Init(Metal_Context* theCtx,
                              const NCollection_Vec2<int>& theSize,
                              const NCollection_Vector<Metal_PixelFormat>& theColorFormats,
                              Metal_PixelFormat theDepthFormat,
                              int theNbSamples)
{
  Release(theCtx);

  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  if (theSize.x() <= 0 || theSize.y() <= 0)
  {
    return false;
  }

  mySizeX = theSize.x();
  mySizeY = theSize.y();
  myVPSizeX = mySizeX;
  myVPSizeY = mySizeY;
  myNbSamples = (theNbSamples <= 1) ? 0 : theNbSamples;
  myColorFormats = theColorFormats;
  myDepthFormat = theDepthFormat;

  // Create color attachments
  for (int i = 0; i < theColorFormats.Length(); ++i)
  {
    Metal_PixelFormat aFormat = theColorFormats.Value(i);
    if (aFormat == Metal_PixelFormat_Unknown)
    {
      continue;
    }

    // Create resolve target (non-MSAA)
    occ::handle<Metal_Texture> aColorTex;
    if (!createTexture(theCtx, aColorTex, mySizeX, mySizeY, aFormat, 1, true))
    {
      Release(theCtx);
      return false;
    }
    myColorTextures.Append(aColorTex);

    // Create MSAA texture if needed
    if (myNbSamples > 1)
    {
      occ::handle<Metal_Texture> aColorTexMSAA;
      if (!createTexture(theCtx, aColorTexMSAA, mySizeX, mySizeY, aFormat, myNbSamples, true))
      {
        Release(theCtx);
        return false;
      }
      myColorTexturesMSAA.Append(aColorTexMSAA);
    }
  }

  // Create depth attachment
  if (theDepthFormat != Metal_PixelFormat_Unknown)
  {
    // Create resolve target (non-MSAA)
    if (!createTexture(theCtx, myDepthStencilTexture, mySizeX, mySizeY, theDepthFormat, 1, true))
    {
      Release(theCtx);
      return false;
    }

    // Create MSAA depth texture if needed
    if (myNbSamples > 1)
    {
      if (!createTexture(theCtx, myDepthStencilTextureMSAA, mySizeX, mySizeY, theDepthFormat, myNbSamples, true))
      {
        Release(theCtx);
        return false;
      }
    }
  }

  myIsValid = true;
  return true;
}

// =======================================================================
// function : InitLazy
// purpose  : Initialize framebuffer lazily
// =======================================================================
bool Metal_FrameBuffer::InitLazy(Metal_Context* theCtx,
                                  const NCollection_Vec2<int>& theViewportSize,
                                  Metal_PixelFormat theColorFormat,
                                  Metal_PixelFormat theDepthFormat,
                                  int theNbSamples)
{
  // Check if reinitialization is needed
  if (myIsValid
   && mySizeX == theViewportSize.x()
   && mySizeY == theViewportSize.y()
   && myNbSamples == ((theNbSamples <= 1) ? 0 : theNbSamples)
   && myDepthFormat == theDepthFormat
   && myColorFormats.Length() == 1
   && myColorFormats.Value(0) == theColorFormat)
  {
    return true;
  }

  return Init(theCtx, theViewportSize, theColorFormat, theDepthFormat, theNbSamples);
}

// =======================================================================
// function : SetupViewport
// purpose  : Setup viewport
// =======================================================================
void Metal_FrameBuffer::SetupViewport(Metal_Context* /*theCtx*/)
{
  // Viewport is set via MTLRenderCommandEncoder, not stored here
  // This is a placeholder for compatibility
}

// =======================================================================
// function : createTexture
// purpose  : Create texture for attachment
// =======================================================================
bool Metal_FrameBuffer::createTexture(Metal_Context* theCtx,
                                        occ::handle<Metal_Texture>& theTexture,
                                        int theWidth, int theHeight,
                                        Metal_PixelFormat theFormat,
                                        int theNbSamples,
                                        bool theIsRenderTarget)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  MTLPixelFormat aMTLFormat = toMTLPixelFormat(theFormat);
  if (aMTLFormat == MTLPixelFormatInvalid)
  {
    return false;
  }

  MTLTextureDescriptor* aDesc = [MTLTextureDescriptor new];
  aDesc.width = theWidth;
  aDesc.height = theHeight;
  aDesc.pixelFormat = aMTLFormat;
  aDesc.storageMode = MTLStorageModePrivate;

  if (theNbSamples > 1)
  {
    aDesc.textureType = MTLTextureType2DMultisample;
    aDesc.sampleCount = theNbSamples;
  }
  else
  {
    aDesc.textureType = MTLTextureType2D;
    aDesc.sampleCount = 1;
  }

  if (theIsRenderTarget)
  {
    aDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  }
  else
  {
    aDesc.usage = MTLTextureUsageShaderRead;
  }

  id<MTLTexture> aMTLTexture = [theCtx->Device() newTextureWithDescriptor:aDesc];
  if (aMTLTexture == nil)
  {
    return false;
  }

  // Create wrapper
  theTexture = new Metal_Texture();
  theTexture->SetTexture(aMTLTexture, theWidth, theHeight);

  return true;
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
size_t Metal_FrameBuffer::EstimatedDataSize() const
{
  if (!myIsValid)
  {
    return 0;
  }

  size_t aSize = 0;

  // Color attachments
  for (int i = 0; i < myColorFormats.Length(); ++i)
  {
    int aBpp = bytesPerPixel(myColorFormats.Value(i));
    aSize += mySizeX * mySizeY * aBpp;

    // MSAA textures
    if (myNbSamples > 1)
    {
      aSize += mySizeX * mySizeY * aBpp * myNbSamples;
    }
  }

  // Depth attachment
  if (myDepthFormat != Metal_PixelFormat_Unknown)
  {
    int aBpp = bytesPerPixel(myDepthFormat);
    aSize += mySizeX * mySizeY * aBpp;

    if (myNbSamples > 1)
    {
      aSize += mySizeX * mySizeY * aBpp * myNbSamples;
    }
  }

  return aSize;
}

// =======================================================================
// function : RenderPassDescriptor
// purpose  : Create render pass descriptor
// =======================================================================
MTLRenderPassDescriptor* Metal_FrameBuffer::RenderPassDescriptor(bool theToClear,
                                                                   const float* theClearColor,
                                                                   float theClearDepth)
{
  if (!myIsValid)
  {
    return nil;
  }

  MTLRenderPassDescriptor* aDesc = [MTLRenderPassDescriptor renderPassDescriptor];

  // Setup color attachments
  for (int i = 0; i < myColorTextures.Length(); ++i)
  {
    MTLRenderPassColorAttachmentDescriptor* aColorAttach = aDesc.colorAttachments[i];

    if (myNbSamples > 1 && i < myColorTexturesMSAA.Length())
    {
      // MSAA: render to MSAA texture, resolve to non-MSAA
      aColorAttach.texture = myColorTexturesMSAA.Value(i)->Texture();
      aColorAttach.resolveTexture = myColorTextures.Value(i)->Texture();
      aColorAttach.storeAction = MTLStoreActionMultisampleResolve;
    }
    else
    {
      aColorAttach.texture = myColorTextures.Value(i)->Texture();
      aColorAttach.storeAction = MTLStoreActionStore;
    }

    if (theToClear)
    {
      aColorAttach.loadAction = MTLLoadActionClear;
      if (theClearColor != nullptr)
      {
        aColorAttach.clearColor = MTLClearColorMake(theClearColor[0],
                                                     theClearColor[1],
                                                     theClearColor[2],
                                                     theClearColor[3]);
      }
      else
      {
        aColorAttach.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
      }
    }
    else
    {
      aColorAttach.loadAction = MTLLoadActionLoad;
    }
  }

  // Setup depth attachment
  if (myDepthFormat != Metal_PixelFormat_Unknown && !myDepthStencilTexture.IsNull())
  {
    MTLRenderPassDepthAttachmentDescriptor* aDepthAttach = aDesc.depthAttachment;

    if (myNbSamples > 1 && !myDepthStencilTextureMSAA.IsNull())
    {
      aDepthAttach.texture = myDepthStencilTextureMSAA->Texture();
      aDepthAttach.resolveTexture = myDepthStencilTexture->Texture();
      aDepthAttach.storeAction = MTLStoreActionMultisampleResolve;
    }
    else
    {
      aDepthAttach.texture = myDepthStencilTexture->Texture();
      aDepthAttach.storeAction = MTLStoreActionStore;
    }

    if (theToClear)
    {
      aDepthAttach.loadAction = MTLLoadActionClear;
      aDepthAttach.clearDepth = theClearDepth;
    }
    else
    {
      aDepthAttach.loadAction = MTLLoadActionLoad;
    }

    // Setup stencil if format includes it
    if (myDepthFormat == Metal_PixelFormat_Depth24Stencil8)
    {
      MTLRenderPassStencilAttachmentDescriptor* aStencilAttach = aDesc.stencilAttachment;

      if (myNbSamples > 1 && !myDepthStencilTextureMSAA.IsNull())
      {
        aStencilAttach.texture = myDepthStencilTextureMSAA->Texture();
        aStencilAttach.resolveTexture = myDepthStencilTexture->Texture();
        aStencilAttach.storeAction = MTLStoreActionMultisampleResolve;
      }
      else
      {
        aStencilAttach.texture = myDepthStencilTexture->Texture();
        aStencilAttach.storeAction = MTLStoreActionStore;
      }

      if (theToClear)
      {
        aStencilAttach.loadAction = MTLLoadActionClear;
        aStencilAttach.clearStencil = 0;
      }
      else
      {
        aStencilAttach.loadAction = MTLLoadActionLoad;
      }
    }
  }

  return aDesc;
}

// =======================================================================
// function : MetalColorTexture
// purpose  : Return raw Metal texture for color attachment
// =======================================================================
id<MTLTexture> Metal_FrameBuffer::MetalColorTexture(int theIndex) const
{
  if (theIndex < 0 || theIndex >= myColorTextures.Length())
  {
    return nil;
  }
  return myColorTextures.Value(theIndex)->Texture();
}

// =======================================================================
// function : MetalDepthTexture
// purpose  : Return raw Metal texture for depth attachment
// =======================================================================
id<MTLTexture> Metal_FrameBuffer::MetalDepthTexture() const
{
  if (myDepthStencilTexture.IsNull())
  {
    return nil;
  }
  return myDepthStencilTexture->Texture();
}

// =======================================================================
// function : ReadColorPixels
// purpose  : Read color buffer pixels into CPU memory
// =======================================================================
bool Metal_FrameBuffer::ReadColorPixels(Metal_Context* theCtx,
                                          Standard_Byte* theData,
                                          int theIndex) const
{
  if (theCtx == nullptr || theData == nullptr || !myIsValid)
  {
    return false;
  }

  if (theIndex < 0 || theIndex >= myColorTextures.Length())
  {
    return false;
  }

  id<MTLTexture> aSrcTexture = myColorTextures.Value(theIndex)->Texture();
  if (aSrcTexture == nil)
  {
    return false;
  }

  // Calculate bytes per row and total size
  int aBpp = 4; // Assume 4 bytes per pixel for RGBA/BGRA
  MTLPixelFormat aFormat = aSrcTexture.pixelFormat;
  if (aFormat == MTLPixelFormatRGBA16Float)
  {
    aBpp = 8;
  }
  else if (aFormat == MTLPixelFormatRGBA32Float)
  {
    aBpp = 16;
  }

  size_t aBytesPerRow = mySizeX * aBpp;
  size_t aTotalBytes = aBytesPerRow * mySizeY;

  // For private storage textures, we need to use a blit encoder to copy to a shared buffer
  if (aSrcTexture.storageMode == MTLStorageModePrivate)
  {
    // Create a temporary shared buffer for readback
    id<MTLBuffer> aReadbackBuffer = [theCtx->Device() newBufferWithLength:aTotalBytes
                                                                  options:MTLResourceStorageModeShared];
    if (aReadbackBuffer == nil)
    {
      return false;
    }

    // Create command buffer and blit encoder
    id<MTLCommandBuffer> aCmdBuffer = theCtx->CreateCommandBuffer();
    id<MTLBlitCommandEncoder> aBlitEncoder = [aCmdBuffer blitCommandEncoder];

    // Copy texture to buffer
    [aBlitEncoder copyFromTexture:aSrcTexture
                      sourceSlice:0
                      sourceLevel:0
                     sourceOrigin:MTLOriginMake(0, 0, 0)
                       sourceSize:MTLSizeMake(mySizeX, mySizeY, 1)
                         toBuffer:aReadbackBuffer
                destinationOffset:0
           destinationBytesPerRow:aBytesPerRow
         destinationBytesPerImage:aTotalBytes];

    [aBlitEncoder endEncoding];
    [aCmdBuffer commit];
    [aCmdBuffer waitUntilCompleted];

    // Copy from buffer to destination
    memcpy(theData, aReadbackBuffer.contents, aTotalBytes);
  }
  else
  {
    // Texture is already CPU-accessible, read directly
    MTLRegion aRegion = MTLRegionMake2D(0, 0, mySizeX, mySizeY);
    [aSrcTexture getBytes:theData
              bytesPerRow:aBytesPerRow
               fromRegion:aRegion
              mipmapLevel:0];
  }

  return true;
}

// =======================================================================
// function : ReadDepthPixels
// purpose  : Read depth buffer pixels into CPU memory
// =======================================================================
bool Metal_FrameBuffer::ReadDepthPixels(Metal_Context* theCtx,
                                          float* theData) const
{
  if (theCtx == nullptr || theData == nullptr || !myIsValid)
  {
    return false;
  }

  if (myDepthStencilTexture.IsNull())
  {
    return false;
  }

  id<MTLTexture> aSrcTexture = myDepthStencilTexture->Texture();
  if (aSrcTexture == nil)
  {
    return false;
  }

  size_t aBytesPerRow = mySizeX * sizeof(float);
  size_t aTotalBytes = aBytesPerRow * mySizeY;

  // For private storage textures, we need to use a blit encoder
  if (aSrcTexture.storageMode == MTLStorageModePrivate)
  {
    id<MTLBuffer> aReadbackBuffer = [theCtx->Device() newBufferWithLength:aTotalBytes
                                                                  options:MTLResourceStorageModeShared];
    if (aReadbackBuffer == nil)
    {
      return false;
    }

    id<MTLCommandBuffer> aCmdBuffer = theCtx->CreateCommandBuffer();
    id<MTLBlitCommandEncoder> aBlitEncoder = [aCmdBuffer blitCommandEncoder];

    [aBlitEncoder copyFromTexture:aSrcTexture
                      sourceSlice:0
                      sourceLevel:0
                     sourceOrigin:MTLOriginMake(0, 0, 0)
                       sourceSize:MTLSizeMake(mySizeX, mySizeY, 1)
                         toBuffer:aReadbackBuffer
                destinationOffset:0
           destinationBytesPerRow:aBytesPerRow
         destinationBytesPerImage:aTotalBytes];

    [aBlitEncoder endEncoding];
    [aCmdBuffer commit];
    [aCmdBuffer waitUntilCompleted];

    memcpy(theData, aReadbackBuffer.contents, aTotalBytes);
  }
  else
  {
    MTLRegion aRegion = MTLRegionMake2D(0, 0, mySizeX, mySizeY);
    [aSrcTexture getBytes:theData
              bytesPerRow:aBytesPerRow
               fromRegion:aRegion
              mipmapLevel:0];
  }

  return true;
}

// =======================================================================
// function : BindBuffer
// purpose  : Bind this framebuffer for rendering
// =======================================================================
void Metal_FrameBuffer::BindBuffer(const occ::handle<Metal_Context>& theCtx)
{
  // In Metal, framebuffer binding is handled through render pass descriptors
  // This method is provided for API compatibility with OpenGL patterns
  // The actual binding happens when creating a render command encoder
  // with RenderPassDescriptor()
  (void)theCtx;
}

// =======================================================================
// function : UnbindBuffer
// purpose  : Unbind this framebuffer
// =======================================================================
void Metal_FrameBuffer::UnbindBuffer(const occ::handle<Metal_Context>& theCtx)
{
  // In Metal, framebuffer unbinding is handled by ending the render encoder
  // This method is provided for API compatibility with OpenGL patterns
  (void)theCtx;
}
