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

#include <Metal_Texture.hxx>
#include <Metal_Context.hxx>
#include <Standard_Assert.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Texture, Metal_Resource)

// =======================================================================
// function : Metal_Texture
// purpose  : Constructor
// =======================================================================
Metal_Texture::Metal_Texture()
: myTexture(nil),
  myTextureType(Metal_TextureType_2D),
  myWidth(0),
  myHeight(0),
  myDepth(1),
  myMipLevels(1),
  myArrayLayers(1),
  myPixelFormat(0),
  myEstimatedSize(0)
{
  //
}

// =======================================================================
// function : ~Metal_Texture
// purpose  : Destructor
// =======================================================================
Metal_Texture::~Metal_Texture()
{
  Standard_ASSERT_RAISE(myTexture == nil,
    "Metal_Texture destroyed without explicit Release()");
}

// =======================================================================
// function : ToMetalPixelFormat
// purpose  : Convert Image_Format to Metal pixel format
// =======================================================================
int Metal_Texture::ToMetalPixelFormat(Image_Format theFormat, bool theSRGB)
{
  switch (theFormat)
  {
    case Image_Format_Gray:
      return MTLPixelFormatR8Unorm;
    case Image_Format_Alpha:
      return MTLPixelFormatA8Unorm;
    case Image_Format_GrayF:
      return MTLPixelFormatR32Float;
    case Image_Format_AlphaF:
      return MTLPixelFormatR32Float;
    case Image_Format_RGBA:
      return theSRGB ? MTLPixelFormatRGBA8Unorm_sRGB : MTLPixelFormatRGBA8Unorm;
    case Image_Format_BGRA:
      return theSRGB ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
    case Image_Format_RGB32:
      // No direct 3-component format in Metal, use RGBA
      return theSRGB ? MTLPixelFormatRGBA8Unorm_sRGB : MTLPixelFormatRGBA8Unorm;
    case Image_Format_BGR32:
      return theSRGB ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
    case Image_Format_RGB:
    case Image_Format_BGR:
      // 3-byte RGB requires conversion to RGBA
      return theSRGB ? MTLPixelFormatRGBA8Unorm_sRGB : MTLPixelFormatRGBA8Unorm;
    case Image_Format_RGBAF:
      return MTLPixelFormatRGBA32Float;
    case Image_Format_RGBF:
      return MTLPixelFormatRGBA32Float; // Will need padding
    case Image_Format_BGRAF:
      return MTLPixelFormatRGBA32Float; // Metal doesn't have BGRA float
    case Image_Format_GrayF_half:
      return MTLPixelFormatR16Float;
    case Image_Format_RGF_half:
      return MTLPixelFormatRG16Float;
    case Image_Format_RGBAF_half:
      return MTLPixelFormatRGBA16Float;
    default:
      return 0;
  }
}

// =======================================================================
// function : BytesPerPixel
// purpose  : Return bytes per pixel for Metal format
// =======================================================================
int Metal_Texture::BytesPerPixel(int theMetalFormat)
{
  switch (theMetalFormat)
  {
    case MTLPixelFormatA8Unorm:
    case MTLPixelFormatR8Unorm:
      return 1;
    case MTLPixelFormatR16Float:
    case MTLPixelFormatRG8Unorm:
      return 2;
    case MTLPixelFormatRGBA8Unorm:
    case MTLPixelFormatRGBA8Unorm_sRGB:
    case MTLPixelFormatBGRA8Unorm:
    case MTLPixelFormatBGRA8Unorm_sRGB:
    case MTLPixelFormatR32Float:
    case MTLPixelFormatRG16Float:
      return 4;
    case MTLPixelFormatRG32Float:
    case MTLPixelFormatRGBA16Float:
      return 8;
    case MTLPixelFormatRGBA32Float:
      return 16;
    default:
      return 4;
  }
}

// =======================================================================
// function : Create2D (from image)
// purpose  : Create 2D texture from image
// =======================================================================
bool Metal_Texture::Create2D(Metal_Context* theCtx,
                             const Image_PixMap& theImage,
                             bool theGenerateMips)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  if (theImage.IsEmpty())
  {
    return false;
  }

  myWidth = (int)theImage.Width();
  myHeight = (int)theImage.Height();
  myDepth = 1;
  myTextureType = Metal_TextureType_2D;
  myArrayLayers = 1;

  // Convert format
  myPixelFormat = ToMetalPixelFormat(theImage.Format(), false);
  if (myPixelFormat == 0)
  {
    return false;
  }

  // Calculate mip levels
  if (theGenerateMips)
  {
    myMipLevels = 1;
    int aSize = std::max(myWidth, myHeight);
    while (aSize > 1)
    {
      aSize /= 2;
      myMipLevels++;
    }
  }
  else
  {
    myMipLevels = 1;
  }

  // Create texture descriptor
  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType2D;
  aDesc.pixelFormat = (MTLPixelFormat)myPixelFormat;
  aDesc.width = myWidth;
  aDesc.height = myHeight;
  aDesc.depth = 1;
  aDesc.mipmapLevelCount = myMipLevels;
  aDesc.arrayLength = 1;
  aDesc.sampleCount = 1;
  aDesc.storageMode = MTLStorageModeShared;
  aDesc.usage = MTLTextureUsageShaderRead;

  if (theGenerateMips)
  {
    aDesc.usage |= MTLTextureUsageRenderTarget; // Required for mipmap generation
  }

  // Create texture
  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];
  if (myTexture == nil)
  {
    return false;
  }

  // Upload base level
  if (!Upload(theCtx, theImage, 0, 0, 0))
  {
    Release(theCtx);
    return false;
  }

  // Generate mipmaps
  if (theGenerateMips && myMipLevels > 1)
  {
    GenerateMipmaps(theCtx);
  }

  // Estimate memory size
  myEstimatedSize = size_t(myWidth) * size_t(myHeight) * BytesPerPixel(myPixelFormat);
  if (myMipLevels > 1)
  {
    myEstimatedSize = myEstimatedSize * 4 / 3; // Approximate mipmap overhead
  }

  return true;
}

// =======================================================================
// function : Create2D (empty)
// purpose  : Create empty 2D texture
// =======================================================================
bool Metal_Texture::Create2D(Metal_Context* theCtx,
                             int theWidth,
                             int theHeight,
                             int theFormat,
                             int theMipLevels)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  if (theWidth <= 0 || theHeight <= 0)
  {
    return false;
  }

  myWidth = theWidth;
  myHeight = theHeight;
  myDepth = 1;
  myTextureType = Metal_TextureType_2D;
  myMipLevels = std::max(1, theMipLevels);
  myArrayLayers = 1;
  myPixelFormat = theFormat;

  // Create texture descriptor
  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType2D;
  aDesc.pixelFormat = (MTLPixelFormat)myPixelFormat;
  aDesc.width = myWidth;
  aDesc.height = myHeight;
  aDesc.depth = 1;
  aDesc.mipmapLevelCount = myMipLevels;
  aDesc.arrayLength = 1;
  aDesc.sampleCount = 1;
  aDesc.storageMode = MTLStorageModeShared;
  aDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

  // Create texture
  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];

  myEstimatedSize = size_t(myWidth) * size_t(myHeight) * BytesPerPixel(myPixelFormat);

  return myTexture != nil;
}

// =======================================================================
// function : CreateCube
// purpose  : Create cube texture from 6 images
// =======================================================================
bool Metal_Texture::CreateCube(Metal_Context* theCtx,
                               const Image_PixMap* theFaces[6],
                               bool theGenerateMips)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  // Validate all faces
  for (int i = 0; i < 6; ++i)
  {
    if (theFaces[i] == nullptr || theFaces[i]->IsEmpty())
    {
      return false;
    }
  }

  // All faces must have same dimensions
  myWidth = (int)theFaces[0]->Width();
  myHeight = (int)theFaces[0]->Height();
  myDepth = 1;
  myTextureType = Metal_TextureType_Cube;
  myArrayLayers = 6;

  for (int i = 1; i < 6; ++i)
  {
    if ((int)theFaces[i]->Width() != myWidth || (int)theFaces[i]->Height() != myHeight)
    {
      return false;
    }
  }

  // Convert format
  myPixelFormat = ToMetalPixelFormat(theFaces[0]->Format(), false);
  if (myPixelFormat == 0)
  {
    return false;
  }

  // Calculate mip levels
  if (theGenerateMips)
  {
    myMipLevels = 1;
    int aSize = std::max(myWidth, myHeight);
    while (aSize > 1)
    {
      aSize /= 2;
      myMipLevels++;
    }
  }
  else
  {
    myMipLevels = 1;
  }

  // Create texture descriptor
  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureTypeCube;
  aDesc.pixelFormat = (MTLPixelFormat)myPixelFormat;
  aDesc.width = myWidth;
  aDesc.height = myHeight;
  aDesc.depth = 1;
  aDesc.mipmapLevelCount = myMipLevels;
  aDesc.arrayLength = 1;
  aDesc.sampleCount = 1;
  aDesc.storageMode = MTLStorageModeShared;
  aDesc.usage = MTLTextureUsageShaderRead;

  if (theGenerateMips)
  {
    aDesc.usage |= MTLTextureUsageRenderTarget;
  }

  // Create texture
  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];
  if (myTexture == nil)
  {
    return false;
  }

  // Upload all faces
  for (int i = 0; i < 6; ++i)
  {
    if (!Upload(theCtx, *theFaces[i], 0, 0, i))
    {
      Release(theCtx);
      return false;
    }
  }

  // Generate mipmaps
  if (theGenerateMips && myMipLevels > 1)
  {
    GenerateMipmaps(theCtx);
  }

  myEstimatedSize = size_t(myWidth) * size_t(myHeight) * BytesPerPixel(myPixelFormat) * 6;
  if (myMipLevels > 1)
  {
    myEstimatedSize = myEstimatedSize * 4 / 3;
  }

  return true;
}

// =======================================================================
// function : Upload
// purpose  : Upload image data to texture
// =======================================================================
bool Metal_Texture::Upload(Metal_Context* theCtx,
                           const Image_PixMap& theImage,
                           int theMipLevel,
                           int theArrayLayer,
                           int theCubeFace)
{
  (void)theCtx;

  if (myTexture == nil || theImage.IsEmpty())
  {
    return false;
  }

  int aBytesPerPixel = BytesPerPixel(myPixelFormat);
  NSUInteger aBytesPerRow = theImage.Width() * aBytesPerPixel;

  // Handle potential format conversion (RGB to RGBA, etc.)
  // For now, assume formats match
  const void* aData = theImage.Data();

  MTLRegion aRegion = MTLRegionMake2D(0, 0, theImage.Width(), theImage.Height());

  if (myTextureType == Metal_TextureType_Cube)
  {
    [myTexture replaceRegion:aRegion
                 mipmapLevel:theMipLevel
                       slice:theCubeFace
                   withBytes:aData
                 bytesPerRow:aBytesPerRow
               bytesPerImage:0];
  }
  else if (myArrayLayers > 1)
  {
    [myTexture replaceRegion:aRegion
                 mipmapLevel:theMipLevel
                       slice:theArrayLayer
                   withBytes:aData
                 bytesPerRow:aBytesPerRow
               bytesPerImage:0];
  }
  else
  {
    [myTexture replaceRegion:aRegion
                 mipmapLevel:theMipLevel
                   withBytes:aData
                 bytesPerRow:aBytesPerRow];
  }

  return true;
}

// =======================================================================
// function : GenerateMipmaps
// purpose  : Generate mipmaps
// =======================================================================
void Metal_Texture::GenerateMipmaps(Metal_Context* theCtx)
{
  if (myTexture == nil || theCtx == nullptr || myMipLevels <= 1)
  {
    return;
  }

  id<MTLCommandBuffer> aCmdBuffer = theCtx->CurrentCommandBuffer();
  id<MTLBlitCommandEncoder> aBlitEncoder = [aCmdBuffer blitCommandEncoder];
  [aBlitEncoder generateMipmapsForTexture:myTexture];
  [aBlitEncoder endEncoding];
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Texture::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (myTexture != nil)
  {
    myTexture = nil;
  }

  myWidth = 0;
  myHeight = 0;
  myDepth = 1;
  myMipLevels = 1;
  myArrayLayers = 1;
  myEstimatedSize = 0;
}
