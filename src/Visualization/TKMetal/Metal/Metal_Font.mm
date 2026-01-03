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

#include <Metal_Font.hxx>
#include <Metal_Context.hxx>

#include <Font_FTFont.hxx>
#include <Graphic3d_TextureParams.hxx>
#include <Image_PixMap.hxx>
#include <Standard_Assert.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Font, Metal_Resource)

// =======================================================================
// function : Metal_Font
// purpose  : Constructor
// =======================================================================
Metal_Font::Metal_Font(const occ::handle<Font_FTFont>& theFont,
                       const TCollection_AsciiString&  theKey)
: myKey(theKey),
  myFont(theFont),
  myAscender(0.0f),
  myDescender(0.0f),
  myTileSizeY(0),
  myLastTileId(-1),
  myTextureFormat(0)
{
  memset(&myLastTilePx, 0, sizeof(myLastTilePx));
}

// =======================================================================
// function : ~Metal_Font
// purpose  : Destructor
// =======================================================================
Metal_Font::~Metal_Font()
{
  Release(nullptr);
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Font::Release(Metal_Context* theCtx)
{
  if (myTextures.IsEmpty())
  {
    return;
  }

  for (int anIter = 0; anIter < myTextures.Length(); ++anIter)
  {
    occ::handle<Metal_Texture>& aTexture = myTextures.ChangeValue(anIter);
    if (!aTexture.IsNull() && aTexture->IsValid())
    {
      Standard_ASSERT_RETURN(theCtx != nullptr,
        "Metal_Font destroyed without Metal context! Possible GPU memory leakage...",
        Standard_VOID_RETURN);
    }

    if (!aTexture.IsNull())
    {
      aTexture->Release(theCtx);
      aTexture.Nullify();
    }
  }
  myTextures.Clear();
  myTiles.Clear();
  myGlyphMap.Clear();
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
size_t Metal_Font::EstimatedDataSize() const
{
  size_t aSize = 0;
  for (int anIter = 0; anIter < myTextures.Length(); ++anIter)
  {
    const occ::handle<Metal_Texture>& aTexture = myTextures.Value(anIter);
    if (!aTexture.IsNull())
    {
      aSize += aTexture->EstimatedDataSize();
    }
  }
  return aSize;
}

// =======================================================================
// function : Init
// purpose  : Initialize Metal resources
// =======================================================================
bool Metal_Font::Init(Metal_Context* theCtx)
{
  Release(theCtx);
  if (myFont.IsNull() || !myFont->IsValid())
  {
    return false;
  }

  myAscender  = myFont->Ascender();
  myDescender = myFont->Descender();
  myTileSizeY = myFont->GlyphMaxSizeY(true);

  myLastTileId = -1;
  if (!createTexture(theCtx))
  {
    Release(theCtx);
    return false;
  }
  return true;
}

// =======================================================================
// function : createTexture
// purpose  : Allocate new texture
// =======================================================================
bool Metal_Font::createTexture(Metal_Context* theCtx)
{
  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  // Single font might define very wide range of symbols, with very few of them actually used.
  // Limit single texture to circa 4096 glyphs.
  static const int THE_MAX_GLYPHS_PER_TEXTURE = 4096;

  myTileSizeY = myFont->GlyphMaxSizeY(true);
  const int aGlyphsNb = std::min(THE_MAX_GLYPHS_PER_TEXTURE,
                                  myFont->GlyphsNumber(true) - myLastTileId + 1);
  const int aMaxTileSizeX = myFont->GlyphMaxSizeX(true);
  const int aMaxSize = theCtx->MaxTextureSize();

  // Calculate power of two texture sizes
  auto getPowerOfTwo = [](int theValue, int theMaxSize) -> int
  {
    int aPow2 = 1;
    while (aPow2 < theValue && aPow2 < theMaxSize)
    {
      aPow2 <<= 1;
    }
    return aPow2;
  };

  const int aTextureSizeX = getPowerOfTwo(aGlyphsNb * aMaxTileSizeX, aMaxSize);
  const int aTilesPerRow = aTextureSizeX / std::max(1, aMaxTileSizeX);
  const int aTextureSizeY = getPowerOfTwo((aGlyphsNb / std::max(1, aTilesPerRow) + 1) * myTileSizeY, aMaxSize);

  memset(&myLastTilePx, 0, sizeof(myLastTilePx));
  myLastTilePx.Bottom = myTileSizeY;

  // Create texture
  occ::handle<Metal_Texture> aTexture = new Metal_Texture();

  // Create black (zeroed) image for initial texture
  Image_PixMap aBlackImg;
  if (!aBlackImg.InitZero(Image_Format_Alpha, size_t(aTextureSizeX), size_t(aTextureSizeY)))
  {
    return false;
  }

  if (!aTexture->Create2D(theCtx, aBlackImg, false))
  {
    return false;
  }

  myTextures.Append(aTexture);
  return true;
}

// =======================================================================
// function : renderGlyph
// purpose  : Render new glyph to texture
// =======================================================================
bool Metal_Font::renderGlyph(Metal_Context* theCtx, const char32_t theChar)
{
  if (!myFont->RenderGlyph(theChar))
  {
    return false;
  }

  if (myTextures.IsEmpty())
  {
    return false;
  }

  occ::handle<Metal_Texture>& aTexture = myTextures.ChangeLast();
  if (aTexture.IsNull() || !aTexture->IsValid())
  {
    return false;
  }

  const Image_PixMap& anImg = myFont->GlyphImage();
  const int aTileId = myLastTileId + 1;

  myLastTilePx.Left = myLastTilePx.Right + 3;
  myLastTilePx.Right = myLastTilePx.Left + (int)anImg.SizeX();

  if (myLastTilePx.Right > aTexture->Width() || (int)anImg.SizeY() > myTileSizeY)
  {
    myTileSizeY = myFont->GlyphMaxSizeY(true);

    myLastTilePx.Left = 0;
    myLastTilePx.Right = (int)anImg.SizeX();
    myLastTilePx.Top += myTileSizeY;
    myLastTilePx.Bottom += myTileSizeY;

    if (myLastTilePx.Bottom > aTexture->Height() || myLastTilePx.Right > aTexture->Width())
    {
      if (!createTexture(theCtx))
      {
        return false;
      }
      return renderGlyph(theCtx, theChar);
    }
  }

  // Upload glyph data to texture
  aTexture->Upload(theCtx, anImg, 0, 0, 0,
                   myLastTilePx.Left, myLastTilePx.Top);

  // Record tile info
  Tile aTile;
  aTile.uv.Left   = float(myLastTilePx.Left) / float(aTexture->Width());
  aTile.uv.Right  = float(myLastTilePx.Right) / float(aTexture->Width());
  aTile.uv.Top    = float(myLastTilePx.Top) / float(aTexture->Height());
  aTile.uv.Bottom = float(myLastTilePx.Top + anImg.SizeY()) / float(aTexture->Height());
  aTile.texture   = myTextures.Size() - 1;
  myFont->GlyphRect(aTile.px);

  myLastTileId = aTileId;
  myTiles.Append(aTile);
  return true;
}

// =======================================================================
// function : RenderGlyph
// purpose  : Render glyph to texture if not already
// =======================================================================
bool Metal_Font::RenderGlyph(Metal_Context* theCtx,
                             const char32_t theUChar,
                             Tile&          theGlyph)
{
  int aTileId = 0;
  if (!myGlyphMap.Find(theUChar, aTileId))
  {
    if (renderGlyph(theCtx, theUChar))
    {
      aTileId = myLastTileId;
    }
    else
    {
      return false;
    }

    myGlyphMap.Bind(theUChar, aTileId);
  }

  const Tile& aTile = myTiles.Value(aTileId);
  theGlyph.px      = aTile.px;
  theGlyph.uv      = aTile.uv;
  theGlyph.texture = aTile.texture;

  return true;
}
