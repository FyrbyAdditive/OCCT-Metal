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

#ifdef __OBJC__
@protocol MTLTexture;
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

  //! Generate mipmaps for texture.
  //! @param theCtx Metal context
  Standard_EXPORT void GenerateMipmaps(Metal_Context* theCtx);

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal texture object.
  id<MTLTexture> Texture() const { return myTexture; }
#endif

  //! Convert Image_Format to Metal pixel format.
  //! @return Metal pixel format value, or 0 if unsupported
  Standard_EXPORT static int ToMetalPixelFormat(Image_Format theFormat, bool theSRGB = false);

  //! Return bytes per pixel for Metal pixel format.
  Standard_EXPORT static int BytesPerPixel(int theMetalFormat);

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
