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
#include <vector>
#include <cstring>

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
  // Release Metal texture if still held.
  // Under ARC, setting to nil releases the reference.
  if (myTexture != nil)
  {
    myTexture = nil;
  }
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
// function : ToMetalCompressedFormat
// purpose  : Convert Image_CompressedFormat to Metal pixel format
// =======================================================================
int Metal_Texture::ToMetalCompressedFormat(Image_CompressedFormat theFormat, bool theSRGB)
{
  switch (theFormat)
  {
    case Image_CompressedFormat_RGB_S3TC_DXT1:
      return theSRGB ? MTLPixelFormatBC1_RGBA_sRGB : MTLPixelFormatBC1_RGBA;
    case Image_CompressedFormat_RGBA_S3TC_DXT1:
      return theSRGB ? MTLPixelFormatBC1_RGBA_sRGB : MTLPixelFormatBC1_RGBA;
    case Image_CompressedFormat_RGBA_S3TC_DXT3:
      return theSRGB ? MTLPixelFormatBC2_RGBA_sRGB : MTLPixelFormatBC2_RGBA;
    case Image_CompressedFormat_RGBA_S3TC_DXT5:
      return theSRGB ? MTLPixelFormatBC3_RGBA_sRGB : MTLPixelFormatBC3_RGBA;
    default:
      return 0;
  }
}

// =======================================================================
// function : CompressedBlockSize
// purpose  : Return block size for compressed format
// =======================================================================
int Metal_Texture::CompressedBlockSize(int theMetalFormat)
{
  switch (theMetalFormat)
  {
    case MTLPixelFormatBC1_RGBA:
    case MTLPixelFormatBC1_RGBA_sRGB:
    case MTLPixelFormatBC2_RGBA:
    case MTLPixelFormatBC2_RGBA_sRGB:
    case MTLPixelFormatBC3_RGBA:
    case MTLPixelFormatBC3_RGBA_sRGB:
    case MTLPixelFormatBC4_RUnorm:
    case MTLPixelFormatBC4_RSnorm:
    case MTLPixelFormatBC5_RGUnorm:
    case MTLPixelFormatBC5_RGSnorm:
    case MTLPixelFormatBC6H_RGBFloat:
    case MTLPixelFormatBC6H_RGBUfloat:
    case MTLPixelFormatBC7_RGBAUnorm:
    case MTLPixelFormatBC7_RGBAUnorm_sRGB:
      return 4; // 4x4 block
    default:
      return 0; // Not compressed
  }
}

// =======================================================================
// function : CompressedBytesPerBlock
// purpose  : Return bytes per block for compressed format
// =======================================================================
int Metal_Texture::CompressedBytesPerBlock(int theMetalFormat)
{
  switch (theMetalFormat)
  {
    case MTLPixelFormatBC1_RGBA:
    case MTLPixelFormatBC1_RGBA_sRGB:
    case MTLPixelFormatBC4_RUnorm:
    case MTLPixelFormatBC4_RSnorm:
      return 8;  // 8 bytes per 4x4 block
    case MTLPixelFormatBC2_RGBA:
    case MTLPixelFormatBC2_RGBA_sRGB:
    case MTLPixelFormatBC3_RGBA:
    case MTLPixelFormatBC3_RGBA_sRGB:
    case MTLPixelFormatBC5_RGUnorm:
    case MTLPixelFormatBC5_RGSnorm:
    case MTLPixelFormatBC6H_RGBFloat:
    case MTLPixelFormatBC6H_RGBUfloat:
    case MTLPixelFormatBC7_RGBAUnorm:
    case MTLPixelFormatBC7_RGBAUnorm_sRGB:
      return 16; // 16 bytes per 4x4 block
    default:
      return 0;
  }
}

// =======================================================================
// function : NeedsFormatConversion
// purpose  : Check if image format requires conversion
// =======================================================================
bool Metal_Texture::NeedsFormatConversion(Image_Format theFormat)
{
  switch (theFormat)
  {
    case Image_Format_RGB:
    case Image_Format_BGR:
    case Image_Format_RGBF:
    case Image_Format_BGRF:
      return true;
    default:
      return false;
  }
}

// =======================================================================
// function : ConvertImageFormat
// purpose  : Convert image data to Metal-compatible format
// =======================================================================
void Metal_Texture::ConvertImageFormat(const void* theSrc,
                                        void* theDst,
                                        int theWidth,
                                        int theHeight,
                                        size_t theSrcRowBytes,
                                        Image_Format theSrcFormat,
                                        int theDstBytesPerPixel)
{
  const uint8_t* aSrcRow = static_cast<const uint8_t*>(theSrc);
  uint8_t* aDstRow = static_cast<uint8_t*>(theDst);
  const size_t aDstRowBytes = theWidth * theDstBytesPerPixel;

  switch (theSrcFormat)
  {
    case Image_Format_RGB:
    {
      // RGB (3 bytes) -> RGBA (4 bytes)
      for (int y = 0; y < theHeight; ++y)
      {
        const uint8_t* aSrc = aSrcRow;
        uint8_t* aDst = aDstRow;
        for (int x = 0; x < theWidth; ++x)
        {
          aDst[0] = aSrc[0];  // R
          aDst[1] = aSrc[1];  // G
          aDst[2] = aSrc[2];  // B
          aDst[3] = 255;      // A
          aSrc += 3;
          aDst += 4;
        }
        aSrcRow += theSrcRowBytes;
        aDstRow += aDstRowBytes;
      }
      break;
    }
    case Image_Format_BGR:
    {
      // BGR (3 bytes) -> RGBA (4 bytes, swapped)
      for (int y = 0; y < theHeight; ++y)
      {
        const uint8_t* aSrc = aSrcRow;
        uint8_t* aDst = aDstRow;
        for (int x = 0; x < theWidth; ++x)
        {
          aDst[0] = aSrc[2];  // R (from B position)
          aDst[1] = aSrc[1];  // G
          aDst[2] = aSrc[0];  // B (from R position)
          aDst[3] = 255;      // A
          aSrc += 3;
          aDst += 4;
        }
        aSrcRow += theSrcRowBytes;
        aDstRow += aDstRowBytes;
      }
      break;
    }
    case Image_Format_RGBF:
    {
      // RGBF (3 floats = 12 bytes) -> RGBAF (4 floats = 16 bytes)
      for (int y = 0; y < theHeight; ++y)
      {
        const float* aSrc = reinterpret_cast<const float*>(aSrcRow);
        float* aDst = reinterpret_cast<float*>(aDstRow);
        for (int x = 0; x < theWidth; ++x)
        {
          aDst[0] = aSrc[0];  // R
          aDst[1] = aSrc[1];  // G
          aDst[2] = aSrc[2];  // B
          aDst[3] = 1.0f;     // A
          aSrc += 3;
          aDst += 4;
        }
        aSrcRow += theSrcRowBytes;
        aDstRow += aDstRowBytes;
      }
      break;
    }
    case Image_Format_BGRF:
    {
      // BGRF (3 floats = 12 bytes) -> RGBAF (4 floats = 16 bytes, swapped)
      for (int y = 0; y < theHeight; ++y)
      {
        const float* aSrc = reinterpret_cast<const float*>(aSrcRow);
        float* aDst = reinterpret_cast<float*>(aDstRow);
        for (int x = 0; x < theWidth; ++x)
        {
          aDst[0] = aSrc[2];  // R (from B position)
          aDst[1] = aSrc[1];  // G
          aDst[2] = aSrc[0];  // B (from R position)
          aDst[3] = 1.0f;     // A
          aSrc += 3;
          aDst += 4;
        }
        aSrcRow += theSrcRowBytes;
        aDstRow += aDstRowBytes;
      }
      break;
    }
    default:
      // Unsupported format for conversion - just copy
      for (int y = 0; y < theHeight; ++y)
      {
        memcpy(aDstRow, aSrcRow, aDstRowBytes);
        aSrcRow += theSrcRowBytes;
        aDstRow += aDstRowBytes;
      }
      break;
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
  const int aWidth = (int)theImage.Width();
  const int aHeight = (int)theImage.Height();

  // Handle format conversion if needed (RGB->RGBA, BGR->RGBA, etc.)
  std::vector<uint8_t> aConvertedData;
  const void* aData = theImage.Data();

  if (NeedsFormatConversion(theImage.Format()))
  {
    const size_t aConvertedSize = aWidth * aHeight * aBytesPerPixel;
    aConvertedData.resize(aConvertedSize);
    ConvertImageFormat(theImage.Data(),
                       aConvertedData.data(),
                       aWidth,
                       aHeight,
                       theImage.SizeRowBytes(),
                       theImage.Format(),
                       aBytesPerPixel);
    aData = aConvertedData.data();
  }

  MTLRegion aRegion = MTLRegionMake2D(0, 0, aWidth, aHeight);

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
// function : Upload (with offset)
// purpose  : Upload image data to a sub-region of texture
// =======================================================================
bool Metal_Texture::Upload(Metal_Context* theCtx,
                           const Image_PixMap& theImage,
                           int theMipLevel,
                           int theArrayLayer,
                           int theCubeFace,
                           int theOffsetX,
                           int theOffsetY)
{
  (void)theCtx;

  if (myTexture == nil || theImage.IsEmpty())
  {
    return false;
  }

  int aBytesPerPixel = BytesPerPixel(myPixelFormat);
  NSUInteger aBytesPerRow = theImage.Width() * aBytesPerPixel;

  const void* aData = theImage.Data();

  MTLRegion aRegion = MTLRegionMake2D(theOffsetX, theOffsetY,
                                       theImage.Width(), theImage.Height());

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

// =======================================================================
// function : Create3D
// purpose  : Create 3D texture
// =======================================================================
bool Metal_Texture::Create3D(Metal_Context* theCtx,
                             int theWidth,
                             int theHeight,
                             int theDepth,
                             int theFormat,
                             int theMipLevels)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  if (theWidth <= 0 || theHeight <= 0 || theDepth <= 0)
  {
    return false;
  }

  myWidth = theWidth;
  myHeight = theHeight;
  myDepth = theDepth;
  myTextureType = Metal_TextureType_3D;
  myMipLevels = std::max(1, theMipLevels);
  myArrayLayers = 1;
  myPixelFormat = theFormat;

  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType3D;
  aDesc.pixelFormat = (MTLPixelFormat)myPixelFormat;
  aDesc.width = myWidth;
  aDesc.height = myHeight;
  aDesc.depth = myDepth;
  aDesc.mipmapLevelCount = myMipLevels;
  aDesc.arrayLength = 1;
  aDesc.sampleCount = 1;
  aDesc.storageMode = MTLStorageModeShared;
  aDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];

  myEstimatedSize = size_t(myWidth) * size_t(myHeight) * size_t(myDepth) * BytesPerPixel(myPixelFormat);

  return myTexture != nil;
}

// =======================================================================
// function : Create2DArray
// purpose  : Create 2D texture array
// =======================================================================
bool Metal_Texture::Create2DArray(Metal_Context* theCtx,
                                  int theWidth,
                                  int theHeight,
                                  int theLayers,
                                  int theFormat,
                                  int theMipLevels)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  if (theWidth <= 0 || theHeight <= 0 || theLayers <= 0)
  {
    return false;
  }

  myWidth = theWidth;
  myHeight = theHeight;
  myDepth = 1;
  myTextureType = Metal_TextureType_2DArray;
  myMipLevels = std::max(1, theMipLevels);
  myArrayLayers = theLayers;
  myPixelFormat = theFormat;

  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType2DArray;
  aDesc.pixelFormat = (MTLPixelFormat)myPixelFormat;
  aDesc.width = myWidth;
  aDesc.height = myHeight;
  aDesc.depth = 1;
  aDesc.mipmapLevelCount = myMipLevels;
  aDesc.arrayLength = myArrayLayers;
  aDesc.sampleCount = 1;
  aDesc.storageMode = MTLStorageModeShared;
  aDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];

  myEstimatedSize = size_t(myWidth) * size_t(myHeight) * size_t(myArrayLayers) * BytesPerPixel(myPixelFormat);

  return myTexture != nil;
}

// =======================================================================
// function : CreateCompressed
// purpose  : Create texture from compressed image data
// =======================================================================
bool Metal_Texture::CreateCompressed(Metal_Context* theCtx,
                                     const Image_CompressedPixMap& theImage)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  if (theImage.FaceData().IsNull() || theImage.FaceData()->IsEmpty())
  {
    return false;
  }

  myPixelFormat = ToMetalCompressedFormat(theImage.CompressedFormat(), false);
  if (myPixelFormat == 0)
  {
    // Unsupported compressed format
    return false;
  }

  myWidth = (int)theImage.SizeX();
  myHeight = (int)theImage.SizeY();
  myDepth = 1;
  myTextureType = Metal_TextureType_2D;
  // MipMaps() contains mip sizes including base level
  myMipLevels = std::max(1, (int)theImage.MipMaps().Size());
  myArrayLayers = 1;

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

  id<MTLDevice> aDevice = theCtx->Device();
  myTexture = [aDevice newTextureWithDescriptor:aDesc];
  if (myTexture == nil)
  {
    return false;
  }

  // Upload base level
  int aBlockSize = CompressedBlockSize(myPixelFormat);
  int aBytesPerBlock = CompressedBytesPerBlock(myPixelFormat);
  int aBlocksWide = (myWidth + aBlockSize - 1) / aBlockSize;
  int aBytesPerRow = aBlocksWide * aBytesPerBlock;

  MTLRegion aRegion = MTLRegionMake2D(0, 0, myWidth, myHeight);
  [myTexture replaceRegion:aRegion
               mipmapLevel:0
                 withBytes:theImage.FaceData()->Data()
               bytesPerRow:aBytesPerRow];

  // Upload mipmap levels
  // MipMaps() returns an array of mip level sizes (in bytes) stored sequentially in FaceData()
  const NCollection_Array1<int>& aMipSizes = theImage.MipMaps();
  const uint8_t* aDataPtr = theImage.FaceData()->Data();
  size_t aDataOffset = 0;

  // First entry in MipMaps is typically the base level size, subsequent are mip levels
  int aMipWidth = myWidth;
  int aMipHeight = myHeight;

  for (int aLevel = 0; aLevel < aMipSizes.Size() && aLevel < myMipLevels; ++aLevel)
  {
    int aMipBlocksWide = (aMipWidth + aBlockSize - 1) / aBlockSize;
    int aMipBlocksHigh = (aMipHeight + aBlockSize - 1) / aBlockSize;
    int aMipBytesPerRow = aMipBlocksWide * aBytesPerBlock;
    int aMipSize = aMipBlocksWide * aMipBlocksHigh * aBytesPerBlock;

    if (aLevel > 0) // Base level already uploaded
    {
      MTLRegion aMipRegion = MTLRegionMake2D(0, 0, aMipWidth, aMipHeight);
      [myTexture replaceRegion:aMipRegion
                   mipmapLevel:aLevel
                     withBytes:(aDataPtr + aDataOffset)
                   bytesPerRow:aMipBytesPerRow];
    }

    aDataOffset += aMipSize;
    aMipWidth = std::max(1, aMipWidth / 2);
    aMipHeight = std::max(1, aMipHeight / 2);
  }

  // Estimate size (approximate for compressed textures)
  myEstimatedSize = 0;
  int w = myWidth, h = myHeight;
  for (int i = 0; i < myMipLevels; ++i)
  {
    int blocksW = (w + aBlockSize - 1) / aBlockSize;
    int blocksH = (h + aBlockSize - 1) / aBlockSize;
    myEstimatedSize += blocksW * blocksH * aBytesPerBlock;
    w = std::max(1, w / 2);
    h = std::max(1, h / 2);
  }

  return true;
}
