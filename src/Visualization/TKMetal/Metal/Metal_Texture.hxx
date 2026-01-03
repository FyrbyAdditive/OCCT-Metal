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

#ifndef Metal_Texture_HeaderFile
#define Metal_Texture_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_TextureUnit.hxx>
#include <Image_PixMap.hxx>
#include <Image_CompressedFormat.hxx>
#include <Image_CompressedPixMap.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
@protocol MTLSamplerState;
#endif

class Metal_Context;

//! Texture type enumeration.
enum Metal_TextureType
{
  Metal_TextureType_1D,
  Metal_TextureType_2D,
  Metal_TextureType_3D,
  Metal_TextureType_Cube,
  Metal_TextureType_2DArray,
  Metal_TextureType_2DMS
};

//! Texture wrapper for Metal MTLTexture.
//! Supports 2D textures, cube maps, and texture arrays.
class Metal_Texture : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_Texture, Metal_Resource)

public:

  //! Create uninitialized texture.
  Standard_EXPORT Metal_Texture();

  //! Destructor.
  Standard_EXPORT ~Metal_Texture() override;

  //! @return true if current object was initialized
  bool IsValid() const { return myTexture != nullptr; }

  //! Return texture type.
  Metal_TextureType TextureType() const { return myTextureType; }

  //! Return texture width.
  int Width() const { return myWidth; }

  //! Return texture height.
  int Height() const { return myHeight; }

  //! Return texture depth (for 3D textures).
  int Depth() const { return myDepth; }

  //! Return number of mipmap levels.
  int MipLevels() const { return myMipLevels; }

  //! Return number of array layers (for array textures).
  int ArrayLayers() const { return myArrayLayers; }

  //! Return estimated GPU memory usage.
  size_t EstimatedDataSize() const override { return myEstimatedSize; }

  //! Create 2D texture from image.
  //! @param theCtx Metal context
  //! @param theImage source image
  //! @param theGenerateMips generate mipmaps if true
  //! @return true on success
  Standard_EXPORT bool Create2D(Metal_Context* theCtx,
                                const Image_PixMap& theImage,
                                bool theGenerateMips = true);

  //! Create empty 2D texture with specified format.
  //! @param theCtx Metal context
  //! @param theWidth texture width
  //! @param theHeight texture height
  //! @param theFormat pixel format (Metal pixel format value)
  //! @param theMipLevels number of mip levels
  //! @return true on success
  Standard_EXPORT bool Create2D(Metal_Context* theCtx,
                                int theWidth,
                                int theHeight,
                                int theFormat,
                                int theMipLevels = 1);

  //! Create cube texture from 6 images.
  //! @param theCtx Metal context
  //! @param theFaces array of 6 face images (+X, -X, +Y, -Y, +Z, -Z)
  //! @param theGenerateMips generate mipmaps if true
  //! @return true on success
  Standard_EXPORT bool CreateCube(Metal_Context* theCtx,
                                  const Image_PixMap* theFaces[6],
                                  bool theGenerateMips = true);

  //! Create 3D texture with specified dimensions.
  //! @param theCtx Metal context
  //! @param theWidth texture width
  //! @param theHeight texture height
  //! @param theDepth texture depth
  //! @param theFormat pixel format (Metal pixel format value)
  //! @param theMipLevels number of mip levels
  //! @return true on success
  Standard_EXPORT bool Create3D(Metal_Context* theCtx,
                                int theWidth,
                                int theHeight,
                                int theDepth,
                                int theFormat,
                                int theMipLevels = 1);

  //! Create 2D texture array.
  //! @param theCtx Metal context
  //! @param theWidth texture width
  //! @param theHeight texture height
  //! @param theLayers number of array layers
  //! @param theFormat pixel format (Metal pixel format value)
  //! @param theMipLevels number of mip levels
  //! @return true on success
  Standard_EXPORT bool Create2DArray(Metal_Context* theCtx,
                                     int theWidth,
                                     int theHeight,
                                     int theLayers,
                                     int theFormat,
                                     int theMipLevels = 1);

  //! Create texture from compressed image data.
  //! @param theCtx Metal context
  //! @param theImage compressed image data
  //! @return true on success
  Standard_EXPORT bool CreateCompressed(Metal_Context* theCtx,
                                        const Image_CompressedPixMap& theImage);

  //! Upload image data to existing texture.
  //! @param theCtx Metal context
  //! @param theImage source image
  //! @param theMipLevel mip level to update (0 = base)
  //! @param theArrayLayer array layer (for array textures)
  //! @param theCubeFace cube face (for cube textures, 0-5)
  //! @return true on success
  Standard_EXPORT bool Upload(Metal_Context* theCtx,
                              const Image_PixMap& theImage,
                              int theMipLevel = 0,
                              int theArrayLayer = 0,
                              int theCubeFace = 0);

  //! Upload image data to a sub-region of existing texture.
  //! @param theCtx Metal context
  //! @param theImage source image
  //! @param theMipLevel mip level to update (0 = base)
  //! @param theArrayLayer array layer (for array textures)
  //! @param theCubeFace cube face (for cube textures, 0-5)
  //! @param theOffsetX X offset in texture
  //! @param theOffsetY Y offset in texture
  //! @return true on success
  Standard_EXPORT bool Upload(Metal_Context* theCtx,
                              const Image_PixMap& theImage,
                              int theMipLevel,
                              int theArrayLayer,
                              int theCubeFace,
                              int theOffsetX,
                              int theOffsetY);

  //! Generate mipmaps for texture.
  //! @param theCtx Metal context
  Standard_EXPORT void GenerateMipmaps(Metal_Context* theCtx);

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal texture object.
  id<MTLTexture> Texture() const { return myTexture; }

  //! Set Metal texture directly (for framebuffer attachments).
  //! @param theTexture Metal texture object
  //! @param theWidth texture width
  //! @param theHeight texture height
  void SetTexture(id<MTLTexture> theTexture, int theWidth, int theHeight)
  {
    myTexture = theTexture;
    myWidth = theWidth;
    myHeight = theHeight;
    myDepth = 1;
    myMipLevels = 1;
    myArrayLayers = 1;
    myTextureType = Metal_TextureType_2D;
  }
#endif

  //! Convert Image_Format to Metal pixel format.
  //! @return Metal pixel format value, or 0 if unsupported
  Standard_EXPORT static int ToMetalPixelFormat(Image_Format theFormat, bool theSRGB = false);

  //! Convert Image_CompressedFormat to Metal pixel format.
  //! @return Metal pixel format value, or 0 if unsupported
  Standard_EXPORT static int ToMetalCompressedFormat(Image_CompressedFormat theFormat, bool theSRGB = false);

  //! Return bytes per pixel for Metal pixel format.
  Standard_EXPORT static int BytesPerPixel(int theMetalFormat);

  //! Return block size for compressed format (4 for BC/DXT, 0 for uncompressed).
  Standard_EXPORT static int CompressedBlockSize(int theMetalFormat);

  //! Return bytes per block for compressed format.
  Standard_EXPORT static int CompressedBytesPerBlock(int theMetalFormat);

  //! Check if image format requires conversion for Metal (e.g., RGB->RGBA).
  //! @return true if conversion is needed
  Standard_EXPORT static bool NeedsFormatConversion(Image_Format theFormat);

  //! Convert image data from source format to Metal-compatible format.
  //! Handles RGB->RGBA, BGR->BGRA, RGBF->RGBAF, etc.
  //! @param theSrc source image data
  //! @param theDst destination buffer (must be pre-allocated)
  //! @param theWidth image width
  //! @param theHeight image height
  //! @param theSrcFormat source format
  //! @param theDstBytesPerPixel bytes per pixel in destination
  Standard_EXPORT static void ConvertImageFormat(const void* theSrc,
                                                  void* theDst,
                                                  int theWidth,
                                                  int theHeight,
                                                  size_t theSrcRowBytes,
                                                  Image_Format theSrcFormat,
                                                  int theDstBytesPerPixel);

protected:

#ifdef __OBJC__
  id<MTLTexture>   myTexture;      //!< Metal texture object
#else
  void*            myTexture;      //!< Metal texture object (opaque)
#endif
  Metal_TextureType myTextureType; //!< texture type
  int               myWidth;       //!< texture width
  int               myHeight;      //!< texture height
  int               myDepth;       //!< texture depth
  int               myMipLevels;   //!< number of mip levels
  int               myArrayLayers; //!< number of array layers
  int               myPixelFormat; //!< Metal pixel format
  size_t            myEstimatedSize; //!< estimated GPU memory usage
};

#endif // Metal_Texture_HeaderFile
