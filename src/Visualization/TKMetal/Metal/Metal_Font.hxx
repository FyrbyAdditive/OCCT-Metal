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

#ifndef Metal_Font_HeaderFile
#define Metal_Font_HeaderFile

#include <Metal_Resource.hxx>
#include <Metal_Texture.hxx>

#include <Font_Rect.hxx>
#include <NCollection_DataMap.hxx>
#include <NCollection_Vector.hxx>
#include <TCollection_AsciiString.hxx>

class Font_FTFont;
class Metal_Context;

//! Texture font for Metal.
//! Renders glyphs to a texture atlas for efficient text rendering.
class Metal_Font : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_Font, Metal_Resource)

public:

  //! Structure storing tile (glyph) rectangle.
  struct Tile
  {
    Font_Rect uv;      //!< UV coordinates in texture
    Font_Rect px;      //!< pixel displacement coordinates
    int       texture; //!< texture index in array
  };

  //! Rectangle with integer coordinates.
  struct RectI
  {
    int Left;
    int Right;
    int Top;
    int Bottom;
  };

public:

  //! Constructor.
  //! @param theFont FreeType font instance
  //! @param theKey  key for shared resource
  Standard_EXPORT Metal_Font(const occ::handle<Font_FTFont>& theFont,
                             const TCollection_AsciiString&  theKey = "");

  //! Destructor.
  Standard_EXPORT ~Metal_Font() override;

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const override;

  //! Return key of shared resource.
  const TCollection_AsciiString& ResourceKey() const { return myKey; }

  //! Return FreeType font instance.
  const occ::handle<Font_FTFont>& FTFont() const { return myFont; }

  //! Return true if font was loaded successfully.
  bool IsValid() const { return !myTextures.IsEmpty() && !myTextures.First().IsNull() && myTextures.First()->IsValid(); }

  //! Return true if initialization was already called.
  bool WasInitialized() const { return !myTextures.IsEmpty(); }

  //! Initialize Metal resources.
  //! FreeType font instance should be already initialized!
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Return vertical distance from baseline to highest character coordinate.
  float Ascender() const { return myAscender; }

  //! Return vertical distance from baseline to lowest character coordinate.
  float Descender() const { return myDescender; }

  //! Render glyph to texture if not already.
  //! @param theCtx   Metal context
  //! @param theUChar unicode symbol to render
  //! @param theGlyph computed glyph position rectangle, texture ID and UV coordinates
  //! @return true on success
  Standard_EXPORT bool RenderGlyph(Metal_Context* theCtx,
                                   const char32_t theUChar,
                                   Tile&          theGlyph);

  //! Return first texture.
  const occ::handle<Metal_Texture>& Texture() const { return myTextures.First(); }

  //! Return texture at index.
  const occ::handle<Metal_Texture>& Texture(int theIndex) const { return myTextures.Value(theIndex); }

  //! Return number of textures.
  int NbTextures() const { return myTextures.Size(); }

protected:

  //! Render new glyph to texture.
  bool renderGlyph(Metal_Context* theCtx, const char32_t theChar);

  //! Allocate new texture.
  bool createTexture(Metal_Context* theCtx);

protected:

  TCollection_AsciiString  myKey;        //!< key of shared resource
  occ::handle<Font_FTFont> myFont;       //!< FreeType font instance
  float                    myAscender;   //!< ascender from FT font
  float                    myDescender;  //!< descender from FT font
  int                      myTileSizeY;  //!< tile height
  int                      myLastTileId; //!< id of last tile
  RectI                    myLastTilePx; //!< position of last tile
  int                      myTextureFormat; //!< texture format

  NCollection_Vector<occ::handle<Metal_Texture>> myTextures; //!< array of textures
  NCollection_Vector<Tile>                       myTiles;    //!< array of loaded tiles

  NCollection_DataMap<char32_t, int> myGlyphMap; //!< map from unicode to tile index
};

DEFINE_STANDARD_HANDLE(Metal_Font, Metal_Resource)

#endif // Metal_Font_HeaderFile
